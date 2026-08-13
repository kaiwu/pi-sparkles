import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_market_data/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_market_data/index.js"),
};

const originalFetch = globalThis.fetch;
const requests = [];

function quoteFixture(code) {
  if (code === "00700") {
    return {
      rc: 0,
      data: {
        f43: 492200,
        f44: 497800,
        f45: 482200,
        f46: 493400,
        f47: 25662478,
        f57: "00700",
        f58: "腾讯控股",
        f59: 3,
        f60: 487600,
        f86: 1785917339,
      },
    };
  }
  return {
    rc: 0,
    data: {
      f43: 1516,
      f44: 1531,
      f45: 1460,
      f46: 1477,
      f47: 100327,
      f51: 1921,
      f52: 1035,
      f57: "920079",
      f58: "乔路铭",
      f59: 2,
      f60: 1478,
      f86: 1785915322,
    },
  };
}

function historyFixture(code) {
  return {
    rc: 0,
    data: {
      code,
      name: code === "00700" ? "腾讯控股" : "乔路铭",
      klines: [
        "2026-08-03,14.77,14.91,15.20,14.60,90000,1350000.00,4.06,0.95,0.14,1.23",
        "2026-08-04,14.91,15.16,15.31,14.80,100327,1516000.00,3.42,1.68,0.25,1.37",
      ],
    },
  };
}

beforeEach(() => {
  requests.length = 0;
  process.env.EASTMONEY_USER_AGENT_CONTACT = "market-data@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const code = url.searchParams.get("secid").split(".").at(-1);
    const body = url.pathname.endsWith("/stock/get")
      ? quoteFixture(code)
      : historyFixture(code);
    return new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  delete process.env.EASTMONEY_USER_AGENT_CONTACT;
});

async function harness(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?market-data=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "market-data-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("isolated CN/HK Eastmoney market-data boundaries", () => {
  test("CN preserves explicit BSE identity, source scaling, and raw bars", async () => {
    const tools = await harness("cn");
    expect([...tools.keys()].sort()).toEqual([
      "cn_raw_vendor_history",
      "cn_raw_vendor_quote",
    ]);

    const quote = await execute(tools.get("cn_raw_vendor_quote"), {
      venue: "bse",
      code: "920079",
    });
    expect(quote.details.track).toBe("cn");
    expect(quote.details.trackContext.venueMic).toBe("XBSE");
    expect(quote.details.market).toBe("cn_bse");
    expect(quote.details.last).toBe("15.16");
    expect(quote.details.priceLimitUp).toBe("19.21");
    expect(quote.details.declaredCurrency).toBe("CNY");
    expect(quote.details.latency).toBe("unknown");
    expect(quote.details.redistribution).toBe("unknown");
    expect(quote.details.retrievedAtUnixMilliseconds).toBeGreaterThan(0);

    const history = await execute(tools.get("cn_raw_vendor_history"), {
      venue: "bse",
      code: "920079",
      startDate: "2026-08-01",
      endDate: "2026-08-05",
      limit: 10,
    });
    expect(history.details.track).toBe("cn");
    expect(history.details.adjustment).toBe("raw_unadjusted_fqt_0");
    expect(history.details.bars[0].amount).toBe("1350000.00");
    expect(history.details.bars[1].close).toBe("15.16");
    expect(history.content[0].text).toContain(
      "Complete bounded daily rows follow as CSV",
    );
    expect(history.content[0].text).toContain(
      "do not request TUSHARE_TOKEN or CNINFO for this returned series",
    );
    expect(history.content[0].text).toContain(
      "2026-08-04,14.91,15.31,14.80,15.16,100327,1516000.00",
    );
    expect(typeof tools.get("cn_raw_vendor_history").renderResult).toBe(
      "function",
    );
    const theme = { fg: (_color, text) => text };
    const collapsed = tools
      .get("cn_raw_vendor_history")
      .renderResult(
        history,
        { expanded: false, isPartial: false },
        theme,
        {},
      )
      .render(500)
      .join("\n");
    expect(collapsed).toContain("2 bars");
    expect(collapsed).not.toContain("date,open,high,low,close");
    const expanded = tools
      .get("cn_raw_vendor_history")
      .renderResult(
        history,
        { expanded: true, isPartial: false },
        theme,
        {},
      )
      .render(500)
      .join("\n");
    expect(expanded).toContain("date,open,high,low,close,volume,amount");
    expect(requests[0].url.searchParams.get("secid")).toBe("0.920079");
    expect(requests[0].headers.get("user-agent")).toContain(
      "market-data@example.test",
    );
  });

  test("HK never assumes currency and retains its five-digit market ID", async () => {
    const tools = await harness("hk");
    expect([...tools.keys()].sort()).toEqual([
      "hk_stock_history",
      "hk_stock_quote",
    ]);

    const quote = await execute(tools.get("hk_stock_quote"), {
      code: "00700",
      currency: "HKD",
    });
    expect(quote.details.track).toBe("hk");
    expect(quote.details.trackContext.venueMic).toBe("XHKG");
    expect(quote.details.last).toBe("492.200");
    expect(quote.details.declaredCurrency).toBe("HKD");
    expect(quote.details.currencyEvidence).toBe(
      "caller_declared_not_provider_verified",
    );
    expect(quote.details.priceLimitUp).toBeNull();
    expect(requests[0].url.searchParams.get("secid")).toBe("116.00700");

    const history = await execute(tools.get("hk_stock_history"), {
      code: "00700",
      currency: "HKD",
      startDate: "2026-08-01",
      endDate: "2026-08-05",
      limit: 10,
    });
    expect(history.details.track).toBe("hk");
    expect(history.details.currencyEvidence).toBe(
      "caller_declared_not_provider_verified",
    );
    expect(history.details.bars).toHaveLength(2);
    expect(history.content[0].text).toContain(
      "Complete bounded daily rows follow as CSV",
    );
    expect(history.content[0].text).toContain(
      "2026-08-04,14.91,15.31,14.80,15.16,100327,1516000.00",
    );
    expect(typeof tools.get("hk_stock_history").renderResult).toBe("function");
    const theme = { fg: (_color, text) => text };
    const collapsed = tools
      .get("hk_stock_history")
      .renderResult(
        history,
        { expanded: false, isPartial: false },
        theme,
        {},
      )
      .render(500)
      .join("\n");
    expect(collapsed).toContain("2 bars");
    expect(collapsed).not.toContain("date,open,high,low,close");
    const expanded = tools
      .get("hk_stock_history")
      .renderResult(
        history,
        { expanded: true, isPartial: false },
        theme,
        {},
      )
      .render(500)
      .join("\n");
    expect(expanded).toContain("date,open,high,low,close,volume,amount");
  });
});
