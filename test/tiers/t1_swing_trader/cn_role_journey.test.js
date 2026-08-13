import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const originalFetch = globalThis.fetch;
const originalContact = process.env.EASTMONEY_USER_AGENT_CONTACT;

const historyBody = JSON.stringify({
  rc: 0,
  data: {
    code: "600519",
    name: "贵州茅台",
    klines: [
      "2026-08-03,10.00,10.00,10.30,9.80,1000,10000.00,5.00,0.00,0.00,1.00",
      "2026-08-04,10.00,11.00,11.20,9.90,1100,11500.00,6.00,10.00,1.00,1.10",
      "2026-08-05,11.00,12.00,12.20,10.80,1200,13500.00,6.00,9.09,1.00,1.20",
      "2026-08-06,12.00,13.00,13.20,11.80,1300,15500.00,6.00,8.33,1.00,1.30",
      "2026-08-07,13.00,14.00,14.50,12.80,1400,19000.00,7.00,7.69,1.00,1.40",
    ],
  },
});

const hash = (digit) => digit.repeat(64);

beforeAll(() => {
  process.env.EASTMONEY_USER_AGENT_CONTACT = "t1-swing@example.test";
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    if (
      url.hostname !== "push2his.eastmoney.com" ||
      url.pathname !== "/api/qt/stock/kline/get"
    ) {
      throw new Error(`unexpected T1 provider request: ${url}`);
    }
    return new Response(historyBody, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterAll(() => {
  globalThis.fetch = originalFetch;
  if (originalContact === undefined) {
    delete process.env.EASTMONEY_USER_AGENT_CONTACT;
  } else {
    process.env.EASTMONEY_USER_AGENT_CONTACT = originalContact;
  }
});

function sessionEntry(id, customType, data) {
  return {
    type: "custom",
    id,
    parentId: null,
    timestamp: "2026-08-11T00:00:00.000Z",
    customType,
    data,
  };
}

async function harness(name, entries = []) {
  const tools = new Map();
  let sequence = entries.length;
  const api = {
    registerCommand() {},
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    on() {},
    appendEntry(customType, data) {
      sequence += 1;
      entries.push(sessionEntry(`t1-${sequence}`, customType, data));
    },
  };
  const artifact = resolve(
    import.meta.dir,
    `../../../dist/${name}/index.js`,
  );
  const module = await import(
    `${artifact}?t1-role=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { tools, entries };
}

function context(entries = []) {
  return {
    hasUI: false,
    ui: {},
    sessionManager: {
      getBranch: () => entries,
      getEntries: () => entries,
    },
  };
}

async function execute(tool, input, id, entries = []) {
  return tool.execute(
    id,
    input,
    new AbortController().signal,
    undefined,
    context(entries),
  );
}

function technicalInput(history) {
  return {
    context: {
      instructionRef: hash("1"),
      track: "cn",
      instrumentId: "cn:XSHG:600519",
      mic: "XSHG",
      timezone: "Asia/Shanghai",
      dateStart: "2026-08-03",
      dateEnd: "2026-08-07",
      source: {
        provider: history.selectedProvider,
        sourceReference: history.source.reference,
        acquisitionReceipt: history.acquisitionReceipt.canonicalSha256,
        retrievalTimeUnixMilliseconds:
          history.source.retrievedAtUnixMilliseconds,
      },
      inputField: "close",
      inputUnit: { state: "known", label: "CNY" },
      basis: { kind: "raw", evidenceRoots: [] },
      retainedAlternatives: [],
      gapFacts: [],
      evidenceRoots: [history.acquisitionReceipt.contentSha256],
    },
    calculation: {
      formulaVariant: "sma_v1",
      period: 3,
      windowVariant: "slot_window_v1",
      parseablePolicy: "exclude_parseable_with_checks",
      rounding: {
        mode: "half_up",
        policy: "per_step",
        outputScale: 2,
        intermediateScale: 6,
      },
    },
    projection: { kind: "compact", priorOffset: 1 },
    observations: history.bars.map((bar) => ({
      date: bar.date,
      value: { state: "known", raw: bar.close },
    })),
  };
}

function source(value, unit, reference) {
  return {
    kind: "calculated",
    reference,
    effectiveAtUnixMilliseconds: 1_775_779_200_000,
    retrievedAtUnixMilliseconds: 1_775_779_200_100,
    currency: "CNY",
    unit,
    sourceLexeme: value,
    scope: "t1_cn_swing_acceptance",
    retainedAlternatives: [],
  };
}

function known(value, unit, reference) {
  return {
    state: "known",
    value,
    source: source(value, unit, reference),
    alternatives: [],
  };
}

function planInput(entryValue, technicalReceipt) {
  return {
    common: {
      context: {
        instructionRef: hash("2"),
        accountScope: "paper:cn-swing",
        portfolioScope: "watchlist:t1",
        track: "cn",
        listingId: "cn:XSHG:600519",
        asOfUnixMilliseconds: 1_775_779_200_000,
        nativeCurrency: "CNY",
        evidenceRoots: [technicalReceipt],
      },
      rounding: {
        mode: "half_up",
        policy: "final_only",
        outputScale: 2,
        intermediateScale: 6,
      },
      branchPolicy: { kind: "all_branches" },
      maximumOperations: 10,
      maximumOutputs: 10,
      projection: "compact",
    },
    operationId: "t1_planned_loss",
    entry: known(entryValue, "currency_per_share", technicalReceipt),
    stop: known("12.50", "currency_per_share", hash("3")),
  };
}

function simulationInput(lastBar, planReceipt) {
  return {
    operationId: "t1_daily_bar_paths",
    instruction: {
      instructionId: "t1-paper-instruction",
      instructionReceipt: planReceipt,
      track: "cn",
      listingId: "cn:XSHG:600519",
      mic: "XSHG",
      accountScope: "paper:cn-swing",
      currency: "CNY",
      side: "buy",
      intent: "open",
      quantity: "100",
      quantityUnit: "shares",
      orderBehavior: { kind: "limit", price: lastBar.close },
      timeInForce: { kind: "day" },
      requestedSession: "regular",
      timezone: "Asia/Shanghai",
      ruleReferences: [hash("4")],
      capabilityReferences: [hash("5")],
      accountReferences: [hash("6")],
      retainedAlternatives: { state: "known", values: [] },
    },
    bar: {
      state: "known",
      value: {
        open: lastBar.open,
        high: lastBar.high,
        low: lastBar.low,
        close: lastBar.close,
      },
      source: source(
        [lastBar.open, lastBar.high, lastBar.low, lastBar.close].join("|"),
        "ohlc",
        hash("7"),
      ),
      alternatives: [],
    },
    desiredOrderSupported: {
      state: "known",
      value: true,
      source: source("supported", "boolean", hash("8")),
      alternatives: [],
    },
    policy: {
      model: "bar_possible_paths_v1",
      calculationPolicy: "limit_touch_v1",
      capabilityPolicy: "record_only_v1",
      branchPolicy: "all_branches",
      sessionScope: "regular",
      dateTimeScope: "2026-08-07",
      currencyPolicy: "native",
      rounding: { outputScale: 4, mode: "half_up" },
      references: {
        capabilityReferences: [hash("5")],
        ruleReferences: [hash("4")],
        calendarReferences: [hash("9")],
        marketEventReferences: [],
        lifecycleReferences: [],
        positionReferences: [],
        riskReceiptReferences: [planReceipt],
        costReceiptReferences: [],
        fxReceipts: [],
      },
      maximumBranches: 10,
      maximumOutputs: 10,
      maximumBytes: 100_000,
      maximumOperations: 10,
      projection: "compact",
    },
  };
}

describe("T1 CN swing-trader role journey", () => {
  test("acquires exact daily data, calculates, plans, simulates, and manages offline replay", async () => {
    const providerEntries = [];
    const historyHarness = await harness("cn_stock_history", providerEntries);
    const historyResult = await execute(
      historyHarness.tools.get("cn_stock_history"),
      {
        track: "cn",
        provider: "eastmoney",
        venue: "sse",
        code: "600519",
        shareClass: "a_share",
        identityEvidenceId: hash("a"),
        startDate: "2026-08-03",
        endDate: "2026-08-07",
        limit: 10,
      },
      "t1-history",
      providerEntries,
    );

    expect(historyResult.details).toMatchObject({
      track: "cn",
      selectedProvider: "eastmoney",
      fallbackPerformed: false,
      adjustment: "raw_unadjusted",
      omissionAssessment: "not_performed_no_calendar_join",
    });
    expect(historyResult.details.bars).toHaveLength(5);
    expect(historyResult.content[0].text).toContain(
      "Complete bounded daily rows follow as CSV",
    );
    expect(historyResult.content[0].text).toContain(
      "2026-08-07,13.00,14.50,12.80,14.00,1400,19000.00",
    );
    expect(providerEntries).toHaveLength(1);
    expect(providerEntries[0].customType).toBe(
      "pi_sparkles_finance_cache.event.v1",
    );

    const technicalHarness = await harness("stock_technicals");
    const technical = await execute(
      technicalHarness.tools.get("sma"),
      technicalInput(historyResult.details),
      "t1-sma",
    );
    expect(technical.details.latestValue.output).toMatchObject({
      date: "2026-08-07",
      value: "13.00",
      unit: "CNY",
    });
    expect(technical.details.decisionOwner).toBe("llm");

    const planHarness = await harness("trade_plan");
    const plan = await execute(
      planHarness.tools.get("plan_loss"),
      planInput(
        technical.details.latestValue.output.value,
        technical.details.semanticReceiptHandle,
      ),
      "t1-plan",
    );
    expect(plan.details.result.plannedLoss).toMatchObject({
      state: "calculated",
      value: "0.50",
      currency: "CNY",
      unit: "currency_per_share",
    });

    const simulatorHarness = await harness("order_simulator");
    const simulation = await execute(
      simulatorHarness.tools.get("simulate_bar_paths"),
      simulationInput(
        historyResult.details.bars.at(-1),
        plan.details.semanticReceiptHandle,
      ),
      "t1-simulation",
    );
    expect(simulation.details.result).toMatchObject({
      state: "performed",
      resultKind: "hypothetical",
    });
    expect(simulation.details.result.branches.map((branch) => branch.outcome)).toEqual([
      "compatible_fill",
      "compatible_non_fill",
    ]);
    expect(simulation.details.decisionOwner).toBe("llm");

    const cacheHarness = await harness("finance_cache", providerEntries);
    const inspection = await execute(
      cacheHarness.tools.get("finance_cache_inspect"),
      { provider: "eastmoney", maximumEntries: 10 },
      "t1-cache-inspect",
      providerEntries,
    );
    expect(inspection.details.activeEntryCount).toBe(1);
    expect(inspection.details.providerUsage).toEqual([
      { provider: "eastmoney", activeEntryCount: 1 },
    ]);
    const cached = inspection.details.entries[0];
    expect(cached).toMatchObject({
      provider: "eastmoney",
      cached: true,
      sourceOfTruth: false,
      content: null,
    });

    const exported = await execute(
      cacheHarness.tools.get("finance_cache_export"),
      { cacheKeySha256: cached.cacheKeySha256, includeContent: true },
      "t1-cache-export",
      providerEntries,
    );
    expect(exported.details.offlineReplay).toBeTrue();
    expect(exported.details.entry.content).toBe(historyBody);

    const expired = await execute(
      cacheHarness.tools.get("finance_cache_expire"),
      {
        cacheKeySha256: cached.cacheKeySha256,
        expectedContentSha256: cached.contentSha256,
        reason: "t1_acceptance_targeted_expiry",
      },
      "t1-cache-expire",
      providerEntries,
    );
    expect(expired.details).toMatchObject({
      action: "expired_exact_entry",
      persisted: true,
    });
    expect(providerEntries).toHaveLength(2);

    const afterExpiry = await execute(
      cacheHarness.tools.get("finance_cache_inspect"),
      { maximumEntries: 10 },
      "t1-cache-after-expiry",
      providerEntries,
    );
    expect(afterExpiry.details.activeEntryCount).toBe(0);
    expect(afterExpiry.details.expiryReceiptCount).toBe(1);
  });

  test("does not fall back from an explicitly selected unavailable provider", async () => {
    const priorToken = process.env.TUSHARE_TOKEN;
    delete process.env.TUSHARE_TOKEN;
    let calls = 0;
    const currentFetch = globalThis.fetch;
    globalThis.fetch = async (...args) => {
      calls += 1;
      return currentFetch(...args);
    };
    try {
      const historyHarness = await harness("cn_stock_history");
      await expect(
        execute(
          historyHarness.tools.get("cn_stock_history"),
          {
            track: "cn",
            provider: "tushare",
            venue: "sse",
            code: "600519",
            shareClass: "a_share",
            identityEvidenceId: hash("a"),
            startDate: "2026-08-03",
            endDate: "2026-08-07",
            limit: 10,
          },
          "t1-no-fallback",
        ),
      ).rejects.toThrow("TUSHARE_TOKEN");
      expect(calls).toBe(0);
    } finally {
      globalThis.fetch = currentFetch;
      if (priorToken === undefined) delete process.env.TUSHARE_TOKEN;
      else process.env.TUSHARE_TOKEN = priorToken;
    }
  });
});
