import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_research_report/index.js",
);

async function harness() {
  const commands = new Map();
  const tools = new Map();
  const queued = [];
  const activeTools = [
    "us_stock_quote",
    "us_stock_ohlcv",
    "sec_company_submissions",
    "stock_fundamental_period",
    "us_company_brief",
  ];
  const api = {
    registerCommand(name, definition) {
      commands.set(name, definition);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    sendUserMessage(content, options) {
      queued.push({ content, options });
    },
    getActiveTools() {
      return activeTools;
    },
  };
  const module = await import(
    `${artifact}?stock-research=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { commands, tools, queued };
}

function context(notifications = []) {
  return {
    mode: "tui",
    hasUI: true,
    ui: {
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

async function execute(tool, input) {
  return tool.execute(
    "us-company-brief",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input() {
  return {
    company: "Apple Inc.",
    symbol: "AAPL",
    cik: "0000320193",
    asOfDate: "2026-08-06",
    quotes: [
      {
        feed: "iex",
        providerTimestamp: "2024-08-06T19:59:59.123456789Z",
        retrievedAtUnixMilliseconds: 1800000000000,
        bidExchange: "V",
        bidPrice: "189.1000",
        bidSize: "7",
        askExchange: "V",
        askPrice: "189.1200",
        askSize: "4",
        conditionCodes: ["R"],
        tape: "C",
        requestId: "quote-request-one",
        entitlement: "credentialed_iex_latest",
        sourceReference:
          "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols=AAPL&feed=iex&currency=USD",
      },
    ],
    histories: [
      {
        feed: "iex",
        startDate: "2024-08-01",
        endDate: "2024-08-05",
        bars: 3,
        pagination: "complete",
        calendarCompleteness: "calendar_not_assessed",
        sourceReference:
          "https://data.alpaca.markets/v2/stocks/bars?symbols=AAPL&timeframe=1Day&start=2024-08-01&end=2024-08-05&adjustment=raw&feed=iex&currency=USD&sort=asc&asof=2024-08-06",
      },
    ],
    filings: [
      {
        accession: "0000320193-24-000123",
        filingDate: "2024-08-02",
        reportDate: "2024-06-29",
        form: "10-Q",
        primaryDocument: "aapl-20240629.htm",
        sourceReference:
          "https://data.sec.gov/submissions/CIK0000320193.json",
      },
    ],
    fundamentals: [
      {
        metric: "revenue",
        value: "383285000000",
        canonicalDecimal: "383285000000",
        unit: "USD",
        periodClass: "annual",
        start: "2023-10-01",
        end: "2024-09-28",
        tag: "RevenueFromContractWithCustomerExcludingAssessedTax",
        accession: "0000320193-24-000123",
        form: "10-K",
        filed: "2024-11-01",
        sourceReference:
          "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
      },
    ],
    missingCapabilities: ["effective US market rules are unavailable"],
  };
}

describe("US stock research report boundary", () => {
  test("queues the evidence workflow instead of duplicating provider clients", async () => {
    const instance = await harness();
    const notifications = [];
    await instance.commands
      .get("us-research")
      .handler("Apple AAPL 0000320193 annual 2024-09-28", context(notifications));

    expect(instance.queued).toHaveLength(1);
    expect(instance.queued[0].options.deliverAs).toBe("followUp");
    expect(instance.queued[0].content).toContain("us_stock_quote");
    expect(instance.queued[0].content).toContain("sec_company_submissions");
    expect(instance.queued[0].content).toContain("Do not choose among ambiguous");
    expect(notifications.at(-1).message).toContain("Queued");
  });

  test("assembles exact receipts into a cited, replayable source-fact brief", async () => {
    const instance = await harness();
    expect([...instance.tools.keys()]).toEqual(["us_company_brief"]);
    const result = await execute(instance.tools.get("us_company_brief"), input());

    expect(result.details.track).toBe("us");
    expect(result.details.trackContext.marketScope).toBe("us_company_brief");
    expect(result.details.status).toBe("assembled");
    expect(result.details.identity.symbol).toBe("AAPL");
    expect(result.details.quote.bid.rawPrice).toBe("189.1000");
    expect(result.details.history.bars).toBe(3);
    expect(result.details.fundamentals[0].value).toBe("383285000000");
    expect(result.details.filings[0].accession).toBe(
      "0000320193-24-000123",
    );
    expect(result.details.evidenceRoots.map(({ id }) => id)).toEqual([
      "Q1",
      "H1",
      "S1",
      "F1",
    ]);
    expect(result.details.receiptIntegrity).toBe(
      "caller_supplied_not_cryptographically_verified",
    );
    expect(result.details.interpretation).toBe("not_generated");
    expect(result.details.inactiveDependencyTools).toEqual([]);
    expect(result.content[0].text).toContain("## Evidence roots");
    expect(result.content[0].text).toContain(
      "https://www.sec.gov/Archives/edgar/data/320193/",
    );
  });

  test("rejects a quote copied under a different symbol identity", async () => {
    const instance = await harness();
    const invalid = input();
    invalid.quotes[0].sourceReference = invalid.quotes[0].sourceReference.replace(
      "AAPL",
      "MSFT",
    );
    await expect(
      execute(instance.tools.get("us_company_brief"), invalid),
    ).rejects.toThrow("InvalidQuoteSource");
  });
});
