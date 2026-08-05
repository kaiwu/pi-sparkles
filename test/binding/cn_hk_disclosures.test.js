import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_disclosures/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_disclosures/index.js"),
};

const saved = {};

beforeEach(() => {
  saved.fetch = globalThis.fetch;
  for (const name of [
    "CNINFO_USER_AGENT_PRODUCT",
    "CNINFO_USER_AGENT_CONTACT",
    "HKEX_USER_AGENT_PRODUCT",
    "HKEX_USER_AGENT_CONTACT",
  ]) {
    saved[name] = process.env[name];
  }
  process.env.CNINFO_USER_AGENT_PRODUCT = "pi-sparkles-cn-test/0.1";
  process.env.CNINFO_USER_AGENT_CONTACT = "fixtures@example.com";
  process.env.HKEX_USER_AGENT_PRODUCT = "pi-sparkles-hk-test/0.1";
  process.env.HKEX_USER_AGENT_CONTACT = "fixtures@example.com";
});

afterEach(() => {
  globalThis.fetch = saved.fetch;
  for (const name of [
    "CNINFO_USER_AGENT_PRODUCT",
    "CNINFO_USER_AGENT_CONTACT",
    "HKEX_USER_AGENT_PRODUCT",
    "HKEX_USER_AGENT_CONTACT",
  ]) {
    restore(name, saved[name]);
  }
});

describe("CN/HK official disclosure boundaries", () => {
  test("CN resolves catalogue identity before bounded announcement discovery", async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const payload = String(url).includes("szse_stock.json")
        ? {
            stockList: [
              {
                code: "000001",
                pinyin: "payh",
                category: "A股",
                orgId: "gssz0000001",
                zwjc: "平安银行",
              },
            ],
          }
        : {
            totalAnnouncement: 1,
            totalpages: 1,
            hasMore: false,
            announcements: [
              {
                secCode: "000001",
                secName: "平安银行",
                orgId: "gssz0000001",
                announcementId: "1225022887",
                announcementTitle: "2025年年度报告",
                announcementTime: 1774022400000,
                adjunctUrl: "finalpage/2026-03-21/1225022887.PDF",
                adjunctSize: 1930,
                announcementType: "01010503||010112||010301",
              },
            ],
          };
      return new Response(JSON.stringify(payload), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };

    const tools = await loadTools("cn");
    expect([...tools.keys()]).toEqual([
      "cn_security_search",
      "cn_disclosure_search",
    ]);
    const security = await execute(tools, "cn_security_search", {
      code: "000001",
    });
    expectTrack(security.details, "cn", "cn_cninfo_security_reference");
    expect(security.details.resolution).toBe("unique");
    expect(security.details.candidates[0]).toMatchObject({
      code: "000001",
      organizationId: "gssz0000001",
      shortName: "平安银行",
      venueMic: null,
    });

    calls.length = 0;
    const disclosures = await execute(tools, "cn_disclosure_search", {
      code: "000001",
      startDate: "2025-01-01",
      endDate: "2026-08-05",
      category: "annual",
      pageSize: 3,
    });
    expectTrack(disclosures.details, "cn", "cn_cninfo_disclosure_search");
    expect(disclosures.details.announcements[0]).toMatchObject({
      announcementId: "1225022887",
      title: "2025年年度报告",
      documentUrl:
        "https://static.cninfo.com.cn/finalpage/2026-03-21/1225022887.PDF",
      providerTimeMeaning: "unverified_cninfo_source_field",
    });
    expect(calls.map(({ url }) => url)).toEqual([
      "https://www.cninfo.com.cn/new/data/szse_stock.json",
      "https://www.cninfo.com.cn/new/hisAnnouncement/query",
    ]);
    expect(String(calls[1].init.body)).toContain(
      "stock=000001%2Cgssz0000001",
    );
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-cn-test/0.1 fixtures@example.com",
      );
    }
  });

  test("HK resolves stock ID before preserving bounded title rows", async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const body = String(url).includes("prefix.do")
        ? 'pi_sparkles({"more":"1","stockInfo":[{"stockId":7609,"code":"00700","name":"TENCENT"}]});'
        : '<html><input id="stockId" type="hidden" value="7609" /><input id="stockCode" type="hidden" value="00700 TENCENT" /><div class="total-records">Total records found: 259 </div><table><tr><td><span>Release Time: </span>09/07/2026 17:58</td><td><span>Stock Code: </span>00700<br/>80700</td><td><span>Stock Short Name: </span>TENCENT<br/>TENCENT-R</td><td><div class="headline">Next Day Disclosure Returns - [Share Buyback]<br/></div><div class="doc-link"><a href="/listedco/listconews/sehk/2026/0709/2026070900827.pdf" target="_blank">Next Day Disclosure Return</a> (<span class="attachment_filesize">89KB</span>)</div></td></tr></table></html>';
      return new Response(body, {
        status: 200,
        headers: {
          "content-type": String(url).includes("prefix.do")
            ? "application/javascript"
            : "text/html",
        },
      });
    };

    const tools = await loadTools("hk");
    expect([...tools.keys()]).toEqual([
      "hk_security_search",
      "hk_disclosure_search",
    ]);
    const security = await execute(tools, "hk_security_search", {
      code: "00700",
    });
    expectTrack(security.details, "hk", "hk_hkexnews_security_reference");
    expect(security.details.candidates[0]).toEqual({
      stockId: 7609,
      code: "00700",
      name: "TENCENT",
      venueMic: "XHKG",
    });

    calls.length = 0;
    const disclosures = await execute(tools, "hk_disclosure_search", {
      code: "00700",
      limit: 20,
    });
    expectTrack(disclosures.details, "hk", "hk_hkexnews_disclosure_search");
    expect(disclosures.details.totalRecords).toBe(259);
    expect(disclosures.details.truncated).toBeTrue();
    expect(disclosures.details.documents[0]).toMatchObject({
      codes: ["00700", "80700"],
      names: ["TENCENT", "TENCENT-R"],
      releaseTimezone: "Asia/Hong_Kong",
      documentUrl:
        "https://www1.hkexnews.hk/listedco/listconews/sehk/2026/0709/2026070900827.pdf",
    });
    expect(calls).toHaveLength(2);
    expect(calls[0].url).toContain("/search/prefix.do?");
    expect(calls[1].url).toContain("/search/titlesearch.xhtml?");
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-hk-test/0.1 fixtures@example.com",
      );
    }
  });
});

async function loadTools(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?disclosures=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tools, name, input) {
  return tools.get(name).execute(
    `${name}-test`,
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function expectTrack(details, track, marketScope) {
  expect(details.track).toBe(track);
  expect(details.trackContext).toMatchObject({
    schemaVersion: 1,
    track,
    marketScope,
  });
}

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
