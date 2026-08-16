// DSH all-in-one plugin bundler.
//
// A dedicated builder that turns the pi-sparkles ledger (T1–T6, 135 proposals)
// into one npm bundle DeepSeek Harness can load: a Cordis plugin package whose
// manifest declares `dsh.bundle.patch`, with every compiled Pi extension
// mounted behind a Pi-API facade over the Harness `ctx` (tools -> ctx.tools,
// commands -> ctx.commands).
//
// Not every Pi plugin is DSH-compatible: dsh/bundle.json declares which ledger
// proposals are `exclude_pi` (Pi-specific surfaces such as the TUI statusline)
// and which `extra_dsh` plugins (future DSH-dedicated packages) are added. The
// bundle ships the ledger minus exclusions plus extras.
//
// The existing Pi builder/bundler (scripts/build.js, scripts/aggregate-bundle.js)
// is untouched: this script consumes its `dist/<plugin>/index.js` artifacts
// (auto-building any missing one) and never changes tier state.
//
//   bun run dsh:bundle            # build the T6 (T1–T6) all-in-one DSH bundle
//   bun run dsh:bundle -- T5      # prior release boundary
//   bun run dsh:bundle -- --no-build
//
// Output: dist/dsh/dsh-sparkles/  (install with:
//   dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles)

import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { buildPlugin } from "./build.js";
import {
  aggregateBundlePlan,
  DEFAULT_AGGREGATE_TARGET,
} from "./aggregate-bundle.js";
import { DIST_DIR, ROOT, WORK_DIR, plugins } from "./modules.js";
import { readTierManifest } from "./tiers.js";

const ALLOWED_TARGETS = new Set(["T5", "T6"]);
export const DSH_PACKAGE_NAME = "@dsh-sparkles/dsh-sparkles";
export const DSH_PLUGIN_NAME = "dsh-sparkles";
export const DSH_OUTPUT_DIR = join(DIST_DIR, "dsh", "dsh-sparkles");
const DSH_MANIFEST_PATH = join(ROOT, "dsh", "bundle.json");
const ENTRY_DIR = join(WORK_DIR, "dsh");
const ENTRY_PATH = join(ENTRY_DIR, "entry.mjs");
const LOCK_SCHEMA_VERSION = 1;
const PDFJS_VERSION = "6.2.108";

/** Every file the DSH bundle emits; the npm packager consumes this inventory. */
export const DSH_BUNDLE_FILES = [
  "CONFIGURATION.md",
  "README.md",
  "SHA256SUMS",
  "cordis.patch.yml",
  "dsh-lock.json",
  "index.js",
  "index.js.map",
  "package.json",
];

const PACKAGE_NAME = DSH_PACKAGE_NAME;
const OUTPUT_DIR = DSH_OUTPUT_DIR;

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sha256File(path) {
  return sha256(readFileSync(path));
}

function moduleSpecifier(fromDirectory, target) {
  const path = relative(fromDirectory, target).split(sep).join("/");
  return path.startsWith(".") ? path : `./${path}`;
}

function rootVersion() {
  const manifest = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8"));
  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    throw new Error("Root package.json has no version");
  }
  return manifest.version;
}

function assertSafeOutput() {
  const output = resolve(OUTPUT_DIR);
  if (output === ROOT || output === DIST_DIR) {
    throw new Error(`Refusing DSH bundle output at protected path: ${output}`);
  }
  if (existsSync(output) && !lstatSync(output).isDirectory()) {
    throw new Error(`Refusing to replace non-directory DSH output: ${output}`);
  }
  // Fresh output or a directory whose lock matches ours.
  if (existsSync(output)) {
    const lockPath = join(output, "dsh-lock.json");
    if (!existsSync(lockPath)) {
      throw new Error(`Refusing to replace a directory without dsh-lock.json: ${output}`);
    }
    let lock;
    try {
      lock = JSON.parse(readFileSync(lockPath, "utf8"));
    } catch {
      throw new Error(`Refusing to replace an invalid DSH output: ${output}`);
    }
    if (
      lock.schemaVersion !== LOCK_SCHEMA_VERSION ||
      lock.package?.name !== PACKAGE_NAME ||
      lock.target !== targetForLock()
    ) {
      throw new Error(`Refusing to replace a different DSH output: ${output}`);
    }
  }
}

