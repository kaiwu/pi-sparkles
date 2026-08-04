import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/finance_symbols/index.js",
);

let originalFetch;
let originalKey;

beforeEach(() => {
  originalFetch = globalThis.fetch;
  originalKey = process.env.OPENFIGI_API_KEY;
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalKey === undefined) delete process.env.OPENFIGI_API_KEY;
  else process.env.OPENFIGI_API_KEY = originalKey;
});

describe("finance_symbols provider boundary", () => {
  test("uses authenticated v3 mapping and paginated search without exposing the key", async () => {
    process.env.OPENFIGI_API_KEY = "fixture-openfigi-key";
    const calls = [];
    globalThis.fetch = async (url, init) => {
      const body = JSON.parse(init.body);
      calls.push({ url: String(url), init, body });
      const payload = String(url).endsWith("/v3/mapping")
        ? [
            {
              data: [
                {
                  figi: "BBG000BLNNH6",
                  name: "INTL BUSINESS MACHINES CORP",
                  ticker: "IBM",
                  exchCode: "US",
                  compositeFIGI: "BBG000BLNNH6",
                  shareClassFIGI: "BBG001S5S399",
                  securityType2: "Common Stock",
                  marketSector: "Equity",
                },
              ],
            },
          ]
        : { data: [], next: "cursor-2", total: 101 };
      return new Response(JSON.stringify(payload), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };

    const tools = new Map();
    const api = {
      registerCommand() {},
      registerTool(definition) {
        tools.set(definition.name, definition);
      },
    };
    const module = await import(`${artifact}?symbols=${Date.now()}`);
    await module.default(api);

    expect([...tools.keys()]).toEqual([
      "security_search",
      "security_resolve",
      "security_identifiers",
    ]);

    const resolveResult = await tools.get("security_resolve").execute(
      "mapping-1",
      { idType: "TICKER", idValue: "IBM", micCode: "XNYS" },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(resolveResult.details.resolution).toBe("unique");
    expect(resolveResult.details.access).toBe("authenticated");
    expect(JSON.stringify(resolveResult)).not.toContain("fixture-openfigi-key");

    const searchResult = await tools.get("security_search").execute(
      "search-1",
      { query: "IBM", micCode: "XNYS", cursor: "cursor-1" },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(searchResult.details.next).toBe("cursor-2");
    expect(searchResult.details.total).toBe(101);

    expect(calls).toHaveLength(2);
    expect(calls[0].url).toBe("https://api.openfigi.com/v3/mapping");
    expect(calls[0].init.headers.get("x-openfigi-apikey")).toBe(
      "fixture-openfigi-key",
    );
    expect(calls[0].init.headers.has("idempotency-key")).toBeFalse();
    expect(calls[0].body).toEqual([
      {
        idType: "TICKER",
        idValue: "IBM",
        micCode: "XNYS",
      },
    ]);
    expect(calls[1].url).toBe("https://api.openfigi.com/v3/filter");
    expect(calls[1].body).toEqual({
      query: "IBM",
      micCode: "XNYS",
      start: "cursor-1",
    });
  });
});
