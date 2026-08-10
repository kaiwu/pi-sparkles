import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/finance_data_quality/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-data-quality=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function source(sourceId, provider, receipt) {
  return {
    sourceId,
    provider,
    reference: sourceId === "alpha"
      ? "https://user:password@example.test/quote?api_key=redact-me#fragment"
      : `https://example.test/${sourceId}`,
    kind: "licensed_vendor",
    otherKind: null,
    feed: "fixture-feed",
    entitlement: { state: "delayed", delayMilliseconds: 900_000 },
    licence: {
      label: "fixture-local-analysis",
      redistribution: "no_redistribution",
      notes: "caller supplied",
    },
    receiptHash: receipt.repeat(64),
  };
}

function observed(rawValue) {
  return {
    state: "observed",
    rawValue,
    reason: null,
    alternatives: [],
  };
}

function fact(factId, observationKey, sourceId, rawValue, asOf) {
  return {
    factId,
    observationKey,
    metric: "last_price",
    sourceId,
    asOfUnixMilliseconds: asOf,
    retrievedAtUnixMilliseconds: asOf + 100,
    unit: {
      kind: "currency_per_share",
      currencyCode: "USD",
      otherLabel: null,
    },
    adjustment: { kind: "raw", provider: null, basis: null },
    value: observed(rawValue),
  };
}

function input(overrides = {}) {
  return {
    track: "us",
    scope: {
      kind: "listing",
      scopeId: "listing:AAPL:XNAS",
      mic: "XNAS",
      symbol: "AAPL",
    },
    freshnessPolicy: {
      state: "assess",
      evaluatedAtUnixMilliseconds: 2_000,
      maximumAgeMilliseconds: 500,
      reason: null,
    },
    expectedCoordinates: [
      { observationKey: "t1", metric: "last_price" },
      { observationKey: "t2", metric: "last_price" },
      { observationKey: "t3", metric: "last_price" },
    ],
    sources: [source("alpha", "alpha-provider", "a"), source("beta", "beta-provider", "b")],
    facts: [
      fact("alpha:t1", "t1", "alpha", "100.00", 1_600),
      fact("beta:t1", "t1", "beta", "100", 1_600),
      fact("alpha:t2", "t2", "alpha", "101", 1_000),
      fact("beta:t2", "t2", "beta", "102", 1_000),
    ],
    page: { offset: 0, limit: 100 },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "finance-data-quality-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral finance data quality boundary", () => {
  test("registers one network-free tool and returns exact mechanical findings", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("finance_data_quality must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["data_quality_check"]);

      const result = await execute(tools.get("data_quality_check"), input());
      expect(result.details.track).toBe("us");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "us_finance_data_quality",
        venueMic: "XNAS",
        timezone: "America/New_York",
        entitlement: "mixed_caller_declared",
      });
      expect(result.details.summary).toMatchObject({
        coordinates: 3,
        expectedCoordinates: 3,
        missingExpectedCoordinates: 1,
        duplicateSourceGroups: 0,
        freshness: { fresh: 2, stale: 2, unknown: 0 },
        providerComparisons: {
          exactAgreements: 1,
          exactDisagreements: 1,
          insufficientProviders: 1,
          indeterminate: 0,
        },
        overallVerdict: null,
      });
      expect(result.details.coordinates[0].providerComparison).toMatchObject({
        state: "exact_agreement",
        exactNormalizedValue: "100",
        selectedProvider: null,
        correctnessVerdict: null,
      });
      expect(result.details.coordinates[1].providerComparison.state).toBe(
        "exact_disagreement",
      );
      expect(result.details.coordinates[2]).toMatchObject({
        expected: true,
        missing: true,
        factCount: 0,
      });
      expect(result.details.coordinates[1].facts[0].observation.freshness).toEqual({
        state: "stale",
        maximumAgeMilliseconds: 500,
        ageMilliseconds: 1_000,
      });
      expect(result.details.sources[0]).toMatchObject({
        sourceId: "alpha",
        referenceRedacted: true,
        receiptBinding: "caller_supplied_unverified",
      });
      expect(result.details.assessmentStatus).toBe(
        "findings_only_no_quality_verdict",
      );
      expect(result.details.decisionOwner).toBe("llm");
      expect(result.details.pluginDecisionFields).toEqual([]);
      const details = JSON.stringify(result.details);
      expect(details).not.toContain("redact-me");
      expect(details).not.toContain("user:password");
      expect(details).not.toContain("#fragment");
      expect(requests).toBe(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("retains duplicates and incompatible contexts without choosing a row", async () => {
    const tools = await harness();
    const value = input();
    value.expectedCoordinates = [];
    const duplicate = fact("alpha:t1:duplicate", "t1", "alpha", "100.000", 1_600);
    const incompatible = fact("beta:t1:unit", "t1", "beta", "100", 1_600);
    incompatible.unit.currencyCode = "HKD";
    value.facts = [value.facts[0], duplicate, incompatible];

    const result = await execute(tools.get("data_quality_check"), value);
    expect(result.details.summary).toMatchObject({
      duplicateSourceGroups: 1,
      unitIncompatibleCoordinates: 1,
    });
    expect(result.details.coordinates[0].duplicateGroups[0]).toMatchObject({
      sourceId: "alpha",
      classification: "exact_repeated_fact",
      count: 2,
      resolution: "not_performed",
    });
    expect(result.details.coordinates[0].unitCompatibility.state).toBe(
      "incompatible_distinct_keys",
    );
    expect(result.details.coordinates[0].providerComparison).toMatchObject({
      state: "incompatible_context",
      reason: "unit_incompatibility",
      selectedProvider: null,
    });
  });

  test("fails closed on track scope, future facts, and false conflicts", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("data_quality_check"), input({ track: "cn" })),
    ).rejects.toThrow("scope.mic");

    const future = input();
    future.facts = [fact("future", "future", "alpha", "10", 2_100)];
    await expect(execute(tools.get("data_quality_check"), future)).rejects.toThrow(
      "facts[0].asOfUnixMilliseconds",
    );

    const falseConflict = input();
    falseConflict.facts[0].value = {
      state: "conflicting",
      rawValue: null,
      reason: "same_value",
      alternatives: [
        { rawValue: "10.0", evidenceId: "c".repeat(64) },
        { rawValue: "10.00", evidenceId: "d".repeat(64) },
      ],
    };
    await expect(
      execute(tools.get("data_quality_check"), falseConflict),
    ).rejects.toThrow("facts[0].value.alternatives");
  });
});
