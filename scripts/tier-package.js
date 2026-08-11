import { createHash, randomUUID } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import {
  basename,
  dirname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
} from "node:path";
import { buildPlugins } from "./build.js";
import {
  BINDING_DIR,
  DIST_DIR,
  FINANCE_DIR,
  PLUGINS_DIR,
  ROOT,
  plugins,
} from "./modules.js";
import {
  missingImplementations,
  readTierManifest,
  tierById,
  validateTierManifest,
} from "./tiers.js";

const PACKAGE_SCHEMA_VERSION = 1;
const ARTIFACT_FILES = [
  "index.js",
  "index.js.map",
  "build.json",
  "metafile.json",
];
const HOST_PEERS = {
  "@earendil-works/pi-agent-core": "*",
  "@earendil-works/pi-ai": "*",
  "@earendil-works/pi-coding-agent": "*",
  "@earendil-works/pi-tui": "*",
  typebox: "*",
};

function sha256Bytes(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sha256File(path) {
  return sha256Bytes(readFileSync(path));
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function isInside(parent, candidate) {
  const path = relative(parent, candidate);
  return path === "" || (!path.startsWith(`..${sep}`) && path !== "..");
}

function safeOutputDirectory(path) {
  const output = resolve(path);
  const forbidden = [ROOT, DIST_DIR, PLUGINS_DIR, FINANCE_DIR, BINDING_DIR];
  if (forbidden.some((directory) => output === directory)) {
    throw new Error(`Refusing tier package output at protected path: ${output}`);
  }
  if (isInside(output, ROOT)) {
    throw new Error(
      `Refusing tier package output that contains the repository: ${output}`,
    );
  }
  if (
    [PLUGINS_DIR, FINANCE_DIR, BINDING_DIR].some((directory) =>
      isInside(directory, output),
    )
  ) {
    throw new Error(`Refusing tier package output inside source: ${output}`);
  }
  return output;
}

function sourceFiles(directory) {
  if (!existsSync(directory)) return [];
  const found = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) found.push(...sourceFiles(path));
    if (entry.isFile() && /\.(?:js|mjs)$/.test(entry.name)) found.push(path);
  }
  return found;
}

