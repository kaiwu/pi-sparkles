import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_order_book/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-order-book=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function source(sourceId, receiptCharacter = "a") {
  return {
    sourceId,
    provider: "fixture-provider",
    reference: sourceId === "alpha"
      ? "https://user:password@example.test/book?api_key=redact-me#fragment"
      : `https://example.test/${sourceId}`,
    kind: "licensed_vendor",
    otherKind: null,
    feed: "fixture-top-feed",
    entitlement: { state: "delayed", delayMilliseconds: 900_000 },
    licence: {
      label: "fixture-local-analysis",
      redistribution: "no_redistribution",
      notes: "caller supplied",
    },
    receiptHash: receiptCharacter.repeat(64),
  };
}

function venue(code = "XHKG", kind = "mic") {
  return { kind, code };
}

function observed(rawPrice, rawSize, reportedVenue = venue()) {
  return {
    state: "observed",
    candidate: { rawPrice, rawSize, venue: reportedVenue },
    reason: null,
    alternatives: [],
  };
}

function report(reportId = "report-1") {
  return {
    reportId,
    sourceId: "alpha",
    currency: "HKD",
    providerTimestamp: "2026-08-11T09:30:00.100+08:00",
    providerTimeUnixMilliseconds: 100,
    receivedAtUnixMilliseconds: 110,
    exchangeTime: {
      state: "reported",
      unixMilliseconds: 90,
      sourceLexeme: "2026-08-11T09:30:00.090+08:00",
      reason: null,
    },
    sequence: { state: "reported", value: 12, scope: "listing", reason: null },
    gap: {
      state: "no_gap_reported",
      fromSequence: null,
      toSequence: null,
      reason: null,
    },
    aggregation: {
      kind: "single_venue",
      venues: [venue()],
      coverage: "declared_complete",
      methodLabel: null,
      reason: null,
    },
    sizeUnit: { kind: "shares", label: null, reason: null },
    conditionCodes: ["regular"],
    bid: observed("10.5000", "00100.00"),
    ask: observed("10.6000", "00200.00"),
  };
}

function input(overrides = {}) {
  return {
    track: "hk",
    listing: {
      listingId: "listing:00700:XHKG",
      mic: "XHKG",
      symbol: "00700",
      currency: "HKD",
    },
    sources: [source("alpha")],
    reports: [report()],
    page: { offset: 0, limit: 50 },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "stock-top-of-book-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral stock top-of-book boundary", () => {
  test("registers one network-free tool and retains exact report evidence", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_order_book must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["stock_top_of_book"]);

      const result = await execute(tools.get("stock_top_of_book"), input());
      expect(result.details.track).toBe("hk");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "hk_stock_order_book",
        venueMic: "XHKG",
        timezone: "Asia/Hong_Kong",
        entitlement: "mixed_caller_declared",
      });
      expect(result.details.summary).toMatchObject({
        reports: 1,
        fullyObserved: 1,
        bidStates: { observed: 1, unavailable: 0, conflicting: 0 },
        askStates: { observed: 1, unavailable: 0, conflicting: 0 },
        reportedSequences: 1,
      });
      expect(result.details.reports[0]).toMatchObject({
        reportId: "report-1",
        sourceId: "alpha",
        currencyMatchesListing: true,
        observation: {
          currency: "HKD",
          gap: { state: "no_gap_reported", continuityProven: false },
          aggregation: { kind: "single_venue", nbboClaim: false },
          bid: {
            state: "observed",
            candidate: {
              rawPrice: "10.5000",
              normalizedPrice: "10.5",
              rawSize: "00100.00",
              normalizedSize: "100",
              displayed: true,
            },
          },
        },
      });
      expect(result.details.liquidityWarning).toEqual({
        displayedOnly: true,
        hiddenLiquidityKnown: false,
        durabilityClaim: false,
        executablePricePromise: false,
        fillPrediction: false,
      });
      expect(result.details.calculation).toMatchObject({
        reportMerge: "not_performed",
        sourceSelection: "not_performed",
        gapRepair: "not_performed",
        depthReconstruction: "not_performed",
      });
      expect(result.details.sources[0]).toMatchObject({
        sourceId: "alpha",
        referenceRedacted: true,
        receiptBinding: "caller_supplied_unverified",
      });
      expect(result.details.calculation.receiptHash).toMatch(/^[0-9a-f]{64}$/);
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

  test("preserves unavailable, conflicting, sequence-gap, and unknown facts", async () => {
    const tools = await harness();
    const value = input();
    const mixed = report("mixed");
    mixed.bid = {
      state: "unavailable",
      candidate: null,
      reason: "bid withheld",
      alternatives: [],
    };
    mixed.ask = {
      state: "conflicting",
      candidate: null,
      reason: "two rows",
      alternatives: [
        {
          rawPrice: "10.60",
          rawSize: "200",
          venue: venue(),
          evidenceId: "c".repeat(64),
        },
        {
          rawPrice: "10.61",
          rawSize: "180",
          venue: venue(),
          evidenceId: "d".repeat(64),
        },
      ],
    };
    mixed.sequence = {
      state: "unknown",
      value: null,
      scope: "unknown",
      reason: "unsequenced feed",
    };
    mixed.gap = {
      state: "sequence_gap",
      fromSequence: 13,
      toSequence: 15,
      reason: null,
    };
    value.reports = [mixed];

    const result = await execute(tools.get("stock_top_of_book"), value);
    expect(result.details.summary).toMatchObject({
      fullyObserved: 0,
      bidStates: { unavailable: 1 },
      askStates: { conflicting: 1 },
      reportedSequences: 0,
      reportedSequenceGaps: 1,
    });
    expect(result.details.reports[0].observation).toMatchObject({
      sequence: { state: "unknown", reason: "unsequenced feed" },
      gap: { state: "sequence_gap", fromSequence: 13, toSequence: 15 },
      bid: { state: "unavailable", resolution: "not_performed" },
      ask: { state: "conflicting", resolution: "not_performed" },
    });
    expect(result.details.reports[0].observation.ask.alternatives).toHaveLength(2);
  });

  test("rejects cross-track or aggregation-inconsistent venue facts", async () => {
    const tools = await harness();
    const wrongTrack = input({ track: "cn" });
    await expect(
      execute(tools.get("stock_top_of_book"), wrongTrack),
    ).rejects.toThrow("listing.mic");

    const wrongSet = input();
    wrongSet.reports[0].bid = observed(
      "10.50",
      "100",
      venue("NOT-IN-SET", "provider_code"),
    );
    await expect(
      execute(tools.get("stock_top_of_book"), wrongSet),
    ).rejects.toThrow("reports[0].bid");
  });
});
