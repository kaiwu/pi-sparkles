import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_technicals/index.js",
);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-technicals=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const hash = (digit) => digit.repeat(64);
const known = (raw) => ({ state: "known", raw });

function context({
  track = "cn",
  instrumentId = "CNE000000001",
  mic = "XSHG",
  timezone = "Asia/Shanghai",
  inputField = "close",
  unit = "CNY",
} = {}) {
  return {
    instructionRef: hash("1"),
    track,
    instrumentId,
    mic,
    timezone,
    dateStart: "2026-02-01",
    dateEnd: "2026-02-28",
    source: {
      provider: "fixture-provider",
      sourceReference: "fixture://exact-bars",
      acquisitionReceipt: hash("2"),
      retrievalTimeUnixMilliseconds: 1_770_000_000_000,
    },
    inputField,
    inputUnit: { state: "known", label: unit },
    basis: { kind: "raw", evidenceRoots: [] },
    retainedAlternatives: [],
    gapFacts: [],
    evidenceRoots: [hash("3")],
  };
}

const rounding = (outputScale, intermediateScale) => ({
  mode: "half_up",
  policy: "per_step",
  outputScale,
  intermediateScale,
});

function smaInput(projection) {
  return {
    context: context(),
    calculation: {
      formulaVariant: "sma_v1",
      period: 3,
      windowVariant: "slot_window_v1",
      parseablePolicy: "exclude_parseable_with_checks",
      rounding: rounding(2, 6),
    },
    projection: { kind: projection, priorOffset: 1 },
    observations: [
      ["2026-02-18", "10.85"],
      ["2026-02-19", "10.92"],
      ["2026-02-20", "10.95"],
      ["2026-02-24", "10.88"],
      ["2026-02-25", "10.91"],
    ].map(([date, raw]) => ({ date, value: known(raw) })),
  };
}

function rsiInput() {
  return {
    context: context({
      track: "us",
      instrumentId: "US-A",
      mic: "XNAS",
      timezone: "America/New_York",
      unit: "USD",
    }),
    calculation: {
      formulaVariant: "rsi_wilder_v1",
      period: 5,
      windowVariant: "slot_window_v1",
      seedVariant: "seed_wilder_first_n",
      gapPolicy: "stop_at_gap_v1",
      zeroZeroConvention: "zero_zero_unperformed_v1",
      parseablePolicy: "exclude_parseable_with_checks",
      rounding: rounding(4, 8),
    },
    projection: { kind: "compact", priorOffset: 1 },
    observations: [
      ["2026-02-02", "44.34"],
      ["2026-02-03", "44.09"],
      ["2026-02-04", "44.15"],
      ["2026-02-05", "43.61"],
      ["2026-02-06", "44.33"],
      ["2026-02-09", "44.83"],
      ["2026-02-10", "45.10"],
    ].map(([date, raw]) => ({ date, value: known(raw) })),
  };
}

function atrInput() {
  const bar = (date, high, low, close) => ({
    date,
    high: known(high),
    low: known(low),
    close: known(close),
  });
  return {
    context: context({
      track: "hk",
      instrumentId: "HK-700",
      mic: "XHKG",
      timezone: "Asia/Hong_Kong",
      inputField: "ohlc",
      unit: "HKD",
    }),
    calculation: {
      formulaVariant: "atr_wilder_v1",
      period: 3,
      windowVariant: "slot_window_v1",
      seedVariant: "seed_wilder_tr_mean_v1",
      firstTrueRange: "tr_first_hl_v1",
      gapPolicy: "stop_at_gap_v1",
      parseablePolicy: "exclude_parseable_with_checks",
      rounding: rounding(4, 4),
    },
    projection: { kind: "intermediate", priorOffset: 1 },
    bars: [
      bar("2026-02-02", "10.50", "9.80", "10.20"),
      bar("2026-02-03", "10.80", "10.10", "10.60"),
      bar("2026-02-04", "11.00", "10.40", "10.80"),
      bar("2026-02-05", "10.90", "10.30", "10.50"),
    ],
  };
}

async function execute(tool, input) {
  return tool.execute(
    "stock-technicals-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("stock technicals bundled boundary", () => {
  test("supports compact then intermediate evidence queries without making a decision", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["sma", "rsi", "atr"]);

    const compact = await execute(tools.get("sma"), smaInput("compact"));
    expect(compact.details.projection).toBe("compact");
    expect(compact.details.latestValue.output).toMatchObject({
      date: "2026-02-25",
      value: "10.91",
      unit: "CNY",
    });
    expect(compact.details.priorValue.output).toMatchObject({
      date: "2026-02-24",
      value: "10.92",
    });
    expect(compact.details.orderedOutputs).toBeUndefined();

    const drilldown = await execute(
      tools.get("sma"),
      smaInput("intermediate"),
    );
    expect(drilldown.details.semanticReceiptHandle).toBe(
      compact.details.semanticReceiptHandle,
    );
    expect(drilldown.details.orderedOutputs).toHaveLength(5);
    expect(drilldown.details.orderedOutputs.at(-1)).toMatchObject({
      state: "calculated",
      intermediateValues: [
        { name: "sum", value: "32.74" },
        { name: "count", value: "3" },
      ],
    });
    expect(drilldown.details.decisionOwner).toBe("llm");
    expect(drilldown.details.pluginDecisionFields).toEqual([]);
    expect(JSON.stringify(drilldown.details)).not.toMatch(
      /"(signal|rank|recommended|correct|ready|nextAction)"/,
    );
  });

  test("runs the explicit Wilder RSI and ATR paths and rejects missing policies", async () => {
    const tools = await harness();
    const rsi = await execute(tools.get("rsi"), rsiInput());
    expect(rsi.details.latestValue.output.value).toBe("67.1859");
    expect(rsi.details.policies).toMatchObject({
      seedVariant: "seed_wilder_first_n",
      gapPolicy: "stop_at_gap_v1",
      zeroZeroConvention: "zero_zero_unperformed_v1",
    });

    const atr = await execute(tools.get("atr"), atrInput());
    expect(atr.details.latestValue.output.value).toBe("0.6445");
    expect(atr.details.orderedOutputs.at(-1).intermediateValues).toContainEqual(
      { name: "true_range", value: "0.6" },
    );
    expect(atr.details.policies.firstTrueRange).toBe("tr_first_hl_v1");

    const missingGapPolicy = rsiInput();
    delete missingGapPolicy.calculation.gapPolicy;
    await expect(
      execute(tools.get("rsi"), missingGapPolicy),
    ).rejects.toThrow("Invalid parameters for tool rsi");
  });
});
