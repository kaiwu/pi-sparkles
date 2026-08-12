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
import { piInstallArguments } from "../../scripts/tier-install.js";
import {
  assembleTierPackage,
  tierDependencyClosure,
  tierPackagePlan,
  verifyTierPackage,
} from "../../scripts/tier-package.js";
import { readTierManifest, tierById } from "../../scripts/tiers.js";

const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), "pi-sparkles-tier-package-"));
  temporaryDirectories.push(directory);
  return directory;
}

function fixturePlugin(root, shortName, environmentSource = "") {
  const directory = join(root, "sources", shortName);
  mkdirSync(join(directory, "src"), { recursive: true });
  writeFileSync(join(directory, "src", "environment.mjs"), environmentSource);
  return {
    directory,
    shortName,
    name: `pi_sparkles_${shortName}`,
    version: "0.1.0",
    metadata: {
      metadata: {
        pi: { tested_version: "0.83.0" },
        finance: { provider: `${shortName}-provider`, access: "read-only" },
      },
    },
  };
}

function fixtureArtifact(root, shortName) {
  const directory = join(root, shortName);
  mkdirSync(directory, { recursive: true });
  writeFileSync(
    join(directory, "index.js"),
    `export default function ${shortName}() {}\n//# sourceMappingURL=index.js.map\n`,
  );
  writeFileSync(join(directory, "index.js.map"), "{}\n");
  writeFileSync(join(directory, "build.json"), "{}\n");
  writeFileSync(join(directory, "metafile.json"), "{}\n");
}

