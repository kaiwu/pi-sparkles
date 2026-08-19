import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
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
  process.env.AGENT_CONTACT = "market-data@example.test";
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
  delete process.env.AGENT_CONTACT;
});

async function harness() {
  const tools = new Map();
  tools.sessionEntries = [];
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    appendEntry(customType, data) {
      tools.sessionEntries.push({
        type: "custom",
        id: `session-entry-${tools.sessionEntries.length + 1}`,
        parentId: null,
        timestamp: "2026-08-19T00:00:00.000Z",
        customType,
        data,
      });
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
      mic: "XNAS",
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
    expect(result.details.trackContext.venueMic).toBe("XNAS");
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
    expect(result.details.gapAssessmentReceipt).toMatchObject({
      schema: "pi-sparkles/us-ohlcv-gap-receipt",
      schemaVersion: 1,
      digestAlgorithm: "sha256",
      provider: "alpaca",
      symbol: "AAPL",
      startDate: "2024-08-01",
      endDate: "2024-08-05",
      identityAsOf: "2024-08-06",
      feed: "sip",
      pagination: "complete",
      barDates: ["2024-08-01", "2024-08-02", "2024-08-05"],
      integrity: {
        state: "sha256_content_bound",
        scope: "canonical_gap_projection_v1",
        providerAuthenticated: false,
      },
    });
    expect(result.details.gapAssessmentReceipt.digest).toMatch(/^[0-9a-f]{64}$/);
    expect(result.details.gapAssessmentReceipt.digest).toBe(
      receiptDigest(result.details.gapAssessmentReceipt),
    );
    expect(result.details.gapAssessmentReceipt.pages).toEqual([
      {
        sequence: 1,
        requestId: "request-one",
        byteLength: Buffer.byteLength(firstPage),
        contentSha256: createHash("sha256").update(firstPage).digest("hex"),
      },
      {
        sequence: 2,
        requestId: "request-two",
        byteLength: Buffer.byteLength(secondPage),
        contentSha256: createHash("sha256").update(secondPage).digest("hex"),
      },
    ]);
    expect(result.details.availability).toBe("bars_returned");
    expect(result.details.bars).toHaveLength(3);
    expect(result.details.bars[0].raw.open).toBe("185.6200");
    expect(result.details.bars[0].normalized.open).toBe("185.62");
    expect(result.details.bars[1].raw.close).toBe("189.840");
    expect(result.details.bars[2].normalized.close).toBe("209.27");
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");
    expect(result.content[0].text).toContain(
      "Complete bounded, exact de-duplicated daily rows follow as CSV",
    );
    expect(result.content[0].text).toContain("pass only seriesReceipt");
    expect(result.content[0].text).toContain(
      "never manufacture an instructionRef or use a script",
    );
    expect(result.details.seriesReceipt).toMatch(/^[0-9a-f]{64}$/);
    expect(result.details.seriesReceipt).not.toBe(result.details.acquisitionReceipt);
    expect(result.details.seriesHandoff.state).toBe("supported");
    expect(tools.sessionEntries).toHaveLength(1);
    expect(tools.sessionEntries[0]).toMatchObject({
      customType: "pi_sparkles_finance_ohlcv.series_handoff.v1",
      data: {
        schema: "pi-sparkles/ohlcv-series-handoff",
        schemaVersion: 1,
        track: "us",
        instrumentId: "AAPL",
        mic: "XNAS",
        acquisitionReceipt: result.details.seriesReceipt,
      },
    });
    expect(result.details.sourceReference).toBe(
      result.details.gapAssessmentReceipt.sourceReference,
    );
    expect(result.content[0].text).toContain(
      `sourceReference=${result.details.sourceReference}`,
    );
    expect(result.content[0].text).toContain(
      "2024-08-01,2024-08-01T04:00:00Z,185.6200,188.10,184.22,187.12,50292117,612345,186.432100",
    );
    expect(result.content[0].text.match(/2024-08-02T04:00:00Z/g)).toHaveLength(
      1,
    );
    expect(typeof tools.get("us_stock_ohlcv").renderResult).toBe("function");
    const theme = { fg: (_color, text) => text };
    const collapsed = tools
      .get("us_stock_ohlcv")
      .renderResult(
        result,
        { expanded: false, isPartial: false },
        theme,
        {},
      )
      .render(500)
      .join("\n");
    expect(collapsed).toContain("3 bars");
    expect(collapsed).not.toContain("date,provider_timestamp,open");

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
    expect(result.details.seriesReceipt).toBeNull();
    expect(result.details.seriesHandoff).toEqual({
      state: "track_partial",
      reason: "missing_exact_caller_proven_mic",
    });
    expect(result.content[0].text).toContain(
      "No session seriesReceipt was created",
    );
    expect(result.content[0].text).toContain(
      "Never use acquisitionReceipt or gapAssessmentReceiptDigest as seriesReceipt",
    );
    expect(tools.sessionEntries).toHaveLength(0);
  });
});

function receiptDigest(receipt) {
  const canonical = {
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: "us",
    provider: receipt.provider,
    symbol: receipt.symbol,
    start_date: receipt.startDate,
    end_date: receipt.endDate,
    identity_as_of: receipt.identityAsOf,
    feed: receipt.feed,
    source_reference: receipt.sourceReference,
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    pagination: receipt.pagination,
    pages: receipt.pages.map((page) => ({
      sequence: page.sequence,
      request_id: page.requestId,
      byte_length: String(page.byteLength),
      content_sha256: page.contentSha256,
    })),
    bar_dates: receipt.barDates,
  };
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}