let lockTarget = "T6";
function targetForLock() {
  return lockTarget;
}

/**
 * The DSH bundle inventory: which Pi ledger proposals are excluded from the
 * Harness distribution and which DSH-dedicated plugins are added. See
 * dsh/bundle.json.
 */
export function readDshManifest() {
  const manifest = JSON.parse(readFileSync(DSH_MANIFEST_PATH, "utf8"));
  const exclude = Array.isArray(manifest.exclude_pi) ? manifest.exclude_pi : [];
  const extra = Array.isArray(manifest.extra_dsh) ? manifest.extra_dsh : [];
  if (
    exclude.some((name) => typeof name !== "string" || name.trim() === "") ||
    extra.some((name) => typeof name !== "string" || name.trim() === "")
  ) {
    throw new Error("DSH bundle manifest must list plugin short names as strings");
  }
  return { schemaVersion: manifest.schema_version ?? 1, excludePi: [...exclude], extraDsh: [...extra] };
}

export function dshBundlePlan(throughTierId = DEFAULT_AGGREGATE_TARGET) {
  const target = throughTierId.toUpperCase();
  if (!ALLOWED_TARGETS.has(target)) {
    throw new Error("DSH bundle target must be T5 or T6");
  }
  lockTarget = target;
  const base = aggregateBundlePlan(readTierManifest(), target);
  const manifest = readDshManifest();

  const baseByName = new Map(base.plugins.map((plugin) => [plugin.shortName, plugin]));
  const exclude = new Set(manifest.excludePi);
  for (const name of manifest.excludePi) {
    if (!baseByName.has(name)) {
      throw new Error(`DSH bundle excludes unknown ledger proposal: ${name}`);
    }
  }
  const available = new Map(plugins().map((plugin) => [plugin.shortName, plugin]));
  const extras = manifest.extraDsh.map((name) => {
    const plugin = available.get(name);
    if (!plugin) throw new Error(`DSH bundle extra plugin not found: ${name}`);
    if (baseByName.has(name)) {
      throw new Error(`DSH bundle extra plugin duplicates a ledger proposal: ${name}`);
    }
    return plugin;
  });

  const included = [
    ...base.plugins.filter((plugin) => !exclude.has(plugin.shortName)),
    ...extras,
  ];
  return {
    ...base,
    plugins: included,
    pluginTiers: { ...base.pluginTiers },
    excludedPiProposals: manifest.excludePi,
    extraDshPlugins: manifest.extraDsh,
  };
}

function entrySource(plan) {
  const imports = plan.plugins.map((plugin, index) =>
    `import extension${index} from ${JSON.stringify(
      moduleSpecifier(ENTRY_DIR, join(DIST_DIR, plugin.shortName, "index.js")),
    )};`,
  );
  const records = plan.plugins.map(
    (plugin, index) =>
      `  [${JSON.stringify(plugin.shortName)}, extension${index}],`,
  );
  return `${imports.join("\n")}

import { createPlugin } from ${JSON.stringify(
    moduleSpecifier(ENTRY_DIR, join(ROOT, "dsh", "plugin.mjs")),
  )};

const extensions = [
${records.join("\n")}
];

export default createPlugin(extensions, ${JSON.stringify(DSH_PLUGIN_NAME)});
`;
}

function pluginRecord(plan, plugin) {
  const finance = plugin.metadata.metadata?.finance ?? {};
  return {
    tierId: plan.pluginTiers[plugin.shortName] ?? null,
    shortName: plugin.shortName,
    gleamPackage: plugin.name,
    version: plugin.version,
    sourceArtifactSha256: sha256File(
      join(DIST_DIR, plugin.shortName, "index.js"),
    ),
    provider: typeof finance.provider === "string" ? finance.provider : null,
  };
}

