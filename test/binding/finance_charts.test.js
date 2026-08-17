import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/finance_charts/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-charts=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const hash = (digit) => digit.repeat(64);

function input() {
  return {
    context: {
      instructionRef: hash("1"),
      track: "us",
      instrumentId: "US-AAPL",
      mic: "XNAS",
      timezone: "America/New_York",
      sourceLanguage: "en-US",
      priceUnit: "USD",
      volumeUnit: "shares",
      adjustment: { kind: "raw", label: null },
      source: {
        provider: "fixture-provider",
        sourceReference: "fixture://daily-bars",
        acquisitionReceipt: hash("2"),
        retrievedAtUnixMilliseconds: 1_800_000_000_000,
        sourceCutoffUnixMilliseconds: 1_799_999_000_000,
        entitlement: "fixture_local_analysis",
      },
      limitations: ["fixture_only"],
    },
    series: [
      {
        date: "2026-02-02",
        sessionType: "regular",
        open: "10.00",
        high: "11.00",
        low: "9.00",
        close: "10.50",
        volume: "100",
      },
      {
        date: "2026-02-03",
        sessionType: "regular",
        open: "10.50",
        high: "12.00",
        low: "10.00",
        close: "11.50",
        volume: "150",
      },
      {
        date: "2026-02-04",
        sessionType: "half_day",
        open: "11.50",
        high: "12.00",
        low: "10.50",
        close: "10.75",
        volume: "80",
      },
    ],
    indicators: [
      {
        indicatorId: "sma_2",
        label: "SMA 2",
        panel: "price_overlay",
        unit: "USD",
        warmupSessions: 1,
        calculationReceipt: hash("3"),
        points: [
          { state: "unperformed", date: "2026-02-02", reason: "warmup" },
          { state: "calculated", date: "2026-02-03", value: "11.00" },
          { state: "calculated", date: "2026-02-04", value: "11.125" },
        ],
      },
      {
        indicatorId: "rsi_2",
        label: "RSI 2",
        panel: "lower_panel",
        unit: "ratio_0_100",
        warmupSessions: 1,
        calculationReceipt: hash("4"),
        points: [
          { state: "unperformed", date: "2026-02-02", reason: "warmup" },
          { state: "calculated", date: "2026-02-03", value: "75" },
          { state: "calculated", date: "2026-02-04", value: "40" },
        ],
      },
    ],
    trades: [
      {
        tradeId: "matched",
        date: "2026-02-03",
        side: "buy",
        price: "10.75",
        quantity: "5",
        status: "simulated",
        evidenceReceipt: hash("5"),
      },
      {
        tradeId: "outside",
        date: "2026-02-06",
        side: "sell",
        price: "11.25",
        quantity: "5",
        status: "proposed",
        evidenceReceipt: hash("6"),
      },
    ],
    gaps: [
      {
        date: "2026-02-05",
        state: "market_closure",
        reason: "published closure",
        evidenceRoots: [hash("7")],
      },
    ],
    inputOmissions: ["trade costs not supplied"],
    fallbackMaximumRows: 2,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "finance-chart-query",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("finance charts bundled boundary", () => {
  test("registers one chart tool and returns only exact text plus structured details", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["chart_ohlcv"]);

    const first = await execute(tools.get("chart_ohlcv"), input());
    expect(first.content.map((part) => part.type)).toEqual(["text"]);
    expect(first.content[0].text).toContain(
      "| Date | Session | Open | High | Low | Close | Volume |",
    );
    expect(first.content[0].text).toContain("active host renders this result inline");
  });

  test("retains exact decimals and mandatory structured fallback", async () => {
    const tools = await harness();
    const result = await execute(tools.get("chart_ohlcv"), input());

    expect(result.details).toMatchObject({
      schema: "pi-sparkles/finance-chart-result",
      schemaVersion: 2,
      track: "us",
      instrumentId: "US-AAPL",
      mic: "XNAS",
      priceUnit: "USD",
      volumeUnit: "shares",
      structuredFallback: {
        format: "finance_table_v1",
        omittedRows: 1,
        allExactRowsRetainedInDetails: true,
      },
      presentation: {
        kind: "responsive_ohlcv_view",
        interval: "completed_daily",
        initialRangeAnchor: "latest_bar",
        spanPolicy: {
          kind: "available_plot_width_per_host_slot",
          selection: "latest_contiguous_suffix",
          downsampling: false,
          aggregation: false,
          interpolation: false,
          inferredGaps: false,
        },
      },
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(result.details.bars).toHaveLength(3);
    expect(result.details.bars[0]).toMatchObject({
      open: "10.00",
      high: "11.00",
      low: "9.00",
      close: "10.50",
      volume: "100",
    });
    expect(result.details.structuredFallback.table.rows).toHaveLength(2);
  });

  test("renders a width-bounded latest suffix as inline ASCII", async () => {
    const tools = await harness();
    const definition = tools.get("chart_ohlcv");
    const value = input();
    value.series = Array.from({ length: 30 }, (_, index) => ({
      date: `2026-01-${String(index + 1).padStart(2, "0")}`,
      sessionType: "regular",
      open: String(100 + index),
      high: String(102 + index),
      low: String(99 + index),
      close: String(101 + index),
      volume: String(1000 + index * 10),
    }));
    value.indicators = [];
    value.trades = [];
    value.gaps = [];
    const result = await execute(definition, value);

    expect(typeof definition.renderResult).toBe("function");
    const narrow = definition.renderResult(
      result,
      { expanded: false },
      {},
      { lastComponent: null },
    );
    const narrowLines = narrow.render(60);
    expect(narrowLines[0]).toContain("2026-01-06..2026-01-30");
    expect(narrowLines[0]).toContain("25/30 bars");
    expect(narrowLines.every((line) => line.length <= 60)).toBeTrue();
    expect(narrowLines.join("\n")).toContain("legend # up");

    const wide = definition.renderResult(
      result,
      { expanded: false },
      {},
      { lastComponent: narrow },
    );
    const wideLines = wide.render(80);
    expect(wide).toBe(narrow);
    expect(wideLines[0]).toContain("2026-01-01..2026-01-30");
    expect(wideLines[0]).toContain("30/30 bars");
    expect(wideLines.every((line) => line.length <= 80)).toBeTrue();
    expect(wideLines.join("\n")).not.toContain("\u001b[");
  });

  test("expanded Pi output keeps the exact text fallback inline", async () => {
    const tools = await harness();
    const definition = tools.get("chart_ohlcv");
    const result = await execute(definition, input());
    const component = definition.renderResult(
      result,
      { expanded: true },
      {},
      { lastComponent: null },
    );
    const rendered = component.render(100).join("\n");
    expect(rendered).toContain("legend # up");
    expect(rendered).toContain("| Date | Session | Open | High | Low | Close | Volume |");
  });

  test("discloses warm-up, gaps, omissions, and unmatched marker dates", async () => {
    const tools = await harness();
    const result = await execute(tools.get("chart_ohlcv"), input());

    expect(result.details.indicators[0].points[0]).toEqual({
      state: "unperformed",
      date: "2026-02-02",
      reason: "warmup",
      rendered: false,
      renderOmission: "unperformed",
    });
    expect(result.details.trades[0]).toMatchObject({ rendered: true });
    expect(result.details.trades[1]).toMatchObject({
      rendered: false,
      renderOmission: "no_matching_bar_date",
    });
    expect(result.details.gaps[0]).toMatchObject({
      date: "2026-02-05",
      state: "market_closure",
      reason: "published closure",
    });
    expect(result.details.inputOmissions).toEqual(["trade costs not supplied"]);
  });

  test("rejects market and OHLC mismatches instead of guessing", async () => {
    const tools = await harness();
    const wrongMarket = input();
    wrongMarket.context.mic = "XHKG";
    await expect(execute(tools.get("chart_ohlcv"), wrongMarket)).rejects.toThrow(
      /no fallback was used/,
    );

    const wrongBar = input();
    wrongBar.series[1].high = "9";
    await expect(execute(tools.get("chart_ohlcv"), wrongBar)).rejects.toThrow(
      /OHLC ordering/,
    );
  });

  test("honors cancellation before bounded validation work", async () => {
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();

    await expect(
      tools.get("chart_ohlcv").execute(
        "cancelled-finance-chart",
        input(),
        controller.signal,
        undefined,
        { hasUI: false, ui: {} },
      ),
    ).rejects.toThrow(/cancelled before work began/);
  });
});
