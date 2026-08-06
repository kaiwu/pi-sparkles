import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

for (const name of [
  "finance_setup",
  "finance_track_status",
  "cn_setup",
  "cn_disclosures",
  "cn_market_calendar",
  "cn_market_data",
  "cn_ohlcv",
  "cn_ohlcv_gaps",
  "cn_fundamentals",
  "cn_market_rules",
  "hk_setup",
  "hk_disclosures",
  "hk_market_calendar",
  "hk_market_data",
  "hk_ohlcv",
  "hk_ohlcv_gaps",
  "hk_fundamentals",
  "hk_market_rules",
  "finance_guardrails",
  "finance_symbols",
  "sec_edgar",
  "sec_xbrl",
  "stock_fundamentals",
  "stock_research_report",
  "watchlist",
  "us_market_calendar",
  "us_market_rules",
  "us_ohlcv_gaps",
  "us_quote",
  "us_ohlcv",
]) {
  describe(`${name} artifact`, () => {
    test("exports a Pi extension factory", async () => {
      const artifact = resolve(import.meta.dir, `../../dist/${name}/index.js`);
      const module = await import(`${artifact}?test=${Date.now()}`);
      expect(typeof module.default).toBe("function");
    });
  });
}
