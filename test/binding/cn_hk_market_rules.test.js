import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_market_rules/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_market_rules/index.js"),
};

async function harness(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?market-rules=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "market-rules-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("isolated official CN/HK effective rules", () => {
  test("CN retains exact board, date, clauses, and standard rule scope", async () => {
    const tools = await harness("cn");
    expect([...tools.keys()]).toEqual(["cn_trading_rules"]);

    const result = await execute(tools.get("cn_trading_rules"), {
      venue: "sse",
      board: "star",
      regime: "established_normal_equity",
      date: "2026-08-05",
    });
    expect(result.details.track).toBe("cn");
    expect(result.details.trackContext.venueMic).toBe("XSHG");
    expect(result.details.trackContext.board).toBe("star");
    expect(result.details.currency).toBe("CNY");
    expect(result.details.effective.start).toBe("2026-07-06");
    expect(result.details.rule).toMatchObject({
      tickSize: "0.01",
      minimumBuyQuantity: 200,
      buyQuantityIncrement: null,
      dailyPriceLimitRatio: "0.2",
    });
    expect(result.details.source.reference).toContain("sse.com.cn");
    expect(result.details.clauses).toEqual(["3.3.11", "6.6", "6.7"]);
    expect(result.details.audit.callerMustVerifyListingRegime).toBeTrue();

    await expect(
      execute(tools.get("cn_trading_rules"), {
        venue: "sse",
        board: "chinext",
        regime: "established_normal_equity",
        date: "2026-08-05",
      }),
    ).rejects.toThrow("venue and board");
  });

  test("HK computes only reviewed price bands and preserves board-lot evidence", async () => {
    const tools = await harness("hk");
    expect([...tools.keys()]).toEqual(["hk_trading_rules"]);

    const result = await execute(tools.get("hk_trading_rules"), {
      date: "2026-08-05",
      currency: "HKD",
      productClass: "applicable_equity",
      nominalPrice: "9.995",
      boardLot: 500,
      boardLotSource: "HKEX issuer profile for 00700 retrieved 2026-08-05",
    });
    expect(result.details.track).toBe("hk");
    expect(result.details.trackContext.venueMic).toBe("XHKG");
    expect(result.details.effective.start).toBe("2026-08-03");
    expect(result.details.rule).toMatchObject({
      nominalPrice: "9.995",
      priceBand: "0.50_to_10.00",
      tickSize: "0.005",
      boardLot: 500,
      boardLotEvidenceStatus: "caller_supplied_unverified",
    });
    expect(result.details.rule.boardLotEvidence).toContain("00700");
    expect(result.details.sources).toHaveLength(2);
    expect(result.details.audit.callerMustAuditBoardLotEvidence).toBeTrue();

    await expect(
      execute(tools.get("hk_trading_rules"), {
        date: "2026-08-05",
        currency: "HKD",
        productClass: "applicable_equity",
        nominalPrice: "50.00",
        boardLot: 500,
        boardLotSource: "HKEX issuer profile",
      }),
    ).rejects.toThrow("0.50 inclusive to 50.00 exclusive");
  });
});
