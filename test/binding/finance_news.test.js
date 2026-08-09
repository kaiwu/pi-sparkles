import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/finance_news/index.js");
const originalFetch = globalThis.fetch;
const originalKeyId = process.env.ALPACA_API_KEY_ID;
const originalSecretKey = process.env.ALPACA_API_SECRET_KEY;
const originalContact = process.env.ALPACA_USER_AGENT_CONTACT;
const originalProduct = process.env.ALPACA_USER_AGENT_PRODUCT;
const requests = [];

const firstPage = JSON.stringify({
  news: [
    {
      id: 101,
      headline: "Apple publishes an exact update",
      summary: "Licensed summary must not leave the plugin boundary.",
      author: "Benzinga Newsdesk",
      created_at: "2026-07-01T10:00:00.123456Z",
      updated_at: "2026-07-01T10:01:00Z",
      url: "https://www.benzinga.com/news/101",
      symbols: ["AAPL", "MSFT"],
      source: "benzinga",
      images: [{ size: "small", url: "https://example.test/101.jpg" }],
    },
    {
      id: 102,
      headline: "A second exact headline",
      summary: "Another withheld summary.",
      author: "Benzinga Newsdesk",
      created_at: "2026-07-01T10:02:00Z",
      updated_at: "2026-07-01T10:03:00Z",
      url: "https://www.benzinga.com/news/102",
      symbols: ["AAPL"],
      source: "benzinga",
      images: [],
    },
  ],
  next_page_token: "page-two",
});

const secondPage = JSON.stringify({
  news: [
    {
      id: 103,
      headline: "A third exact headline",
      author: "Benzinga Newsdesk",
      created_at: "2026-07-01T10:04:00Z",
      updated_at: "2026-07-01T10:05:00Z",
      url: "https://www.benzinga.com/news/103",
      symbols: ["AAPL"],
      source: "benzinga",
    },
  ],
  next_page_token: null,
});