describe("plain Pi tier packaging", () => {
  test("plans cumulative ProductUseful tiers and refuses unfinished tiers", () => {
    const manifest = readTierManifest();
    const t1 = tierPackagePlan(manifest, "T1");
    expect(t1.includedTiers.map((tier) => tier.id)).toEqual(["T1"]);
    expect(t1.plugins).toHaveLength(45);
    expect(t1.excludedExtraPackages).toEqual([
      "cn_setup",
      "hello",
      "hk_setup",
      "lifecycle",
      "safety_gate",
    ]);
    expect(t1.plugins.map((plugin) => plugin.shortName)).not.toContain("hello");
    const t2Tier = tierById(manifest, "T2");
    if (t2Tier.status === "product_useful") {
      const t2 = tierPackagePlan(manifest, "T2");
      expect(t2.includedTiers.map((tier) => tier.id)).toEqual(["T1", "T2"]);
      expect(t2.plugins).toHaveLength(90);
      expect(t2.excludedExtraPackages).toEqual([
        "cn_setup",
        "hello",
        "hk_setup",
        "lifecycle",
        "safety_gate",
        "cn_fundamentals",
        "hk_fundamentals",
      ]);
      expect(t2.plugins.map((plugin) => plugin.shortName)).not.toContain(
        "cn_fundamentals",
      );
    } else {
      expect(() => tierPackagePlan(manifest, "T2")).toThrow(
        "only ProductUseful tiers can be packaged",
      );
    }
    const t3 = tierPackagePlan(manifest, "T3");
    expect(t3.includedTiers.map((tier) => tier.id)).toEqual([
      "T1",
      "T2",
      "T3",
    ]);
    expect(t3.plugins).toHaveLength(101);
    expect(t3.plugins.map((plugin) => plugin.shortName)).toContain(
      "finance_alerts",
    );
    expect(t3.plugins.map((plugin) => plugin.shortName)).not.toContain(
      "cn_fundamentals",
    );
    expect(() => tierPackagePlan(manifest, "T4")).toThrow(
      "only ProductUseful tiers can be packaged",
    );
  });

  test("orders dependency tiers before the selected product", () => {
    const manifest = readTierManifest();
    expect(
      tierDependencyClosure(manifest, tierById(manifest, "T3")).map(
        (tier) => tier.id,
      ),
    ).toEqual(["T1", "T2", "T3"]);
  });

  test("assembles a content-locked package without credential values", () => {
    const root = temporaryDirectory();
    const artifactRoot = join(root, "artifacts");
    const output = join(root, "package");
    const alpha = fixturePlugin(
      root,
      "alpha",
      "export const token = process.env.ALPHA_API_TOKEN ?? '';\n",
    );
    const beta = fixturePlugin(root, "beta");
    fixtureArtifact(artifactRoot, "alpha");
    fixtureArtifact(artifactRoot, "beta");
    const plan = {
      tier: {
        id: "T9",
        name: "Fixture product",
        status: "product_useful",
        product_outcome: "A fixture user can complete one bounded journey.",
        track_profile: "One fixture profile.",
      },
      includedTiers: [{ id: "T9" }],
      plugins: [alpha, beta],
      excludedExtraPackages: ["reference_demo"],
      packageName: "pi-sparkles-t9",
      packageVersion: "0.1.0",
      outputDirectory: output,
    };

    const prior = process.env.ALPHA_API_TOKEN;
    process.env.ALPHA_API_TOKEN = "must-never-enter-package";
    try {
      const summary = assembleTierPackage(plan, artifactRoot, output);
      expect(summary.extensionCount).toBe(2);
      expect(verifyTierPackage(output)).toEqual(summary);
      const manifest = JSON.parse(
        readFileSync(join(output, "package.json"), "utf8"),
      );
      expect(manifest.pi.extensions).toEqual([
        "./extensions/alpha/index.js",
        "./extensions/beta/index.js",
      ]);
      expect(manifest.license).toBe("Apache-2.0");
      const configuration = readFileSync(
        join(output, "CONFIGURATION.md"),
        "utf8",
      );
      expect(configuration).toContain("ALPHA_API_TOKEN");
      expect(configuration).not.toContain("must-never-enter-package");
      expect(readFileSync(join(output, "tier-lock.json"), "utf8")).not.toContain(
        "must-never-enter-package",
      );
    } finally {
      if (prior === undefined) delete process.env.ALPHA_API_TOKEN;
      else process.env.ALPHA_API_TOKEN = prior;
    }
  });

  test("rejects changed or untracked package content", () => {
    const root = temporaryDirectory();
    const artifactRoot = join(root, "artifacts");
    const output = join(root, "package");
    const plugin = fixturePlugin(root, "alpha");
    fixtureArtifact(artifactRoot, "alpha");
    const plan = {
      tier: {
        id: "T9",
        name: "Fixture product",
        status: "product_useful",
        product_outcome: "A fixture outcome.",
        track_profile: "One fixture profile.",
      },
      includedTiers: [{ id: "T9" }],
      plugins: [plugin],
      excludedExtraPackages: [],
      packageName: "pi-sparkles-t9",
      packageVersion: "0.1.0",
      outputDirectory: output,
    };
    assembleTierPackage(plan, artifactRoot, output);
    writeFileSync(join(output, "unexpected.txt"), "unlocked\n");
    expect(() => verifyTierPackage(output)).toThrow(
      "checksum inventory is incomplete",
    );
    rmSync(join(output, "unexpected.txt"));
    writeFileSync(join(output, "extensions", "alpha", "index.js"), "changed\n");
    expect(() => verifyTierPackage(output)).toThrow("hash mismatch");
  });

  test("constructs user and project Pi install commands", () => {
    expect(piInstallArguments("./dist/tiers/t1", "user")).toEqual([
      "install",
      expect.stringContaining("/dist/tiers/t1"),
    ]);
    expect(
      piInstallArguments("./dist/tiers/t1", "project", true),
    ).toEqual([
      "install",
      expect.stringContaining("/dist/tiers/t1"),
      "--local",
      "--approve",
    ]);
    expect(() => piInstallArguments(".", "user", true)).toThrow(
      "applies only to project-local",
    );
  });
});
