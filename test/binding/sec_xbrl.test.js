import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/sec_xbrl/index.js");

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

describe("sec_xbrl provider boundary", () => {
  test("preserves exact fact values and every SEC context field", async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const body = String(url).includes("/companyfacts/")
        ? '{"cik":320193,"entityName":"Apple Inc.","facts":{"us-gaap":{"Assets":{"label":"Assets","description":"Assets owned","units":{"USD":[]}}}}}'
        : '{"cik":320193,"taxonomy":"us-gaap","tag":"Assets","label":"Assets","description":"Assets owned","entityName":"Apple Inc.","units":{"USD":[{"end":"2025-06-28","val":9007199254740993.100,"accn":"0000320193-25-000079","fy":2025,"fp":"Q3","form":"10-Q","filed":"2025-08-01","frame":"CY2025Q2I"},{"end":"2025-06-28","val":9007199254740994.200,"accn":"0000320193-25-000080","fy":2025,"fp":"Q3","form":"10-Q/A","filed":"2025-08-02"}]}}';
      return new Response(body, {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };

    const tools = new Map();
    const api = {
      registerTool(definition) {
        tools.set(definition.name, definition);
      },
    };
    const module = await import(`${artifact}?xbrl=${Date.now()}`);
    await module.default(api);

    expect([...tools.keys()]).toEqual([
      "sec_xbrl_concepts",
      "sec_xbrl_facts",
    ]);

    const concepts = await tools.get("sec_xbrl_concepts").execute(
      "concepts-1",
      { cik: "320193", query: "assets", taxonomy: "us-gaap" },
      new AbortController().signal,
      undefined,
      {},
    );
    expectUsTrack(concepts.details);
    expect(
      concepts.content[0].text.startsWith("US track | SEC EDGAR XBRL\n"),
    ).toBeTrue();
    expect(concepts.details.candidates[0]).toMatchObject({
      taxonomy: "us-gaap",
      tag: "Assets",
      match: "exact_tag",
    });

    const facts = await tools.get("sec_xbrl_facts").execute(
      "facts-1",
      { cik: "320193", taxonomy: "us-gaap", tag: "Assets", unit: "USD" },
      new AbortController().signal,
      undefined,
      {},
    );
    expectUsTrack(facts.details);
    expect(
      facts.content[0].text.startsWith("US track | SEC EDGAR XBRL\n"),
    ).toBeTrue();
    expect(facts.details.facts).toHaveLength(2);
    expect(facts.details.facts[0]).toMatchObject({
      value: "9007199254740994.200",
      valueKind: "numeric_exact_lexeme",
      unit: "USD",
      form: "10-Q/A",
      amendment: true,
      periodKind: "instant",
    });
    expect(facts.details.facts[1].value).toBe("9007199254740993.100");
    expect(facts.details.duplicatesPreserved).toBeTrue();

    expect(calls.map((call) => call.url)).toEqual([
      "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
      "https://data.sec.gov/api/xbrl/companyconcept/CIK0000320193/us-gaap/Assets.json",
    ]);
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-sec-xbrl/0.1 fixtures@example.com",
      );
    }
  });
});

function expectUsTrack(details) {
  expect(details).toMatchObject({
    track: "us",
    trackContext: {
      schemaVersion: 1,
      track: "us",
      marketScope: "us_sec_xbrl_company_facts",
      venueMic: null,
      board: null,
      timezone: null,
      sourceLanguage: "en-US",
      providers: ["SEC EDGAR XBRL"],
      entitlement: "sec_public_data_fair_access_terms_apply",
      limitations: ["non_custom_taxonomies_only", "entity_wide_facts_only"],
    },
  });
}

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
