import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_market_calendar/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-market-calendar=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function source(sourceId, provider, receipt) {
  return {
    sourceId,
    provider,
    reference: sourceId === "alpha"
      ? "https://user:password@example.test/status?api_key=redact-me#fragment"
      : `https://example.test/${sourceId}`,
    kind: "licensed_vendor",
    otherKind: null,
    feed: "fixture-session-feed",
    coverage: {
      state: "exact_range",
      startUnixMilliseconds: 0,
      endUnixMilliseconds: 2_000,
      reason: null,
    },
    entitlement: { state: "delayed", delayMilliseconds: 900_000 },
    licence: {
      label: "fixture-local-analysis",
      redistribution: "no_redistribution",
      notes: "caller supplied",
    },
    receiptHash: receipt.repeat(64),
  };
}

function observed(category, startsAtLocal = null, endsAtLocal = null) {
  return {
    state: "observed",
    category,
    otherLabel: null,
    startsAtLocal,
    endsAtLocal,
    reason: null,
    alternatives: [],
  };
}

function fact(factId, kind, sourceId, category, interval = {}) {
  return {
    factId,
    kind,
    sourceId,
    date: kind === "schedule" ? "2026-08-11" : null,
    asOfUnixMilliseconds: 900,
    retrievedAtUnixMilliseconds: 950,
    value: observed(category, interval.start ?? null, interval.end ?? null),
  };
}

function input(overrides = {}) {
  return {
    track: "hk",
    scope: {
      kind: "listing",
      scopeId: "listing:00700:XHKG",
      mic: "XHKG",
      symbol: "00700",
    },
    query: {
      date: "2026-08-11",
      localTime: "09:30:00",
      timezone: "Asia/Hong_Kong",
      atUnixMilliseconds: 1_000,
    },
    sources: [
      source("alpha", "alpha-provider", "a"),
      source("beta", "beta-provider", "b"),
    ],
    facts: [
      fact("schedule-a", "schedule", "alpha", "regular_shortened"),
      fact("schedule-b", "schedule", "beta", "regular_shortened"),
      fact("phase-opening", "phase", "alpha", "opening_auction", {
        start: "2026-08-11T09:00:00",
        end: "2026-08-11T09:30:00",
      }),
      fact("phase-continuous", "phase", "alpha", "continuous", {
        start: "2026-08-11T09:30:00",
        end: "2026-08-11T12:00:00",
      }),
      fact("status-a", "market_status", "alpha", "continuous"),
      fact("status-b", "market_status", "beta", "midday_break"),
      fact("halt-a", "listing_halt", "alpha", "not_halted"),
    ],
    page: { offset: 0, limit: 100 },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "stock-session-status-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral stock market calendar boundary", () => {
  test("registers one network-free tool and returns exact session facts", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_market_calendar must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["stock_session_status"]);

      const result = await execute(tools.get("stock_session_status"), input());
      expect(result.details.track).toBe("hk");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "hk_stock_market_calendar",
        venueMic: "XHKG",
        timezone: "Asia/Hong_Kong",
        entitlement: "mixed_caller_declared",
      });
      expect(result.details.summary).toEqual({
        facts: 7,
        scheduleFacts: 2,
        phaseFacts: 2,
        marketStatusFacts: 2,
        listingHaltFacts: 1,
        observed: 7,
        unavailable: 0,
        conflicting: 0,
      });
      expect(result.details.assessment.scheduleReports.state).toBe(
        "exact_agreement",
      );
      expect(result.details.assessment.marketStatusReports.state).toBe(
        "exact_disagreement",
      );
      expect(result.details.assessment.listingHaltReports.state).toBe(
        "single_report",
      );
      expect(result.details.assessment.activeObservedPhases).toHaveLength(1);
      expect(result.details.assessment.activeObservedPhases[0]).toMatchObject({
        factId: "phase-continuous",
        value: { category: "continuous" },
      });
      expect(result.details.assessment.explicitShortenedScheduleFactIds).toEqual([
        "schedule-a",
        "schedule-b",
      ]);
      expect(result.details.assessment.inferredMarketStatus).toBeNull();
      expect(result.details.assessment.correctnessVerdict).toBeNull();
      expect(result.details.sources[0]).toMatchObject({
        sourceId: "alpha",
        referenceRedacted: true,
        receiptBinding: "caller_supplied_unverified",
        coverage: { state: "exact_range", coversQuery: true },
      });
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

  test("retains unavailable and conflicting reports without phase selection", async () => {
    const tools = await harness();
    const value = input();
    value.facts = [
      {
        ...fact("status-missing", "market_status", "alpha", "continuous"),
        value: {
          state: "unavailable",
          category: null,
          otherLabel: null,
          startsAtLocal: null,
          endsAtLocal: null,
          reason: "not reported",
          alternatives: [],
        },
      },
      {
        ...fact("phase-conflict", "phase", "beta", "continuous", {
          start: "2026-08-11T09:30:00",
          end: "2026-08-11T12:00:00",
        }),
        value: {
          state: "conflicting",
          category: null,
          otherLabel: null,
          startsAtLocal: null,
          endsAtLocal: null,
          reason: "two provider rows",
          alternatives: [
            {
              category: "opening_auction",
              otherLabel: null,
              startsAtLocal: "2026-08-11T09:00:00",
              endsAtLocal: "2026-08-11T09:31:00",
              evidenceId: "c".repeat(64),
            },
            {
              category: "continuous",
              otherLabel: null,
              startsAtLocal: "2026-08-11T09:30:00",
              endsAtLocal: "2026-08-11T12:00:00",
              evidenceId: "d".repeat(64),
            },
          ],
        },
      },
    ];

    const result = await execute(tools.get("stock_session_status"), value);
    expect(result.details.assessment.marketStatusReports).toMatchObject({
      state: "indeterminate",
      reason: "unavailable_or_conflicting_reported_fact",
    });
    expect(
      result.details.assessment.activeConflictingPhaseAlternatives,
    ).toHaveLength(2);
    expect(result.details.assessment.phaseSelection).toBe(
      "not_performed_all_matches_retained",
    );
    expect(result.details.facts[1].value).toMatchObject({
      state: "conflicting",
      resolution: "not_performed",
    });
  });

  test("fails closed on track, local time, and market halt mismatches", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("stock_session_status"), input({ track: "cn" })),
    ).rejects.toThrow("scope.mic");

    const badTime = input();
    badTime.query.localTime = "9:30:00";
    await expect(
      execute(tools.get("stock_session_status"), badTime),
    ).rejects.toThrow("query.localTime");

    const marketHalt = input();
    marketHalt.scope = {
      kind: "market",
      scopeId: "market:XHKG",
      mic: "XHKG",
      symbol: null,
    };
    marketHalt.facts = [fact("halt", "listing_halt", "alpha", "halted")];
    await expect(
      execute(tools.get("stock_session_status"), marketHalt),
    ).rejects.toThrow("facts[0].kind");
  });
});
