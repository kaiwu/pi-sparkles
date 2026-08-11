import { existsSync } from "node:fs";
import { join } from "node:path";
import { ROOT, readGleamPackage } from "./modules.js";
import { run } from "./process.js";
import {
  implementedPackagesForTier,
  readTierManifest,
  tierById,
  tierSummary,
  validateTierManifest,
  verificationBlockers,
} from "./tiers.js";

function fail(messages) {
  for (const message of messages) console.error(`- ${message}`);
  process.exit(1);
}

function printSummary(manifest) {
  console.table(tierSummary(manifest));
  console.log(`Active tier: ${manifest.active_tier}`);
}

function changedPaths() {
  const result = Bun.spawnSync(
    ["git", "status", "--porcelain", "--untracked-files=all"],
    { cwd: ROOT, stdout: "pipe", stderr: "pipe" },
  );
  if (result.exitCode !== 0) {
    process.stdout.write(result.stdout.toString());
    process.stderr.write(result.stderr.toString());
    throw new Error(`git status exited with code ${result.exitCode}`);
  }
  return result.stdout
    .toString()
    .split("\n")
    .filter(Boolean)
    .map((line) => line.slice(3).split(" -> ").at(-1));
}

function changedGleamPackages(paths) {
  const directories = new Set();
  for (const path of paths) {
    const match = path.match(
      /^(plugins|finance)\/([^/]+)\/(?:gleam\.toml|src\/|test\/)/,
    );
    if (match) directories.add(join(ROOT, match[1], match[2]));
    if (/^pi_gleam\/(?:gleam\.toml|src\/|test\/)/.test(path)) {
      directories.add(join(ROOT, "pi_gleam"));
    }
  }
  return [...directories]
    .filter((directory) => existsSync(join(directory, "gleam.toml")))
    .map(readGleamPackage)
    .sort((left, right) => left.shortName.localeCompare(right.shortName));
}

function tierDependencyClosure(manifest, tier) {
  const ids = new Set([tier.id]);
  const visit = (current) => {
    for (const dependencyId of current.depends_on) {
      if (ids.has(dependencyId)) continue;
      ids.add(dependencyId);
      visit(tierById(manifest, dependencyId));
    }
  };
  visit(tier);
  return manifest.tiers.filter((candidate) => ids.has(candidate.id));
}

const command = process.argv[2] ?? "audit";
const manifest = readTierManifest();
const manifestErrors = validateTierManifest(manifest);
if (manifestErrors.length > 0) fail(manifestErrors);

if (command === "audit" || command === "list") {
  printSummary(manifest);
  process.exit(0);
}

if (command === "show") {
  const id = process.argv[3] ?? manifest.active_tier;
  const tier = tierById(manifest, id);
  if (!tier) fail([`unknown tier: ${id}`]);
  console.log(JSON.stringify(tier, null, 2));
  process.exit(0);
}

if (command === "checkpoint") {
  const id = process.argv[3] ?? manifest.active_tier;
  const tier = tierById(manifest, id);
  if (!tier) fail([`unknown tier: ${id}`]);
  if (manifest.active_tier !== tier.id) {
    fail([`${tier.id} is not the active tier (${manifest.active_tier})`]);
  }

  const paths = changedPaths();
  const packages = changedGleamPackages(paths);
  const allowedPlugins = new Set(
    tierDependencyClosure(manifest, tier).flatMap((candidate) => [
      ...candidate.proposals,
      ...candidate.extra_packages,
    ]),
  );
  const outOfScope = packages.filter(
    (pkg) =>
      pkg.directory.startsWith(join(ROOT, "plugins")) &&
      !allowedPlugins.has(pkg.shortName),
  );
  if (outOfScope.length > 0) {
    fail(
      outOfScope.map(
        (pkg) => `${pkg.shortName} is outside active ${tier.id} dependency scope`,
      ),
    );
  }
  if (
    packages.some((pkg) => pkg.directory.startsWith(join(ROOT, "plugins"))) &&
    !new Set(["building", "verifying"]).has(tier.status)
  ) {
    fail([
      `${tier.id} plugin code changed while status is ${tier.status}; resolve blockers and move the tier to building first`,
    ]);
  }

  for (const pkg of packages) {
    console.log(`checkpointing ${pkg.shortName}`);
    const formatPaths = ["src"];
    if (existsSync(join(pkg.directory, "test"))) formatPaths.push("test");
    run("gleam", ["format", "--check", ...formatPaths], {
      cwd: pkg.directory,
    });
    run(
      "gleam",
      ["build", "--target", "javascript", "--warnings-as-errors"],
      { cwd: pkg.directory },
    );
    if (existsSync(join(pkg.directory, "test"))) {
      run("gleam", ["test", "--target", "javascript", "--runtime", "bun"], {
        cwd: pkg.directory,
      });
    }
  }
  run("bun", ["test", "test/workflow"], { cwd: ROOT });
  console.log(
    `${tier.id} atomic checkpoint passed for ${packages.length} changed Gleam package(s); no delivery status changed.`,
  );
  process.exit(0);
}

if (command === "verify") {
  const id = process.argv[3] ?? manifest.active_tier;
  const tier = tierById(manifest, id);
  if (!tier) fail([`unknown tier: ${id}`]);
  const blockers = verificationBlockers(manifest, tier);
  if (blockers.length > 0) fail(blockers);

  console.log(`verifying ${tier.id}: ${tier.name}`);
  console.log(
    `${tier.proposals.length} proposals; ${implementedPackagesForTier(tier).length} implementation packages`,
  );

  // The expensive repository matrix runs exactly once at the tier gate. It is
  // never a per-plugin promotion loop.
  run("bun", ["scripts/test.js"], { cwd: ROOT });
  run("bun", ["test", join(ROOT, tier.acceptance_lane)], { cwd: ROOT });
  console.log(
    `${tier.id} verification passed. Record the evidence in R2.md and change the tier to product_useful in a separate reviewed patch.`,
  );
  process.exit(0);
}

fail([`unknown tier command: ${command}`]);
