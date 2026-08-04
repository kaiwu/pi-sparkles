import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_fundamentals/index.js",
);

let originalFetch;
let originalProduct;
let originalContact;

beforeEach(() => {
  originalFetch = globalThis.fetch;
  originalProduct = process.env.SEC_USER_AGENT_PRODUCT;
  originalContact = process.env.SEC_USER_AGENT_CONTACT;
  process.env.SEC_USER_AGENT_PRODUCT = "pi-sparkles-test/0.1";
  process.env.SEC_USER_AGENT_CONTACT = "fixtures@example.com";
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("SEC_USER_AGENT_PRODUCT", originalProduct);
  restore("SEC_USER_AGENT_CONTACT", originalContact);
});

describe("stock_fundamentals normalization boundary", () => {
  test("exposes its registry and leaves amended facts ambiguous", async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const body = `{
        "cik": 320193,
        "entityName": "Apple Inc.",
        "facts": {"us-gaap": {
          "RevenueFromContractWithCustomerExcludingAssessedTax": {
            "label": "Revenue", "description": "Revenue", "units": {"USD": [
              {"start":"2023-01-01","end":"2023-12-31","val":8007199254740993.100,"accn":"annual-2023","fy":2023,"fp":"FY","form":"10-K","filed":"2024-02-01"},
              {"start":"2024-01-01","end":"2024-03-31","val":100,"accn":"quarter-1","fy":2024,"fp":"Q1","form":"10-Q","filed":"2024-05-01"},
              {"start":"2024-04-01","end":"2024-06-30","val":110,"accn":"quarter-2","fy":2024,"fp":"Q2","form":"10-Q","filed":"2024-08-01"},
              {"start":"2024-07-01","end":"2024-09-30","val":121,"accn":"quarter-3","fy":2024,"fp":"Q3","form":"10-Q","filed":"2024-11-01"},
              {"start":"2024-01-01","end":"2024-09-30","val":7007199254740993.100,"accn":"nine-month-2024","fy":2024,"fp":"Q3","form":"10-Q","filed":"2024-11-01"},
              {"start":"2024-10-01","end":"2024-12-31","val":133.1,"accn":"quarter-4","fy":2024,"fp":"FY","form":"10-K","filed":"2025-02-01"},
              {"start":"2024-01-01","end":"2024-12-31","val":9007199254740993.100,"accn":"original","fy":2024,"fp":"FY","form":"10-K","filed":"2025-02-01"},
              {"start":"2024-01-01","end":"2024-12-31","val":9007199254740994.200,"accn":"amended","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"},
              {"start":"2025-01-01","end":"2025-03-31","val":140,"accn":"quarter-2025-1","fy":2025,"fp":"Q1","form":"10-Q","filed":"2025-05-01"},
              {"start":"2025-04-01","end":"2025-06-30","val":150,"accn":"quarter-2025-2","fy":2025,"fp":"Q2","form":"10-Q","filed":"2025-08-01"},
              {"start":"2025-07-01","end":"2025-09-30","val":160,"accn":"quarter-2025-3","fy":2025,"fp":"Q3","form":"10-Q","filed":"2025-11-01"}
            ]}
          },
          "NetIncomeLoss": {
            "label": "Net income", "units": {"USD": [
              {"start":"2024-01-01","end":"2024-12-31","val":900719925474099.420,"accn":"amended","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
            ]}
          },
          "NetCashProvidedByUsedInOperatingActivities": {
            "label": "Operating cash flow", "units": {"USD": [
              {"start":"2024-01-01","end":"2024-09-30","val":700,"accn":"ocf-ytd-2024","fy":2024,"fp":"Q3","form":"10-Q","filed":"2024-11-01"},
              {"start":"2024-01-01","end":"2024-12-31","val":1200,"accn":"amended","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"},
              {"start":"2025-01-01","end":"2025-09-30","val":800,"accn":"ocf-ytd-2025","fy":2025,"fp":"Q3","form":"10-Q","filed":"2025-11-01"}
            ]}
          },
          "PaymentsToAcquirePropertyPlantAndEquipment": {
            "label": "Capital expenditures", "units": {"USD": [
              {"start":"2024-01-01","end":"2024-12-31","val":200,"accn":"amended","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
            ]}
          },
          "WeightedAverageNumberOfDilutedSharesOutstanding": {
            "label": "Diluted shares", "units": {"shares": [
              {"start":"2024-01-01","end":"2024-12-31","val":100,"accn":"amended","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
            ]}
          }
        }}
      }`;
      return new Response(body, {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };

    const commands = new Map();
    const tools = new Map();
    const api = {
      registerCommand(name, options) {
        commands.set(name, options);
      },
      registerTool(definition) {
        tools.set(definition.name, definition);
      },
    };
    const module = await import(`${artifact}?fundamentals=${Date.now()}`);
    await module.default(api);

    expect([...commands.keys()]).toEqual(["fundamentals"]);
    const notifications = [];
    await commands.get("fundamentals").handler("", {
      cwd: process.cwd(),
      mode: "tui",
      hasUI: true,
      ui: {
        notify(message, kind) {
          notifications.push({ message, kind });
        },
      },
    });
    expect(notifications).toHaveLength(1);
    expect(notifications[0].kind).toBe("info");
    expect(notifications[0].message).toContain("stock_fundamental_period");
    expect(notifications[0].message).toContain("exact accession");

    expect([...tools.keys()]).toEqual([
      "stock_fundamental_definitions",
      "stock_fundamental_q4",
      "stock_fundamental_trend",
      "stock_fundamental_growth",
      "stock_fundamental_ttm",
      "stock_fundamental_ttm_bridge",
      "stock_fundamental_ttm_composed",
      "stock_fundamental_metric",
      "stock_fundamental",
      "stock_fundamental_period",
    ]);

    const definitions = await tools
      .get("stock_fundamental_definitions")
      .execute(
        "definitions-1",
        {},
        new AbortController().signal,
        undefined,
        {},
      );
    expect(definitions.details.definitions).toHaveLength(7);
    expect(
      definitions.details.definitions.find((item) => item.metric === "revenue"),
    ).toMatchObject({ periodKind: "duration", unitKind: "monetary" });

    const result = await tools.get("stock_fundamental").execute(
      "fundamental-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        start: "2024-01-01",
        end: "2024-12-31",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(result.details.resolution).toBe("ambiguous");
    expect(result.details.candidates.map((candidate) => candidate.value)).toEqual([
      "9007199254740994.200",
      "9007199254740993.100",
    ]);
    expect(result.details.candidates[0]).toMatchObject({
      form: "10-K/A",
      amendment: true,
      accession: "amended",
    });
    const classified = await tools.get("stock_fundamental_period").execute(
      "fundamental-period-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        period: "annual",
        end: "2024-12-31",
        filingPolicy: "latest_filed",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(classified.details.resolution).toBe("unique");
    expect(classified.details.periodClass).toBe("annual");
    expect(classified.details.filingPolicy).toBe("latest_filed");
    expect(classified.details.candidates[0].accession).toBe("amended");

    const q4 = await tools.get("stock_fundamental_q4").execute(
      "fundamental-q4-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        annualEnd: "2024-12-31",
        nineMonthEnd: "2024-09-30",
        annualAccession: "original",
        nineMonthAccession: "nine-month-2024",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(q4.details).toMatchObject({
      status: "derived",
      metric: "revenue",
      value: "2000000000000000",
      unit: "USD",
      start: "2024-10-01",
      end: "2024-12-31",
      annualPolicy: "exact_accession",
      nineMonthPolicy: "exact_accession",
    });
    expect(q4.details.annual.accession).toBe("original");
    expect(q4.details.nineMonthYtd.accession).toBe("nine-month-2024");

    const trend = await tools.get("stock_fundamental_trend").execute(
      "fundamental-trend-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        period: "annual",
        ends: ["2024-12-31", "2023-12-31"],
        filingPolicy: "latest_filed",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(trend.details).toMatchObject({
      status: "comparable",
      metric: "revenue",
      unit: "USD",
      taxonomy: "us-gaap",
      tag: "RevenueFromContractWithCustomerExcludingAssessedTax",
      periodClass: "annual",
      filingPolicy: "latest_filed",
    });
    expect(trend.details.points.map((point) => point.accession)).toEqual([
      "annual-2023",
      "amended",
    ]);

    const growth = await tools.get("stock_fundamental_growth").execute(
      "fundamental-growth-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        period: "quarter",
        comparison: "quarter_over_quarter",
        ends: ["2024-09-30", "2024-03-31", "2024-12-31", "2024-06-30"],
        filingPolicy: "latest_filed",
        scale: 4,
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(growth.details).toMatchObject({
      status: "calculated",
      metric: "revenue",
      sourceUnit: "USD",
      unit: "percentage_points",
      periodClass: "quarter",
      comparison: "quarter_over_quarter",
      scale: 4,
      rounding: "half_even",
    });
    expect(growth.details.points.map((point) => point.value)).toEqual([
      "10",
      "10",
      "10",
    ]);
    expect(growth.details.points[0].formula.operation).toBe("divide");
    expect(growth.details.points[0].previous.accession).toBe("quarter-1");

    const ttm = await tools.get("stock_fundamental_ttm").execute(
      "fundamental-ttm-1",
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        ends: ["2024-12-31", "2024-06-30", "2024-03-31", "2024-09-30"],
        filingPolicy: "latest_filed",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(ttm.details).toMatchObject({
      status: "calculated",
      metric: "revenue",
      calculation: "trailing_twelve_months",
      value: "464.1",
      unit: "USD",
      start: "2024-01-01",
      end: "2024-12-31",
      periodClass: "trailing_twelve_months",
    });
    expect(ttm.details.formula.operation).toBe("sum");
    expect(ttm.details.sources.map((source) => source.name)).toEqual([
      "quarter_1",
      "quarter_2",
      "quarter_3",
      "quarter_4",
    ]);

    const ttmBridge = await tools.get("stock_fundamental_ttm_bridge").execute(
      "fundamental-ttm-bridge-1",
      {
        cik: "320193",
        metric: "operating_cash_flow",
        unit: "USD",
        ytdPeriod: "nine_month_ytd",
        annualEnd: "2024-12-31",
        currentYtdEnd: "2025-09-30",
        priorYtdEnd: "2024-09-30",
        annualAccession: "amended",
        currentYtdAccession: "ocf-ytd-2025",
        priorYtdAccession: "ocf-ytd-2024",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(ttmBridge.details).toMatchObject({
      status: "calculated",
      metric: "operating_cash_flow",
      calculation: "trailing_twelve_months_bridge",
      value: "1300",
      unit: "USD",
      start: "2024-10-01",
      end: "2025-09-30",
      annualPolicy: "exact_accession",
      currentYtdPolicy: "exact_accession",
      priorYtdPolicy: "exact_accession",
    });
    expect(ttmBridge.details.formula.operation).toBe("subtract");
    expect(ttmBridge.details.sources.map((source) => source.name)).toEqual([
      "annual",
      "current_ytd",
      "prior_ytd",
    ]);

    const composedTtm = await tools
      .get("stock_fundamental_ttm_composed")
      .execute(
        "fundamental-ttm-composed-1",
        {
          cik: "320193",
          metric: "revenue",
          unit: "USD",
          directEnds: ["2025-09-30", "2025-03-31", "2025-06-30"],
          directAccessions: [
            "quarter-2025-3",
            "quarter-2025-1",
            "quarter-2025-2",
          ],
          annualEnd: "2024-12-31",
          nineMonthEnd: "2024-09-30",
          annualAccession: "original",
          nineMonthAccession: "nine-month-2024",
        },
        new AbortController().signal,
        undefined,
        {},
      );
    expect(composedTtm.details).toMatchObject({
      status: "calculated",
      metric: "revenue",
      calculation: "trailing_twelve_months_composed",
      value: "2000000000000450",
      unit: "USD",
      start: "2024-10-01",
      end: "2025-09-30",
      annualPolicy: "exact_accession",
      nineMonthPolicy: "exact_accession",
    });
    expect(composedTtm.details.inputNames).toEqual([
      "quarter_1_annual",
      "quarter_1_nine_month_ytd",
      "quarter_2",
      "quarter_3",
      "quarter_4",
    ]);
    expect(composedTtm.details.quarters.map((quarter) => quarter.kind)).toEqual([
      "derived_q4",
      "direct",
      "direct",
      "direct",
    ]);
    expect(composedTtm.details.quarters[0].annual.accession).toBe("original");
    expect(composedTtm.details.formula.operation).toBe("sum");

    const freeCashFlow = await tools.get("stock_fundamental_metric").execute(
      "fundamental-metric-fcf-1",
      {
        cik: "320193",
        metric: "free_cash_flow",
        currencyUnit: "USD",
        period: "annual",
        end: "2024-12-31",
        filingPolicy: "latest_filed",
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(freeCashFlow.details).toMatchObject({
      status: "calculated",
      metric: "free_cash_flow",
      value: "1000",
      unit: "USD",
      periodClass: "annual",
      baseFilingPolicy: "latest_filed",
    });
    expect(freeCashFlow.details.formula.operation).toBe("subtract");
    expect(freeCashFlow.details.sources.map((source) => source.name)).toEqual([
      "operating_cash_flow",
      "capital_expenditures_reported",
    ]);

    const netMargin = await tools.get("stock_fundamental_metric").execute(
      "fundamental-metric-margin-1",
      {
        cik: "320193",
        metric: "net_margin",
        currencyUnit: "USD",
        period: "annual",
        end: "2024-12-31",
        sourceAccessions: {
          net_income: "amended",
          revenue: "amended",
        },
        scale: 6,
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(netMargin.details).toMatchObject({
      status: "calculated",
      metric: "net_margin",
      value: "10",
      unit: "percentage_points",
      scale: 6,
      rounding: "half_even",
      baseFilingPolicy: "preserve_all",
    });
    expect(netMargin.details.inputNames).toEqual(["net_income", "revenue"]);
    expect(netMargin.details.sourcePolicies).toEqual([
      { name: "net_income", filingPolicy: "exact_accession" },
      { name: "revenue", filingPolicy: "exact_accession" },
    ]);
    expect(netMargin.details.formula).toMatchObject({
      operation: "divide",
      scale: 6,
      rounding: "half_even",
    });
    await expect(
      tools.get("stock_fundamental_metric").execute(
        "fundamental-metric-cross-filing-1",
        {
          cik: "320193",
          metric: "net_margin",
          currencyUnit: "USD",
          period: "annual",
          end: "2024-12-31",
          sourceAccessions: {
            net_income: "amended",
            revenue: "original",
          },
        },
        new AbortController().signal,
        undefined,
        {},
      ),
    ).rejects.toThrow("SourceFilingMismatch");

    const dilutedEps = await tools.get("stock_fundamental_metric").execute(
      "fundamental-metric-eps-1",
      {
        cik: "320193",
        metric: "diluted_eps",
        currencyUnit: "USD",
        sharesUnit: "shares",
        period: "annual",
        end: "2024-12-31",
        filingPolicy: "latest_filed",
        scale: 4,
      },
      new AbortController().signal,
      undefined,
      {},
    );
    expect(dilutedEps.details).toMatchObject({
      status: "calculated",
      metric: "diluted_eps",
      value: "9007199254740.9942",
      unit: "USD/share",
    });
    expect(
      dilutedEps.details.sources.map(
        (source) => source.candidate.accession,
      ),
    ).toEqual(["amended", "amended"]);

    expect(calls).toHaveLength(12);
    expect(calls[0].url).toBe(
      "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
    );
    expect(calls[0].init.headers.get("user-agent")).toBe(
      "pi-sparkles-test/0.1 fixtures@example.com",
    );
  });
});

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
