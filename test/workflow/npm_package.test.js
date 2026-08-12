import { afterEach, describe, expect, test } from "bun:test";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  assembleAggregateBundle,
} from "../../scripts/aggregate-bundle.js";
import {
  assembleNpmRelease,
  assertNpmPublishable,
  npmPackagePlan,
  parseNpmPackageArguments,
  verifyNpmPackageDirectory,
  verifyNpmRelease,
} from "../../scripts/npm-package.js";
import { readTierManifest } from "../../scripts/tiers.js";

const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), "pi-sparkles-npm-test-"));
  temporaryDirectories.push(directory);
  return directory;
}

function fixturePlugin(root) {
  const directory = join(root, "source", "fixture");
  mkdirSync(join(directory, "src"), { recursive: true });
  return {
    directory,
    shortName: "fixture",
    name: "pi_sparkles_fixture",
    version: "0.1.0",
    metadata: {
      metadata: {
        pi: { tested_version: "0.83.0" },
        finance: { broker_order_mutation: false },
      },
    },
  };
}

function fixturePlan(root, { throughTierId = "T5", releasable = true } = {}) {
  const plugin = fixturePlugin(root);
  const artifactDirectory = join(root, "artifacts", plugin.shortName);
  mkdirSync(artifactDirectory, { recursive: true });
  writeFileSync(
    join(artifactDirectory, "index.js"),
    "export default function (api) { api.registerTool({ name: 'fixture_tool' }); }\n",
  );
  const tier = {
    id: throughTierId,
    name: "Fixture",
    status: releasable ? "product_useful" : "blocker_resolution",
    product_outcome: "Fixture outcome",
    track_profile: "Fixture track",
    proposals: [plugin.shortName],
    extra_packages: [],
  };
  const aggregateDirectory = join(root, "aggregate");
  return {
    throughTierId,
    includedTiers: [tier],
    plugins: [plugin],
    pluginTiers: { fixture: throughTierId },
    omittedProposals: [],
    partialImplementations: [],
    openBlockers: [],
    excludedExtraPackages: [],
    releasable,
    maturity: releasable
      ? "product_useful_aggregate"
      : "blocked_inventory_preview",
    packageName: `pi-sparkles-aggregate-${throughTierId.toLowerCase()}-fixture`,
    packageVersion: "0.1.0",
    outputDirectory: aggregateDirectory,
    aggregateDirectory,
    npmPackageName: "pi-sparkles-all-in-one",
    npmOutputDirectory: join(root, "npm"),
    artifactDirectory: join(root, "artifacts"),
  };
}

async function buildFixture(plan) {
  await assembleAggregateBundle(
    plan,
    plan.artifactDirectory,
    plan.aggregateDirectory,
  );
  return assembleNpmRelease(
    plan,
    plan.aggregateDirectory,
    plan.npmOutputDirectory,
  );
}

describe("all-in-one npm packaging", () => {
  test("derives either selected aggregate while preserving the current release gate", () => {
    const manifest = readTierManifest();
    const t5 = npmPackagePlan(manifest, "T5");
    expect(t5.npmPackageName).toBe("pi-sparkles-all-in-one");
    expect(t5.plugins).toHaveLength(124);
    expect(t5.releasable).toBeTrue();

    const t6 = npmPackagePlan(manifest, "T6");
    expect(t6.npmPackageName).toBe("pi-sparkles-all-in-one");
    expect(t6.plugins).toHaveLength(133);
    expect(t6.releasable).toBeFalse();
    expect(t6.omittedProposals).toHaveLength(2);
  });

  test("packs a content-locked npm tarball with one Pi entrypoint", async () => {
    const root = temporaryDirectory();
    const plan = fixturePlan(root);
    const summary = await buildFixture(plan);
    expect(summary).toMatchObject({
      name: "pi-sparkles-all-in-one",
      version: "0.1.0",
      throughTierId: "T5",
      pluginCount: 1,
      publishable: true,
    });
    expect(verifyNpmRelease(plan.npmOutputDirectory, plan)).toEqual(summary);
    expect(
      verifyNpmPackageDirectory(
        join(plan.npmOutputDirectory, "package"),
        plan,
      ),
    ).toMatchObject({ publishable: true });

    const packageManifest = JSON.parse(
      readFileSync(
        join(plan.npmOutputDirectory, "package", "package.json"),
        "utf8",
      ),
    );
    expect(packageManifest.pi.extensions).toEqual(["./index.js"]);
    expect(packageManifest.dependencies).toEqual({
      "pdfjs-dist": "6.2.108",
    });
    expect(packageManifest.scripts).toBeUndefined();
    expect(packageManifest.publishConfig).toEqual({
      access: "public",
      registry: "https://registry.npmjs.org/",
    });
    expect(() => assertNpmPublishable(summary)).not.toThrow();

    const rebuilt = await assembleNpmRelease(
      plan,
      plan.aggregateDirectory,
      plan.npmOutputDirectory,
    );
    expect(rebuilt.tarballSha256).toBe(summary.tarballSha256);
  });

  test("packs T6-format inventory privately and refuses its publish gate", async () => {
    const root = temporaryDirectory();
    const plan = fixturePlan(root, {
      throughTierId: "T6",
      releasable: false,
    });
    const summary = await buildFixture(plan);
    const packageManifest = JSON.parse(
      readFileSync(
        join(plan.npmOutputDirectory, "package", "package.json"),
        "utf8",
      ),
    );
    expect(summary.publishable).toBeFalse();
    expect(packageManifest.private).toBeTrue();
    expect(packageManifest.publishConfig).toBeUndefined();
    expect(() => assertNpmPublishable(summary)).toThrow(
      "T6 npm aggregate is a blocked preview and cannot be published",
    );
  });

  test("detects package tampering after npm packing", async () => {
    const root = temporaryDirectory();
    const plan = fixturePlan(root);
    await buildFixture(plan);
    writeFileSync(
      join(plan.npmOutputDirectory, "package", "index.js"),
      "export default function () {}\n",
    );
    expect(() => verifyNpmRelease(plan.npmOutputDirectory, plan)).toThrow();
  });

  test("parses an explicit T5 or T6 target", () => {
    expect(parseNpmPackageArguments([])).toMatchObject({
      throughTierId: "T5",
      build: true,
    });
    expect(parseNpmPackageArguments(["T6", "--no-build"])).toMatchObject({
      throughTierId: "T6",
      build: false,
    });
    expect(() => parseNpmPackageArguments(["T4"])).toThrow(
      "target must be T5 or T6",
    );
  });
});
