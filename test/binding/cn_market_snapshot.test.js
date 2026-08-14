import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/cn_market_snapshot/index.js",
);

const originalFetch = globalThis.fetch;
const requests = [];

const overviewBody =
  '{"rc":0,"data":{"total":4,"diff":[{"f2":392718,"f3":1,"f4":22,"f5":499525613,"f6":990371924237.7,"f12":"000001","f13":1,"f14":"上证指数","f15":393264,"f16":390370,"f17":393002,"f18":392696,"f104":1012,"f105":1254,"f106":85},{"f2":1435431,"f3":45,"f4":6487,"f5":642557319,"f6":1152471301164.9692,"f12":"399001","f13":0,"f14":"深证成指","f15":1438418,"f16":1420399,"f17":1433541,"f18":1428944,"f104":1338,"f105":1499,"f106":95},{"f2":362630,"f3":112,"f4":4026,"f5":199294854,"f6":556471146251.9,"f12":"399006","f13":0,"f14":"创业板指","f15":363303,"f16":357861,"f17":361019,"f18":358604,"f104":753,"f105":612,"f106":36},{"f2":466588,"f3":4,"f4":193,"f5":178430696,"f6":549769606284.4,"f12":"000300","f13":1,"f14":"沪深300","f15":467671,"f16":463713,"f17":467298,"f18":466395,"f104":108,"f105":186,"f106":6}]}}';

beforeEach(() => {
  requests.length = 0;
  process.env.AGENT_CONTACT = "market-overview@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    requests.push({ url, init });
    const code = url.searchParams.get("secid")?.split(".").at(-1);
    const body = url.pathname.endsWith("/stock/kline/get")
      ? JSON.stringify({
          rc: 0,
          data: {
            code,
            name: `provider-${code}`,
            klines: [
              "2026-08-07,100,100,101,99,1,1,1,0,0,0",
              "2026-08-10,101,101,102,100,1,1,1,1,1,0",
              "2026-08-11,102,102,103,101,1,1,1,1,1,0",
              "2026-08-12,103,103,104,102,1,1,1,1,1,0",
              "2026-08-13,104,104,105,103,1,1,1,1,1,0",
              "2026-08-14,110,110,111,109,1,1,1,1,1,0",
            ],
          },
        })
      : overviewBody;
    return new Response(body, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
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
    `${artifact}?cn-market-snapshot=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input = {}) {
  return tool.execute(
    "cn-market-overview",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("acquisition-backed CN market overview", () => {
  test("uses one exact batch and preserves evidence boundaries", async () => {
    const tools = await harness();
    expect([...tools.keys()].sort()).toEqual([
      "cn_market_overview",
      "cn_market_snapshot",
      "cn_sector_trends",
    ]);

    const result = await execute(tools.get("cn_market_overview"));
    expect(requests).toHaveLength(1);
    expect(requests[0].url.pathname).toBe("/api/qt/ulist.np/get");
    expect(requests[0].url.searchParams.get("secids")).toBe(
      "1.000001,0.399001,0.399006,1.000300",
    );
    expect(result.details).toMatchObject({
      track: "cn",
      provider: "eastmoney",
      marketScope: "sse_szse_provider_index_associated_overview",
      latency: "unknown",
      entitlement: "public_web_local_analysis",
      redistribution: "unknown",
    });
    expect(result.details.benchmarks).toHaveLength(4);
    expect(result.details.benchmarks[0]).toMatchObject({
      code: "000001",
      instrumentKind: "benchmark_index",
      last: { state: "observed", raw: "3927.18", unit: "CNY" },
      changePercent: { state: "observed", raw: "0.01", unit: "percent" },
      providerReportedAmount: {
        state: "observed",
        raw: "990371924237.7",
        unit: "declared_CNY_semantics_unverified",
      },
    });
    expect(result.details.benchmarks[1].providerReportedAmount.raw).toBe(
      "1152471301164.9692",
    );
    expect(result.details.marketBreadth).toMatchObject({
      state: "observed_provider_aggregate",
      completeness: "unknown",
      advanced: 2350,
      declined: 2753,
      unchanged: 180,
      excludedCnVenue: "bse",
    });
    expect(result.details.intradaySequence.state).toBe("unavailable");
    expect(result.details.fundFlow.state).toBe("unavailable");
    expect(result.details.sectorRotation.state).toBe("unavailable");
    expect(
      result.details.providerReportedAmounts.trendVersusPriorSession.state,
    ).toBe("unavailable");
    expect(result.content[0].text).toContain("No intraday ordering");
    expect(result.content[0].text).not.toContain(
      "market-overview@example.test",
    );
    expect(result.details.acquisitionReceipt.canonicalSha256).toMatch(
      /^[0-9a-f]{64}$/,
    );
  });

  test(
    "uses one Pi call for the exact eleven-sector profile and returns mechanical price comparisons",
    async () => {
      const tools = await harness();
      const result = await execute(tools.get("cn_sector_trends"), {
        startDate: "2026-08-07",
        endDate: "2026-08-14",
      });

      const secids = requests.map((request) =>
        request.url.searchParams.get("secid"),
      );
      expect(requests).toHaveLength(11);
      expect(secids).toEqual([
        "1.000928",
        "1.000929",
        "1.000930",
        "1.000931",
        "1.000932",
        "1.000933",
        "1.000974",
        "0.399965",
        "1.000935",
        "1.000936",
        "1.000937",
      ]);
      expect(secids).not.toContain("1.000934");
      expect(result.details).toMatchObject({
        track: "cn",
        provider: "eastmoney",
        classificationAuthority: "CSI",
        profileSectorCount: 11,
        legacyCombinedFinancialRealEstateIndexIncluded: false,
        firstObservedDate: "2026-08-07",
        latestObservedDate: "2026-08-14",
        fundFlow: { state: "unavailable" },
        constituentBreadth: { state: "unavailable" },
        causalRotation: { state: "unavailable" },
        themeExposure: { state: "unavailable" },
        acquisitionReceipt: { providerRequestCount: 11 },
      });
      expect(result.details.sectors).toHaveLength(11);
      expect(result.details.sectors).toContainEqual(
        expect.objectContaining({
          sectorCode: "000974",
          sectorLabel: "financials",
          instrumentKind: "sector_index",
          latestSessionReturnPercent: "5.77",
          fiveSessionReturnPercent: "10",
          windowReturnPercent: "10",
        }),
      );
      expect(result.details.sectors).toContainEqual(
        expect.objectContaining({
          sectorCode: "399965",
          sectorLabel: "real_estate",
          providerMarket: "cn_szse",
        }),
      );
      expect(result.content[0].text).toContain(
        "do not establish fund flow, constituent breadth, causal rotation",
      );
      expect(result.content[0].text).not.toContain("AI");
      expect(result.content[0].text).not.toContain("资金回流");
    },
    20_000,
  );

  test("returns a typed identity failure for a mismatched benchmark set", async () => {
    globalThis.fetch = async () =>
      new Response(overviewBody.replace('"399006"', '"399007"'), {
        status: 200,
      });
    const tools = await harness();
    try {
      await execute(tools.get("cn_market_overview"));
      throw new Error("expected overview failure");
    } catch (error) {
      expect(error.code).toBe("provider_decode_failed");
      expect(error.details).toMatchObject({
        code: "provider_decode_failed",
        track: "cn",
        provider: "eastmoney",
        fallbackAttempted: false,
      });
      expect(error.message).toContain("identity-mismatched");
    }
  });
});
