import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/investor_workbench/index.js",
);
const hash = (marker) => marker.repeat(64);
const reviewedAt = 1_770_000_000_000;

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?investor-workbench=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function provided(marker) {
  return { state: "provided", receipts: [hash(marker)] };
}

function notObtained(reason) {
  return { state: "not_obtained", reason };
}

function callerDeclared(declarationSource) {
  return { state: "caller_declared", declarationSource };
}

function sections() {
  return {
    identity: provided("a"),
    businessDescription: callerDeclared("LLM thesis v2"),
    reportingBasis: provided("b"),
    statementSet: provided("c"),
    segmentData: notObtained("not_extracted"),
    debtLiquidity: provided("d"),
    cashFlowEarningsQuality: provided("e"),
    capitalAllocation: provided("f"),
    governanceManagement: notObtained("proxy_not_retrieved"),
    industryPeers: notObtained("peer_set_not_selected"),
    macroContext: notObtained("no_macro_leg_attached"),
    corporateActions: provided("1"),
    valuation: notObtained("no_method_selected"),
    thesisRisks: callerDeclared("user thesis v1"),
    portfolioFit: notObtained("portfolio_not_supplied"),
    reviewHistory: provided("2"),
  };
}

function statement({
  statementId = "10k_2025",
  formType = "10-K",
  amendment = "original",
  originalStatementId = null,
  sourceMarker = "c",
} = {}) {
  return {
    statementId,
    formType,
    filingEntity: "Apple Inc.",
    periodStart: "2024-10-01",
    periodEnd: "2025-09-30",
    periodKind: "annual",
    inclusiveDurationDays: 365,
    auditOpinion: "unqualified",
    amendment,
    originalStatementId,
    restatement: "not_restated",
    restatementReason: null,
    consolidation: "consolidated",
    filingDate: "2025-11-15",
    acceptanceDate: "2025-11-15",
    sourceReceipt: hash(sourceMarker),
    taxonomy: "US-GAAP",
    currency: "USD",
    unit: "millions",
    scale: 6,
  };
}

function dossierInput() {
  return {
    dossierId: "dossier_AAPL_2026",
    dossierAsOf: "2026-02-01",
    reviewedAtUnixMilliseconds: reviewedAt,
    identity: {
      instrumentId: "US0378331005",
      mic: "XNAS",
      track: "us",
      symbol: "AAPL",
      shareClass: "common",
      reportingEntity: "Apple Inc.",
      entityType: "operating_company",
      currency: "USD",
      fiscalYearEnd: "09-30",
      isin: "US0378331005",
      localId: null,
      listingStart: "1980-12-12",
      listingEnd: null,
      status: "trading",
    },
    relatedListings: [],
    sections: sections(),
    reportingBasis: {
      accountingStandard: "US-GAAP",
      fiscalYearEnd: "09-30",
      auditorName: "Ernst & Young",
      auditOpinion: "unqualified",
      consolidation: "consolidated",
    },
    statements: [
      statement(),
      statement({
        statementId: "10ka_2025",
        formType: "10-K/A",
        amendment: "amendment",
        originalStatementId: "10k_2025",
        sourceMarker: "d",
      }),
    ],
    reviews: [
      {
        reviewId: "review_001",
        reviewedAtUnixMilliseconds: reviewedAt,
        reviewerKind: "llm_declared",
        reviewerRef: "course-session-19-fixture",
        dossierAsOf: "2026-02-01",
        priorReviewId: null,
        changes: [
          {
            section: "statement_set",
            kind: "added",
            addedReceipts: [hash("c")],
            removedReceipts: [],
          },
        ],
        conclusionRef: null,
      },
    ],
  };
}

function operand(name, exactLexeme, unit, marker, periodEnd = "2025-09-30") {
  return {
    name,
    exactLexeme,
    entityId: "Apple Inc.",
    periodStart: "2024-10-01",
    periodEnd,
    periodKind: "annual",
    inclusiveDurationDays: 365,
    currency: "USD",
    unit,
    reportedScale: 6,
    sourceReceipt: hash(marker),
    basis: "statement_fact",
  };
}

