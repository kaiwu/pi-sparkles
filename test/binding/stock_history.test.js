import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/stock_history/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-history=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function bar(sessionDate, values = {}) {
  return {
    sessionDate,
    sourceTimestamp: sessionDate,
    timeBasis: "session_date_anchor",
    atUnixMilliseconds: null,
    rawOpen: "612.5000",
    rawHigh: "620.0000",
    rawLow: "610.0000",
    rawClose: "618.5000",
    rawVolume: "100000.00",
    rawTradeCount: "700",
    rawVwap: "616.2500",
    ...values,
  };
}

function input(overrides = {}) {
  return {
    track: "hk",
    listing: {
      listingId: "listing:00700:XHKG",
      mic: "XHKG",
      symbol: "00700",
    },
    range: { startDate: "2026-08-03", endDate: "2026-08-05" },
    batch: {
      retrievedAtUnixMilliseconds: 2_000_000_000_000,
      currency: "HKD",
      volumeUnit: "shares",
      adjustment: { kind: "raw", provider: null, basis: null },
      session: { state: "regular", otherLabel: null },
      pagination: { state: "complete", maximum: null },
      calendar: {
        state: "assessed",
        reason: null,
        gaps: [{
          sessionDate: "2026-08-05",
          state: "market_closure",
          evidenceReference: "https://example.test/calendar?token=redact-me",
        }],
      },
    },
    bars: [bar("2026-08-03"), bar("2026-08-04", {
      rawOpen: "618.5000",
      rawHigh: "622.0000",
      rawLow: "617.0000",
      rawClose: "620.0000",
      rawVolume: "120000",
      rawTradeCount: null,
      rawVwap: null,
    })],
    source: {
      provider: "licensed-fixture-adapter",
      reference: "https://example.test/hk/bars?symbol=00700",
      kind: "licensed_vendor",
      otherKind: null,
      feed: "fixture-daily",
      entitlement: { state: "delayed", delayMilliseconds: 900_000 },
      licence: {
        label: "fixture-local-analysis",
        redistribution: "no_redistribution",
        notes: "caller supplied",
      },
      receiptHash: "a".repeat(64),
    },
    page: { offset: 0, limit: 1 },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "stock-history-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral stock history boundary", () => {
  test("registers one network-free tool and retains exact paged daily facts", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_history must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["stock_bars"]);

      const result = await execute(tools.get("stock_bars"), input());
      expect(result.details.track).toBe("hk");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "hk_stock_history",
        venueMic: "XHKG",
        timezone: "Asia/Hong_Kong",
        entitlement: "declared_delayed",
      });
      expect(result.details.listing.identityStatus).toBe(
        "caller_supplied_unverified",
      );
      expect(result.details.batch).toMatchObject({
        interval: "1_day",
        currency: "HKD",
        volumeUnit: "shares",
        inputRowCount: 2,
        observationCount: 2,
        duplicatesCollapsed: 0,
      });
      expect(result.details.page).toEqual({
        offset: 0,
        limit: 1,
        returned: 1,
        total: 2,
        nextOffset: 1,
      });
      expect(result.details.bars[0].raw).toMatchObject({
        open: "612.5000",
        volume: "100000.00",
        tradeCount: "700",
        vwap: "616.2500",
      });
      expect(result.details.bars[0].normalized).toMatchObject({
        open: "612.5",
        volume: "100000",
        tradeCount: 700,
        vwap: "616.25",
      });
      expect(result.details.bars[0].timeBasis).toBe("session_date_anchor");
      expect(result.details.bars[0].atStatus).toBe(
        "ordering_anchor_not_provider_time",
      );
      expect(result.details.bars[0].evidenceId).toBe("a".repeat(64));
      expect(result.details.bars[0].entitlement.state).toBe("delayed");
      expect(result.details.batch.calendar.gaps[0].state).toBe(
        "market_closure",
      );
      expect(JSON.stringify(result.details)).not.toContain("redact-me");
      expect(result.details.source.receiptBinding).toBe(
        "caller_supplied_unverified",
      );
      expect(result.details.decisionOwner).toBe("llm");
      expect(result.details.pluginDecisionFields).toEqual([]);
      expect(requests).toBe(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("fails closed on track-MIC mismatch and bar-gap overlap", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("stock_bars"), input({ track: "us" })),
    ).rejects.toThrow("listing.mic");

    const value = input();
    value.batch.calendar.gaps[0].sessionDate = "2026-08-03";
    await expect(execute(tools.get("stock_bars"), value)).rejects.toThrow(
      "batch.calendar.gaps",
    );
  });

  test("fails closed on invalid time-basis variants and bar geometry", async () => {
    const tools = await harness();
    const invalidBasis = input();
    invalidBasis.bars[0].sourceTimestamp = "not-the-date";
    await expect(execute(tools.get("stock_bars"), invalidBasis)).rejects.toThrow(
      "sourceTimestamp",
    );

    const invalidGeometry = input();
    invalidGeometry.bars[0].rawHigh = "600";
    await expect(
      execute(tools.get("stock_bars"), invalidGeometry),
    ).rejects.toThrow("bars[0]");
  });
});
