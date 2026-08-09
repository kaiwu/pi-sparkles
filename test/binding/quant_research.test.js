import { createHash } from "node:crypto";
import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/quant_research/index.js");

const sha = (value) => createHash("sha256").update(value).digest("hex");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?quant-research=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "quant-research-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function hypothesis() {
  const content = {
    schema: "pi-sparkles/research-hypothesis",
    schemaVersion: 1,
    hypothesisId: "hypothesis-fixture",
    version: "1.0.0",
    author: { kind: "user", importSource: null },
    authorId: "user-fixture",
    declaredTimeUnixMilliseconds: 10,
    text: "Exact fixture hypothesis",
    structuredExpression: "close_t > close_t_minus_1",
    targetValue: "net_return",
    populationRef: sha("universe"),
    featureRefs: [sha("feature")],
    strategyRef: sha("strategy"),
    sourceCutoffUnixMilliseconds: 9,
    supportingRefs: [sha("journal")],
    privacy: "research_context",
    exportClassification: "review_visible",
    decisionOwner: "llm",
    pluginDecisionFields: [],
  };
  return {
    hypothesisId: content.hypothesisId,
    version: content.version,
    contentHash: sha(JSON.stringify(content)),
    author: { kind: "user" },
    authorId: content.authorId,
    declaredTimeUnixMilliseconds: content.declaredTimeUnixMilliseconds,
    text: content.text,
    structuredExpression: content.structuredExpression,
    targetValue: content.targetValue,
    populationRef: content.populationRef,
    featureRefs: content.featureRefs,
    strategyRef: content.strategyRef,
    sourceCutoffUnixMilliseconds: content.sourceCutoffUnixMilliseconds,
    supportingRefs: content.supportingRefs,
    privacy: content.privacy,
    exportClassification: content.exportClassification,
  };
}

function ledgerEvent(suffix, status) {
  return {
    ledgerEventId: `event-${suffix}`,
    trial: {
      trialId: `trial-${suffix}`,
      batchId: "batch-fixture",
      runDefinitionHash: sha(`run-${suffix}`),
      parameterValues: [
        {
          name: "period",
          exactValue: suffix,
          author: { kind: "llm" },
          sourceReceipt: {
            state: "known",
            value: sha(`parameter-${suffix}`),
          },
        },
      ],
      trialRationale: {
        state: "known",
        value: "caller-authored rationale",
      },
      partitionRef: sha("partition"),
      modelRefs: [sha("model")],
      seed: { state: "known", value: `seed-${suffix}` },
      metricRefs: [sha("metric")],
      budgetRefs: [sha("budget")],
      author: { kind: "llm" },
      declaredTimeUnixMilliseconds: 10,
      privacy: "research_context",
    },
    status,
    startTimeUnixMilliseconds: 20,
    endTime: { state: "known", value: 30 },
    outputReceiptHashes: [sha(`output-${suffix}`)],
    errorFacts:
      status.state === "failed" ? ["fixture failure retained"] : [],
    effectReceiptHash: sha(`effect-${suffix}`),
    idempotencyKey: `key-${suffix}`,
  };
}

function metricInput(request) {
  return {
    metadata: {
      requestId: `metric-${request.kind}`,
      formula: `requested(${request.kind})`,
      formulaVersion: "1.0.0",
      unit: "dimensionless",
      scale: 4,
      rounding: "half_even",
      missingConflictPolicy: "preserve_unknown_v1",
      samplePopulation: "caller-selected fixture population",
      ordering: "caller-supplied order",
      benchmark: { state: "not_applicable", reason: "not requested" },
      sourceReceipts: [sha("metric-source")],
    },
    request,
  };
}

function runDefinition(id, version, branchPolicy) {
  const content = {
    schema: "finance_replay_run_definition",
    schema_version: 1,
    decision_owner: "llm",
    run_definition_id: id,
    version,
    feature_receipts: [sha("feature")],
    strategy_receipt: sha("strategy"),
    risk_receipts: [sha("risk")],
    execution_receipt: sha("execution"),
    universe_manifest: sha("universe"),
    dataset_manifest: sha("dataset"),
    partition_receipt: sha("partition"),
    knowledge_cutoff: { state: "known", value: 100 },
    declared_policies: [
      {
        name: "missing_data",
        value: "preserve_unknown",
        source_receipt: null,
      },
    ],
    execution_branch_policy: branchPolicy,
    seed_and_stream: { state: "known", value: "seed:42/stream:main" },
    limitations: ["completed daily fixture"],
    plugin_decision_fields: [],
    available_operations: [
      "inspect_receipt",
      "compare_run_definition",
      "declare_trial",
      "request_scripted_replay",
    ],
  };
  const digest = sha(JSON.stringify(content));
  return {
    canonicalJson: JSON.stringify({
      payload: { content, content_hash: digest },
      canonical_content_hash: digest,
    }),
    contentHash: digest,
  };
}

