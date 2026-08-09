import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_corporate_actions/index.js",
);
const originalFetch = globalThis.fetch;
const originalKeyId = process.env.ALPACA_API_KEY_ID;
const originalSecretKey = process.env.ALPACA_API_SECRET_KEY;
const originalContact = process.env.ALPACA_USER_AGENT_CONTACT;
const originalProduct = process.env.ALPACA_USER_AGENT_PRODUCT;
const requests = [];

const firstPage =
  '{"corporate_actions":{"cash_dividends":[{"id":"cash-1","symbol":"AAPL","cusip":"037833100","isin":"US0378331005","rate":0.2400,"special":false,"foreign":false,"process_date":"2024-08-10","ex_date":"2024-08-11","record_date":"2024-08-12","payable_date":"2024-08-20","currency":"USD"}],"forward_splits":[{"id":"forward-1","symbol":"AAPL","cusip":"037833100","old_rate":1,"new_rate":4.000,"process_date":"2024-08-12","ex_date":"2024-08-13"}]},"next_page_token":"page-two"}';

const secondPage =
  '{"corporate_actions":{"stock_dividends":[{"id":"stock-1","symbol":"AAPL","cusip":"037833100","rate":0.050,"process_date":"2024-08-13","ex_date":"2024-08-14"}],"reverse_splits":[{"id":"reverse-1","symbol":"AAPL","new_symbol":"APLC","old_cusip":"037833100","new_cusip":"037833209","old_rate":10,"new_rate":1,"process_date":"2024-08-14","ex_date":"2024-08-15"}],"name_changes":[{"id":"name-1","old_symbol":"AAPL","new_symbol":"APPL","old_cusip":"037833100","new_cusip":"037833308","process_date":"2024-08-15","currency":""}]},"next_page_token":null}';

