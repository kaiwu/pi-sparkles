import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/finance_sources/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-sources=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const hash = (digit) => digit.repeat(64);

function catalogue() {
  return {
    instructionRef: hash("1"),
    additionalSensitiveQueryKeys: [],
    assumptions: [
      {
        id: "method-scale",
        name: "Display scale",
        origin: "method",
        explanation: "Exact scale supplied by the caller",
        value: { kind: "decimal", decimal: "2" },
      },
      {
        id: "caller-reviewed",
        name: "Caller review state",
        origin: "user",
        explanation: "Caller-reported review state",
        value: { kind: "boolean", boolean: true },
      },
    ],
    evidence: [
      {
        receiptHash: hash("3"),
        sourceFingerprint: hash("5"),
        source: {
          provider: "fixture-exchange",
          reference: "https://example.test/source/one",
          kind: "exchange",
        },
        licence: {
          label: "Fixture terms",
          redistribution: "attribution_required",
          notes: "Attribution required by supplied metadata",
        },
        asOfUnixMilliseconds: 1_770_000_000_000,
        retrievedAtUnixMilliseconds: 1_770_000_000_100,
        mediaType: "application/json",
        byteLength: 120,
        contentHash: hash("6"),
        parents: [],
        assumptions: ["method-scale"],
        availability: { state: "available" },
      },
      {
        receiptHash: hash("4"),
        sourceFingerprint: hash("7"),
        source: {
          provider: "fixture-calculation",
          reference: "calculation://exact-output",
          kind: "synthetic",
        },
        licence: { label: "Unknown terms", redistribution: "unknown" },
        asOfUnixMilliseconds: 1_770_000_000_100,
        retrievedAtUnixMilliseconds: 1_770_000_000_200,
        mediaType: "application/json",
        byteLength: 80,
        contentHash: hash("8"),
        parents: [hash("3")],
        assumptions: ["method-scale", "caller-reviewed"],
        availability: {
          state: "verification_failed",
          reason: "provider omitted checksum header",
        },
      },
    ],
    roots: [hash("4")],
  };
}

async function execute(tool, input) {
  return tool.execute(
    "finance-sources-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("finance sources bundled boundary", () => {
  test("supports the compact list, exact inspection, and bounded export workflow", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "list_sources",
      "inspect_source",
      "export_manifest",
    ]);

    const listed = await execute(tools.get("list_sources"), {
      catalogue: catalogue(),
      offset: 0,
      limit: 1,
    });
    expect(listed.details).toMatchObject({
      operation: "list_sources",
      counts: { assumptions: 2, evidence: 2, roots: 1 },
      returnedCount: 1,
      omittedCount: 1,
      nextOffset: 1,
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(listed.details.sources[0]).toMatchObject({
      receiptHash: hash("3"),
      provider: "fixture-exchange",
      sourceKind: "exchange",
      availability: { state: "available" },
    });

    const inspected = await execute(tools.get("inspect_source"), {
      catalogue: catalogue(),
      receiptHash: hash("4"),
    });
    expect(inspected.details.manifestHandle).toBe(listed.details.manifestHandle);
    expect(inspected.details.source).toMatchObject({
      receiptHash: hash("4"),
      parents: [hash("3")],
      availability: {
        state: "verification_failed",
        reason: "provider omitted checksum header",
      },
    });
    expect(inspected.details.linkedAssumptions.map(({ id }) => id)).toEqual([
      "method-scale",
      "caller-reviewed",
    ]);

    const exported = await execute(tools.get("export_manifest"), {
      catalogue: catalogue(),
      maximumManifestBytes: 100_000,
    });
    expect(exported.details.manifestHandle).toBe(listed.details.manifestHandle);
    expect(exported.details.canonicalManifestJson).toContain(
      '"schema_version":1',
    );
    expect(exported.details).toMatchObject({ truncated: false, signed: false });
    expect(JSON.stringify(exported.details)).not.toMatch(
      /"(correct|quality|trusted|rank|recommended|nextAction)"/,
    );
  });

  test("redacts unsafe references and fails exact handles, budgets, and missing fields", async () => {
    const tools = await harness();
    const unsafe = catalogue();
    unsafe.additionalSensitiveQueryKeys = ["vendor_secret"];
    unsafe.evidence[0].source.reference =
      "https://user:password@example.test/data?api_key=do-not-leak&vendor_secret=also-secret#fragment";

    const listed = await execute(tools.get("list_sources"), {
      catalogue: unsafe,
      offset: 0,
      limit: 2,
    });
    const serialized = JSON.stringify(listed.details);
    expect(serialized).not.toContain("do-not-leak");
    expect(serialized).not.toContain("also-secret");
    expect(serialized).not.toContain("user:password");
    expect(serialized).not.toContain("#fragment");
    expect(listed.details.sources[0]).toMatchObject({
      referenceRedacted: true,
    });
    expect(listed.details.sources[0].reference).toMatch(
      /^redacted-reference:sha256:[0-9a-f]{64}$/,
    );

    await expect(
      execute(tools.get("inspect_source"), {
        catalogue: catalogue(),
        receiptHash: hash("f"),
      }),
    ).rejects.toThrow("exact receipt hash was not present");
    await expect(
      execute(tools.get("export_manifest"), {
        catalogue: catalogue(),
        maximumManifestBytes: 1,
      }),
    ).rejects.toThrow("nothing was truncated");

    const missingCatalogue = { offset: 0, limit: 1 };
    await expect(
      execute(tools.get("list_sources"), missingCatalogue),
    ).rejects.toThrow("Invalid parameters for tool list_sources");
  });
});