describe("quant research bundled boundary", () => {
  test("registers only the three research-information tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "inspect_trial_ledger",
      "request_metric",
      "compare_runs",
    ]);
  });

  test("retains exact ledger states, counts, paging, and optional payloads", async () => {
    const tools = await harness();
    const events = [
      ledgerEvent("completed", { state: "completed" }),
      ledgerEvent("failed", { state: "failed", reason: "fixture failure" }),
    ];
    const result = await execute(tools.get("inspect_trial_ledger"), {
      hypothesis: hypothesis(),
      populationId: "population-fixture",
      completenessPolicy: "caller_declared_complete_population_v1",
      expectedCounts: {
        total: 2,
        completed: 1,
        failed: 1,
        cancelled: 0,
        truncated: 0,
        duplicate: 0,
        unperformed: 0,
      },
      events,
      includeHypothesisText: true,
      includeTrialPayloads: true,
      offset: 0,
      limit: 1,
    });

    expect(result.details).toMatchObject({
      operation: "inspect_trial_ledger",
      populationId: "population-fixture",
      counts: { total: 2, completed: 1, failed: 1 },
      returnedCount: 1,
      nextOffset: 1,
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(result.details.hypothesis.text).toBe("Exact fixture hypothesis");
    expect(result.details.events[0].eventEnvelope.payload).toMatchObject({
      schema: "finance_replay_trial_ledger_event",
      ledger_event_id: "event-completed",
    });

    const wrongCounts = {
      hypothesis: hypothesis(),
      populationId: "population-fixture",
      completenessPolicy: "caller_declared_complete_population_v1",
      expectedCounts: {
        total: 2,
        completed: 2,
        failed: 0,
        cancelled: 0,
        truncated: 0,
        duplicate: 0,
        unperformed: 0,
      },
      events,
      includeHypothesisText: false,
      includeTrialPayloads: false,
      offset: 0,
      limit: 2,
    };
    await expect(
      execute(tools.get("inspect_trial_ledger"), wrongCounts),
    ).rejects.toThrow("reconstructed ledger status counts do not match");
  });

  test("executes only the four requested finance_replay metrics", async () => {
    const tools = await harness();
    const source = sha("operand");
    const cases = [
      {
        request: {
          kind: "net_return",
          denominator: {
            state: "known",
            value: {
              name: "starting_equity",
              exactLexeme: "100",
              sourceReceipt: source,
            },
          },
          endingValue: {
            state: "known",
            value: {
              name: "ending_equity",
              exactLexeme: "120",
              sourceReceipt: sha("ending"),
            },
          },
        },
        kind: "net_return",
      },
      {
        request: {
          kind: "win_loss_counts",
          trades: [
            { tradeId: "one", netPnlLexeme: "2", sourceReceipt: source },
            {
              tradeId: "two",
              netPnlLexeme: "-1",
              sourceReceipt: sha("loss"),
            },
          ],
          zeroPolicy: "zero_is_tie_v1",
        },
        kind: "win_loss_counts",
      },
      {
        request: {
          kind: "drawdown_series",
          points: [
            {
              label: "one",
              value: {
                name: "equity-one",
                exactLexeme: "100",
                sourceReceipt: source,
              },
            },
            {
              label: "two",
              value: {
                name: "equity-two",
                exactLexeme: "80",
                sourceReceipt: sha("equity-two"),
              },
            },
          ],
          peakConvention: "running_peak_inclusive_v1",
        },
        kind: "drawdown_series",
      },
      {
        request: {
          kind: "trade_list",
          trades: [
            {
              tradeId: "one",
              instructionReceipt: sha("instruction"),
              lifecycleReceipts: [sha("fill")],
              exactPayload: '{"netPnl":"2"}',
            },
          ],
        },
        kind: "trade_list",
      },
    ];

    for (const value of cases) {
      const result = await execute(
        tools.get("request_metric"),
        metricInput(value.request),
      );
      expect(result.details).toMatchObject({
        operation: "request_metric",
        metricKind: value.kind,
        interpretation: "llm_owned",
        decisionOwner: "llm",
        pluginDecisionFields: [],
      });
    }
  });

  test("compares exact canonical definitions without choosing a run", async () => {
    const tools = await harness();
    const result = await execute(tools.get("compare_runs"), {
      comparisonPolicy: "caller_selected_exact_runs_and_outputs_v1",
      leftDefinition: runDefinition("run-left", "1.0.0", "all_branches"),
      rightDefinition: runDefinition("run-right", "1.1.0", "stop_first"),
      leftOutputs: [
        {
          name: "net_return",
          exactValue: "0.10",
          sourceReceipt: sha("left-return"),
        },
      ],
      rightOutputs: [
        {
          name: "net_return",
          exactValue: "0.12",
          sourceReceipt: sha("right-return"),
        },
      ],
    });

    expect(result.details).toMatchObject({
      operation: "compare_runs",
      runs: { left: { id: "run-left" }, right: { id: "run-right" } },
      interpretation: "llm_owned",
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(result.details.inputDifferenceCount).toBeGreaterThan(0);
    expect(result.details.outputDifferenceCount).toBe(1);
    expect(JSON.stringify(result.details)).not.toMatch(
      /"(preferredRun|verdict|recommendation|significant|robust|deployable)"/,
    );
  });
});
