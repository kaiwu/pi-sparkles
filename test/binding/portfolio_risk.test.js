import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/portfolio_risk/index.js");
const asOf = 1_770_000_000_000;
const hash = (digit) => digit.repeat(64);

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?portfolio-risk=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function source(value, currency, unit, marker, kind, effectiveAt = asOf) {
  return {
    kind,
    reference: hash(marker),
    effectiveAtUnixMilliseconds: effectiveAt,
    retrievedAtUnixMilliseconds: effectiveAt + 100,
    currency,
    unit,
    sourceLexeme: value,
    scope: "binding-fixture",
    retainedAlternatives: [],
  };
}

function known(value, currency, unit, marker, kind, effectiveAt = asOf) {
  return {
    state: "known",
    value,
    source: source(value, currency, unit, marker, kind, effectiveAt),
    alternatives: [],
  };
}

function unknown(reason, currency, unit, marker) {
  return {
    state: "unknown",
    source: source(
      "not supplied",
      currency,
      unit,
      marker,
      "caller_declared",
    ),
    reason,
    alternatives: [],
  };
}

function position({
  positionId = "position_001",
  listingId = "listing_001",
  mic = "XNAS",
  track = "us",
  quantity = "10",
  mark = "50.00",
  stop = "45.00",
  marker = "b",
} = {}) {
  return {
    positionId,
    listingId,
    mic,
    track,
    direction: "long",
    quantity: known(
      quantity,
      "N/A",
      "shares",
      marker,
      "custodian_observation",
    ),
    quantityUnit: "shares",
    currentMark: known(
      mark,
      "USD",
      "currency_per_share",
      marker,
      "provider_observation",
    ),
    markTimeUnixMilliseconds: asOf,
    desiredStop: known(
      stop,
      "USD",
      "currency_per_share",
      marker,
      "llm_instruction",
    ),
    stopTimeUnixMilliseconds: asOf,
    positionCurrency: "USD",
    asOfUnixMilliseconds: asOf,
  };
}

function input(projection = "compact") {
  return {
    portfolioId: "portfolio_001",
    instructionRef: hash("f"),
    account: {
      accountId: "account_001",
      netLiquidationValue: known(
        "100000.00",
        "USD",
        "currency",
        "a",
        "caller_declared",
      ),
      accountCurrency: "USD",
      asOfUnixMilliseconds: asOf,
      sourceKind: "caller_declared",
      sourceReceipt: hash("a"),
    },
    positions: [position()],
    calculation: {
      informationPolicy: "partial_totals_v1",
      heatVariant: "heat_mark_basis_v1",
      heatDenominator: { kind: "denom_nlv_v1" },
      positionWeightFormat: "fraction_v1",
      roundingMode: "half_up",
      currencyScale: 2,
      weightScale: 4,
      percentageScale: 2,
      intermediateScale: 8,
    },
    requestedSummaryFields: [
      "position_count",
      "gross_market_exposure",
      "net_market_exposure",
      "portfolio_heat",
      "heat_pct",
      "largest_position_weight",
      "position_contributions",
      "reconciliation",
      "temporal_coherence",
      "unknown_count",
      "conflict_count",
      "receipt_handle",
    ],
    projection,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "portfolio-risk-query",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("portfolio risk bundled boundary", () => {
  test("registers one focused calculation tool and returns exact requested facts", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["portfolio_risk"]);

    const output = await execute(tools.get("portfolio_risk"), input());
    expect(output.details.result.grossMarketExposure).toMatchObject({
      knownTotal: { state: "calculated", value: "500.00", currency: "USD" },
      partial: false,
      unknownContributions: [],
    });
    expect(output.details.result.portfolioHeat.knownTotal.value).toBe("50.00");
    expect(output.details.result.heatPct).toMatchObject({
      denominator: "denom_nlv_v1",
      value: { value: "0.05", unit: "percentage_points" },
    });
    expect(output.details.result.positionContributions[0]).toMatchObject({
      positionId: "position_001",
      exposure: { value: "500.00" },
      weight: { value: "0.0050" },
      heat: { value: "50.00" },
      duplicateCount: 1,
    });
    expect(output.details.result.reconciliation.exposure.reconciled).toBe(true);
    expect(output.details.decisionOwner).toBe("llm");
    expect(output.details.pluginDecisionFields).toEqual([]);
  });

  test("returns partial known totals with unresolved contributions", async () => {
    const value = input();
    const missing = position({ positionId: "missing", marker: "c" });
    missing.currentMark = unknown(
      "provider omission",
      "USD",
      "currency_per_share",
      "c",
    );
    delete missing.markTimeUnixMilliseconds;
    value.positions.push(missing);

    const output = await execute((await harness()).get("portfolio_risk"), value);
    expect(output.details.result.grossMarketExposure).toMatchObject({
      knownTotal: { value: "500.00" },
      partial: true,
      unknownContributions: [
        { positionId: "missing", reasons: ["missing_mark"] },
      ],
    });
    expect(output.details.result.unknownCount).toBe(1);
    expect(output.details.result.positionContributions[1].heat.state).toBe(
      "unperformed",
    );
  });

  test("keeps semantic receipt identity stable across compact and receipt projections", async () => {
    const tool = (await harness()).get("portfolio_risk");
    const compact = await execute(tool, input("compact"));
    const receipt = await execute(tool, input("receipt"));
    expect(compact.details.semanticReceiptHandle).toBe(
      receipt.details.semanticReceiptHandle,
    );
    expect(compact.details.semanticReceiptEnvelope).toBeUndefined();
    expect(receipt.details.semanticReceiptEnvelope).toMatchObject({
      canonicalContentHash: receipt.details.semanticReceiptHandle,
      payload: {
        schema: "pi-sparkles/portfolio-risk-semantic-result",
        selfHashFieldExcluded: true,
      },
    });
  });

  test("rejects unsupported shorts and cross-currency fallback", async () => {
    const tool = (await harness()).get("portfolio_risk");
    const short = input();
    short.positions[0].direction = "short";
    await expect(execute(tool, short)).rejects.toThrow(
      "short positions are typed but deferred",
    );

    const crossCurrency = input();
    crossCurrency.positions[0].positionCurrency = "HKD";
    crossCurrency.positions[0].currentMark = known(
      "50.00",
      "HKD",
      "currency_per_share",
      "b",
      "provider_observation",
    );
    crossCurrency.positions[0].desiredStop = known(
      "45.00",
      "HKD",
      "currency_per_share",
      "b",
      "llm_instruction",
    );
    await expect(execute(tool, crossCurrency)).rejects.toThrow(
      "FX fallback is forbidden",
    );
  });

  test("requires an explicit denominator exactly when heat percentage is requested", async () => {
    const tool = (await harness()).get("portfolio_risk");
    const missing = input();
    delete missing.calculation.heatDenominator;
    await expect(execute(tool, missing)).rejects.toThrow(
      "is required when heat_pct is explicitly requested",
    );

    const unused = input();
    unused.requestedSummaryFields = ["position_count"];
    await expect(execute(tool, unused)).rejects.toThrow(
      "is only accepted when heat_pct is explicitly requested",
    );
  });
});
