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
import { pathToFileURL } from "node:url";
import {
  aggregateBundlePlan,
  assembleAggregateBundle,
  parseAggregateArguments,
  verifyAggregateBundle,
} from "../../scripts/aggregate-bundle.js";
import { readTierManifest } from "../../scripts/tiers.js";

const temporaryDirectories = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function temporaryDirectory() {
  const directory = mkdtempSync(join(tmpdir(), "pi-sparkles-aggregate-"));
  temporaryDirectories.push(directory);
  return directory;
}

function fixturePlugin(root, shortName) {
  const directory = join(root, "sources", shortName);
  mkdirSync(join(directory, "src"), { recursive: true });
  return {
    directory,
    shortName,
    name: `pi_sparkles_${shortName}`,
    version: "0.1.0",
    metadata: { metadata: { finance: { broker_order_mutation: false } } },
  };
}

function fixtureArtifact(root, shortName, body) {
  const directory = join(root, shortName);
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "index.js"), body);
}

function fixturePlan(root, plugins) {
  return {
    throughTierId: "T5",
    includedTiers: [{
      id: "T5",
      name: "Fixture tier",
      status: "product_useful",
      product_outcome: "Fixture outcome",
      track_profile: "Fixture track",
      proposals: plugins.map((plugin) => plugin.shortName),
      extra_packages: [],
    }],
    plugins,
    pluginTiers: Object.fromEntries(
      plugins.map((plugin) => [plugin.shortName, "T5"]),
    ),
    omittedProposals: [],
    partialImplementations: [],
    openBlockers: [],
    excludedExtraPackages: [],
    releasable: true,
    maturity: "product_useful_aggregate",
    packageName: "pi-sparkles-aggregate-fixture",
    packageVersion: "0.1.0",
    outputDirectory: join(root, "package"),
  };
}

