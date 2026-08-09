import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/finance_calendar/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-calendar=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "finance-calendar-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("shared exact finance calendar boundary", () => {
  test("registers only the three read-only calendar tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "inspect_session",
      "list_holidays",
      "next_session",
    ]);
  });

  test("inspects HK shortened sessions without flattening phase intervals", async () => {
    const tools = await harness();
    const result = await execute(tools.get("inspect_session"), {
      track: "hk",
      venue: "XHKG",
      date: "2026-12-24",
    });

    expect(result.details).toMatchObject({
      operation: "inspect_session",
      track: "hk",
      venue: "XHKG",
      version: "official-2026-ct-075-25-v1",
      coverage: { start: "2026-01-01", end: "2026-12-31" },
      source: { provider: "hkex", kind: "exchange" },
      licence: { redistribution: "unknown_redistribution" },
      decisionOwner: "llm",
      pluginDecisionFields: [],
      day: {
        date: "2026-12-24",
        status: "open",
        sessionType: "regular_shortened",
      },
    });
    expect(result.details.trackContext).toMatchObject({
      track: "hk",
      venueMic: "XHKG",
      timezone: "Asia/Hong_Kong",
    });
    expect(result.details.day.phaseIntervals).toEqual([
      {
        label: "pre_opening",
        opensAt: "09:00",
        closesAt: "09:30",
        closeDay: "same_day",
        timezone: "Asia/Hong_Kong",
        timeBasis: "venue_local_wall_clock",
      },
      {
        label: "continuous_morning",
        opensAt: "09:30",
        closesAt: "12:00",
        closeDay: "same_day",
        timezone: "Asia/Hong_Kong",
        timeBasis: "venue_local_wall_clock",
      },
    ]);
  });

  test("pages published holidays stably and excludes an intervening weekend", async () => {
    const tools = await harness();
    const first = await execute(tools.get("list_holidays"), {
      track: "cn",
      venue: "XBSE",
      startDate: "2026-01-01",
      endDate: "2026-01-04",
      offset: 0,
      limit: 1,
    });
    const second = await execute(tools.get("list_holidays"), {
      track: "cn",
      venue: "XBSE",
      startDate: "2026-01-01",
      endDate: "2026-01-04",
      offset: 1,
      limit: 1,
    });

    expect(first.details).toMatchObject({
      operation: "list_holidays",
      track: "cn",
      venue: "XBSE",
      rangeId: "cn:XBSE:official-2026-v1:2026-01-01:2026-01-04",
      matchedCount: 2,
      returnedCount: 1,
      nextOffset: 1,
      holidays: [
        {
          date: "2026-01-01",
          kind: "published_full_closure",
          reason: "new_year",
        },
      ],
    });
    expect(second.details.rangeId).toBe(first.details.rangeId);
    expect(second.details.nextOffset).toBeNull();
    expect(second.details.holidays).toEqual([
      {
        date: "2026-01-02",
        weekday: "friday",
        kind: "published_full_closure",
        reason: "new_year",
      },
    ]);
  });

  test("finds the strictly later US early-close session and bounds exhaustion", async () => {
    const tools = await harness();
    const next = await execute(tools.get("next_session"), {
      track: "us",
      venue: "XNAS",
      after: "2026-11-26",
    });
    expect(next.details).toMatchObject({
      operation: "next_session",
      track: "us",
      venue: "XNAS",
      query: {
        after: "2026-11-26",
        searchPolicy: "strictly_after_within_coverage_v1",
      },
      availability: "available",
      session: {
        date: "2026-11-27",
        sessionType: "regular_shortened",
      },
    });
    expect(next.details.session.phaseIntervals[0]).toMatchObject({
      label: "regular_market_early_close",
      opensAt: "09:30",
      closesAt: "13:00",
      timezone: "America/New_York",
    });

    const unavailable = await execute(tools.get("next_session"), {
      track: "us",
      venue: "XNYS",
      after: "2026-12-31",
    });
    expect(unavailable.details).toMatchObject({
      availability: "unavailable",
      unavailableReason: "no_later_open_date_in_coverage",
      session: null,
    });
  });

  test("rejects a mismatched track and out-of-coverage date", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("inspect_session"), {
        track: "cn",
        venue: "XHKG",
        date: "2026-03-10",
      }),
    ).rejects.toThrow("does not belong to track cn");
    await expect(
      execute(tools.get("next_session"), {
        track: "us",
        venue: "XNYS",
        after: "2027-01-01",
      }),
    ).rejects.toThrow("outside exact calendar coverage");
  });
});