describe("investor workbench bundled boundary", () => {
  test("registers only the three Session 19 read-only tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "inspect_dossier",
      "dossier_metric",
      "dossier_valuation",
    ]);
  });

  test("returns the 16-section matrix and amendment facts without a verdict", async () => {
    const tools = await harness();
    const result = await tools
      .get("inspect_dossier")
      .execute("inspect-1", dossierInput(), undefined, undefined, {});

    expect(Object.keys(result.details.sectionStates)).toHaveLength(16);
    expect(result.details.identity).toMatchObject({
      instrumentId: "US0378331005",
      mic: "XNAS",
      track: "us",
      reportingEntity: "Apple Inc.",
    });
    expect(result.details.statementCoverage).toMatchObject({
      statementCount: 2,
      amendmentCount: 1,
      mechanicalEvidenceState:
        "no_session_19_insufficiency_condition_detected",
    });
    expect(result.details.sectionStates.governanceManagement).toMatchObject({
      state: "not_obtained",
      reason: "proxy_not_retrieved",
    });
    expect(result.details.reviewabilityVerdict).toBeNull();
    expect(result.details.investmentVerdict).toBeNull();
    expect(result.details.pluginDecisionFields).toEqual([]);
  });

  test("calculates only the selected metric and leaves missing inputs unperformed", async () => {
    const tools = await harness();
    const metric = tools.get("dossier_metric");
    const calculated = await metric.execute(
      "metric-1",
      {
        requestId: "gross-margin-1",
        metricId: "gross_margin",
        operands: [
          operand("revenue", "383000", "currency", "a"),
          operand("cogs", "210000", "currency", "b"),
        ],
        outputScale: 4,
        rounding: "half_up",
      },
      undefined,
      undefined,
      {},
    );
    expect(calculated.details.calculation).toMatchObject({
      state: "calculated",
      metricId: "gross_margin",
      value: "0.4517",
      economicInterpretation: null,
    });

    const unperformed = await metric.execute(
      "metric-2",
      {
        requestId: "bank-gross-margin",
        metricId: "gross_margin",
        operands: [operand("revenue", "180000", "currency", "a")],
        outputScale: 4,
        rounding: "half_up",
      },
      undefined,
      undefined,
      {},
    );
    expect(unperformed.details.calculation).toMatchObject({
      state: "unperformed",
      reason: "missing_operands",
      missingOperands: ["cogs"],
    });
    expect(unperformed.details.substituteMetricSelected).toBe(false);
  });

  test("returns calculated and incompatible valuation rows in one explicit grid", async () => {
    const tools = await harness();
    const scenarios = ["2025-09-30", "2025-12-31"].map(
      (debtPeriod, index) => ({
        label: `caller_case_${index + 1}`,
        methodResult: {
          ...operand("enterprise_value", "22500", "currency", "a"),
          basis: "caller_declared",
        },
        netDebt: operand("net_debt", "5000", "currency", "b", debtPeriod),
        dilutedShares: operand(
          "diluted_shares",
          "1000",
          "shares",
          "c",
        ),
        assumptions: [
          {
            name: "terminal_growth",
            exactValue: "0.025",
            basis: "caller_declared",
            sourceReference: "LLM instruction ref-001",
          },
        ],
      }),
    );
    const result = await tools.get("dossier_valuation").execute(
      "valuation-1",
      {
        requestId: "dcf-grid-1",
        method: "dcf",
        valuationCurrency: "USD",
        scenarios,
        outputScale: 2,
        rounding: "half_even",
      },
      undefined,
      undefined,
      {},
    );

    expect(result.details).toMatchObject({
      method: "dcf",
      methodSelectionOwner: "caller",
      scenarioCount: 2,
      calculatedScenarioCount: 1,
      unperformedScenarioCount: 1,
      authoritativeTargetPrice: null,
      valuationVerdict: null,
    });
    expect(result.details.scenarios[0].result).toMatchObject({
      state: "calculated",
      equityValue: "17500",
      perShareValue: "17.5",
    });
    expect(result.details.scenarios[1].result).toMatchObject({
      state: "unperformed",
      reason: "incompatible_periods",
    });
  });

  test("rejects identity absence and malformed review links", async () => {
    const tools = await harness();
    const inspect = tools.get("inspect_dossier");
    const absentIdentity = dossierInput();
    absentIdentity.sections.identity = notObtained("identity_missing");
    await expect(
      inspect.execute("bad-identity", absentIdentity, undefined, undefined, {}),
    ).rejects.toThrow("identity must be provided");

    const brokenReview = dossierInput();
    brokenReview.reviews[0].priorReviewId = "unknown_prior";
    await expect(
      inspect.execute("bad-review", brokenReview, undefined, undefined, {}),
    ).rejects.toThrow("priorReviewId");
  });
});
