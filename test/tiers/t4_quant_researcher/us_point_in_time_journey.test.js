import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

let directory;
const sha = (value) => createHash("sha256").update(value).digest("hex");

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "pi-sparkles-t4-"));
});

afterAll(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function harness(name) {
  const tools = new Map();
  const api = { registerTool(definition) { tools.set(definition.name, definition); } };
  const artifact = resolve(import.meta.dir, `../../../dist/${name}/index.js`);
  const module = await import(`${artifact}?t4=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return tools;
}

function execute(tool, input, id = "t4-role") {
  return tool.execute(id, input, new AbortController().signal, undefined, { hasUI: false, ui: {} });
}

async function packetFile(name, value) {
  const text = JSON.stringify(value);
  const path = join(directory, name);
  await writeFile(path, text, "utf8");
  return { path, expectedSha256: sha(text), maximumBytes: 5_000_000 };
}

function canonicalManifests() {
  const date = (year, month, day) => ({ year, month, day });
  const start = date(2026, 1, 1);
  const end = date(2026, 4, 30);
  const listingStart = date(2020, 1, 1);
  const observationDate = date(2026, 2, 24);
  const ids = ["A", "B", "C", "D"];
  const memberships = ids.map((suffix) => ({
    listing_id: `listing:${suffix}`,
    mic: "XNAS",
    track: "us",
    symbol: { state: "known", value: suffix },
    symbol_interval: { state: "known", value: { start: listingStart, end: null } },
    listing_interval: { start: listingStart, end: null },
    security_class: { state: "known", value: "common_stock" },
    status_interval: { state: "known", value: { start: listingStart, end: null } },
    membership_effective: listingStart,
    membership_end: { state: "not_applicable", reason: "open membership" },
    publication_time: { state: "known", value: 90 },
    knowledge_time: { state: "known", value: 100 },
    retrieval_time_unix_ms: 200,
    source_receipt: sha(`membership:${suffix}`),
    correction_lineage: [],
    state: { state: "known" },
  }));
  const universeContent = {
    schema: "finance_replay_universe_manifest",
    schema_version: 1,
    decision_owner: "llm",
    manifest_id: "t4-us-universe",
    version: "1.0.0",
    track: "us",
    definition_kind: { kind: "exact_enumerated" },
    as_of_time_unix_ms: 900,
    coverage: { start, end },
    source_receipt: sha("universe-source"),
    provenance: "caller_declared",
    limitations: ["rights-safe point-in-time US acceptance fixture"],
    memberships,
    plugin_decision_fields: [],
  };
  const universeHash = sha(JSON.stringify(universeContent));
  const observations = ids.map((suffix) => ({
    observation_id: `obs-listing:${suffix}`,
    listing_id: `listing:${suffix}`,
    mic: "XNAS",
    track: "us",
    observation_date: observationDate,
    observation_time: { state: "known", value: 300 },
    publication_time: { state: "known", value: 310 },
    availability_time: { state: "known", value: 320 },
    knowledge_time: { state: "known", value: 330 },
    retrieval_time_unix_ms: 400,
    source_cutoff: { state: "known", value: 1000 },
    correction_vintage: { state: "known", value: "original" },
    correction_lineage: [],
    session_type: { state: "known", value: "regular_full" },
    calendar_ref: { state: "known", value: sha("calendar") },
    status_ref: { state: "known", value: sha("status") },
    unit: { state: "known", value: "price_and_factor_inputs" },
    currency: { state: "known", value: "USD" },
    scale: { state: "known", value: 6 },
    timezone: { state: "known", value: "America/New_York" },
    adjustment_basis: { state: "known", value: "raw" },
    quantity_semantics: { state: "known", value: "shares" },
    entitlement: { state: "known", value: "fixture-local-analysis" },
    licence: { state: "known", value: "rights-safe-fixture" },
    state: { state: "known", value: "reported" },
    content_hash: sha(`observation:${suffix}`),
    corporate_action_refs: [sha(`corporate-action:${suffix}`)],
    transformation_refs: [],
  }));
  const datasetContent = {
    schema: "finance_replay_dataset_manifest",
    schema_version: 1,
    decision_owner: "llm",
    manifest_id: "t4-us-dataset",
    version: "1.0.0",
    provider: "scripted-acceptance-fixture",
    source_or_import_provenance: "fixture://t4/us-point-in-time",
    track: "us",
    coverage: { start, end },
    observations,
    limitations: ["daily fixture does not prove intraday behavior"],
    plugin_decision_fields: [],
  };
  const datasetHash = sha(JSON.stringify(datasetContent));
  return {
    universe: {
      manifestJson: JSON.stringify({ payload: { content: universeContent, content_hash: universeHash }, canonical_content_hash: universeHash }),
      manifestHash: universeHash,
    },
    dataset: {
      manifestJson: JSON.stringify({ payload: { content: datasetContent, content_hash: datasetHash }, canonical_content_hash: datasetHash }),
      manifestHash: datasetHash,
      omissions: [],
      receiptRoots: [sha("dataset-root")],
    },
  };
}

function binding(manifests) {
  return {
    track: "us",
    universe: manifests.universe,
    dataset: { manifestJson: manifests.dataset.manifestJson, manifestHash: manifests.dataset.manifestHash },
    knowledgeCutoffUnixMilliseconds: 1000,
    calendarReceipt: sha("calendar"),
    trialId: "trial-anchor",
  };
}

function knownFact(raw, receipt, knownAt = 900) {
  return { state: "known", raw, knownAtUnixMilliseconds: knownAt, reason: null, alternatives: [], receipts: [sha(receipt)] };
}

function factorMember(listingId, factorRaw, returnRaw, knownAt = 900) {
  return {
    listingId,
    mic: "XNAS",
    observationId: `obs-${listingId}`,
    membershipState: "member",
    membershipReceipt: sha(`projected-membership:${listingId}`),
    factor: knownFact(factorRaw, `factor:${listingId}`, knownAt),
    forwardReturn: knownFact(returnRaw, `return:${listingId}`),
    weight: null,
    delisted: false,
    suspended: false,
  };
}

function factorPacket(manifests, late = false) {
  const period = (periodId, at, rows) => ({
    periodId,
    atUnixMilliseconds: at,
    knowledgeCutoffUnixMilliseconds: 1000,
    rebalanceReceipt: sha(`rebalance:${periodId}`),
    members: rows.map(([id, factorRaw, returnRaw], index) => factorMember(id, factorRaw, returnRaw, late && index === 0 ? 1200 : 900)),
  });
  return {
    schemaVersion: 1,
    contractId: "stock_factor_lab_v1",
    operation: "calculate",
    binding: binding(manifests),
    definition: {
      factorId: "size-rank-v1",
      sourceField: "point_in_time_market_cap",
      sourceUnit: "USD",
      calculation: "identity(point_in_time_market_cap)",
      transformation: "rank_v1",
      availabilityRule: "known_at_or_before_period_cutoff",
      rebalanceSchedule: "caller_supplied_month_end",
      weighting: "equal_weight",
      bucketCount: 2,
      direction: "high_minus_low",
      returnHorizon: "next_month",
      currency: "USD",
      missingPolicy: "retain_unperformed",
      survivorshipPolicy: "include_delisted_with_unknown_return",
      icMethod: "pearson_v1",
      scale: 6,
      rounding: "half_even",
    },
    periods: [
      period("2026-02", 100, [["listing:A", "1", "0.01"], ["listing:B", "2", "0.02"], ["listing:C", "3", "0.03"], ["listing:D", "4", "0.04"]]),
      period("2026-03", 200, [["listing:A", "4", "0.04"], ["listing:B", "3", "0.03"], ["listing:C", "2", "0.02"], ["listing:D", "1", "0.01"]]),
    ],
  };
}

function pricePoints(values, prefix) {
  return values.map(([offset, raw], index) => ({ offset, raw, sourceReceipt: sha(`${prefix}:${index}`) }));
}

function eventPacket(manifests) {
  return {
    schemaVersion: 1,
    contractId: "stock_event_study_v1",
    operation: "calculate",
    binding: binding(manifests),
    definition: {
      studyId: "earnings-market-adjusted-v1",
      eventType: "earnings_release",
      model: "market_adjusted_v1",
      returnKind: "simple_return_v1",
      estimationWindow: { startOffset: -2, endOffset: -1 },
      eventWindow: { startOffset: 0, endOffset: 1 },
      clusterPolicy: "include_all",
      missingPolicy: "retain_partial_unperformed",
      scale: 6,
      rounding: "half_even",
      requestedStatistics: ["car_mean"],
    },
    events: [
      {
        eventId: "earnings-A",
        listingId: "listing:A",
        mic: "XNAS",
        eventDate: "2026-02-24",
        clusterId: "issuer-A-q1",
        duplicateOf: null,
        delistedDuringWindow: false,
        unperformedReason: null,
        securityPrices: pricePoints([[-3, "100"], [-2, "110"], [-1, "121"], [0, "121"], [1, "133.1"]], "security"),
        benchmarkPrices: pricePoints([[-3, "100"], [-2, "105"], [-1, "110.25"], [0, "110.25"], [1, "115.7625"]], "benchmark"),
        eventReceipt: sha("event:A"),
      },
      {
        eventId: "earnings-B",
        listingId: "listing:B",
        mic: "XNAS",
        eventDate: "2026-02-25",
        clusterId: "issuer-B-q1",
        duplicateOf: null,
        delistedDuringWindow: true,
        unperformedReason: "delisted_during_event_window",
        securityPrices: [],
        benchmarkPrices: [],
        eventReceipt: sha("event:B"),
      },
    ],
  };
}

function snapshotInput() {
  const observed = (id, current, previous) => ({
    listingId: id,
    mic: "XNAS",
    symbol: id.slice(-1),
    label: null,
    groups: [{ kind: "index", id: "anchor", label: "US anchor supplied set" }],
    price: { state: "observed", rawCurrent: current, rawPreviousClose: previous, reason: null, alternatives: [] },
    volume: { state: "reported", rawValue: "1000", unit: "shares", method: null, reason: null },
    volatility: { state: "unavailable", rawValue: null, unit: null, method: null, reason: "not requested" },
  });
  return {
    track: "us",
    market: { mic: "XNAS", scopeKind: "index", scopeId: "anchor", label: "US anchor supplied set" },
    snapshot: { providerTimestamp: "2026-04-30T20:00:00Z", asOfUnixMilliseconds: 1000, retrievedAtUnixMilliseconds: 1100, currency: "USD", session: { state: "closed", otherLabel: null }, coverage: { state: "partial", expectedMembers: 4, reason: "one member absent and one supplied row unavailable" } },
    members: [observed("listing:A", "110", "100"), observed("listing:B", "90", "100"), { ...observed("listing:C", "100", "100"), price: { state: "unavailable", rawCurrent: null, rawPreviousClose: null, reason: "delisted", alternatives: [] } }],
    calculation: { changeFractionScale: 6, rounding: "half_even", extremaLimit: 10 },
    source: { provider: "scripted-acceptance-fixture", reference: "fixture://t4/us-snapshot", kind: "user_supplied", otherKind: null, feed: "daily-close", entitlement: { state: "unknown", delayMilliseconds: null }, licence: { label: "rights-safe", redistribution: "no_redistribution", notes: null }, receiptHash: sha("snapshot") },
    page: { offset: 0, limit: 10 },
  };
}

function runDefinition(manifests, featureReceipts, id = "run-anchor", branch = "all_branches") {
  const content = {
    schema: "finance_replay_run_definition",
    schema_version: 1,
    decision_owner: "llm",
    run_definition_id: id,
    version: "1.0.0",
    feature_receipts: featureReceipts,
    strategy_receipt: sha("strategy"),
    risk_receipts: [sha("risk")],
    execution_receipt: sha("execution"),
    universe_manifest: manifests.universe.manifestHash,
    dataset_manifest: manifests.dataset.manifestHash,
    partition_receipt: sha("fixed-train-test-partition"),
    knowledge_cutoff: { state: "known", value: 1000 },
    declared_policies: [{ name: "missing_data", value: "preserve_unknown", source_receipt: null }],
    execution_branch_policy: branch,
    seed_and_stream: { state: "known", value: "seed:42/stream:anchor" },
    limitations: ["completed daily acceptance fixture"],
    plugin_decision_fields: [],
    available_operations: ["inspect_receipt", "compare_run_definition", "declare_trial", "request_scripted_replay"],
  };
  const digest = sha(JSON.stringify(content));
  return { canonicalJson: JSON.stringify({ payload: { content, content_hash: digest }, canonical_content_hash: digest }), contentHash: digest };
}

function replayEvent(suffix, kind, replayClock, runId, references) {
  const eventTime = { state: "known", value: replayClock * 10 };
  const payload = JSON.stringify({ fixture: suffix });
  const refs = references.map((hash, index) => ({ kind: index === 0 ? "feature" : "source", hash }));
  const semantic = { run_id: runId, kind, event_time: eventTime, availability_time: eventTime, replay_clock: replayClock, track: { state: "known", value: "us" }, session_date: { state: "known", value: { year: 2026, month: 4, day: replayClock } }, payload, references: refs };
  const canonical = { schema: "finance_replay_event", schema_version: 1, decision_owner: "llm", run_id: runId, event_id: `event-${suffix}`, kind, event_time: eventTime, availability_time: eventTime, replay_clock: replayClock, track: semantic.track, session_date: semantic.session_date, payload, references: refs, recording_time: 100 + replayClock, idempotency_key: `key-${suffix}`, semantic_content_hash: sha(JSON.stringify(semantic)), plugin_decision_fields: [] };
  const digest = sha(JSON.stringify(canonical));
  return { canonicalJson: JSON.stringify({ payload: canonical, canonical_content_hash: digest }), contentHash: digest, elapsedMilliseconds: 1, sessionIncrement: suffix === "observation" ? 1 : 0 };
}

function runInput(definition, featureReceipts, cancellation = { kind: "continue" }) {
  return {
    cadencePolicy: "caller_declared_completed_daily_cash_equity_v1",
    definition,
    events: [
      replayEvent("observation", "market_observation_available", 1, "run-anchor", [sha("dataset-row")]),
      replayEvent("feature", "feature_result_produced", 2, "run-anchor", featureReceipts),
      replayEvent("complete", "run_completed", 3, "run-anchor", [sha("output")]),
    ],
    budget: { maximumEvents: 100, maximumBytes: 1_000_000, maximumWallTimeMilliseconds: 100, maximumSessions: 10 },
    cancellation,
  };
}

function manifestInput(featureReceipts) {
  return {
    manifestId: "t4-reproduction-anchor",
    environmentVersions: [{ name: "finance_quant", version: "0.1.0", semantic: true }, { name: "finance_replay", version: "0.1.0", semantic: true }],
    trialIds: ["trial-completed", "trial-cancelled"],
    orderedSourceHashes: [sha("dataset-row")],
    transformationReceipts: featureReceipts,
    calendarReceipts: [sha("calendar")],
    ruleReceipts: [sha("us-rules")],
    corporateActionReceipts: [sha("corporate-actions")],
    costReceipts: [sha("cost-model")],
    seedAndRandomStreamFacts: ["seed:42/stream:anchor"],
    additionalEffectFacts: ["bounded scripted replay"],
    outputReceiptHashes: [sha("output")],
    checkpointHashes: [sha("checkpoint")],
    entitlementLimitations: ["rights-safe acceptance fixture only"],
    omittedDependencies: [],
    unknownDependencies: [{ receiptHash: { state: "unknown", reason: "external live provider not requested" }, reason: "not required for completed-daily anchor" }],
    conflictingDependencies: [],
    exportProvenance: "local acceptance export",
    privacyPolicy: "no credentials or private research prose",
  };
}

function hypothesis(manifests, featureReceipts) {
  const content = { schema: "pi-sparkles/research-hypothesis", schemaVersion: 1, hypothesisId: "hypothesis-anchor", version: "1.0.0", author: { kind: "user", importSource: null }, authorId: "researcher", declaredTimeUnixMilliseconds: 10, text: "Caller-declared factor and event hypothesis", structuredExpression: "size_rank AND event_abnormal_return", targetValue: "net_return", populationRef: manifests.universe.manifestHash, featureRefs: featureReceipts, strategyRef: sha("strategy"), sourceCutoffUnixMilliseconds: 9, supportingRefs: [manifests.dataset.manifestHash], privacy: "research_context", exportClassification: "review_visible", decisionOwner: "llm", pluginDecisionFields: [] };
  return { ...content, author: { kind: "user" }, contentHash: sha(JSON.stringify(content)) };
}

function ledgerEvent(suffix, status, runHash) {
  return {
    ledgerEventId: `ledger-${suffix}`,
    trial: { trialId: `trial-${suffix}`, batchId: "batch-anchor", runDefinitionHash: runHash, parameterValues: [{ name: "factor_direction", exactValue: suffix, author: { kind: "llm" }, sourceReceipt: { state: "known", value: sha(`parameter:${suffix}`) } }], trialRationale: { state: "known", value: "caller-declared comparison" }, partitionRef: sha("fixed-train-test-partition"), modelRefs: [sha("model")], seed: { state: "known", value: `seed-${suffix}` }, metricRefs: [sha("net-return-metric")], budgetRefs: [sha("budget")], author: { kind: "llm" }, declaredTimeUnixMilliseconds: 10, privacy: "research_context" },
    status,
    startTimeUnixMilliseconds: 20,
    endTime: { state: "known", value: 30 },
    outputReceiptHashes: status.state === "completed" ? [sha("output")] : [],
    errorFacts: [],
    effectReceiptHash: sha(`effect:${suffix}`),
    idempotencyKey: `trial-key-${suffix}`,
  };
}

function metricInput() {
  return { metadata: { requestId: "metric-net-return", formula: "(ending-starting)/starting", formulaVersion: "1.0.0", unit: "fraction", scale: 6, rounding: "half_even", missingConflictPolicy: "preserve_unknown_v1", samplePopulation: "US point-in-time anchor", ordering: "replay order", benchmark: { state: "not_applicable", reason: "not requested" }, sourceReceipts: [sha("output")] }, request: { kind: "net_return", denominator: { state: "known", value: { name: "starting_equity", exactLexeme: "100", sourceReceipt: sha("starting") } }, endingValue: { state: "known", value: { name: "ending_equity", exactLexeme: "102", sourceReceipt: sha("ending") } } } };
}

describe("Tier 4 US point-in-time quant researcher product", () => {
  test("completes one bounded feature, replay, trial, comparison, and reproduction journey", async () => {
    const manifests = canonicalManifests();

    const datasetTools = await harness("finance_dataset");
    const inspected = await execute(datasetTools.get("inspect_dataset"), { dataset: manifests.dataset });
    expect(inspected.details.manifestHandle).toBe(manifests.dataset.manifestHash);
    expect(inspected.details.manifest.track).toBe("us");
    expect(inspected.details.counts.observations).toBe(4);

    const snapshotTools = await harness("stock_market_snapshot");
    const snapshot = await execute(snapshotTools.get("market_snapshot"), snapshotInput());
    expect(snapshot.details.track).toBe("us");
    expect(snapshot.details.overall).toMatchObject({ advancing: 1, declining: 1, unavailable: 1 });
    expect(snapshot.details.snapshot.coverage.state).toBe("partial");

    const factorTools = await harness("stock_factor_lab");
    const factorFile = await packetFile("factor.json", factorPacket(manifests));
    const factorResult = await execute(factorTools.get("stock_factor_lab"), factorFile);
    expect(factorResult.details.binding).toMatchObject({ track: "us", universeManifestHash: manifests.universe.manifestHash, datasetManifestHash: manifests.dataset.manifestHash });
    expect(factorResult.details.periodCount).toBe(2);
    expect(factorResult.details.periods[0].factorReturn).toBe("0.02");
    expect(factorResult.details.periods[1].turnover).toBe("1");
    expect(factorResult.details.decisionOwner).toBe("llm");

    const lateFile = await packetFile("factor-late.json", factorPacket(manifests, true));
    const lateResult = await execute(factorTools.get("stock_factor_lab"), lateFile, "late-factor");
    expect(lateResult.details.periods[0].members[0]).toMatchObject({ state: "omitted", reason: "factor_known_after_cutoff" });
    expect(lateResult.details.periods[0].members).toHaveLength(4);

    const eventTools = await harness("stock_event_study");
    const eventFile = await packetFile("event.json", eventPacket(manifests));
    const eventResult = await execute(eventTools.get("stock_event_study"), eventFile);
    expect(eventResult.details).toMatchObject({ performedCount: 1, unperformedCount: 1, carMean: "0.05" });
    expect(eventResult.details.events[1]).toMatchObject({ state: "unperformed", reason: "delisted_during_event_window", delistedDuringWindow: true });
    expect(eventResult.details.pluginDecisionFields).toEqual([]);

    const featureReceipts = [factorResult.details.contentHash, eventResult.details.contentHash];
    const definition = runDefinition(manifests, featureReceipts);
    const backtestTools = await harness("backtest");
    const cancelled = await execute(backtestTools.get("submit_run"), runInput(definition, featureReceipts, { kind: "cancel_before", replayClock: 2, cancelledAtUnixMilliseconds: 25, cancelledBy: "researcher" }), "cancelled-replay");
    expect(cancelled.details.state.stop).toMatchObject({ kind: "cancelled", continuationReplayClock: 2 });
    expect(cancelled.details.state.omittedEventCount).toBe(2);

    const run = runInput(definition, featureReceipts);
    const completed = await execute(backtestTools.get("submit_run"), run);
    expect(completed.details.state).toMatchObject({ status: "completed", retainedEventCount: 3, omittedEventCount: 0 });
    expect(completed.details.definition.contentHash).toBe(definition.contentHash);

    const quantTools = await harness("quant_research");
    const metric = await execute(quantTools.get("request_metric"), metricInput());
    expect(metric.details).toMatchObject({ metricKind: "net_return", interpretation: "llm_owned", decisionOwner: "llm" });

    const comparisonDefinition = runDefinition(manifests, [factorResult.details.contentHash], "run-comparison", "stop_first");
    const ledgerEvents = [
      ledgerEvent("completed", { state: "completed" }, definition.contentHash),
      ledgerEvent("cancelled", { state: "cancelled", atUnixMilliseconds: 25, by: "researcher" }, comparisonDefinition.contentHash),
    ];
    const ledger = await execute(quantTools.get("inspect_trial_ledger"), {
      hypothesis: hypothesis(manifests, featureReceipts),
      populationId: "population-us-anchor",
      completenessPolicy: "caller_declared_complete_population_v1",
      expectedCounts: { total: 2, completed: 1, failed: 0, cancelled: 1, truncated: 0, duplicate: 0, unperformed: 0 },
      events: ledgerEvents,
      includeHypothesisText: false,
      includeTrialPayloads: false,
      offset: 0,
      limit: 10,
    });
    expect(ledger.details.counts).toMatchObject({ total: 2, completed: 1, cancelled: 1 });
    expect(ledger.details.returnedCount).toBe(2);
    expect(ledger.details.completenessLimitation).toContain("caller");

    const compared = await execute(quantTools.get("compare_runs"), {
      comparisonPolicy: "caller_selected_exact_runs_and_outputs_v1",
      leftDefinition: definition,
      rightDefinition: comparisonDefinition,
      leftOutputs: [{ name: "net_return", exactValue: "0.02", sourceReceipt: metric.details.calculationHandle }],
      rightOutputs: [{ name: "net_return", exactValue: "0.01", sourceReceipt: sha("comparison-output") }],
    });
    expect(compared.details.inputDifferenceCount).toBeGreaterThan(0);
    expect(compared.details.outputDifferenceCount).toBe(1);
    expect(compared.details.interpretation).toBe("llm_owned");

    const exported = await execute(backtestTools.get("export_backtest_manifest"), { run, manifest: manifestInput(featureReceipts), offset: 0, maximumEvents: 100, maximumCharacters: 1_000_000 });
    const reproduction = JSON.parse(exported.details.manifestJson).payload;
    expect(reproduction.universe_manifest_hash).toBe(manifests.universe.manifestHash);
    expect(reproduction.dataset_manifest_hash).toBe(manifests.dataset.manifestHash);
    expect(exported.details).toMatchObject({ pageComplete: true, bundleComplete: true, returnedCount: 3 });
    expect(exported.details.manifestHandle).toHaveLength(64);
    expect(JSON.stringify({ factor: factorResult.details, event: eventResult.details, comparison: compared.details, exported: exported.details })).not.toMatch(/"(preferredRun|recommendation|significant|robust|deployable|nextAction)"/);
  });
});
