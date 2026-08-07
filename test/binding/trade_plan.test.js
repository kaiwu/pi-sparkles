import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/trade_plan/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?trade-plan=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const hash = (digit) => digit.repeat(64);

function source(
  sourceLexeme,
  currency,
  unit,
  marker,
  kind = "caller_declared",
) {
  return {
    kind,
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

function known(value, currency, unit, marker) {
  return {
    state: "known",
    value,
    source: source(value, currency, unit, marker),
    alternatives: [],
  };
}

function tradeUnit(minimum, increment, marker = "d") {
  return {
    state: "known",
    value: { minimum, increment },
    source: source(
      `${minimum}x${increment}`,
      "N/A",
      "shares",
      marker,
      "market_rule",
    ),
    alternatives: [],
  };
}

function common({ projection = "compact", track = "cn", currency = "CNY" } = {}) {
  return {
    context: {
      instructionRef: hash("f"),
      accountScope: "account:A",
      portfolioScope: "portfolio:A",
      track,
      listingId: "listing:A",
      asOfUnixMilliseconds: 1_770_000_000_000,
      nativeCurrency: currency,
      evidenceRoots: [hash("e")],
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
    projection,
  };
}

function stopBound(amount = "2000.00", currency = "CNY") {
  return {
    boundId: "stop_bound",
    formulaVariant: "stop_budget_bound_v1",
    numeratorName: "declared_stop_budget",
    numerator: known(amount, currency, "currency", "c"),
    denominator: {
      kind: "long_planned_loss_per_unit_v1",
      entry: known("10.91", currency, "currency_per_share", "a"),
      stop: known("10.55", currency, "currency_per_share", "b"),
    },
  };
}

function cashBound() {
  return {
    boundId: "cash_bound",
    formulaVariant: "cash_ceiling_bound_v1",
    numeratorName: "available_cash",
    numerator: known("30000.00", "CNY", "currency", "9"),
    denominator: {
      kind: "supplied_denominator_v1",
      operandName: "desired_entry",
      formulaVariant: "desired_entry_value_v1",
      outputUnit: "currency_per_share",
      value: known("10.91", "CNY", "currency_per_share", "a"),
    },
  };
}

function lossInput(projection = "compact") {
  return {
    common: common({ projection }),
    operationId: "planned_loss",
    entry: known("10.91", "CNY", "currency_per_share", "a"),
    stop: known("10.55", "CNY", "currency_per_share", "b"),
  };
}

async function execute(tool, input) {
  return tool.execute(
    "trade-plan-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("trade plan bundled boundary", () => {
  test("runs the three exact calculation tools without selecting a quantity", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "plan_loss",
      "plan_bounds",
      "plan_grid_projection",
    ]);

    const loss = await execute(tools.get("plan_loss"), lossInput());
    expect(loss.details.result.plannedLoss).toMatchObject({
      formulaVariant: "long_planned_loss_per_unit_v1",
      state: "calculated",
      value: "0.36",
      currency: "CNY",
      unit: "currency_per_share",
    });

    const bounds = await execute(tools.get("plan_bounds"), {
      common: common(),
      bounds: [stopBound(), cashBound()],
      tradeUnit: tradeUnit(100, 100),
      intersection: {
        state: "requested",
        operationId: "requested_intersection",
        selectedBoundIds: ["stop_bound", "cash_bound"],
      },
    });
    expect(bounds.details.result.bounds[0]).toMatchObject({
      boundId: "stop_bound",
      gridProjected: { state: "projected", quantity: 5500 },
    });
    expect(bounds.details.result.bounds[1]).toMatchObject({
      boundId: "cash_bound",
      gridProjected: { state: "projected", quantity: 2700 },
    });
    expect(bounds.details.result.requestedIntersection).toMatchObject({
      selectedBoundIds: ["stop_bound", "cash_bound"],
      value: { state: "calculated", quantity: 2700 },
    });

    const grid = await execute(tools.get("plan_grid_projection"), {
      common: common({ track: "hk", currency: "HKD" }),
      bound: stopBound("2000.00", "HKD"),
      tradeUnit: tradeUnit(500, 500),
    });
    expect(grid.details.result.bound).toMatchObject({
      wholeShare: { quantity: 5555 },
      gridProjected: { quantity: 5500, minimum: 500, increment: 500 },
    });
    expect(grid.details.decisionOwner).toBe("llm");
    expect(grid.details.pluginDecisionFields).toEqual([]);
    expect(JSON.stringify(grid.details)).not.toMatch(
      /"(verdict|recommendedSize|selectedQuantity|nextAction|ready|accepted|rejected)"/,
    );
  });

  test("preserves receipt identity across projections and unavailable grids without fallback", async () => {
    const tools = await harness();
    const compact = await execute(tools.get("plan_loss"), lossInput("compact"));
    const full = await execute(tools.get("plan_loss"), lossInput("receipt"));
    expect(full.details.semanticReceiptHandle).toBe(
      compact.details.semanticReceiptHandle,
    );
    expect(compact.details.semanticReceiptEnvelope).toBeUndefined();
    expect(full.details.semanticReceiptEnvelope).toContain(
      "pi-sparkles/risk-calculation-receipt",
    );

    const unknownGrid = {
      state: "unknown",
      source: source("not supplied", "N/A", "shares", "d", "market_rule"),
      reason: "issuer board lot not obtained",
      alternatives: [],
    };
    const projected = await execute(tools.get("plan_grid_projection"), {
      common: common(),
      bound: stopBound(),
      tradeUnit: unknownGrid,
    });
    expect(projected.details.result.bound).toMatchObject({
      rawDecimal: { state: "calculated", value: "5555.555556" },
      wholeShare: { state: "projected", quantity: 5555 },
      gridProjected: {
        state: "unperformed",
      },
    });
    expect(projected.details.result.bound.gridProjected.reason).toContain(
      "missing_trade_unit_fact",
    );

    await expect(
      execute(tools.get("plan_bounds"), {
        common: common(),
        bounds: [stopBound()],
        tradeUnit: tradeUnit(100, 100),
        intersection: {
          state: "requested",
          operationId: "intersection",
          selectedBoundIds: ["missing"],
        },
      }),
    ).rejects.toThrow("every selected ID must name a bound");

    const missingStop = lossInput();
    delete missingStop.stop;
    await expect(
      execute(tools.get("plan_loss"), missingStop),
    ).rejects.toThrow("Invalid parameters for tool plan_loss");
  });
});