function environmentVariables(plugin) {
  const names = new Set();
  const patterns = [
    /(?:process|Bun)\.env\.([A-Z][A-Z0-9_]*)/g,
    /(?:process|Bun)\.env\[['"]([A-Z][A-Z0-9_]*)['"]\]/g,
  ];
  const visit = (directory) => {
    if (!existsSync(directory)) return;
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) visit(path);
      if (entry.isFile() && /\.(?:js|mjs)$/.test(entry.name)) {
        const source = readFileSync(path, "utf8");
        for (const pattern of patterns) {
          for (const match of source.matchAll(pattern)) names.add(match[1]);
        }
      }
    }
  };
  visit(join(plugin.directory, "src"));
  return [...names].sort();
}

function patchSource(plan) {
  return `# Pi Sparkles finance tools as one DeepSeek Harness bundle.
#
# Installed with:
#   dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles
# The profile launcher applies this bundle layer over the profile root, then
# the user's own cordis.patch.yml (last write wins per row).
#
# Optional per-bundle configuration (edit the profile's cordis.patch.yml or
# pass --patch): a \`flags\` map overrides Pi flag defaults, e.g.
#   config:
#     flags:
#       finance-currency: EUR
# Environment variables (AGENT_CONTACT, TUSHARE_TOKEN, ALPACA_API_KEY_ID, ...)
# are read from the process environment at call time; see CONFIGURATION.md.

- insert:
    - id: ${DSH_PLUGIN_NAME}
      name: ${JSON.stringify(PACKAGE_NAME)}
      config:
        flags: {}
`;
}

function configurationSource(plan) {
  const names = [
    ...new Set(
      plan.plugins.flatMap((plugin) => environmentVariables(plugin)),
    ),
  ].sort();
  const excluded = plan.excludedPiProposals ?? [];
  const extras = plan.extraDshPlugins ?? [];
  const lines = [
    "# DSH bundle configuration",
    "",
    `Bundled plugins: ${plan.plugins.length} (${plan.throughTierId} ledger)`,
    ...(excluded.length > 0
      ? [
          "",
          "## Excluded Pi plugins",
          "",
          ...excluded.map((name) => `- \`${name}\``),
        ]
      : []),
    ...(extras.length > 0
      ? [
          "",
          "## DSH-dedicated plugins",
          "",
          ...extras.map((name) => `- \`${name}\``),
        ]
      : []),
    "",
    "## Environment variables read at call time",
    "",
    ...names.map((name) => `- \`${name}\``),
    "",
    "Credentials and provider entitlements are caller-owned runtime inputs and",
    "are never read, written, or persisted by this bundle.",
  ];
  return `${lines.join("\n")}\n`;
}

function readmeSource(plan) {
  const version = rootVersion();
  return `# @dsh-sparkles/dsh-sparkles

One DeepSeek Harness bundle registering the complete pi-sparkles
${plan.throughTierId} ledger: ${plan.plugins.length} read-only finance
evidence tools (quotes, OHLCV, calendars, rules, fundamentals, SEC filings,
portfolio, quant, macro, tape review, ...) as native Harness tools behind a
single Pi-API compatibility facade. No plugin can place, route, cancel,
replace, or otherwise mutate a paper or live order.

## Install

\`\`\`sh
bun run dsh:bundle
dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles
\`\`\`

The bundle patch layer is applied on the next \`dsh --profile <name>\` boot.
Uninstall with \`dsh plugin --profile <name> remove @dsh-sparkles/dsh-sparkles\`.

## Usage

Set the same caller-owned environment variables the Pi distribution uses
(see CONFIGURATION.md): \`AGENT_CONTACT\` is required by every adapter;
\`TUSHARE_TOKEN\`, \`ALPACA_API_KEY_ID\`, \`ALPACA_API_SECRET_KEY\`,
\`OPENFIGI_API_KEY\`, \`TWELVE_DATA_API_KEY\`, and \`FRED_API_KEY\` are optional
credentials. Then ask the agent for evidence, e.g. "get a current quote for
AAPL" or "compare SMA/RSI/ATR for 600519.SH".

## Behavior notes

- Pi-specific surfaces are excluded from this distribution (see CONFIGURATION.md
  for the exact list); the TUI statusline/track-navigation plugin is not
  shipped, and DSH-dedicated replacements are added separately over time.
- Tools register through \`ctx.tools\` and are validated against the DSH
  schema subset; the embedded Pi decoders still enforce the full argument
  contract (lengths, ranges, enums) at call time.
- Commands register through \`ctx.commands\`; their text output is the command
  result.
- Session persistence (journal/watchlist custom entries) is in-memory per
  process; cross-restart persistence is not claimed.
- \`hasUI\` is false: any remaining statusline/notification surfaces are inert.
- Provider identity, entitlement, and completeness are never authenticated by
  this bundle; providers and credentials stay caller-owned.

## Build

\`bun run dsh:bundle\` consumes the compiled artifacts from the ordinary Pi
build (\`bun run build\`) and bundles them into this package. The Pi
builder/bundler and the tier ledger are untouched.
`;
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function hashTree(directory) {
  const files = [];
  const visit = (current) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const path = join(current, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile() && entry.name !== "SHA256SUMS") files.push(path);
    }
  };
  visit(directory);
  return files
    .map((path) => `${sha256File(path)}  ${relative(directory, path).split(sep).join("/")}`)
    .sort()
    .join("\n");
}

