import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/order_simulator/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?order-simulator=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const hash = (digit) => digit.repeat(64);

function source(sourceLexeme, currency, unit, marker) {
  return {
    kind: "caller_declared",
    reference: hash(marker),
    effectiveAtUnixMilliseconds: 1_770_000_000_000,
    retrievedAtUnixMilliseconds: 1_770_000_000_100,
    currency,
    unit,
    sourceLexeme,
    scope: "fixture",
    retainedAlternatives: [],
  };
}

function input({ projection = "compact" } = {}) {
  return {
    operationId: "bar_paths",
    instruction: {
      instructionId: "instruction-1",
      instructionReceipt: hash("1"),
      track: "us",
      listingId: "listing:A",
      mic: "XNAS",
      accountScope: "account:A",
      currency: "USD",
      side: "buy",
      intent: "open",
      quantity: "100",
      quantityUnit: "shares",
      orderBehavior: { kind: "limit", price: "11.20" },
      timeInForce: { kind: "day" },
      requestedSession: "regular",
      timezone: "America/New_York",
      ruleReferences: [hash("2")],
      capabilityReferences: [hash("3")],
      accountReferences: [hash("a")],
      retainedAlternatives: { state: "known", values: [] },
    },
    bar: {
      state: "known",
      value: {
        open: "11.20",
        high: "11.60",
        low: "11.15",
        close: "11.40",
      },
      source: source("11.20|11.60|11.15|11.40", "USD", "ohlc", "b"),
      alternatives: [],
    },
    desiredOrderSupported: {
      state: "known",
      value: true,
      source: source("supported", "N/A", "boolean", "c"),
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
        capabilityReferences: [hash("3")],
        ruleReferences: [hash("2")],
        calendarReferences: [hash("4")],
        marketEventReferences: [hash("b")],
        lifecycleReferences: [],
        positionReferences: [],
        riskReceiptReferences: [],
        costReceiptReferences: [],
        fxReceipts: [],
      },
      maximumBranches: 10,
      maximumOutputs: 10,
      maximumBytes: 100_000,
      maximumOperations: 10,
      projection,
    },
  };
}

async function execute(tool, value) {
  return tool.execute(
    "order-simulation-query",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("order simulator bundled boundary", () => {
  test("returns all compatible daily-bar branches without selecting a fill", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["simulate_bar_paths"]);

    const compact = await execute(tools.get("simulate_bar_paths"), input());
    expect(compact.details.result).toMatchObject({
      state: "performed",
      model: "bar_possible_paths_v1",
      resultKind: "hypothetical",
    });
    expect(compact.details.result.branches).toEqual([
      {
        branchId: "compatible_fill",
        outcome: "compatible_fill",
        fillCompatibility: "compatible_fill",
        compatiblePriceRange: { minimum: "11.15", maximum: "11.2" },
        note: "a fill at or better than the limit is compatible with the bar",
      },
      {
        branchId: "compatible_non_fill",
        outcome: "compatible_non_fill",
        fillCompatibility: "compatible_non_fill",
        compatiblePriceRange: null,
        note: "bar touch does not prove the specific order filled",
      },
    ]);
    expect(compact.details.counts.branches).toBe(2);
    expect(compact.details.decisionOwner).toBe("llm");
    expect(compact.details.pluginDecisionFields).toEqual([]);
    expect(compact.details.semanticReceiptEnvelope).toBeUndefined();
    expect(JSON.stringify(compact.details)).not.toMatch(
      /"(verdict|recommendation|selectedBranch|predictedFill|nextAction|authorization|ready|accepted)"/,
    );

    const full = await execute(
      tools.get("simulate_bar_paths"),
      input({ projection: "receipt" }),
    );
    expect(full.details.semanticReceiptHandle).toBe(
      compact.details.semanticReceiptHandle,
    );
    expect(full.details.semanticReceiptEnvelope).toContain(
      "pi-sparkles/execution-information-receipt",
    );
  });

  test("returns exact unperformed states and rejects malformed boundaries", async () => {
    const tools = await harness();
    const unavailable = input();
    unavailable.bar = {
      state: "unknown",
      source: source("not supplied", "USD", "ohlc", "b"),
      reason: "completed bar absent",
      alternatives: [],
    };
    const result = await execute(tools.get("simulate_bar_paths"), unavailable);
    expect(result.details.result).toMatchObject({
      state: "unperformed",
      model: "bar_possible_paths_v1",
      branches: [],
    });
    expect(result.details.result.reason).toContain(
      "completed_daily_bar_unavailable:unknown",
    );
    expect(result.details.counts).toMatchObject({
      branches: 0,
      unknownInputs: 1,
    });

    const unsupported = input();
    unsupported.instruction.orderBehavior = { kind: "market" };
    const market = await execute(
      tools.get("simulate_bar_paths"),
      unsupported,
    );
    expect(market.details.result.reason).toBe(
      "unsupported_desired_behavior_for_limit_touch_v1",
    );

    const missingBar = input();
    delete missingBar.bar;
    await expect(
      execute(tools.get("simulate_bar_paths"), missingBar),
    ).rejects.toThrow("Invalid parameters for tool simulate_bar_paths");
  });
});

