import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/sec_edgar/index.js");

let originalFetch;
let originalContact;

beforeEach(() => {
  originalFetch = globalThis.fetch;
  originalContact = process.env.AGENT_CONTACT;
  process.env.AGENT_CONTACT = "fixtures@example.com";
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("AGENT_CONTACT", originalContact);
});

describe("sec_edgar provider boundary", () => {
  test("identifies the caller and exposes typed company and filing results", async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const payload = String(url).includes("company_tickers")
        ? {
            0: { cik_str: 320193, ticker: "AAPL", title: "Apple Inc." },
            1: { cik_str: 1433195, ticker: "APPF", title: "AppFolio, Inc." },
          }
        : {
            cik: 320193,
            name: "Apple Inc.",
            tickers: ["AAPL"],
            exchanges: ["Nasdaq"],
            filings: {
              recent: {
                accessionNumber: ["0000320193-25-000079", "0000320193-25-000078"],
                filingDate: ["2025-08-01", "2025-07-31"],
                reportDate: ["2025-06-28", ""],
                form: ["10-Q", "8-K"],
                primaryDocument: ["aapl-20250628.htm", "aapl-8k.htm"],
              },
            },
          };
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
    const module = await import(`${artifact}?sec=${Date.now()}`);
    await module.default(api);

    expect([...tools.keys()]).toEqual([
      "sec_company_search",
      "sec_company_submissions",
    ]);

    const companyResult = await tools.get("sec_company_search").execute(
      "company-1",
      { query: "aapl", limit: 1 },
      new AbortController().signal,
      undefined,
      {},
    );
    expectUsTrack(companyResult.details, "us_sec_company_reference");
    expect(
      companyResult.content[0].text.startsWith("US track | SEC EDGAR\n"),
    ).toBeTrue();
    expect(companyResult.details.candidates).toEqual([
      {
        cik: "0000320193",
        ticker: "AAPL",
        title: "Apple Inc.",
        match: "exact_ticker",
      },
    ]);

    const filingResult = await tools.get("sec_company_submissions").execute(
      "filing-1",
      { cik: "320193", form: "10-q", limit: 5 },
      new AbortController().signal,
      undefined,
      {},
    );
    expectUsTrack(filingResult.details, "us_sec_recent_submissions");
    expect(
      filingResult.content[0].text.startsWith("US track | SEC EDGAR\n"),
    ).toBeTrue();
    expect(filingResult.details.cik).toBe("0000320193");
    expect(filingResult.details.filings).toHaveLength(1);
    expect(filingResult.details.filings[0].form).toBe("10-Q");

    expect(calls.map((call) => call.url)).toEqual([
      "https://www.sec.gov/files/company_tickers.json",
      "https://data.sec.gov/submissions/CIK0000320193.json",
    ]);
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-sec-edgar/0.1 fixtures@example.com",
      );
    }
  });
});

function expectUsTrack(details, marketScope) {
  expect(details).toMatchObject({
    track: "us",
    trackContext: {
      schemaVersion: 1,
      track: "us",
      marketScope,
      venueMic: null,
      board: null,
      timezone: null,
      sourceLanguage: "en-US",
      providers: ["SEC EDGAR"],
      entitlement: "sec_public_data_fair_access_terms_apply",
    },
  });
}

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
