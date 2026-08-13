import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

async function toolsFor(plugin) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const artifact = resolve(import.meta.dir, `../../dist/${plugin}/index.js`);
  const module = await import(
    `${artifact}?cn-routing=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

describe("CN pre-invocation tool routing", () => {
  test("symbol search is limited to unresolved names or identities", async () => {
    const tools = await toolsFor("cn_stock_symbols");
    const search = tools.get("cn_stock_symbol_search");

    expect(search.description).toContain("identity is unresolved or ambiguous");
    expect(search.description).toContain(
      "Do not call this for a caller-supplied exact venue and code",
    );
    expect(search.promptSnippet).toContain(
      "Known exact venue-plus-code market-data requests bypass this tool",
    );
  });

  test("CNINFO is limited to explicitly requested disclosures", async () => {
    const tools = await toolsFor("cn_stock_announcements");
    const announcements = tools.get("cn_stock_announcement_search");

    expect(announcements.description).toContain(
      "only when the user explicitly requests announcements",
    );
    expect(announcements.description).toContain(
      "Never use CNINFO as a prerequisite for quotes, price history, OHLCV, or technical indicators",
    );
    expect(announcements.promptSnippet).toContain(
      "Market-data and indicator requests bypass this tool",
    );
  });
});