beforeEach(() => {
  requests.length = 0;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.ALPACA_USER_AGENT_CONTACT = "research@example.test";
  process.env.ALPACA_USER_AGENT_PRODUCT = "pi-sparkles-test/0.1";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const body = url.searchParams.has("page_token") ? secondPage : firstPage;
    return new Response(body, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": url.searchParams.has("page_token")
          ? "request-two"
          : "request-one",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("ALPACA_API_KEY_ID", originalKeyId);
  restore("ALPACA_API_SECRET_KEY", originalSecretKey);
  restore("ALPACA_USER_AGENT_CONTACT", originalContact);
  restore("ALPACA_USER_AGENT_PRODUCT", originalProduct);
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-news=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tool, value = input(), signal = new AbortController().signal) {
  return tool.execute("finance-news-query", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

function input(overrides = {}) {
  return {
    track: "us",
    venue: "XNAS",
    symbol: "AAPL",
    startAt: "2026-07-01T00:00:00Z",
    endAt: "2026-07-02T00:00:00Z",
    pageSize: 2,
    maximumPages: 3,
    maximumArticles: 5,
    ...overrides,
  };
}

describe("finance news boundary", () => {
  test("registers only the read-only finance_news tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["finance_news"]);
  });

  test("paginates exact metadata-only requests and preserves bounded evidence", async () => {
    const tools = await harness();
    const result = await execute(tools.get("finance_news"));

    expect(requests).toHaveLength(2);
    expect(requests[0].url.origin).toBe("https://data.alpaca.markets");
    expect(requests[0].url.pathname).toBe("/v1beta1/news");
    expect(requests[0].url.searchParams.get("start")).toBe(
      "2026-07-01T00:00:00Z",
    );
    expect(requests[0].url.searchParams.get("end")).toBe(
      "2026-07-02T00:00:00Z",
    );
    expect(requests[0].url.searchParams.get("sort")).toBe("asc");
    expect(requests[0].url.searchParams.get("symbols")).toBe("AAPL");
    expect(requests[0].url.searchParams.get("limit")).toBe("2");
    expect(requests[0].url.searchParams.get("include_content")).toBe("false");
    expect(requests[0].url.searchParams.get("exclude_contentless")).toBe(
      "false",
    );
    expect(requests[1].url.searchParams.get("page_token")).toBe("page-two");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );

    expect(result.details).toMatchObject({
      operation: "finance_news",
      track: "us",
      venue: "XNAS",
      venueEvidence: "caller_declared_not_provider_verified",
      articleCount: 3,
      pageCount: 2,
      pagination: { state: "complete", nextPageToken: null },
      query: {
        symbol: "AAPL",
        sortAxis: "updated_at",
        sort: "asc",
        includeContent: false,
        excludeContentless: false,
      },
      rights: {
        use: "personal_noncommercial_local_analysis",
        redistribution: "requires_express_prior_written_consent",
        articleBodiesReturned: false,
        articleSummariesReturned: false,
        imageUrlsReturned: false,
      },
      scope: {
        eventKind: "vendor_news_article_metadata",
        correctionLineage: null,
        deduplication: false,
        sentiment: null,
        impact: null,
        catalystClassification: null,
        absenceClaim: false,
      },
    });
    expect(result.details.pages[0].articles[0]).toMatchObject({
      providerArticleId: 101,
      headline: "Apple publishes an exact update",
      createdAt: "2026-07-01T10:00:00.123456Z",
      updatedAt: "2026-07-01T10:01:00Z",
      symbols: ["AAPL", "MSFT"],
      source: "benzinga",
      summaryAvailableAtProvider: true,
      contentReturned: false,
      imageUrlsReturned: false,
      eventType: null,
    });
    expect(result.details.pages[0]).toMatchObject({
      sequence: 1,
      requestId: "request-one",
      responseByteLength: Buffer.byteLength(firstPage),
      contentSha256: createHash("sha256").update(firstPage).digest("hex"),
    });
    expect(result.details.pages[1]).toMatchObject({
      sequence: 2,
      requestId: "request-two",
      responseByteLength: Buffer.byteLength(secondPage),
      contentSha256: createHash("sha256").update(secondPage).digest("hex"),
    });
    const serialized = JSON.stringify(result.details);
    expect(serialized).not.toContain("Licensed summary");
    expect(serialized).not.toContain("withheld summary");
    expect(serialized).not.toContain("101.jpg");
    expect(serialized).not.toContain("test-secret-key");
  });

  test("reports article-budget truncation with the next token intact", async () => {
    const tools = await harness();
    const result = await execute(
      tools.get("finance_news"),
      input({ maximumArticles: 2 }),
    );

    expect(requests).toHaveLength(1);
    expect(result.details.articleCount).toBe(2);
    expect(result.details.pagination).toEqual({
      state: "truncated_by_article_budget",
      budget: 2,
      nextPageToken: "page-two",
    });
  });

  test("rejects mismatched source or symbol association", async () => {
    globalThis.fetch = async () =>
      new Response(
        firstPage
          .replaceAll('"benzinga"', '"other"')
          .replace('"next_page_token":"page-two"', '"next_page_token":null'),
        { headers: { "content-type": "application/json" } },
      );
    const tools = await harness();
    await expect(execute(tools.get("finance_news"))).rejects.toThrow(
      "invalid, mismatched, or over-budget news metadata",
    );

    globalThis.fetch = async () =>
      new Response(
        firstPage
          .replaceAll('"AAPL"', '"TSLA"')
          .replace('"next_page_token":"page-two"', '"next_page_token":null'),
        { headers: { "content-type": "application/json" } },
      );
    const secondHarness = await harness();
    await expect(execute(secondHarness.get("finance_news"))).rejects.toThrow(
      "invalid, mismatched, or over-budget news metadata",
    );
  });

  test("reports credential or entitlement rejection without leaking response data", async () => {
    globalThis.fetch = async () =>
      new Response('{"message":"forbidden"}', { status: 403 });
    const tools = await harness();

    await expect(execute(tools.get("finance_news"))).rejects.toThrow(
      "Alpaca news request failed safely",
    );
    await expect(execute(tools.get("finance_news"))).rejects.not.toThrow(
      "forbidden",
    );
  });

  test("honors cancellation before transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(firstPage);
    };
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();

    await expect(
      execute(tools.get("finance_news"), input(), controller.signal),
    ).rejects.toThrow("Cancelled");
    expect(called).toBe(false);
  });
});

function restore(name, value) {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
