import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/us_ohlcv_gaps/index.js");
const originalFetch = globalThis.fetch;
let fetchCalls = 0;

const sourceReference =
  "https://data.alpaca.markets/v2/stocks/bars?symbols=IBM&timeframe=1Day&start=2026-06-18&end=2026-06-24&adjustment=raw&feed=sip&currency=USD&sort=asc&asof=2026-06-25";

beforeEach(() => {
  fetchCalls = 0;
  globalThis.fetch = async () => {
    fetchCalls += 1;
    throw new Error("gap assessment must not perform network I/O");
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?us-ohlcv-gaps=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-ohlcv-gap-assessment",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input(overrides = {}) {
  return {
    venue: "nyse",
    instrumentId: "figi:BBG000BLNNH6",
    symbol: "IBM",
    listingStartDate: "2026-01-01",
    listingEndDate: null,
    listingEvidenceReference: "authority:listing:IBM:XNYS:2026",
    startDate: "2026-06-18",
    endDate: "2026-06-24",
    identityAsOf: "2026-06-25",
    feed: "sip",
    pagination: "complete",
    sourceReference,
    requestIds: ["request-one", "request-two"],
    barDates: ["2026-06-18", "2026-06-24"],
    statusReceipts: [
      {
        date: "2026-06-22",
        status: "suspended",
        evidenceReference: "authority:nyse-halt:IBM:2026-06-22",
      },
      {
        date: "2026-06-23",
        status: "trading",
        evidenceReference: "authority:nyse-status:IBM:2026-06-23",
      },
    ],
    ...overrides,
  };
}

describe("US OHLCV gap receipt composition", () => {
  test("classifies every absent date while retaining all evidence legs", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_ohlcv_gap_assessment"]);

    const result = await execute(tools.get("us_ohlcv_gap_assessment"), input());
    expect(result.details.track).toBe("us");
    expect(result.details.trackContext).toMatchObject({
      marketScope: "us_ohlcv_gap_assessment",
      venueMic: "XNYS",
      board: "nyse",
      timezone: "America/New_York",
    });
    expect(result.details.listing).toMatchObject({
      instrumentId: "figi:BBG000BLNNH6",
      symbol: "IBM",
      mic: "XNYS",
      evidenceStatus: "caller_supplied_unverified",
    });
    expect(result.details.calendarReceipt).toMatchObject({
      provider: "nyse",
      coverage: "2026-01-01/2026-12-31",
    });
    expect(result.details.providerReceipt).toMatchObject({
      provider: "alpaca",
      feed: "sip",
      pagination: "complete",
      requestIds: ["request-one", "request-two"],
    });
    expect(result.details.assessment).toEqual({
      state: "fully_classified_from_supplied_receipts",
      startDate: "2026-06-18",
      endDate: "2026-06-24",
      datesAssessed: 7,
      barsReturned: 2,
      absentDates: 5,
    });
    expect(result.details.gaps.map((gap) => gap.state)).toEqual([
      "market_closure",
      "market_closure",
      "market_closure",
      "suspension",
      "provider_omission",
    ]);
    expect(result.details.gaps[3].evidence.map((leg) => leg.role)).toEqual([
      "calendar_schedule",
      "listing_interval",
      "market_status",
    ]);
    expect(result.details.gaps[4].evidence.map((leg) => leg.role)).toEqual([
      "calendar_schedule",
      "listing_interval",
      "market_status",
      "provider_coverage",
    ]);
    expect(fetchCalls).toBe(0);
  });

  test("rejects incomplete pagination and unexplained open dates", async () => {
    const tools = await harness();
    await expect(
      execute(
        tools.get("us_ohlcv_gap_assessment"),
        input({ pagination: "truncated_by_page_budget" }),
      ),
    ).rejects.toThrow("complete provider pagination");

    await expect(
      execute(
        tools.get("us_ohlcv_gap_assessment"),
        input({ statusReceipts: [] }),
      ),
    ).rejects.toThrow("2026-06-22");
    expect(fetchCalls).toBe(0);
  });
});