function environmentVariables(plugin) {
  const names = new Set();
  const patterns = [
    /(?:process|Bun)\.env\.([A-Z][A-Z0-9_]*)/g,
    /(?:process|Bun)\.env\[['"]([A-Z][A-Z0-9_]*)['"]\]/g,
  ];
  for (const path of sourceFiles(join(plugin.directory, "src"))) {
    const source = readFileSync(path, "utf8");
    for (const pattern of patterns) {
      for (const match of source.matchAll(pattern)) names.add(match[1]);
    }
  }
  return [...names].sort();
}

function rootVersion() {
  const manifest = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"));
  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    throw new Error("Root package.json has no version");
  }
  return manifest.version;
}

function packageSlug(tier) {
  return tier.id.toLowerCase();
}

function tierDefinition(tier) {
  return {
    id: tier.id,
    name: tier.name,
    status: tier.status,
    dependsOn: tier.depends_on,
    trackProfile: tier.track_profile,
    productOutcome: tier.product_outcome,
    proposals: tier.proposals,
  };
}

function tierClosureSha256(tiers) {
  return sha256Bytes(JSON.stringify(tiers.map(tierDefinition)));
}

export function tierDependencyClosure(manifest, tier) {
  const ordered = [];
  const visited = new Set();
  const visit = (current) => {
    if (!current || visited.has(current.id)) return;
    for (const dependencyId of current.depends_on) {
      const dependency = tierById(manifest, dependencyId);
      if (!dependency) {
        throw new Error(`${current.id} depends on unknown tier ${dependencyId}`);
      }
      visit(dependency);
    }
    visited.add(current.id);
    ordered.push(current);
  };
  visit(tier);
  return ordered;
}

export function tierPackagePlan(manifest, tierId) {
  const manifestErrors = validateTierManifest(manifest);
  if (manifestErrors.length > 0) {
    throw new Error(`Invalid tier manifest:\n- ${manifestErrors.join("\n- ")}`);
  }
  const tier = tierById(manifest, tierId);
  if (!tier) throw new Error(`Unknown tier: ${tierId}`);

  const includedTiers = tierDependencyClosure(manifest, tier);
  const unavailable = [];
  for (const included of includedTiers) {
    if (included.status !== "product_useful") {
      unavailable.push(
        `${included.id} is ${included.status}; only ProductUseful tiers can be packaged`,
      );
    }
    for (const proposal of missingImplementations(included)) {
      unavailable.push(`${included.id} implementation is missing: pi_${proposal}`);
    }
  }
  if (unavailable.length > 0) {
    throw new Error(`Tier package is not releasable:\n- ${unavailable.join("\n- ")}`);
  }

  const availablePlugins = new Map(
    plugins().map((plugin) => [plugin.shortName, plugin]),
  );
  const proposalNames = includedTiers.flatMap((included) => included.proposals);
  const selected = proposalNames.map((name) => availablePlugins.get(name));
  const missing = proposalNames.filter((_, index) => !selected[index]);
  if (missing.length > 0) {
    throw new Error(`Missing tier plugin packages: ${missing.join(", ")}`);
  }

  const selectedPlugins = selected.filter(Boolean);
  return {
    tier,
    includedTiers,
    plugins: selectedPlugins,
    excludedExtraPackages: includedTiers.flatMap(
      (included) => included.extra_packages,
    ),
    packageName: `pi-sparkles-${packageSlug(tier)}`,
    packageVersion: rootVersion(),
    outputDirectory: join(DIST_DIR, "tiers", packageSlug(tier)),
  };
}

function packageManifest(plan) {
  return {
    name: plan.packageName,
    version: plan.packageVersion,
    description: `${plan.tier.name}: ${plan.tier.product_outcome}`,
    type: "module",
    license: "Apache-2.0",
    keywords: ["pi-package", "pi-sparkles", plan.tier.id.toLowerCase()],
    peerDependencies: HOST_PEERS,
    pi: {
      extensions: plan.plugins.map(
        (plugin) => `./extensions/${plugin.shortName}/index.js`,
      ),
    },
  };
}

function configurationMarkdown(extensionRecords) {
  const markdownCell = (value) =>
    value.replaceAll("|", "\\|").replaceAll("\n", " ");
  const configured = extensionRecords.filter(
    (extension) =>
      extension.environmentVariables.length > 0 ||
      extension.provider !== null ||
      extension.access !== null,
  );
  const rows = configured.map((extension) => {
    const provider = markdownCell(extension.provider ?? "provider-neutral");
    const access = markdownCell(extension.access ?? "see extension contract");
    const variables =
      extension.environmentVariables.length === 0
        ? "None"
        : extension.environmentVariables.map((name) => `\`${name}\``).join(", ");
    return `| \`${extension.shortName}\` | ${provider} | ${access} | ${variables} |`;
  });
  return `# Runtime configuration\n\nThe package contains variable names only. It never reads or copies credential\nvalues while building. A variable listed here belongs only to the adapter that\nexplicitly selects it; providers never silently fall back or share authority.\nRequired-versus-optional behavior and entitlement limits remain controlled by\nthe named extension's contract.\n\n| Extension | Provider | Access | Referenced environment variables |\n| --- | --- | --- | --- |\n${rows.join("\n")}\n`;
}

function packageReadme(plan, extensionRecords) {
  const included = plan.includedTiers.map((tier) => tier.id).join(", ");
  return `# ${plan.packageName}\n\nA plain Pi package for **${plan.tier.name}**. It contains ${extensionRecords.length}\nversion-locked extension bundles and includes ProductUseful tier dependency\nclosure: ${included}. Extension boundaries remain intact; Pi loads them as one\ninstalled product.\n\n## Product outcome\n\n${plan.tier.product_outcome}\n\n## Install\n\nFrom inside this package directory:\n\n\`\`\`sh\npi install .\n\`\`\`\n\nFor a project-local installation, add \`-l\`. To inspect without installing:\n\n\`\`\`sh\npi --no-extensions -e . --list-models\n\`\`\`\n\nReview \`CONFIGURATION.md\` before provider-backed use and \`tier-lock.json\` /\n\`SHA256SUMS\` for the exact extension inventory. Pi extensions execute with the\nuser's full permissions. Provider rights, data limitations, human decision\nboundaries, and paper/live separation remain those declared by each extension.\n`;
}

function extensionRecord(plugin, artifactRoot, destinationRoot) {
  const sourceDirectory = join(artifactRoot, plugin.shortName);
  const destinationDirectory = join(
    destinationRoot,
    "extensions",
    plugin.shortName,
  );
  mkdirSync(destinationDirectory, { recursive: true });
  for (const file of ARTIFACT_FILES) {
    const source = join(sourceDirectory, file);
    if (!existsSync(source) || !lstatSync(source).isFile()) {
      throw new Error(`Missing built artifact for ${plugin.shortName}: ${source}`);
    }
    copyFileSync(source, join(destinationDirectory, file));
  }

  const finance = plugin.metadata.metadata?.finance ?? {};
  return {
    shortName: plugin.shortName,
    gleamPackage: plugin.name,
    version: plugin.version,
    testedPiVersion: plugin.metadata.metadata?.pi?.tested_version ?? null,
    provider: typeof finance.provider === "string" ? finance.provider : null,
    access: typeof finance.access === "string" ? finance.access : null,
    environmentVariables: environmentVariables(plugin),
    entrypoint: `extensions/${plugin.shortName}/index.js`,
    sha256: sha256File(join(destinationDirectory, "index.js")),
    sourceMapSha256: sha256File(join(destinationDirectory, "index.js.map")),
  };
}

function checksumEntries(directory) {
  const files = [];
  const visit = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) visit(path);
      if (entry.isFile() && entry.name !== "SHA256SUMS") files.push(path);
      if (!entry.isDirectory() && !entry.isFile()) {
        throw new Error(`Tier package contains an unsupported file type: ${path}`);
      }
    }
  };
  visit(directory);
  return files
    .map((path) => ({
      path: relative(directory, path).split(sep).join("/"),
      sha256: sha256File(path),
    }))
    .sort((left, right) => left.path.localeCompare(right.path));
}

