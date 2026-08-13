import {
  afterEach,
  beforeEach,
  describe,
  expect,
  setDefaultTimeout,
  test,
} from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_fundamentals/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_fundamentals/index.js"),
};

const originalFetch = globalThis.fetch;
const requests = [];

setDefaultTimeout(15_000);

const cnIncome =
  '{"success":true,"result":{"data":[{"SECURITY_CODE":"600519","SECURITY_NAME_ABBR":"贵州茅台","ORG_CODE":"10002602","DATE_TYPE_CODE":"001","REPORT_TYPE_CODE":"001","DATA_STATE":"2","NOTICE_DATE":"2025-04-03 00:00:00","REPORT_DATE":"2024-12-31 00:00:00","PARENT_NETPROFIT":86228146421.62,"TOTAL_OPERATE_INCOME":174144069958.2500}]}}';

const hkContext =
  '{"success":true,"result":{"data":[{"REPORT_LIST":[{"SECURITY_CODE":"00700","SECURITY_NAME_ABBR":"腾讯控股","START_DATE":"2024-01-01 00:00:00","REPORT_DATE":"2024-12-31 00:00:00","FISCAL_YEAR":"12-31","CURRENCY":"人民币","ACCOUNT_STANDARD":"国际会计准则","REPORT_TYPE":"年报"}]}]}}';

const hkIncome =
  '{"success":true,"result":{"data":[{"SECURITY_CODE":"00700","SECURITY_NAME_ABBR":"腾讯控股","ORG_CODE":"10009066","REPORT_DATE":"2024-12-31 00:00:00","DATE_TYPE_CODE":"001","FISCAL_YEAR":"12-31","START_DATE":"2024-01-01 00:00:00","STD_ITEM_CODE":"004001001","STD_ITEM_NAME":"营业额","AMOUNT":652498000000.00},{"SECURITY_CODE":"00700","SECURITY_NAME_ABBR":"腾讯控股","ORG_CODE":"10009066","REPORT_DATE":"2024-12-31 00:00:00","DATE_TYPE_CODE":"001","FISCAL_YEAR":"12-31","START_DATE":"2024-01-01 00:00:00","STD_ITEM_CODE":"004025002","STD_ITEM_NAME":"股东应占溢利","AMOUNT":194073000000}]}}';

beforeEach(() => {
  requests.length = 0;
  process.env.AGENT_CONTACT = "fundamentals@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const report = url.searchParams.get("reportName");
    const body =
      report === "RPT_DMSK_FN_INCOME"
        ? cnIncome
        : report === "RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY"
          ? hkContext
          : hkIncome;
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

async function harness(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?fundamentals=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "fundamental-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("isolated CN/HK exact fundamental workflows", () => {
  test("CN retains exact tokens and exposes its executable formula receipt", async () => {
    const tools = await harness("cn");
    expect([...tools.keys()].sort()).toEqual([
      "cn_financial_statement",
      "cn_stock_fundamental",
      "cn_stock_fundamental_metric",
    ]);
    const base = {
      venue: "sse",
      code: "600519",
      reportDate: "2024-12-31",
      currency: "CNY",
    };

    const raw = await execute(tools.get("cn_financial_statement"), base);
    expect(raw.details.track).toBe("cn");
    expect(raw.details.reportStart).toBeNull();
    expect(raw.details.currencyEvidence).toBe(
      "caller_declared_not_provider_verified",
    );
    expect(raw.details.facts.map((fact) => fact.rawValue)).toEqual([
      "174144069958.2500",
      "86228146421.62",
    ]);

    const normalizedTools = await harness("cn");
    const normalized = await execute(normalizedTools.get("cn_stock_fundamental"), {
      ...base,
      metric: "net_income_attributable_to_parent",
    });
    expect(normalized.details.status).toBe("unique");
    expect(normalized.details.mapping.acceptedLineCodes).toEqual([
      "PARENT_NETPROFIT",
    ]);
    expect(normalized.details.sourceFact.originalLabel).toBe(
      "归属于母公司股东的净利润",
    );

    const derivedTools = await harness("cn");
    const derived = await execute(derivedTools.get("cn_stock_fundamental_metric"), {
      ...base,
      scale: 6,
    });
    expect(derived.details.value).toBe("49.515408");
    expect(derived.details.formula.operation).toBe("divide");
    expect(derived.details.inputNames).toEqual([
      "net_income_attributable_to_parent",
      "revenue",
    ]);
    expect(derived.details.sources.map((source) => source.fact.rawValue)).toEqual(
      ["86228146421.62", "174144069958.2500"],
    );
    expect(requests[0].url.hostname).toBe("datacenter-web.eastmoney.com");
    expect(requests[0].headers.get("user-agent")).toContain(
      "fundamentals@example.test",
    );
  });

  test("HK joins report context to exact lines before normalization", async () => {
    const tools = await harness("hk");
    expect([...tools.keys()].sort()).toEqual([
      "hk_financial_statement",
      "hk_stock_fundamental",
      "hk_stock_fundamental_metric",
    ]);
    const base = { code: "00700", reportDate: "2024-12-31" };

    const raw = await execute(tools.get("hk_financial_statement"), base);
    expect(raw.details.track).toBe("hk");
    expect(raw.details.route).toBe("direct_joined_context_and_lines");
    expect(raw.details.reportStart).toBe("2024-01-01");
    expect(raw.details.reportedCurrency).toBe("人民币");
    expect(raw.details.normalizedCurrency).toBe("CNY");
    expect(raw.details.accountingStandard).toBe("国际会计准则");
    expect(raw.details.facts[0]).toMatchObject({
      lineCode: "004001001",
      originalLabel: "营业额",
      rawValue: "652498000000.00",
    });

    const normalizedTools = await harness("hk");
    const normalized = await execute(normalizedTools.get("hk_stock_fundamental"), {
      ...base,
      metric: "revenue",
    });
    expect(normalized.details.mapping.acceptedLineCodes).toEqual(["004001001"]);
    expect(normalized.details.mapping.periodKind).toBe("exact_duration");

    const derivedTools = await harness("hk");
    const derived = await execute(derivedTools.get("hk_stock_fundamental_metric"), {
      ...base,
      scale: 6,
    });
    expect(derived.details.value).toBe("29.74308");
    expect(derived.details.sources).toHaveLength(2);
    const hkReports = requests
      .filter(({ url }) => url.hostname === "datacenter.eastmoney.com")
      .map(({ url }) => url.searchParams.get("reportName"));
    expect(hkReports).toContain("RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY");
    expect(hkReports).toContain("RPT_HKF10_FN_INCOME_PC");
  });
});
