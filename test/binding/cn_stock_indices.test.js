import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/cn_stock_indices/index.js");
const originalFetch = globalThis.fetch;
const requests = [];

function responseBody(count = 50) {
  const result = Array.from({ length: count }, (_, index) => ({
    securityAbbrEn: `Member ${index + 1}`,
    securityAbbr: `成员${index + 1}`,
    inDate: "2026-08-19",
    securityCode: `688${String(index + 1).padStart(3, "0")}`,
    marketSource: "1",
  }));
  return JSON.stringify({
    pageHelp: { pageCount: 1, total: count, pageNo: 1, pageSize: 60 },
    result,
  });
}

function compositionBody() {
  return JSON.stringify({
    result: [
      { securityNum: 31, level1Code: "45", level1Name: "信息技术", indexCode: "000688", weight: 85.544, level1NameEn: "Information Technology", effectiveDate: "20260818" },
      { securityNum: 6, level1Code: "20", level1Name: "工业", indexCode: "000688", weight: 5.123, level1NameEn: "Industrials", effectiveDate: "20260818" },
      { securityNum: 5, level1Code: "35", level1Name: "医疗保健", indexCode: "000688", weight: 3.456, level1NameEn: "Health Care", effectiveDate: "20260818" },
      { securityNum: 4, level1Code: "25", level1Name: "可选消费", indexCode: "000688", weight: 2.345, level1NameEn: "Consumer Discretionary", effectiveDate: "20260818" },
      { securityNum: 3, level1Code: "15", level1Name: "原材料", indexCode: "000688", weight: 2.698, level1NameEn: "Materials", effectiveDate: "20260818" },
      { securityNum: 1, level1Code: "50", level1Name: "通信服务", indexCode: "000688", weight: 0.834, level1NameEn: "Communication Services", effectiveDate: "20260818" },
    ],
  });
}

beforeEach(() => {
  requests.length = 0;
  process.env.AGENT_CONTACT = "sse-index@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    requests.push({ url, init });
    const body = url.searchParams.get("sqlId") === "DB_SZZSLB_QZHYLB"
      ? compositionBody()
      : responseBody();
    return new Response(body, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  delete process.env.AGENT_CONTACT;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?cn-stock-indices=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "cn-index-constituents",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("official SSE index constituent acquisition", () => {
  test("acquires all reviewed STAR 50 members in one bounded request", async () => {
    const tools = await harness();
    expect([...tools.keys()].sort()).toEqual([
      "cn_index_constituents",
      "cn_index_industry_composition",
      "cn_index_record",
      "cn_index_records",
    ]);

    const result = await execute(tools.get("cn_index_constituents"), {
      venue: "sse",
      code: "000688",
    });

    expect(requests).toHaveLength(1);
    const { url, init } = requests[0];
    expect(url.origin).toBe("https://query.sse.com.cn");
    expect(url.pathname).toBe("/commonSoaQuery.do");
    expect(url.searchParams.get("sqlId")).toBe("DB_SZZSLB_CFGLB");
    expect(url.searchParams.get("indexCode")).toBe("000688");
    expect(url.searchParams.get("pageHelp.pageSize")).toBe("60");
    expect(new Headers(init.headers).get("referer")).toBe(
      "https://www.sse.com.cn/",
    );
    expect(result.details).toMatchObject({
      track: "cn",
      provider: "Shanghai Stock Exchange",
      authorityScope: "official_sse_public_index_service",
      venue: "sse",
      mic: "XSHG",
      indexCode: "000688",
      indexName: "科创50",
      publicationDate: "2026-08-19",
      requestCount: 1,
      providerOrder: "sse_response_order",
    });
    expect(result.details.members).toHaveLength(50);
    expect(result.details.members[0]).toEqual({
      venue: "sse",
      mic: "XSHG",
      code: "688001",
      listingId: "XSHG:688001",
      name: "成员1",
      englishName: "Member 1",
    });
    expect(result.details.responseSha256).toMatch(/^[0-9a-f]{64}$/);
    expect(result.details.trackApplicability).toEqual({
      cn: {
        status: "supported",
        scope: "exact_sse_000688_only",
        provider: "Shanghai Stock Exchange",
      },
      hk: {
        status: "track_partial",
        missingEvidence: [
          "reviewed_exact_index_identity_and_administrator_contract",
          "complete_current_membership_decoder",
          "effective_date_and_correction_contract",
          "licence_and_redistribution_decision",
        ],
        candidateAuthority: "Hang Seng Indexes Company",
        substitution: "none",
      },
      us: {
        status: "track_partial",
        missingEvidence: [
          "reviewed_exact_benchmark_and_administrator_contract",
          "complete_current_membership_acquisition_and_decoder",
          "listing_identity_and_correction_contract",
          "licence_and_redistribution_decision",
        ],
        candidateAuthority: "selected US index administrator",
        substitution: "none",
      },
    });
    expect(result.details.limitations).toContain(
      "weights_not_returned_by_this_operation",
    );
    expect(result.content[0].text).toContain(
      "Official SSE 000688 科创50 constituents",
    );
    expect(result.content[0].text).not.toContain("sse-index@example.test");
  });

  test("acquires official aggregate sector weights without per-stock fan-out", async () => {
    const tools = await harness();
    const result = await execute(tools.get("cn_index_industry_composition"), {
      venue: "sse",
      code: "000688",
    });

    expect(requests).toHaveLength(1);
    expect(requests[0].url.searchParams.get("sqlId")).toBe(
      "DB_SZZSLB_QZHYLB",
    );
    expect(requests[0].url.searchParams.get("isPagination")).toBe("false");
    expect(result.details).toMatchObject({
      provider: "Shanghai Stock Exchange",
      indexCode: "000688",
      effectiveDate: "20260818",
      requestCount: 1,
    });
    expect(result.details.sectors).toHaveLength(6);
    expect(result.details.trackApplicability.hk.status).toBe("track_partial");
    expect(result.details.trackApplicability.us.status).toBe("track_partial");
    expect(result.details.sectors[0]).toEqual({
      sectorCode: "45",
      name: "信息技术",
      englishName: "Information Technology",
      securityCount: 31,
      weightPercentRaw: "85.544",
    });
    expect(result.content[0].text).toContain(
      "信息技术: members=31 weight=85.544%",
    );
  });

  test("rejects unreviewed identities before network access", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("cn_index_constituents"), {
        venue: "sse",
        code: "000001",
      }),
    ).rejects.toThrow("unsupported_index_identity");
    expect(requests).toHaveLength(0);
  });

  test("fails closed on an incomplete provider manifest", async () => {
    globalThis.fetch = async (input, init) => {
      requests.push({ url: new URL(String(input)), init });
      return new Response(responseBody(49), { status: 200 });
    };
    const tools = await harness();
    await expect(
      execute(tools.get("cn_index_constituents"), {
        venue: "sse",
        code: "000688",
      }),
    ).rejects.toThrow("invalid_sse_constituent_response");
    expect(requests).toHaveLength(1);
  });
});
