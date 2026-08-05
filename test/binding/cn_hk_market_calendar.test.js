import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_market_calendar/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_market_calendar/index.js"),
};

async function harness(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?calendar=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "calendar-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("isolated official CN/HK market calendars", () => {
  test("CN requires a venue and retains bounded exchange evidence", async () => {
    const tools = await harness("cn");
    expect([...tools.keys()]).toEqual(["cn_market_calendar"]);

    const closed = await execute(tools.get("cn_market_calendar"), {
      venue: "sse",
      date: "2026-10-02",
    });
    expect(closed.details.track).toBe("cn");
    expect(closed.details.trackContext.track).toBe("cn");
    expect(closed.details.trackContext.timezone).toBe("Asia/Shanghai");
    expect(closed.details.venue).toBe("sse");
    expect(closed.details.coverage).toEqual({
      start: "2026-01-01",
      end: "2026-12-31",
    });
    expect(closed.details.source.provider).toBe("sse");
    expect(closed.details.source.reference).toBe(
      "https://www.sse.com.cn/disclosure/dealinstruc/closed/",
    );
    expect(closed.details.day).toEqual({
      status: "closed",
      reason: "national_day",
      sessions: [],
    });
    expect(closed.details.licence.redistribution).toBe(
      "unknown_redistribution",
    );

    const open = await execute(tools.get("cn_market_calendar"), {
      venue: "bse",
      date: "2026-10-08",
    });
    expect(open.details.source.provider).toBe("bse");
    expect(open.details.day.sessions.map(({ label }) => label)).toEqual([
      "opening_call_auction",
      "continuous_auction_morning",
      "continuous_auction_afternoon",
      "closing_call_auction",
    ]);
    expect(open.details.day.sessions[2]).toMatchObject({
      opensAt: "13:00",
      closesAt: "14:57",
      timezone: "Asia/Shanghai",
    });

    await expect(
      execute(tools.get("cn_market_calendar"), {
        venue: "sse",
        date: "2027-01-04",
      }),
    ).rejects.toThrow("covers only 2026");
  });

  test("HK preserves full closures and the exchange's three half-days", async () => {
    const tools = await harness("hk");
    expect([...tools.keys()]).toEqual(["hk_market_calendar"]);

    const halfDay = await execute(tools.get("hk_market_calendar"), {
      date: "2026-12-24",
    });
    expect(halfDay.details.track).toBe("hk");
    expect(halfDay.details.trackContext.timezone).toBe("Asia/Hong_Kong");
    expect(halfDay.details.source.provider).toBe("hkex");
    expect(halfDay.details.version).toBe("official-2026-ct-075-25-v1");
    expect(halfDay.details.day.status).toBe("open");
    expect(halfDay.details.day.dayKind).toBe("half_day");
    expect(halfDay.details.day.sessions).toHaveLength(2);
    expect(halfDay.details.day.sessions.at(-1)).toMatchObject({
      label: "continuous_morning",
      closesAt: "12:00",
      timezone: "Asia/Hong_Kong",
    });

    const closed = await execute(tools.get("hk_market_calendar"), {
      date: "2026-07-01",
    });
    expect(closed.details.day).toMatchObject({
      status: "closed",
      dayKind: "closed",
      reason: "hksar_establishment_day",
    });

    await expect(
      execute(tools.get("hk_market_calendar"), { date: "2025-12-24" }),
    ).rejects.toThrow("covers only 2026");
  });
});
