import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/stock_screener/index.js");
const originalFetch = globalThis.fetch;
const requests = [];

const assets =
  '[{"id":"asset-aapl","class":"us_equity","exchange":"NASDAQ","symbol":"AAPL","name":"Apple Inc. Common Stock","status":"active","tradable":true,"marginable":true,"shortable":true,"easy_to_borrow":true,"fractionable":true,"attributes":["has_options"]},{"id":"asset-msft","class":"us_equity","exchange":"NASDAQ","symbol":"MSFT","name":"Microsoft Corporation","status":"inactive","tradable":false,"marginable":true,"shortable":false,"easy_to_borrow":false,"fractionable":true,"attributes":[]}]';

beforeEach(() => {
  requests.length = 0;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.ALPACA_USER_AGENT_CONTACT = "universe@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    return new Response(assets, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": "assets-request-one",
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
    `${artifact}?stock-screener=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, maximumAssets = 10) {
  return tool.execute(
    "stock-universe-query",
    {
      environment: "paper",
      status: "active",
      exchange: "NASDAQ",
      maximumAssets,
    },
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("stock universe Alpaca boundary", () => {
  test("copies bounded asset-master rows and makes no screening decision", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["stock_universe"]);

    const result = await execute(tools.get("stock_universe"));
    const sourceReference =
      "https://paper-api.alpaca.markets/v2/assets?status=active&asset_class=us_equity&exchange=NASDAQ";

    expect(result.details.track).toBe("us");
    expect(result.details.trackContext.marketScope).toBe("us_stock_universe");
    expect(result.details.provider).toBe("alpaca");
    expect(result.details.environment).toBe("paper");
    expect(result.details.filters).toEqual({
      status: "active",
      assetClass: "us_equity",
      exchange: "NASDAQ",
    });
    expect(result.details.sourceReference).toBe(sourceReference);
    expect(result.details.requestId).toBe("assets-request-one");
    expect(result.details.rowBudget).toEqual({
      maximum: 10,
      received: 2,
      outcome: "within_bound",
    });
    expect(result.details.rows.map((row) => row.symbol)).toEqual([
      "AAPL",
      "MSFT",
    ]);
    expect(result.details.rows[1]).toMatchObject({
      providerMembership: "provider_returned_row",
      status: "inactive",
      tradable: false,
      shortable: false,
    });
    expect(result.details.decisionOwner).toBe("llm");
    expect(result.details.pluginDecisionFields).toEqual([]);
    expect(result.details.sourceReceipt).toBe(sha256(assets));
    expect(result.details.universeReceipt).toBe(
      sha256(`${sourceReference}\n${assets}`),
    );
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");
    expect(JSON.stringify(result.details)).not.toMatch(
      /"(rank|qualified|selected|recommended)"/,
    );

    expect(requests).toHaveLength(1);
    expect(requests[0].url.hostname).toBe("paper-api.alpaca.markets");
    expect(requests[0].url.pathname).toBe("/v2/assets");
    expect(requests[0].url.searchParams.get("status")).toBe("active");
    expect(requests[0].url.searchParams.get("asset_class")).toBe(
      "us_equity",
    );
    expect(requests[0].url.searchParams.get("exchange")).toBe("NASDAQ");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );
  });

  test("fails rather than truncating a response beyond the caller row budget", async () => {
    const tools = await harness();
    await expect(execute(tools.get("stock_universe"), 1)).rejects.toThrow(
      "over-budget asset array",
    );
  });
});

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}
