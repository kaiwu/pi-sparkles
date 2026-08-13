import { createHash } from "node:crypto";
import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/backtest/index.js");
const sha = (value) => createHash("sha256").update(value).digest("hex");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?backtest=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "backtest-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function runDefinition() {
  const content = {
    schema: "finance_replay_run_definition",
    schema_version: 1,
    decision_owner: "llm",
    run_definition_id: "run-fixture",
    version: "1.0.0",
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
    execution_branch_policy: "all_branches",
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

function replayEvent(suffix, kind, replayClock) {
  const eventTime = { state: "known", value: replayClock * 10 };
  const availabilityTime = { state: "known", value: replayClock * 10 };
  const track = { state: "known", value: "us" };
  const sessionDate = {
    state: "known",
    value: { year: 2026, month: 1, day: replayClock },
  };
  const payload = `{"fixture":"${suffix}"}`;
  const references = [{ kind: "source", hash: sha(`source-${suffix}`) }];
  const semantic = {
    run_id: "run-fixture",
    kind,
    event_time: eventTime,
    availability_time: availabilityTime,
    replay_clock: replayClock,
    track,
    session_date: sessionDate,
    payload,
    references,
  };
  const canonical = {
    schema: "finance_replay_event",
    schema_version: 1,
    decision_owner: "llm",
    run_id: "run-fixture",
    event_id: `event-${suffix}`,
    kind,
    event_time: eventTime,
    availability_time: availabilityTime,
    replay_clock: replayClock,
    track,
    session_date: sessionDate,
    payload,
    references,
    recording_time: 100 + replayClock,
    idempotency_key: `key-${suffix}`,
    semantic_content_hash: sha(JSON.stringify(semantic)),
    plugin_decision_fields: [],
  };
  const digest = sha(JSON.stringify(canonical));
  return {
    canonicalJson: JSON.stringify({
      payload: canonical,
      canonical_content_hash: digest,
    }),
    contentHash: digest,
    elapsedMilliseconds: 1,
    sessionIncrement: suffix === "observation" ? 1 : 0,
  };
}

function runInput() {
  return {
    cadencePolicy: "caller_declared_completed_daily_cash_equity_v1",
    definition: runDefinition(),
    events: [
      replayEvent("observation", "market_observation_available", 1),
      replayEvent("feature", "feature_result_produced", 2),
      replayEvent("complete", "run_completed", 3),
    ],
    budget: {
      maximumEvents: 100,
      maximumBytes: 1_000_000,
      maximumWallTimeMilliseconds: 100,
      maximumSessions: 100,
    },
    cancellation: { kind: "continue" },
  };
}

function manifestInput() {
  return {
    manifestId: "manifest-fixture",
    environmentVersions: [
      { name: "finance_replay", version: "0.1.0", semantic: true },
    ],
    trialIds: ["trial-1"],
    orderedSourceHashes: [sha("source")],
    transformationReceipts: [sha("transform")],
    calendarReceipts: [sha("calendar")],
    ruleReceipts: [sha("rule")],
    corporateActionReceipts: [sha("action")],
    costReceipts: [sha("cost")],
    seedAndRandomStreamFacts: ["seed:42/stream:main"],
    additionalEffectFacts: ["caller effect fact"],
    outputReceiptHashes: [sha("output")],
    checkpointHashes: [sha("checkpoint")],
    entitlementLimitations: ["fixture is not redistributable"],
    omittedDependencies: [
      {
        receiptHash: { state: "known", value: sha("omitted") },
        reason: "proprietary source omitted",
      },
    ],
    unknownDependencies: [
      {
        receiptHash: { state: "unknown", reason: "not obtained" },
        reason: "not obtained",
      },
    ],
    conflictingDependencies: [],
    exportProvenance: "local scripted export",
    privacyPolicy: "exclude private notes",
  };
}

describe("backtest bundled boundary", () => {
  test("registers only the three bounded replay tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "submit_run",
      "inspect_events",
      "export_backtest_manifest",
    ]);
  });

  test("executes the exact script and distinguishes fold status from stop", async () => {
    const tools = await harness();
    const completed = await execute(tools.get("submit_run"), runInput());
    expect(completed.details).toMatchObject({
      operation: "submit_run",
      cadencePolicy: "caller_declared_completed_daily_cash_equity_v1",
      definition: { runId: "run-fixture", contentHash: runDefinition().contentHash },
      state: {
        status: "completed",
        revision: 3,
        consumedEventCount: 3,
        retainedEventCount: 3,
        omittedEventCount: 0,
        stop: { kind: "input_exhausted", continuationReplayClock: null },
      },
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });

    const truncatedInput = runInput();
    truncatedInput.budget.maximumEvents = 1;
    const truncated = await execute(
      tools.get("submit_run"),
      truncatedInput,
    );
    expect(truncated.details.state).toMatchObject({
      status: "open",
      consumedEventCount: 1,
      retainedEventCount: 1,
      omittedEventCount: 2,
      stop: {
        kind: "budget_truncated",
        reason: "max_events",
        continuationReplayClock: 2,
      },
    });
  });

  test("pages only retained events and reveals envelopes only on request", async () => {
    const tools = await harness();
    const first = await execute(tools.get("inspect_events"), {
      run: runInput(),
      offset: 0,
      limit: 1,
      includePayloads: false,
    });
    const second = await execute(tools.get("inspect_events"), {
      run: runInput(),
      offset: 1,
      limit: 1,
      includePayloads: true,
    });

    expect(first.details).toMatchObject({
      operation: "inspect_events",
      retainedEventCount: 3,
      returnedCount: 1,
      nextOffset: 1,
      payloadsIncluded: false,
      events: [{ eventId: "event-observation", eventEnvelope: null }],
    });
    expect(second.details.runStateHandle).toBe(first.details.runStateHandle);
    expect(second.details.events[0].eventEnvelope.payload).toMatchObject({
      schema: "finance_replay_event",
      event_id: "event-feature",
    });
  });

  test("exports canonical receipts and marks bounded JSONL pages partial", async () => {
    const tools = await harness();
    const full = await execute(tools.get("export_backtest_manifest"), {
      run: runInput(),
      manifest: manifestInput(),
      offset: 0,
      maximumEvents: 200,
      maximumCharacters: 1_000_000,
    });
    const payload = JSON.parse(full.details.manifestJson).payload;
    expect(payload).toMatchObject({
      schema: "finance_replay_reproduction_manifest",
      run_definition_hash: runDefinition().contentHash,
      partition_receipt: sha("partition"),
      universe_manifest_hash: sha("universe"),
      dataset_manifest_hash: sha("dataset"),
      execution_model_receipt: sha("execution"),
      decision_owner: "llm",
      plugin_decision_fields: [],
    });
    expect(full.details).toMatchObject({
      returnedCount: 3,
      nextOffset: null,
      pageComplete: true,
      bundleComplete: true,
      receiptDirectory: "receipts/",
      checkpointDirectory: "checkpoints/",
    });

    const partial = await execute(tools.get("export_backtest_manifest"), {
      run: runInput(),
      manifest: manifestInput(),
      offset: 0,
      maximumEvents: 1,
      maximumCharacters: 1_000_000,
    });
    expect(partial.details).toMatchObject({
      returnedCount: 1,
      nextOffset: 1,
      pageComplete: false,
      bundleComplete: false,
    });
    expect(JSON.stringify(partial.details)).not.toMatch(
      /"(preferredRun|verdict|recommendation|significant|robust|deployable|nextAction)"/,
    );
  });
});