export async function buildDshBundle(throughTierId = DEFAULT_AGGREGATE_TARGET) {
  const plan = dshBundlePlan(throughTierId);
  assertSafeOutput();

  // Consume the Pi builder's artifacts, auto-building any missing plugin.
  const missing = plan.plugins.filter(
    (plugin) => !existsSync(join(DIST_DIR, plugin.shortName, "index.js")),
  );
  for (const plugin of missing) {
    console.log(`dsh:bundle building missing artifact ${plugin.shortName}`);
    await buildPlugin(plugin);
  }

  mkdirSync(ENTRY_DIR, { recursive: true });
  writeFileSync(ENTRY_PATH, entrySource(plan));

  rmSync(OUTPUT_DIR, { recursive: true, force: true });
  mkdirSync(OUTPUT_DIR, { recursive: true });

  const result = await Bun.build({
    entrypoints: [ENTRY_PATH],
    outdir: OUTPUT_DIR,
    naming: "index.js",
    format: "esm",
    target: "node",
    minify: false,
    sourcemap: "external",
    metafile: true,
    external: ["pdfjs-dist", "pdfjs-dist/*"],
  });
  if (!result.success) {
    for (const log of result.logs) console.error(log);
    throw new Error(`DSH bundle failed: ${result.logs.length} build errors`);
  }

  const version = rootVersion();
  const manifest = {
    name: PACKAGE_NAME,
    version,
    description: `All-in-one DeepSeek Harness plugin for the pi-sparkles ${plan.throughTierId} finance evidence ledger (${plan.plugins.length} tools)`,
    type: "module",
    main: "index.js",
    exports: {
      ".": "./index.js",
      "./cordis.patch.yml": "./cordis.patch.yml",
      "./package.json": "./package.json",
    },
    files: [
      "index.js",
      "index.js.map",
      "cordis.patch.yml",
      "CONFIGURATION.md",
      "README.md",
      "dsh-lock.json",
      "SHA256SUMS",
    ],
    dependencies: { "pdfjs-dist": PDFJS_VERSION },
    peerDependencies: {
      "@deepseek-ai/dsh-tools": "*",
      "@deepseek-ai/dsh-commands": "*",
    },
    dsh: { bundle: { patch: "./cordis.patch.yml" } },
    license: "Apache-2.0",
  };

  writeJson(join(OUTPUT_DIR, "package.json"), manifest);
  writeFileSync(join(OUTPUT_DIR, "cordis.patch.yml"), patchSource(plan));
  writeFileSync(join(OUTPUT_DIR, "CONFIGURATION.md"), configurationSource(plan));
  writeFileSync(join(OUTPUT_DIR, "README.md"), readmeSource(plan));

  const lock = {
    schemaVersion: LOCK_SCHEMA_VERSION,
    package: { name: PACKAGE_NAME, version },
    target: plan.throughTierId,
    pluginCount: plan.plugins.length,
    plugins: plan.plugins.map((plugin) => pluginRecord(plan, plugin)),
    excludedPiProposals: plan.excludedPiProposals,
    extraDshPlugins: plan.extraDshPlugins,
    omittedProposals: plan.omittedProposals,
    partialImplementations: plan.partialImplementations,
    openBlockers: plan.openBlockers,
    maturity: plan.maturity,
    indexSha256: sha256File(join(OUTPUT_DIR, "index.js")),
  };
  writeJson(join(OUTPUT_DIR, "dsh-lock.json"), lock);
  writeFileSync(join(OUTPUT_DIR, "SHA256SUMS"), `${hashTree(OUTPUT_DIR)}\n`);

  const excluded = plan.excludedPiProposals.length;
  const extra = plan.extraDshPlugins.length;
  console.log(
    `DSH bundle ${PACKAGE_NAME}@${version} (${plan.throughTierId}, ${plan.plugins.length} plugins${excluded > 0 ? `, ${excluded} Pi plugin${excluded === 1 ? "" : "s"} excluded` : ""}${extra > 0 ? `, ${extra} DSH extra${extra === 1 ? "" : "s"}` : ""}) at ${OUTPUT_DIR}`,
  );
}

