import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

for (const name of [
  "finance_setup",
  "finance_track_status",
  "cn_setup",
  "hk_setup",
  "finance_guardrails",
  "finance_symbols",
  "sec_edgar",
  "sec_xbrl",
  "stock_fundamentals",
]) {
  describe(`${name} artifact`, () => {
    test("exports a Pi extension factory", async () => {
      const artifact = resolve(import.meta.dir, `../../dist/${name}/index.js`);
      const module = await import(`${artifact}?test=${Date.now()}`);
      expect(typeof module.default).toBe("function");
    });
  });
}