function writeChecksums(directory) {
  const body = checksumEntries(directory)
    .map((entry) => `${entry.sha256}  ${entry.path}`)
    .join("\n");
  writeFileSync(join(directory, "SHA256SUMS"), `${body}\n`);
}

function parseChecksums(source) {
  return source
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      const match = line.match(/^([a-f0-9]{64})  (.+)$/);
      if (!match) throw new Error(`Invalid SHA256SUMS line: ${line}`);
      return { sha256: match[1], path: match[2] };
    });
}

function safePackagePath(root, path) {
  if (
    typeof path !== "string" ||
    path.length === 0 ||
    isAbsolute(path) ||
    path.includes("\\") ||
    path.split("/").includes("..")
  ) {
    throw new Error(`Unsafe tier package path: ${path}`);
  }
  const resolved = resolve(root, path);
  if (!isInside(root, resolved)) throw new Error(`Unsafe tier package path: ${path}`);
  return resolved;
}

export function verifyTierPackage(directory, expectedPlan) {
  const root = resolve(directory);
  const manifestPath = join(root, "package.json");
  const lockPath = join(root, "tier-lock.json");
  const checksumsPath = join(root, "SHA256SUMS");
  for (const path of [manifestPath, lockPath, checksumsPath]) {
    if (!existsSync(path) || !lstatSync(path).isFile()) {
      throw new Error(`Tier package file is missing: ${path}`);
    }
  }

  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const lock = JSON.parse(readFileSync(lockPath, "utf8"));
  if (
    typeof manifest !== "object" ||
    manifest === null ||
    typeof lock !== "object" ||
    lock === null ||
    typeof lock.package !== "object" ||
    lock.package === null ||
    typeof lock.tier !== "object" ||
    lock.tier === null ||
    !Array.isArray(lock.extensions)
  ) {
    throw new Error("Tier package manifest or lock has an invalid shape");
  }
  if (lock.schemaVersion !== PACKAGE_SCHEMA_VERSION) {
    throw new Error(`Unsupported tier package schema: ${lock.schemaVersion}`);
  }
  if (manifest.name !== lock.package.name || manifest.version !== lock.package.version) {
    throw new Error("Tier package manifest and lock identity differ");
  }
  if (lock.tier?.status !== "product_useful") {
    throw new Error("Tier package lock does not identify a ProductUseful tier");
  }
  if (
    lock.extensionCount !== lock.extensions.length ||
    lock.extensions.length === 0
  ) {
    throw new Error("Tier package lock has an invalid extension count");
  }
  if (
    !Array.isArray(lock.includedTiers) ||
    lock.includedTiers.at(-1) !== lock.tier.id ||
    new Set(lock.includedTiers).size !== lock.includedTiers.length
  ) {
    throw new Error("Tier package lock has an invalid dependency closure");
  }
  if (lock.credentialsIncluded !== false) {
    throw new Error("Tier package lock does not prohibit bundled credentials");
  }
  if (
    !Array.isArray(lock.tierClosure) ||
    JSON.stringify(lock.tierClosure.map((tier) => tier.id)) !==
      JSON.stringify(lock.includedTiers) ||
    lock.tierClosureSha256 !== sha256Bytes(JSON.stringify(lock.tierClosure))
  ) {
    throw new Error("Tier package lock has an invalid dependency definition");
  }
  const declared = manifest.pi?.extensions ?? [];
  const locked = lock.extensions.map((extension) => `./${extension.entrypoint}`);
  if (JSON.stringify(declared) !== JSON.stringify(locked)) {
    throw new Error("Tier package extension manifest differs from lock");
  }
  if (new Set(declared).size !== declared.length) {
    throw new Error("Tier package declares duplicate extensions");
  }
  if (expectedPlan) {
    const expectedExtensions = expectedPlan.plugins.map((plugin) => ({
      shortName: plugin.shortName,
      gleamPackage: plugin.name,
      version: plugin.version,
    }));
    const lockedExtensions = lock.extensions.map((extension) => ({
      shortName: extension.shortName,
      gleamPackage: extension.gleamPackage,
      version: extension.version,
    }));
    if (
      manifest.name !== expectedPlan.packageName ||
      manifest.version !== expectedPlan.packageVersion ||
      lock.tierClosureSha256 !==
        tierClosureSha256(expectedPlan.includedTiers) ||
      JSON.stringify(lockedExtensions) !== JSON.stringify(expectedExtensions)
    ) {
      throw new Error("Tier package does not match the current tier package plan");
    }
  }

  for (const extension of lock.extensions) {
    const entrypoint = safePackagePath(root, extension.entrypoint);
    if (!existsSync(entrypoint) || !lstatSync(entrypoint).isFile()) {
      throw new Error(`Tier extension is missing: ${extension.entrypoint}`);
    }
    if (sha256File(entrypoint) !== extension.sha256) {
      throw new Error(`Tier extension hash mismatch: ${extension.entrypoint}`);
    }
  }
  for (const entry of parseChecksums(readFileSync(checksumsPath, "utf8"))) {
    const path = safePackagePath(root, entry.path);
    if (!existsSync(path) || !lstatSync(path).isFile()) {
      throw new Error(`Checksummed tier package file is missing: ${entry.path}`);
    }
    if (sha256File(path) !== entry.sha256) {
      throw new Error(`Tier package checksum mismatch: ${entry.path}`);
    }
  }
  const expectedChecksums = checksumEntries(root);
  const declaredChecksums = parseChecksums(readFileSync(checksumsPath, "utf8"));
  const checksumLine = (entry) => `${entry.sha256}  ${entry.path}`;
  if (
    JSON.stringify(declaredChecksums.map(checksumLine)) !==
    JSON.stringify(expectedChecksums.map(checksumLine))
  ) {
    throw new Error("Tier package checksum inventory is incomplete or out of order");
  }

  return {
    directory: root,
    name: manifest.name,
    version: manifest.version,
    tierId: lock.tier.id,
    includedTierIds: lock.includedTiers,
    extensionCount: lock.extensions.length,
  };
}

