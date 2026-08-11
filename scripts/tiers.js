import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { PLUGINS_DIR, ROOT, discoverPackages } from "./modules.js";

export const TIER_MANIFEST_PATH = join(ROOT, "tiers.json");
export const CATALOG_PATH = join(ROOT, "R1.md");

export function readTierManifest() {
  return JSON.parse(readFileSync(TIER_MANIFEST_PATH, "utf8"));
}

export function catalogProposals() {
  const source = readFileSync(CATALOG_PATH, "utf8");
  return [
    ...new Set(
      [...source.matchAll(/^\| (?:\[)?`pi_([a-z0-9_]+)`/gm)].map(
        (match) => match[1],
      ),
    ),
  ];
}

export function tierById(manifest, id) {
  return manifest.tiers.find((tier) => tier.id === id);
}

export function implementedPackagesForTier(tier) {
  const included = new Set([...tier.proposals, ...tier.extra_packages]);
  return discoverPackages(PLUGINS_DIR).filter((pkg) =>
    included.has(pkg.shortName),
  );
}

export function missingImplementations(tier) {
  return tier.proposals.filter(
    (proposal) => !existsSync(join(PLUGINS_DIR, proposal, "gleam.toml")),
  );
}

export function unresolvedBlockers(tier) {
  return tier.blockers.filter((blocker) => blocker.status !== "resolved");
}

function duplicateValues(values) {
  const counts = new Map();
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1);
  return [...counts].filter(([, count]) => count > 1).map(([value]) => value);
}

function dependencyCycles(manifest) {
  const dependencies = new Map(
    manifest.tiers.map((tier) => [tier.id, tier.depends_on]),
  );
  const visiting = new Set();
  const visited = new Set();
  const cycles = [];

  function visit(id, path) {
    if (visiting.has(id)) {
      cycles.push([...path, id].join(" -> "));
      return;
    }
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dependency of dependencies.get(id) ?? []) {
      visit(dependency, [...path, id]);
    }
    visiting.delete(id);
    visited.add(id);
  }

  for (const id of dependencies.keys()) visit(id, []);
  return cycles;
}