describe("single-entrypoint tier aggregate", () => {
  test("plans every T1-T5 proposal and an honest optional T6 preview", () => {
    const manifest = readTierManifest();
    const t5 = aggregateBundlePlan(manifest, "T5");
    expect(t5.includedTiers.map((tier) => tier.id)).toEqual([
      "T1",
      "T2",
      "T3",
      "T4",
      "T5",
    ]);
    expect(t5.plugins).toHaveLength(124);
    expect(t5.omittedProposals).toEqual([]);
    expect(t5.releasable).toBeTrue();

    const t6 = aggregateBundlePlan(manifest, "T6");
    expect(t6.plugins).toHaveLength(133);
    expect(t6.omittedProposals).toEqual([
      { tierId: "T6", proposal: "stock_tape" },
      { tierId: "T6", proposal: "cn_broker_readonly" },
    ]);
    expect(t6.partialImplementations).toHaveLength(7);
    expect(t6.openBlockers.map((blocker) => blocker.id)).toEqual([
      "T6-INTRADAY-PROVIDERS",
    ]);
    expect(t6.releasable).toBeFalse();
    expect(t6.maturity).toBe("blocked_inventory_preview");
  });

  test("targets the guarded T6 next release by default and keeps T5 explicit", () => {
    expect(parseAggregateArguments([])).toMatchObject({
      throughTierId: "T6",
      build: true,
      verifyOnly: false,
    });
    expect(parseAggregateArguments(["T5", "--no-build"])).toMatchObject({
      throughTierId: "T5",
      build: false,
    });
    expect(() => parseAggregateArguments(["T4"])).toThrow(
      "must be T5 or T6",
    );
  });

  test("builds one Pi entrypoint and preserves deterministic initialization", async () => {
    const root = temporaryDirectory();
    const artifacts = join(root, "artifacts");
    const alpha = fixturePlugin(root, "alpha");
    const beta = fixturePlugin(root, "beta");
    writeFileSync(
      join(alpha.directory, "src", "transport.mjs"),
      "export const token = process.env.ALPHA_TOKEN;\n",
    );
    fixtureArtifact(
      artifacts,
      "alpha",
      "export default async function (api) { api.registerTool({ name: 'alpha_tool' }); }\n",
    );
    fixtureArtifact(
      artifacts,
      "beta",
      "export default function (api) { api.registerCommand('beta_command', {}); }\n",
    );
    const plan = fixturePlan(root, [alpha, beta]);
    const summary = await assembleAggregateBundle(
      plan,
      artifacts,
      plan.outputDirectory,
    );
    expect(summary).toMatchObject({
      throughTierId: "T5",
      pluginCount: 2,
      releasable: true,
    });
    expect(verifyAggregateBundle(plan.outputDirectory, plan)).toEqual(summary);
    const manifest = JSON.parse(
      readFileSync(join(plan.outputDirectory, "package.json"), "utf8"),
    );
    expect(manifest.pi.extensions).toEqual(["./index.js"]);
    expect(manifest.piSparkles).toEqual({
      aggregateThrough: "T5",
      maturity: "product_useful_aggregate",
      pluginCount: 2,
      omittedProposalCount: 0,
      partialImplementationCount: 0,
      openBlockerCount: 0,
      publishable: true,
      brokerOrderMutation: false,
    });
    expect(manifest.peerDependencies).toMatchObject({
      "@earendil-works/pi-coding-agent": "*",
      typebox: "*",
    });
    const lock = JSON.parse(
      readFileSync(join(plan.outputDirectory, "aggregate-lock.json"), "utf8"),
    );
    expect(lock.plugins[0].environmentVariables).toEqual(["ALPHA_TOKEN"]);
    expect(
      readFileSync(join(plan.outputDirectory, "CONFIGURATION.md"), "utf8"),
    ).toContain("`ALPHA_TOKEN`");

    const registrations = [];
    const module = await import(
      `${pathToFileURL(join(plan.outputDirectory, "index.js")).href}?fixture=${Math.random()}`
    );
    await module.default({
      registerTool(definition) {
        registrations.push(`tool:${definition.name}`);
      },
      registerCommand(name) {
        registrations.push(`command:${name}`);
      },
    });
    expect(registrations).toEqual(["tool:alpha_tool", "command:beta_command"]);
  });

  test("fails before forwarding a duplicate named registration", async () => {
    const root = temporaryDirectory();
    const artifacts = join(root, "artifacts");
    const alpha = fixturePlugin(root, "alpha");
    const beta = fixturePlugin(root, "beta");
    const duplicate =
      "export default function (api) { api.registerTool({ name: 'shared_tool' }); }\n";
    fixtureArtifact(artifacts, "alpha", duplicate);
    fixtureArtifact(artifacts, "beta", duplicate);
    const plan = fixturePlan(root, [alpha, beta]);
    await assembleAggregateBundle(plan, artifacts, plan.outputDirectory);
    const module = await import(
      `${pathToFileURL(join(plan.outputDirectory, "index.js")).href}?collision=${Math.random()}`
    );
    const forwarded = [];
    await expect(
      module.default({
        registerTool(definition) {
          forwarded.push(definition.name);
        },
      }),
    ).rejects.toThrow(
      "Aggregate registration collision for registerTool 'shared_tool': alpha and beta",
    );
    expect(forwarded).toEqual(["shared_tool"]);
  });

  test("refuses to replace a directory that is not an aggregate output", async () => {
    const root = temporaryDirectory();
    const artifacts = join(root, "artifacts");
    const alpha = fixturePlugin(root, "alpha");
    fixtureArtifact(
      artifacts,
      "alpha",
      "export default function () {}\n",
    );
    const plan = fixturePlan(root, [alpha]);
    const unrelated = join(root, "unrelated");
    mkdirSync(unrelated);
    writeFileSync(join(unrelated, "keep.txt"), "user data\n");

    await expect(
      assembleAggregateBundle(plan, artifacts, unrelated),
    ).rejects.toThrow("without an aggregate lock");
    expect(readFileSync(join(unrelated, "keep.txt"), "utf8")).toBe(
      "user data\n",
    );
  });
});
