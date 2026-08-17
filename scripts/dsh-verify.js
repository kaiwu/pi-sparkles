// Verify the DSH bridge against the REAL installed DSH runtime.
//
// The unit tests mirror the dsh-tools schema subset by hand; this script runs
// the actual @deepseek-ai/dsh-tools validator and, when the generated bundle
// exists, boots its real Cordis services, applies the all-in-one plugin, and
// executes a deterministic tool through ToolRuntime. It skips gracefully when
// no `dsh` installation is present.
//
//   bun run dsh:verify

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { DSH_OUTPUT_DIR } from "./dsh-bundle.js";
import {
  OUTPUT_SCHEMA,
  translateParameters,
} from "../dsh/schema-translate.mjs";

function resolveDshRuntime() {
  let dshBin;
  try {
    dshBin = execFileSync("which", ["dsh"], { encoding: "utf8" }).trim();
    const real = execFileSync("readlink", ["-f", dshBin], {
      encoding: "utf8",
    }).trim();
    const dshRoot = dirname(dirname(real));
    const packages = join(dshRoot, "node_modules", "@deepseek-ai");
    const entries = {
      context: join(packages, "cordis", "lib", "index.js"),
      systemPrompt: join(packages, "dsh-system-prompt", "lib", "index.js"),
      tools: join(packages, "dsh-tools", "lib", "index.js"),
      commands: join(packages, "dsh-commands", "lib", "index.js"),
    };
    return Object.values(entries).every(existsSync) ? entries : null;
  } catch {
    return null;
  }
}

// Pi schema constructors mirroring pi_gleam/src/pi/schema_ffi.mjs.
const string = () => ({ type: "string" });
const integer = () => ({ type: "integer" });
const stringEnum = (values) => ({ type: "string", enum: values });
const array = (items) => ({ type: "array", items });
const nullable = (schema) => ({ anyOf: [schema, { type: "null" }] });
const boundedString = (min, max) => ({ type: "string", minLength: min, maxLength: max });
const object = (properties) => ({
  type: "object",
  properties,
  required: Object.entries(properties)
    .filter(([, s]) => s.__required)
    .map(([n]) => n),
  additionalProperties: false,
});
const req = (schema) => ({ ...schema, __required: true });

const REPRESENTATIVE = {
  simple: object({ ticker: req(string()), limit: integer() }),
  nullable: object({ exchange: nullable(stringEnum(["NYSE", "NASDAQ"])) }),
  nested: object({
    listing: req(
      object({ symbol: req(string()), mic: req(stringEnum(["XNYS", "XNAS"])) }),
    ),
    notes: array(boundedString(1, 500)),
    pair: { type: "array", prefixItems: [string(), integer()], minItems: 2, maxItems: 2 },
    meta: { type: "object", additionalProperties: string() },
    extra: {},
  }),
  noParams: object({}),
};

const SAMPLES = {
  simple: { ticker: "AAPL", limit: 3 },
  nullable: { exchange: null },
  nested: {
    listing: { symbol: "AAPL", mic: "XNYS" },
    notes: ["a"],
    pair: ["a", 1],
    meta: { any: "value" },
    extra: { anything: true },
  },
  noParams: {},
};

export async function verifyAgainstDshTools({ log = console.log } = {}) {
  const runtime = resolveDshRuntime();
  if (!runtime) {
    return { skipped: true, reason: "dsh CLI / dsh-tools not found" };
  }
  const mod = await import(pathToFileURL(runtime.tools).href);
  const { assertSupportedJsonSchema, validateJsonSchemaValue } = mod;
  if (typeof assertSupportedJsonSchema !== "function") {
    throw new Error("dsh-tools did not export assertSupportedJsonSchema");
  }

  const failures = [];
  for (const [name, piSchema] of Object.entries(REPRESENTATIVE)) {
    const translated = translateParameters(piSchema);
    try {
      assertSupportedJsonSchema(translated);
    } catch (error) {
      failures.push(`${name}: assertSupportedJsonSchema rejected: ${error.message}`);
      continue;
    }
    const violations = validateJsonSchemaValue(translated, SAMPLES[name], "");
    if (violations.length > 0) {
      failures.push(`${name}: sample rejected: ${violations.join("; ")}`);
    }
  }

  try {
    assertSupportedJsonSchema(OUTPUT_SCHEMA);
  } catch (error) {
    failures.push(`OUTPUT_SCHEMA rejected: ${error.message}`);
  }

  if (failures.length > 0) {
    throw new Error(`DSH verification failed:\n- ${failures.join("\n- ")}`);
  }
  const bundleEntry = join(DSH_OUTPUT_DIR, "index.js");
  let runtimeSmoke = false;
  let toolCount = 0;
  if (existsSync(bundleEntry)) {
    const [{ Context }, { default: SystemPrompt }, { default: ToolRuntime }, { default: CommandRuntime }, { default: plugin }] =
      await Promise.all([
        import(pathToFileURL(runtime.context).href),
        import(pathToFileURL(runtime.systemPrompt).href),
        import(pathToFileURL(runtime.tools).href),
        import(pathToFileURL(runtime.commands).href),
        import(`${pathToFileURL(bundleEntry).href}?verify=${Date.now()}`),
      ]);
    const ctx = new Context();
    await ctx.plugin(SystemPrompt);
    await ctx.plugin(ToolRuntime);
    await ctx.plugin(CommandRuntime);
    await plugin.apply(ctx, {});
    toolCount = ctx.tools.schemas().length;
    if (toolCount === 0) failures.push("runtime bundle registered no tools");
    const result = await ctx.tools.execute({
      signal: new AbortController().signal,
      callId: "dsh-verify-finance-capabilities",
      name: "finance_capabilities",
      arguments: {},
    });
    if (!Array.isArray(result?.content) || result.content[0]?.type !== "text") {
      failures.push("runtime tool projection is not a DSH ContentBlock[]");
    }
    if (!Array.isArray(result?.value?.content)) {
      failures.push("runtime canonical tool value does not match the bridge output schema");
    }
    runtimeSmoke = true;
  }

  if (failures.length > 0) {
    throw new Error(`DSH verification failed:\n- ${failures.join("\n- ")}`);
  }
  return {
    skipped: false,
    cases: Object.keys(REPRESENTATIVE).length,
    runtimeSmoke,
    toolCount,
  };
}

if (import.meta.main) {
  try {
    const result = await verifyAgainstDshTools();
    if (result.skipped) {
      console.log(`dsh:verify skipped: ${result.reason}`);
      process.exit(0);
    }
    console.log(
      `dsh:verify passed ${result.cases} representative schemas against real dsh-tools` +
        (result.runtimeSmoke
          ? ` and executed the generated bundle (${result.toolCount} tools) in the real DSH runtime`
          : "; generated bundle not present, runtime execution skipped"),
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
