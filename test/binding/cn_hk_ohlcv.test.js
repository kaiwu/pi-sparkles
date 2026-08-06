import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const originalFetch = globalThis.fetch;
const requests = [];

const cnFixture =
  '{"rc":0,"data":{"code":"600519","name":"贵州茅台","klines":["2024-08-01,1350.6000,1358.98,1363.35,1346.00,36147,4898665275.00,1.28,0.62,8.38,0.29","2024-08-02,1358.98,1328.36,1360.00,1320.00,37450,5004070406.00,2.94,-2.25,-30.62,0.30"]}}';

const hkFixture =
  '{"rc":0,"data":{"code":"00700","name":"腾讯控股","klines":["2024-08-01,370.200,372.400,375.000,368.600,15432100,5743210000.00,1.72,0.59,2.20,0.25","2024-08-02,372.400,368.800,373.600,367.000,17654300,6521000000.00,1.77,-0.97,-3.60,0.29"]}}';

beforeEach(() => {
  requests.length = 0;
  process.env.EASTMONEY_USER_AGENT_CONTACT = "market-data@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const body = url.searchParams.get("secid")?.startsWith("116.")
      ? hkFixture
      : cnFixture;
    return new Response(body, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  delete process.env.EASTMONEY_USER_AGENT_CONTACT;
});

async function harness(name) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const artifact = resolve(import.meta.dir, `../../dist/${name}/index.js`);
  const module = await import(`${artifact}?ohlcv=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "eastmoney-ohlcv-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("CN/HK Eastmoney OHLCV boundaries", () => {
  test("normalizes exact CN rows without inventing timestamps or volume units", async () => {
    const tools = await harness("cn_ohlcv");
    expect([...tools.keys()]).toEqual(["cn_stock_ohlcv"]);

    const result = await execute(tools.get("cn_stock_ohlcv"), {
      venue: "sse",
      board: "main",
      shareClass: "a_share",
      code: "600519",
      currency: "CNY",
      startDate: "2024-08-01",
      endDate: "2024-08-02",
      limit: 3,
    });

    expect(result.details.track).toBe("cn");
    expect(result.details.trackContext.marketScope).toBe("cn_stock_ohlcv");
    expect(result.details.trackContext.venueMic).toBe("XSHG");
    expect(result.details.trackContext.board).toBe("main");
    expect(result.details.trackContext.timezone).toBe("Asia/Shanghai");
    expect(result.details.provider).toBe("eastmoney");
    expect(result.details.shareClass).toBe("a_share");
    expect(result.details.currency).toBe("CNY");
    expect(result.details.currencyEvidence).toBe(
      "caller_declared_not_provider_verified",
    );
    expect(result.details.volumeUnit).toBe("unknown");
    expect(result.details.providerVolumeUnit).toBeNull();
    expect(result.details.adjustment).toBe("raw");
    expect(result.details.session).toBe(
      "eastmoney_klt_101_provider_aggregation",
    );
    expect(result.details.pagination.state).toBe("complete");
    expect(result.details.calendarCompleteness.state).toBe(
      "calendar_not_assessed",
    );
    expect(result.details.bars).toHaveLength(2);
    expect(result.details.bars[0].asOfBasis).toBe("session_date_anchor");
    expect(result.details.bars[0].providerDate).toBe("2024-08-01");
    expect(result.details.bars[0].raw.open).toBe("1350.6000");
    expect(result.details.bars[0].normalized.open).toBe("1350.6");
    expect(result.details.providerRows[0].amount).toBe("4898665275.00");

    expect(requests).toHaveLength(1);
    expect(requests[0].url.hostname).toBe("push2his.eastmoney.com");
    expect(requests[0].url.pathname).toBe("/api/qt/stock/kline/get");
    expect(requests[0].url.searchParams.get("secid")).toBe("1.600519");
    expect(requests[0].url.searchParams.get("klt")).toBe("101");
    expect(requests[0].url.searchParams.get("fqt")).toBe("0");
    expect(requests[0].url.searchParams.get("beg")).toBe("20240801");
    expect(requests[0].url.searchParams.get("end")).toBe("20240802");
    expect(requests[0].url.searchParams.get("lmt")).toBe("3");
    expect(requests[0].headers.get("user-agent")).toContain(
      "market-data@example.test",
    );
  });

  test("keeps HK currency caller-declared and exposes an exhausted row budget", async () => {
    const tools = await harness("hk_ohlcv");
    expect([...tools.keys()]).toEqual(["hk_stock_ohlcv"]);

    const result = await execute(tools.get("hk_stock_ohlcv"), {
      board: "main",
      shareClass: "ordinary_share",
      code: "00700",
      currency: "CNY",
      startDate: "2024-08-01",
      endDate: "2024-08-02",
      limit: 2,
    });

    expect(result.details.track).toBe("hk");
    expect(result.details.trackContext.marketScope).toBe("hk_stock_ohlcv");
    expect(result.details.trackContext.venueMic).toBe("XHKG");
    expect(result.details.trackContext.timezone).toBe("Asia/Hong_Kong");
    expect(result.details.currency).toBe("CNY");
    expect(result.details.volumeUnit).toBe("unknown");
    expect(result.details.pagination.state).toBe(
      "truncated_by_bar_budget",
    );
    expect(result.details.pagination.continuationTokenAvailable).toBe(false);
    expect(result.details.bars[0].raw.close).toBe("372.400");
    expect(result.details.bars[0].normalized.close).toBe("372.4");
    expect(result.details.providerRows[0].turnoverPercent).toBe("0.25");

    expect(requests).toHaveLength(1);
    expect(requests[0].url.searchParams.get("secid")).toBe("116.00700");
  });

  test("rejects incoherent CN board, share-class, and currency declarations before I/O", async () => {
    const tools = await harness("cn_ohlcv");
    await expect(
      execute(tools.get("cn_stock_ohlcv"), {
        venue: "bse",
        board: "beijing",
        shareClass: "b_share",
        code: "920079",
        currency: "CNY",
        startDate: "2024-08-01",
        endDate: "2024-08-02",
      }),
    ).rejects.toThrow("Invalid exact CN Eastmoney OHLCV identity or query");
    expect(requests).toHaveLength(0);
  });
});
