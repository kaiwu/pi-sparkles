import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/us_market_rules/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?market-rules=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-market-rules-query",
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
    date: "2026-08-06",
    currency: "USD",
    securityClass: "nms_stock",
    marketStatus: "normal",
    regime: "regular_displayed_quote",
    nominalPrice: "182.375",
    ...overrides,
  };
}

describe("isolated official US effective rules", () => {
  test("retains exact NYSE listing scope and the SEC relief boundary", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_trading_rules"]);

    const result = await execute(tools.get("us_trading_rules"), input());
    expect(result.details.track).toBe("us");
    expect(result.details.trackContext).toMatchObject({
      track: "us",
      venueMic: "XNYS",
      board: "nyse",
      timezone: "America/New_York",
    });
    expect(result.details.listing).toEqual({
      instrumentId: "figi:BBG000BLNNH6",
      symbol: "IBM",
      mic: "XNYS",
      identityEvidence: "caller_supplied_unverified",
    });
    expect(result.details.effective).toEqual({
      start: "2026-06-11",
      end: "2027-10-31",
    });
    expect(result.details.rule).toMatchObject({
      nominalPrice: "182.375",
      priceBand: "at_or_above_1_usd",
      minimumPriceIncrement: "0.01",
      appliesTo: "regular_displayed_exchange_quotation",
      roundLotShares: null,
      settlement: null,
    });
    expect(result.details.sources).toHaveLength(2);
    expect(result.details.sources[0]).toMatchObject({
      provider: "New York Stock Exchange",
      kind: "exchange",
    });
    expect(result.details.sources[1]).toEqual({
      provider: "U.S. Securities and Exchange Commission",
      reference: "https://www.sec.gov/files/rules/exorders/2026/34-105656.pdf",
      kind: "regulator",
    });
    expect(result.details.audit).toMatchObject({
      sourceReviewed: true,
      callerMustVerifyListingClassAndStatus: true,
      amendedHalfCentRegime: "not_yet_required_under_sec_34_105656",
      nextKnownComplianceBoundary: "2027-11-01",
    });
  });

  test("selects Nasdaq's sub-dollar increment and fails beyond review", async () => {
    const tools = await harness();
    const result = await execute(
      tools.get("us_trading_rules"),
      input({
        venue: "nasdaq",
        instrumentId: "figi:BBG000TEST01",
        symbol: "TEST",
        nominalPrice: "0.98765",
      }),
    );
    expect(result.details.trackContext.venueMic).toBe("XNAS");
    expect(result.details.rule).toMatchObject({
      priceBand: "below_1_usd",
      minimumPriceIncrement: "0.0001",
    });
    expect(result.details.clauses).toEqual([
      "nasdaq_equity_2_section_5_a_2_i",
      "sec_release_34_105656",
    ]);

    await expect(
      execute(
        tools.get("us_trading_rules"),
        input({ date: "2027-11-01" }),
      ),
    ).rejects.toThrow("no historical or future fallback");
  });
});
