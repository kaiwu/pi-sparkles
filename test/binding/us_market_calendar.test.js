import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/us_market_calendar/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?calendar=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-calendar-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("isolated official US market calendar", () => {
  test("requires an exact venue and preserves NYSE closure evidence", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_market_calendar"]);

    const closed = await execute(tools.get("us_market_calendar"), {
      venue: "nyse",
      date: "2026-07-03",
    });
    expect(closed.details.track).toBe("us");
    expect(closed.details.trackContext).toMatchObject({
      track: "us",
      venueMic: "XNYS",
      timezone: "America/New_York",
    });
    expect(closed.details.venue).toBe("nyse");
    expect(closed.details.coverage).toEqual({
      start: "2026-01-01",
      end: "2026-12-31",
    });
    expect(closed.details.source).toMatchObject({
      provider: "nyse",
      reference: "https://www.nyse.com/trade/hours-calendars",
      kind: "exchange",
    });
    expect(closed.details.day).toEqual({
      status: "closed",
      dayKind: "closed",
      reason: "independence_day_observed",
      sessions: [],
    });
    expect(closed.details.licence.redistribution).toBe(
      "unknown_redistribution",
    );
  });

  test("preserves Nasdaq's early close and rejects extrapolation", async () => {
    const tools = await harness();
    const earlyClose = await execute(tools.get("us_market_calendar"), {
      venue: "nasdaq",
      date: "2026-11-27",
    });
    expect(earlyClose.details.trackContext.venueMic).toBe("XNAS");
    expect(earlyClose.details.source.provider).toBe("nasdaq");
    expect(earlyClose.details.source.reference).toBe(
      "https://www.nasdaqtrader.com/trader.aspx?id=Calendar",
    );
    expect(earlyClose.details.day).toMatchObject({
      status: "open",
      dayKind: "early_close",
      reason: null,
    });
    expect(earlyClose.details.day.sessions).toEqual([
      {
        label: "regular_market_early_close",
        opensAt: "09:30",
        closesAt: "13:00",
        timezone: "America/New_York",
      },
    ]);

    await expect(
      execute(tools.get("us_market_calendar"), {
        venue: "nasdaq",
        date: "2027-01-04",
      }),
    ).rejects.toThrow("covers only 2026");
  });
});
