import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/us_ohlcv/index.js");
const originalFetch = globalThis.fetch;
const requests = [];

const firstPage =
  '{"bars":{"AAPL":[{"c":187.12,"h":188.10,"l":184.22,"n":612345,"o":185.6200,"t":"2024-08-01T04:00:00Z","v":50292117,"vw":186.432100},{"c":189.840,"h":190.01,"l":186.31,"n":598765,"o":186.90,"t":"2024-08-02T04:00:00Z","v":49910111,"vw":188.7654}]},"next_page_token":"page-two"}';

const secondPage =
  '{"bars":{"AAPL":[{"c":189.840,"h":190.01,"l":186.31,"n":598765,"o":186.90,"t":"2024-08-02T04:00:00Z","v":49910111,"vw":188.7654},{"c":209.2700,"h":211.89,"l":205.97,"n":701234,"o":207.15,"t":"2024-08-05T04:00:00Z","v":119548589,"vw":209.012300}]},"next_page_token":null}';

beforeEach(() => {
  requests.length = 0;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.ALPACA_USER_AGENT_CONTACT = "market-data@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const pageToken = url.searchParams.get("page_token");
    return new Response(pageToken ? secondPage : firstPage, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": pageToken ? "request-two" : "request-one",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  delete process.env.ALPACA_API_KEY_ID;
  delete process.env.ALPACA_API_SECRET_KEY;
  delete process.env.ALPACA_USER_AGENT_CONTACT;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?us-ohlcv=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-ohlcv-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("US Alpaca OHLCV boundary", () => {
  test("paginates explicitly, preserves exact values, and collapses exact duplicates", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_stock_ohlcv"]);

    const result = await execute(tools.get("us_stock_ohlcv"), {
      symbol: "AAPL",
      startDate: "2024-08-01",
      endDate: "2024-08-05",
      asOf: "2024-08-06",
      feed: "sip",
      pageSize: 2,
      maxPages: 3,
      maxBars: 10,
    });

    expect(result.details.track).toBe("us");
    expect(result.details.trackContext.marketScope).toBe("us_stock_ohlcv");
    expect(result.details.trackContext.timezone).toBe("America/New_York");
    expect(result.details.provider).toBe("alpaca");
    expect(result.details.feed).toBe("sip");
    expect(result.details.currency).toBe("USD");
    expect(result.details.adjustment).toBe("raw");
    expect(result.details.session).toBe("alpaca_1day_provider_aggregation");
    expect(result.details.volumeUnit).toBe("shares");
    expect(result.details.pagesFetched).toBe(2);
    expect(result.details.requestIds).toEqual(["request-one", "request-two"]);
    expect(result.details.pagination.state).toBe("complete");
    expect(result.details.duplicatesCollapsed).toBe(1);
    expect(result.details.calendarCompleteness.state).toBe(
      "calendar_not_assessed",
    );
    expect(result.details.availability).toBe("bars_returned");
    expect(result.details.bars).toHaveLength(3);
    expect(result.details.bars[0].raw.open).toBe("185.6200");
    expect(result.details.bars[0].normalized.open).toBe("185.62");
    expect(result.details.bars[1].raw.close).toBe("189.840");
    expect(result.details.bars[2].normalized.close).toBe("209.27");
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");

    expect(requests).toHaveLength(2);
    expect(requests[0].url.pathname).toBe("/v2/stocks/bars");
    expect(requests[0].url.searchParams.get("symbols")).toBe("AAPL");
    expect(requests[0].url.searchParams.get("timeframe")).toBe("1Day");
    expect(requests[0].url.searchParams.get("adjustment")).toBe("raw");
    expect(requests[0].url.searchParams.get("feed")).toBe("sip");
    expect(requests[0].url.searchParams.get("currency")).toBe("USD");
    expect(requests[0].url.searchParams.get("sort")).toBe("asc");
    expect(requests[0].url.searchParams.get("asof")).toBe("2024-08-06");
    expect(requests[1].url.searchParams.get("page_token")).toBe("page-two");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );
    expect(requests[0].headers.get("user-agent")).toContain(
      "market-data@example.test",
    );
  });

  test("reports caller truncation instead of silently dropping the next page", async () => {
    const tools = await harness();
    const result = await execute(tools.get("us_stock_ohlcv"), {
      symbol: "AAPL",
      startDate: "2024-08-01",
      endDate: "2024-08-05",
      asOf: "2024-08-06",
      feed: "iex",
      pageSize: 2,
      maxPages: 1,
      maxBars: 10,
    });

    expect(result.details.feed).toBe("iex");
    expect(result.details.pagesFetched).toBe(1);
    expect(result.details.pagination.state).toBe(
      "truncated_by_page_budget",
    );
    expect(result.details.pagination.nextPageTokenAvailable).toBe(true);
    expect(result.details.limitations).toContain(
      "iex_only_not_consolidated_us_volume",
    );
  });
});