export function assembleTierPackage(
  plan,
  artifactRoot = DIST_DIR,
  outputDirectory = plan.outputDirectory,
) {
  const output = safeOutputDirectory(outputDirectory);
  mkdirSync(dirname(output), { recursive: true });
  const staging = join(
    dirname(output),
    `.${basename(output)}.staging-${process.pid}-${randomUUID()}`,
  );
  const backup = join(
    dirname(output),
    `.${basename(output)}.previous-${process.pid}-${randomUUID()}`,
  );
  mkdirSync(staging, { recursive: true });

  let movedPrevious = false;
  try {
    const extensionRecords = plan.plugins.map((plugin) =>
      extensionRecord(plugin, artifactRoot, staging),
    );
    const manifest = packageManifest(plan);
    writeJson(join(staging, "package.json"), manifest);
    writeFileSync(
      join(staging, "README.md"),
      packageReadme(plan, extensionRecords),
    );
    writeFileSync(
      join(staging, "CONFIGURATION.md"),
      configurationMarkdown(extensionRecords),
    );
    writeJson(join(staging, "tier-lock.json"), {
      schemaVersion: PACKAGE_SCHEMA_VERSION,
      package: { name: plan.packageName, version: plan.packageVersion },
      tier: {
        id: plan.tier.id,
        name: plan.tier.name,
        status: plan.tier.status,
        productOutcome: plan.tier.product_outcome,
        trackProfile: plan.tier.track_profile,
      },
      includedTiers: plan.includedTiers.map((tier) => tier.id),
      tierClosure: plan.includedTiers.map(tierDefinition),
      tierClosureSha256: tierClosureSha256(plan.includedTiers),
      extensionCount: extensionRecords.length,
      extensions: extensionRecords,
      excludedExtraPackages: plan.excludedExtraPackages,
      credentialsIncluded: false,
    });
    writeChecksums(staging);
    verifyTierPackage(staging, plan);

    if (existsSync(output)) {
      renameSync(output, backup);
      movedPrevious = true;
    }
    renameSync(staging, output);
    if (movedPrevious) rmSync(backup, { recursive: true, force: true });
    return verifyTierPackage(output, plan);
  } catch (error) {
    rmSync(staging, { recursive: true, force: true });
    if (movedPrevious && !existsSync(output) && existsSync(backup)) {
      renameSync(backup, output);
    }
    throw error;
  }
}

