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
  test("registers one chart tool and returns a valid deterministic PNG", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["chart_ohlcv"]);

    const first = await execute(tools.get("chart_ohlcv"), input());
    const second = await execute(tools.get("chart_ohlcv"), input());
    expect(first.content.map((part) => part.type)).toEqual(["text", "image"]);
    expect(first.content[0].text).toContain(
      "| Date | Session | Open | High | Low | Close | Volume |",
    );
    expect(first.content[1].mimeType).toBe("image/png");
    expect(first.content[1].data).toBe(second.content[1].data);

    const bytes = Buffer.from(first.content[1].data, "base64");
    expect([...bytes.subarray(0, 8)]).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(bytes.readUInt32BE(16)).toBe(960);
    expect(bytes.readUInt32BE(20)).toBe(640);
    expect(bytes.includes(Buffer.from("acTL"))).toBeFalse();
  });

  test("retains exact decimals and mandatory structured fallback", async () => {
    const tools = await harness();
    const result = await execute(tools.get("chart_ohlcv"), input());

    expect(result.details).toMatchObject({
      schema: "pi-sparkles/finance-chart-result",
      schemaVersion: 1,
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
      projection: {
        kind: "integer_pixel_projection_only",
        width: 960,
        height: 640,
        mimeType: "image/png",
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

  test("honors cancellation before bounded raster work", async () => {
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
