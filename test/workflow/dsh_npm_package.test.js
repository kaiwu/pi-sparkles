import { afterEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
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
  DSH_OUTPUT_DIR,
  DSH_PACKAGE_NAME,
} from "../../scripts/dsh-bundle.js";
import {
  assertDshNpmPublishable,
  assembleDshNpmRelease,
  dshNpmPackagePlan,
  parseDshNpmPackageArguments,
  verifyDshNpmPackageDirectory,
  verifyDshNpmRelease,
} from "../../scripts/dsh-npm-package.js";
import { readTierManifest } from "../../scripts/tiers.js";

const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), "dsh-sparkles-npm-test-"));
  temporaryDirectories.push(directory);
  return directory;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function fixturePlugin() {
  return {
    directory: join("/", "unused"),
    shortName: "fixture",
    name: "pi_sparkles_fixture",
    version: "0.1.0",
    metadata: { metadata: { finance: { broker_order_mutation: false } } },
  };
}

function fixturePlan(root, { throughTierId = "T6", releasable = true } = {}) {
  const plugin = fixturePlugin();
  return {
    throughTierId,
    includedTiers: [],
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
    packageName: `dsh-sparkles-${throughTierId.toLowerCase()}-fixture`,
    packageVersion: "0.1.0",
    outputDirectory: join(root, "bundle"),
    npmPackageName: DSH_PACKAGE_NAME,
    bundleDirectory: join(root, "bundle"),
    npmOutputDirectory: join(root, "npm"),
  };
}

function writeFixtureBundle(plan) {
  const directory = plan.bundleDirectory;
  mkdirSync(directory, { recursive: true });
  const indexSource =
    "const plugin = { name: 'dsh-sparkles', inject: ['tools', 'commands'], async apply() {} };\nexport default plugin;\n";
  writeFileSync(join(directory, "index.js"), indexSource);
  writeFileSync(join(directory, "index.js.map"), "{}\n");
  writeFileSync(join(directory, "CONFIGURATION.md"), "# Configuration\n");
  writeFileSync(
    join(directory, "cordis.patch.yml"),
    "- insert:\n    - id: dsh-sparkles\n      name: '@dsh-sparkles/dsh-sparkles'\n",
  );
  writeFileSync(join(directory, "README.md"), "# dsh-sparkles\n");
  writeFileSync(join(directory, "SHA256SUMS"), "");
  writeFileSync(
    join(directory, "package.json"),
    `${JSON.stringify(
      {
        name: DSH_PACKAGE_NAME,
        version: plan.packageVersion,
        type: "module",
        main: "index.js",
        dsh: { bundle: { patch: "./cordis.patch.yml" } },
      },
      null,
      2,
    )}\n`,
  );
  writeFileSync(
    join(directory, "dsh-lock.json"),
    `${JSON.stringify(
      {
        schemaVersion: 1,
        package: { name: DSH_PACKAGE_NAME, version: plan.packageVersion },
        target: plan.throughTierId,
        pluginCount: plan.plugins.length,
        plugins: [],
        indexSha256: sha256(indexSource),
      },
      null,
      2,
    )}\n`,
  );
}

async function buildFixture(plan) {
  writeFixtureBundle(plan);
  return assembleDshNpmRelease(
    plan,
    plan.bundleDirectory,
    plan.npmOutputDirectory,
  );
}