export async function packageTier(
  tierId,
  { build = true, outputDirectory } = {},
) {
  const plan = tierPackagePlan(readTierManifest(), tierId);
  if (build) await buildPlugins(plan.plugins);
  const summary = assembleTierPackage(
    plan,
    DIST_DIR,
    outputDirectory ?? plan.outputDirectory,
  );
  console.log(
    `${summary.tierId} plain Pi package: ${summary.directory} (${summary.extensionCount} extensions)`,
  );
  return summary;
}

function usage() {
  return [
    "Usage: bun run tier:package -- T1 [--no-build] [--output <directory>]",
    "       bun run tier:package -- T1 --verify-only [--output <directory>]",
    "Only ProductUseful tiers and their ProductUseful dependency closure can be packaged.",
  ].join("\n");
}

function parseArguments(args) {
  let tierId;
  let build = true;
  let verifyOnly = false;
  let outputDirectory;
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--no-build") build = false;
    else if (arg === "--verify-only") verifyOnly = true;
    else if (arg === "--output") {
      outputDirectory = args[index + 1];
      index += 1;
      if (!outputDirectory) throw new Error("--output requires a directory");
    } else if (arg === "--help" || arg === "-h") {
      console.log(usage());
      process.exit(0);
    } else if (arg.startsWith("-")) throw new Error(`Unknown option: ${arg}`);
    else if (tierId) throw new Error(`Unexpected argument: ${arg}`);
    else tierId = arg;
  }
  return { tierId, build, verifyOnly, outputDirectory };
}

if (import.meta.main) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const manifest = readTierManifest();
    const tierId = options.tierId ?? manifest.active_tier;
    const plan = tierPackagePlan(manifest, tierId);
    const output = options.outputDirectory ?? plan.outputDirectory;
    if (options.verifyOnly) {
      const summary = verifyTierPackage(output, plan);
      if (summary.tierId !== tierId) {
        throw new Error(
          `Tier package contains ${summary.tierId}, expected ${tierId}`,
        );
      }
      console.log(
        `${summary.tierId} package verified: ${summary.extensionCount} extensions at ${summary.directory}`,
      );
    } else {
      await packageTier(tierId, {
        build: options.build,
        outputDirectory: output,
      });
    }
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    console.error(usage());
    process.exit(1);
  }
}