export function parseDshBundleArguments(args) {
  const options = { build: true, target: DEFAULT_AGGREGATE_TARGET, help: false };
  for (const arg of args) {
    if (arg === "--no-build") options.build = false;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else if (!arg.startsWith("--")) options.target = arg;
    else throw new Error(`Unknown dsh:bundle option: ${arg}`);
  }
  return options;
}

function usage() {
  return `usage: bun run dsh:bundle [-- T5|T6] [--no-build]

Build the all-in-one DeepSeek Harness plugin for the pi-sparkles ledger.
T6 (default) bundles the cumulative T1-T6 inventory; T5 selects the prior
release boundary. --no-build reuses existing dist artifacts only.
Output: ${OUTPUT_DIR}`;
}

/**
 * Verify a built DSH bundle directory against its plan and lock, without
 * rebuilding. Shared by the npm packager so the packed tarball always comes
 * from a content-locked bundle.
 */
export function verifyDshBundle(directory, plan) {
  const root = resolve(directory);
  const actual = readdirSync(root).sort().join("\n");
  const expected = [...DSH_BUNDLE_FILES].sort().join("\n");
  if (actual !== expected) {
    throw new Error(
      `DSH bundle file inventory differs:\n${actual}\n--- expected ---\n${expected}`,
    );
  }
  const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
  if (
    manifest.name !== DSH_PACKAGE_NAME ||
    manifest.dsh?.bundle?.patch !== "./cordis.patch.yml" ||
    manifest.main !== "index.js"
  ) {
    throw new Error("DSH bundle manifest is inconsistent");
  }
  const lock = JSON.parse(readFileSync(join(root, "dsh-lock.json"), "utf8"));
  if (
    lock.schemaVersion !== LOCK_SCHEMA_VERSION ||
    lock.package?.name !== DSH_PACKAGE_NAME ||
    lock.target !== plan.throughTierId ||
    lock.pluginCount !== plan.plugins.length ||
    JSON.stringify(lock.excludedPiProposals ?? []) !==
      JSON.stringify(plan.excludedPiProposals ?? []) ||
    JSON.stringify(lock.extraDshPlugins ?? []) !==
      JSON.stringify(plan.extraDshPlugins ?? []) ||
    lock.indexSha256 !== sha256File(join(root, "index.js"))
  ) {
    throw new Error("DSH bundle lock is inconsistent with the bundle content");
  }
  return {
    directory: root,
    name: manifest.name,
    version: manifest.version,
    throughTierId: lock.target,
    pluginCount: lock.pluginCount,
    maturity: lock.maturity,
    publishable: plan.releasable,
  };
}

if (import.meta.main) {
  try {
    const options = parseDshBundleArguments(process.argv.slice(2));
    if (options.help) {
      console.log(usage());
      process.exit(0);
    }
    if (!options.build) {
      // No build flag path: only consume existing artifacts.
      const plan = dshBundlePlan(options.target);
      for (const plugin of plan.plugins) {
        if (!existsSync(join(DIST_DIR, plugin.shortName, "index.js"))) {
          throw new Error(
            `Missing artifact for ${plugin.shortName}; run "bun run dsh:bundle" without --no-build first`,
          );
        }
      }
    }
    await buildDshBundle(options.target);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    console.error(usage());
    process.exit(1);
  }
}