describe("dsh-sparkles npm packaging", () => {
  test("derives the T6 all-in-one bundle and preserves the maturity gate", () => {
    const manifest = readTierManifest();
    const t6 = dshNpmPackagePlan(manifest, "T6");
    expect(t6.npmPackageName).toBe("@dsh-sparkles/dsh-sparkles");
    expect(t6.plugins).toHaveLength(134);
    expect(t6.plugins.some((plugin) => plugin.shortName === "finance_track_status")).toBeFalse();
    expect(t6.excludedPiProposals).toEqual(["finance_track_status"]);
    expect(t6.extraDshPlugins).toEqual([]);
    expect(t6.omittedProposals).toEqual([]);
    expect(t6.partialImplementations).toEqual([]);
    expect(t6.openBlockers).toEqual([]);
    expect(t6.releasable).toBeTrue();

    const t5 = dshNpmPackagePlan(manifest, "T5");
    expect(t5.plugins).toHaveLength(123);
    expect(t5.releasable).toBeTrue();
  });

  test("packs a content-locked tarball with the dsh.bundle manifest", async () => {
    const root = temporaryDirectory();
    const plan = fixturePlan(root);
    const summary = await buildFixture(plan);
    expect(summary).toMatchObject({
      name: "@dsh-sparkles/dsh-sparkles",
      version: "0.1.0",
      throughTierId: "T6",
      pluginCount: 1,
      publishable: true,
    });
    expect(verifyDshNpmRelease(plan.npmOutputDirectory, plan)).toEqual(summary);
    expect(
      verifyDshNpmPackageDirectory(join(plan.npmOutputDirectory, "package"), plan),
    ).toMatchObject({ publishable: true });

    const manifest = JSON.parse(
      readFileSync(
        join(plan.npmOutputDirectory, "package", "package.json"),
        "utf8",
      ),
    );
    expect(manifest.dsh.bundle.patch).toBe("./cordis.patch.yml");
    expect(manifest.main).toBe("./index.js");
    expect(manifest.dshSparkles).toEqual({
      aggregateThrough: "T6",
      maturity: "product_useful_aggregate",
      pluginCount: 1,
      omittedProposalCount: 0,
      partialImplementationCount: 0,
      openBlockerCount: 0,
      excludedPiProposalCount: 0,
      extraDshPluginCount: 0,
      publishable: true,
      brokerOrderMutation: false,
    });
    expect(manifest.dependencies).toEqual({ "pdfjs-dist": "6.2.108" });
    expect(manifest.peerDependencies).toEqual({
      "@deepseek-ai/dsh-tools": "*",
      "@deepseek-ai/dsh-commands": "*",
    });
    expect(manifest.scripts).toBeUndefined();
    expect(manifest.publishConfig).toEqual({
      access: "public",
      registry: "https://registry.npmjs.org/",
    });
    expect(manifest.keywords).toContain("deepseek-harness");
    expect(manifest.homepage).toBe("https://sparkes.extensio.cn");

    const packageReadme = readFileSync(
      join(plan.npmOutputDirectory, "package", "README.md"),
      "utf8",
    );
    expect(packageReadme).toContain("## Install");
    expect(packageReadme).toContain("dsh plugin --profile <name> add @dsh-sparkles/dsh-sparkles");
    expect(packageReadme).toContain("## Boundaries");
    expect(() => assertDshNpmPublishable(summary)).not.toThrow();

    const rebuilt = await assembleDshNpmRelease(
      plan,
      plan.bundleDirectory,
      plan.npmOutputDirectory,
    );
    expect(rebuilt.tarballSha256).toBe(summary.tarballSha256);
  });

  test("packs a blocked preview privately and refuses its publish gate", async () => {
    const root = temporaryDirectory();
    const plan = fixturePlan(root, { throughTierId: "T6", releasable: false });
    const summary = await buildFixture(plan);
    const manifest = JSON.parse(
      readFileSync(
        join(plan.npmOutputDirectory, "package", "package.json"),
        "utf8",
      ),
    );
    expect(summary.publishable).toBeFalse();
    expect(manifest.private).toBeTrue();
    expect(manifest.publishConfig).toBeUndefined();
    expect(manifest.dshSparkles).toMatchObject({
      maturity: "blocked_inventory_preview",
      publishable: false,
    });
    expect(() => assertDshNpmPublishable(summary)).toThrow(
      "blocked preview and cannot be published",
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
    expect(() => verifyDshNpmRelease(plan.npmOutputDirectory, plan)).toThrow();
  });

  test("argument parsing mirrors the Pi packager defaults", () => {
    expect(parseDshNpmPackageArguments([])).toMatchObject({
      throughTierId: "T6",
      build: true,
    });
    expect(
      parseDshNpmPackageArguments(["T5", "--no-build", "--install-smoke"]),
    ).toMatchObject({ throughTierId: "T5", build: false, installSmoke: true });
    expect(() => parseDshNpmPackageArguments(["T4"])).toThrow(
      "target must be T5 or T6",
    );
  });

  test("the real T6 bundle directory is the pack source", () => {
    expect(DSH_OUTPUT_DIR.endsWith("dist/dsh/dsh-sparkles")).toBeTrue();
  });
});