beforeEach(() => {
  requests.length = 0;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.ALPACA_USER_AGENT_CONTACT = "research@example.test";
  process.env.ALPACA_USER_AGENT_PRODUCT = "pi-sparkles-test/0.1";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const body = url.searchParams.has("page_token") ? secondPage : firstPage;
    return new Response(body, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": url.searchParams.has("page_token")
          ? "request-two"
          : "request-one",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("ALPACA_API_KEY_ID", originalKeyId);
  restore("ALPACA_API_SECRET_KEY", originalSecretKey);
  restore("ALPACA_USER_AGENT_CONTACT", originalContact);
  restore("ALPACA_USER_AGENT_PRODUCT", originalProduct);
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-corporate-actions=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tool, value = input(), signal = new AbortController().signal) {
  return tool.execute(
    "corporate-actions-query",
    value,
    signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input(overrides = {}) {
  return {
    track: "us",
    venue: "XNAS",
    symbol: "AAPL",
    cusip: "037833100",
    startDate: "2024-08-01",
    endDate: "2024-08-31",
    types: [
      "cash_dividend",
      "stock_dividend",
      "forward_split",
      "reverse_split",
      "name_change",
    ],
    dataQuality: "all",
    pageSize: 3,
    maximumPages: 3,
    maximumActions: 10,
    ...overrides,
  };
}

describe("stock corporate actions boundary", () => {
  test("registers only the read-only corporate_actions tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["corporate_actions"]);
  });

  test("paginates the exact US request and preserves source fields and evidence", async () => {
    const tools = await harness();
    const result = await execute(tools.get("corporate_actions"));

    expect(requests).toHaveLength(2);
    expect(requests[0].url.origin).toBe("https://data.alpaca.markets");
    expect(requests[0].url.pathname).toBe("/v1/corporate-actions");
    expect(requests[0].url.searchParams.get("symbols")).toBe("AAPL");
    expect(requests[0].url.searchParams.get("cusips")).toBe("037833100");
    expect(requests[0].url.searchParams.get("types")).toBe(
      "cash_dividend,stock_dividend,forward_split,reverse_split,name_change",
    );
    expect(requests[0].url.searchParams.get("region")).toBe("us");
    expect(requests[0].url.searchParams.get("start")).toBe("2024-08-01");
    expect(requests[0].url.searchParams.get("end")).toBe("2024-08-31");
    expect(requests[0].url.searchParams.get("limit")).toBe("3");
    expect(requests[0].url.searchParams.get("data_quality")).toBe("all");
    expect(requests[0].url.searchParams.get("sort")).toBe("asc");
    expect(requests[1].url.searchParams.get("page_token")).toBe("page-two");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );

    expect(result.details).toMatchObject({
      operation: "corporate_actions",
      track: "us",
      venue: "XNAS",
      venueEvidence: "caller_declared_not_provider_verified",
      actionCount: 5,
      pageCount: 2,
      pagination: { state: "complete", nextPageToken: null },
      query: {
        symbol: "AAPL",
        cusip: "037833100",
        dateAxis: "alpaca_process_date_inclusive",
        dataQuality: "all",
        region: "us",
        sort: "asc",
      },
      scope: {
        processDateMeaning: "date_processed_by_alpaca",
        announcementTimestamp: null,
        effectiveDateInference: null,
        priceAdjustment: null,
        absenceClaim: false,
        emptyCurrency: "preserved_without_usd_assumption",
      },
    });
    expect(result.details.pages[0].actions.cashDividends[0]).toMatchObject({
      id: "cash-1",
      rate: "0.2400",
      processDate: "2024-08-10",
      symbolCorrelation: "exact_source_match",
      cusipCorrelation: "exact_source_match",
    });
    expect(result.details.pages[0].actions.forwardSplits[0].newRate).toBe(
      "4.000",
    );
    expect(result.details.pages[1].actions.stockDividends[0].rate).toBe(
      "0.050",
    );
    expect(result.details.pages[1].actions.nameChanges[0]).toMatchObject({
      oldSymbol: "AAPL",
      newSymbol: "APPL",
      currency: "",
    });
    expect(result.details.pages[0]).toMatchObject({
      sequence: 1,
      requestId: "request-one",
      responseByteLength: Buffer.byteLength(firstPage),
      contentSha256: createHash("sha256").update(firstPage).digest("hex"),
    });
    expect(result.details.pages[1]).toMatchObject({
      sequence: 2,
      requestId: "request-two",
      responseByteLength: Buffer.byteLength(secondPage),
      contentSha256: createHash("sha256").update(secondPage).digest("hex"),
    });
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");
  });

  test("reports action-budget truncation with the next token intact", async () => {
    const tools = await harness();
    const result = await execute(
      tools.get("corporate_actions"),
      input({ maximumActions: 2 }),
    );

    expect(requests).toHaveLength(1);
    expect(result.details.actionCount).toBe(2);
    expect(result.details.pagination).toEqual({
      state: "truncated_by_action_budget",
      budget: 2,
      nextPageToken: "page-two",
    });
  });

  test("rejects a returned source identity that cannot match the exact query", async () => {
    globalThis.fetch = async () =>
      new Response(
        firstPage
          .replaceAll("AAPL", "MSFT")
          .replace('"next_page_token":"page-two"', '"next_page_token":null'),
        {
        headers: { "content-type": "application/json" },
        },
      );
    const tools = await harness();

    await expect(execute(tools.get("corporate_actions"))).rejects.toThrow(
      "source identity did not correlate",
    );
  });

  test("rejects unrequested returned action types", async () => {
    globalThis.fetch = async () =>
      new Response(secondPage, {
        headers: { "content-type": "application/json" },
      });
    const tools = await harness();

    await expect(
      execute(
        tools.get("corporate_actions"),
        input({ types: ["cash_dividend"] }),
      ),
    ).rejects.toThrow("invalid, mismatched, or over-budget corporate actions");
  });

  test("honors cancellation before transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(firstPage);
    };
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();

    await expect(
      execute(tools.get("corporate_actions"), input(), controller.signal),
    ).rejects.toThrow("Cancelled");
    expect(called).toBe(false);
  });
});

function restore(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