export function validateTierManifest(manifest = readTierManifest()) {
  const errors = [];
  const requiredStatuses = [
    "queued",
    "blocker_resolution",
    "building",
    "verifying",
    "product_useful",
  ];
  const catalog = catalogProposals();
  const catalogSet = new Set(catalog);
  const tierIds = manifest.tiers.map((tier) => tier.id);
  const validStatuses = new Set(manifest.statuses);
  const allProposals = manifest.tiers.flatMap((tier) => tier.proposals);
  const allExtras = manifest.tiers.flatMap((tier) => tier.extra_packages);
  const implemented = discoverPackages(PLUGINS_DIR).map(
    (pkg) => pkg.shortName,
  );
  const nonCatalogPackages = implemented.filter(
    (name) => !catalogSet.has(name),
  );

  if (manifest.schema_version !== 1) {
    errors.push(`unsupported schema_version: ${manifest.schema_version}`);
  }
  if (manifest.tiers.length !== 6) {
    errors.push(`expected six product tiers, found ${manifest.tiers.length}`);
  }
  if (JSON.stringify(manifest.statuses) !== JSON.stringify(requiredStatuses)) {
    errors.push("tier statuses do not match the controlled lifecycle");
  }
  for (const duplicate of duplicateValues(tierIds)) {
    errors.push(`tier appears more than once: ${duplicate}`);
  }
  if (!tierIds.includes(manifest.active_tier)) {
    errors.push(`active_tier does not exist: ${manifest.active_tier}`);
  }
  for (const duplicate of duplicateValues(allProposals)) {
    errors.push(`proposal appears in more than one tier: pi_${duplicate}`);
  }
  for (const proposal of catalog.filter((name) => !allProposals.includes(name))) {
    errors.push(`catalog proposal has no tier: pi_${proposal}`);
  }
  for (const proposal of allProposals.filter((name) => !catalogSet.has(name))) {
    errors.push(`tier proposal is absent from R1.md: pi_${proposal}`);
  }
  for (const duplicate of duplicateValues(allExtras)) {
    errors.push(`extra package appears in more than one tier: ${duplicate}`);
  }
  for (const duplicate of duplicateValues(
    manifest.tiers.map((tier) => tier.acceptance_lane),
  )) {
    errors.push(`acceptance lane appears in more than one tier: ${duplicate}`);
  }
  for (const pkg of nonCatalogPackages.filter((name) => !allExtras.includes(name))) {
    errors.push(`non-catalog implementation package has no tier: ${pkg}`);
  }
  for (const pkg of allExtras.filter((name) => !nonCatalogPackages.includes(name))) {
    errors.push(`extra package is absent or now belongs to the catalog: ${pkg}`);
  }

  for (const tier of manifest.tiers) {
    if (!/^T[1-9][0-9]*$/.test(tier.id)) {
      errors.push(`invalid tier id: ${tier.id}`);
    }
    if (!validStatuses.has(tier.status)) {
      errors.push(`invalid status for ${tier.id}: ${tier.status}`);
    }
    if (!tier.product_outcome?.trim()) {
      errors.push(`${tier.id} has no product outcome`);
    }
    if (!tier.track_profile?.trim()) {
      errors.push(`${tier.id} has no track profile`);
    }
    if (!tier.acceptance_lane?.startsWith("test/tiers/")) {
      errors.push(`${tier.id} acceptance lane must live under test/tiers/`);
    }
    for (const dependency of tier.depends_on) {
      if (!tierIds.includes(dependency)) {
        errors.push(`${tier.id} depends on unknown tier ${dependency}`);
      }
      if (dependency === tier.id) {
        errors.push(`${tier.id} depends on itself`);
      }
    }
    for (const duplicate of duplicateValues(
      tier.blockers.map((blocker) => blocker.id),
    )) {
      errors.push(`${tier.id} blocker appears more than once: ${duplicate}`);
    }
    for (const blocker of tier.blockers) {
      if (!new Set(["open", "resolved"]).has(blocker.status)) {
        errors.push(`${tier.id} blocker ${blocker.id} has invalid status`);
      }
      if (!blocker.exit?.trim()) {
        errors.push(`${tier.id} blocker ${blocker.id} has no exit evidence`);
      }
      if (blocker.status === "resolved" && !blocker.resolution?.trim()) {
        errors.push(`${tier.id} blocker ${blocker.id} has no resolution record`);
      }
    }
    for (const proposal of tier.proposals) {
      if (!existsSync(join(PLUGINS_DIR, proposal, "README.md"))) {
        errors.push(`${tier.id} proposal has no README: pi_${proposal}`);
      }
    }
  }

  for (const cycle of dependencyCycles(manifest)) {
    errors.push(`tier dependency cycle: ${cycle}`);
  }

  return errors;
}

export function verificationBlockers(manifest, tier) {
  const errors = [];
  if (manifest.active_tier !== tier.id) {
    errors.push(`${tier.id} is not the active tier (${manifest.active_tier})`);
  }
  if (tier.status !== "verifying") {
    errors.push(`${tier.id} status must be verifying, found ${tier.status}`);
  }
  for (const blocker of unresolvedBlockers(tier)) {
    errors.push(`${tier.id} blocker is open: ${blocker.id}`);
  }
  for (const dependencyId of tier.depends_on) {
    const dependency = tierById(manifest, dependencyId);
    if (dependency?.status !== "product_useful") {
      errors.push(`${tier.id} dependency is not ProductUseful: ${dependencyId}`);
    }
  }
  for (const proposal of missingImplementations(tier)) {
    errors.push(`${tier.id} implementation is missing: pi_${proposal}`);
  }
  if (!existsSync(join(ROOT, tier.acceptance_lane))) {
    errors.push(`${tier.id} acceptance lane is missing: ${tier.acceptance_lane}`);
  }
  return errors;
}

export function tierSummary(manifest = readTierManifest()) {
  return manifest.tiers.map((tier) => ({
    id: tier.id,
    name: tier.name,
    status: tier.status,
    proposals: tier.proposals.length,
    implemented: implementedPackagesForTier(tier).filter((pkg) =>
      tier.proposals.includes(pkg.shortName),
    ).length,
    remaining: missingImplementations(tier).length,
    open_blockers: unresolvedBlockers(tier).length,
  }));
}
