import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_market_snapshot/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-market-snapshot=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function unavailable(reason) {
  return {
    state: "unavailable",
    rawValue: null,
    unit: null,
    method: null,
    reason,
  };
}

function observedMember(listingId, symbol, current, previous, groups) {
  return {
    listingId,
    mic: "XHKG",
    symbol,
    label: null,
    groups,
    price: {
      state: "observed",
      rawCurrent: current,
      rawPreviousClose: previous,
      reason: null,
      alternatives: [],
    },
    volume: {
      state: "reported",
      rawValue: "100000.00",
      unit: "shares",
      method: null,
      reason: null,
    },
    volatility: {
      state: "reported",
      rawValue: "0.2000",
      unit: "fraction",
      method: "provider_reported_realized_20_day",
      reason: null,
    },
  };
}

function input(overrides = {}) {
  const market = { kind: "index", id: "hsi", label: "Hang Seng supplied set" };
  const technology = {
    kind: "sector",
    id: "technology",
    label: "Technology",
  };
  const members = [
    observedMember(
      "listing:00700:XHKG",
      "00700",
      "612.5000",
      "600.0000",
      [market, technology],
    ),
    observedMember(
      "listing:09988:XHKG",
      "09988",
      "110.0000",
      "120.0000",
      [market, technology],
    ),
    {
      listingId: "listing:00005:XHKG",
      mic: "XHKG",
      symbol: "00005",
      label: null,
      groups: [market],
      price: {
        state: "unavailable",
        rawCurrent: null,
        rawPreviousClose: null,
        reason: "halted_without_price",
        alternatives: [],
      },
      volume: unavailable("not_reported"),
      volatility: unavailable("not_reported"),
    },
  ];
  return {
    track: "hk",
    market: {
      mic: "XHKG",
      scopeKind: "index",
      scopeId: "caller-supplied-hsi-set",
      label: "Caller-supplied HSI set",
    },
    snapshot: {
      providerTimestamp: "2026-08-10T10:00:00.123456789+08:00",
      asOfUnixMilliseconds: 1_786_332_000_123,
      retrievedAtUnixMilliseconds: 1_786_332_001_000,
      currency: "HKD",
      session: { state: "regular", otherLabel: null },
      coverage: {
        state: "partial",
        expectedMembers: 4,
        reason: "provider_page_budget_exhausted",
      },
    },
    members,
    calculation: {
      changeFractionScale: 6,
      rounding: "half_even",
      extremaLimit: 10,
    },
    source: {
      provider: "licensed-fixture-adapter",
      reference:
        "https://user:password@example.test/snapshot?api_key=redact-me#fragment",
      kind: "licensed_vendor",
      otherKind: null,
      feed: "fixture-snapshot",
      entitlement: { state: "delayed", delayMilliseconds: 900_000 },
      licence: {
        label: "fixture-local-analysis",
        redistribution: "no_redistribution",
        notes: "caller supplied",
      },
      receiptHash: "a".repeat(64),
    },
    page: { offset: 0, limit: 2 },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "stock-market-snapshot-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral stock market snapshot boundary", () => {
  test("registers one network-free tool and returns exact bounded breadth facts", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_market_snapshot must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["market_snapshot"]);

      const result = await execute(tools.get("market_snapshot"), input());
      expect(result.details.track).toBe("hk");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "hk_stock_market_snapshot",
        venueMic: "XHKG",
        timezone: "Asia/Hong_Kong",
        entitlement: "declared_delayed",
      });
      expect(result.details.snapshot.coverage).toMatchObject({
        state: "partial",
        expectedMembers: 4,
        suppliedMembers: 3,
        reason: "provider_page_budget_exhausted",
        status: "caller_or_provider_adapter_declared_unverified",
      });
      expect(result.details.overall).toMatchObject({
        totalMembers: 3,
        observedPriceMembers: 2,
        advancing: 1,
        declining: 1,
        unchanged: 0,
        unavailable: 1,
        conflicting: 0,
        advanceDeclineDifference: 0,
      });
      expect(result.details.overall.fractions).toMatchObject({
        denominator: "observed_price_rows_only",
        advancing: "0.5",
        declining: "0.5",
        unchanged: "0",
      });
      expect(result.details.groupAggregates.find((value) =>
        value.id === "technology"
      ).breadth).toMatchObject({ advancing: 1, declining: 1 });
      expect(result.details.members[0].price).toMatchObject({
        rawCurrent: "612.5000",
        normalizedCurrent: "612.5",
        direction: "advancing",
        currency: "HKD",
      });
      expect(result.details.members[0].volume).toMatchObject({
        rawValue: "100000.00",
        normalizedValue: "100000",
        interpretation: "not_performed",
      });
      expect(result.details.members[0].observation.evidenceId).toBe(
        "a".repeat(64),
      );
      expect(result.details.page.nextOffset).toBe(2);
      expect(result.details.changeExtrema.scope).toBe(
        "supplied_observed_rows_only",
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

  test("retains conflicts and excludes them from the directional denominator", async () => {
    const tools = await harness();
    const value = input();
    value.members[2].price = {
      state: "conflicting",
      rawCurrent: null,
      rawPreviousClose: null,
      reason: "conflicting_provider_rows",
      alternatives: [
        {
          rawCurrent: "50.00",
          rawPreviousClose: "49.00",
          evidenceId: "b".repeat(64),
        },
        {
          rawCurrent: "48.00",
          rawPreviousClose: "49.00",
          evidenceId: "c".repeat(64),
        },
      ],
    };
    value.page = { offset: 2, limit: 1 };
    const result = await execute(tools.get("market_snapshot"), value);
    expect(result.details.overall).toMatchObject({
      observedPriceMembers: 2,
      conflicting: 1,
      unavailable: 0,
    });
    expect(result.details.members[0].price).toMatchObject({
      state: "conflicting",
      direction: null,
      reason: "conflicting_provider_rows",
    });
    expect(result.details.members[0].price.alternatives).toHaveLength(2);
  });

  test("fails closed on track-MIC, coverage, and price-shape conflicts", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("market_snapshot"), input({ track: "us" })),
    ).rejects.toThrow("market.mic");

    const badCoverage = input();
    badCoverage.snapshot.coverage.expectedMembers = 3;
    await expect(
      execute(tools.get("market_snapshot"), badCoverage),
    ).rejects.toThrow("snapshot.coverage.expectedMembers");

    const badPrice = input();
    badPrice.members[0].price.rawPreviousClose = "0";
    await expect(execute(tools.get("market_snapshot"), badPrice)).rejects.toThrow(
      "members[0].price.rawPreviousClose",
    );
  });
});
