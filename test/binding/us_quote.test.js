import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/us_quote/index.js");
const originalFetch = globalThis.fetch;
const requests = [];

const quote =
  '{"quotes":{"AAPL":{"ap":189.1200,"as":4,"ax":"V","bp":189.1000,"bs":7,"bx":"V","c":["R"],"t":"2024-08-06T19:59:59.123456789Z","z":"C"}}}';
const quoteWithoutAsk =
  '{"quotes":{"AAPL":{"ap":0,"as":0,"ax":" ","bp":290.54,"bs":40,"bx":"V","c":["R"],"t":"2026-08-17T20:00:02.436902433Z","z":"C"}}}';
let responseBody;

beforeEach(() => {
  requests.length = 0;
  responseBody = quote;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.AGENT_CONTACT = "market-data@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    return new Response(responseBody, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": "quote-request-one",
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
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?us-quote=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-quote-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("US Alpaca latest quote boundary", () => {
  test("uses an explicit feed and preserves exact quote tokens and market codes", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_stock_quote"]);

    const result = await execute(tools.get("us_stock_quote"), {
      symbol: "AAPL",
      feed: "sip",
    });

    expect(result.details.track).toBe("us");
    expect(result.details.trackContext.marketScope).toBe("us_stock_quote");
    expect(result.details.trackContext.timezone).toBe("America/New_York");
    expect(result.details.provider).toBe("alpaca");
    expect(result.details.feed).toBe("sip");
    expect(result.details.currency).toBe("USD");
    expect(result.details.quoteType).toBe(
      "latest_quote_with_side_availability",
    );
    expect(result.details.bid).toEqual({
      exchange: "V",
      rawPrice: "189.1000",
      normalizedPrice: "189.1",
      rawSize: "7",
      normalizedSize: "7",
    });
    expect(result.details.ask.rawPrice).toBe("189.1200");
    expect(result.details.ask.normalizedPrice).toBe("189.12");
    expect(result.details.sideAvailability).toEqual({
      bid: "available",
      ask: "available",
    });
    expect(result.details.providerSideSentinels).toEqual({
      bid: null,
      ask: null,
    });
    expect(result.details.conditionCodes).toEqual(["R"]);
    expect(result.details.tape).toBe("C");
    expect(result.details.sizeUnit).toBe("provider_reported_unverified");
    expect(result.details.freshness).toBe("unknown");
    expect(result.details.latency).toBe("unknown");
    expect(result.details.session).toBe("unknown");
    expect(result.details.entitlement).toBe("credentialed_sip_latest");
    expect(result.details.requestId).toBe("quote-request-one");
    expect(result.details.limitations).toContain(
      "sip_access_and_recency_depend_on_user_subscription",
    );
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");

    expect(requests).toHaveLength(1);
    expect(requests[0].url.pathname).toBe("/v2/stocks/quotes/latest");
    expect(requests[0].url.searchParams.get("symbols")).toBe("AAPL");
    expect(requests[0].url.searchParams.get("feed")).toBe("sip");
    expect(requests[0].url.searchParams.get("currency")).toBe("USD");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );
    expect(requests[0].headers.get("user-agent")).toContain(
      "market-data@example.test",
    );
  });

  test("preserves a provider no-ask sentinel without presenting zero as a quote", async () => {
    responseBody = quoteWithoutAsk;
    const tools = await harness();
    const result = await execute(tools.get("us_stock_quote"), {
      symbol: "AAPL",
      feed: "iex",
    });

    expect(result.details.bid.rawPrice).toBe("290.54");
    expect(result.details.ask).toBeNull();
    expect(result.details.sideAvailability).toEqual({
      bid: "available",
      ask: "unavailable",
    });
    expect(result.details.providerSideSentinels.ask).toEqual({
      reason: "provider_reported_no_current_side",
      exchangeLexeme: " ",
      rawPrice: "0",
      normalizedPrice: "0",
      rawSize: "0",
      normalizedSize: "0",
    });
    expect(result.content[0].text).toContain("ask unavailable");
    expect(requests).toHaveLength(1);
  });
});
