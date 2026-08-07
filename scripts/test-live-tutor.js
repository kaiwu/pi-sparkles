import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "./build.js";
import { DIST_DIR, ROOT } from "./modules.js";
import { loadReceiptFixture } from "../test/acceptance/receipt-fixture.js";

const maximumDurationMs = 300_000;
const maximumOutputBytes = 10_000_000;
const receiptNames = ["market", "indicator", "risk", "rule", "execution"];

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(
      JSON.stringify(
        {
          schemaVersion: 1,
          kind: "live_tutor_acceptance",
          status: "failed",
          error: error instanceof Error ? error.message : String(error),
        },
        null,
        2,
      ),
    );
    process.exitCode = 1;
  }
}

async function main() {
  const pi = Bun.which("pi");
  invariant(pi, "No runnable Pi installation found");

  await build("cn_ohlcv");
  await build("hk_ohlcv");
  await build("us_ohlcv");
  await build("swing_workbench");
  await build("trade_journal");
  const receiptFixture = await loadReceiptFixture({ build: true });

  const directory = mkdtempSync(join(tmpdir(), "pi-sparkles-live-tutor-"));
  const journalPath = join(directory, "journal.jsonl");
  const sessionDirectory = join(directory, "sessions");
  const sessionId = "pi-sparkles-live-tutor-acceptance";
  const startedAt = Date.now();
  try {
    const fixture = liveFixture(journalPath, receiptFixture.tracks.us);
    const execution = await executePi(pi, livePrompt(fixture), {
      sessionDirectory,
      sessionId,
      tools:
        "swing_candidates,swing_snapshot,swing_plan,swing_review,journal_entry",
    });
    const result = inspectExecution(execution.stdout, fixture, journalPath);
    const resumeExecution = await executePi(pi, resumePrompt(fixture), {
      sessionDirectory,
      sessionId,
      tools: "swing_snapshot",
    });
    const resumed = inspectResume(
      resumeExecution.stdout,
      fixture,
      result.snapshot,
    );
    const persistedSession = inspectPersistedSession(
      sessionDirectory,
      sessionId,
    );
    console.log(
      JSON.stringify(
        {
          schemaVersion: 1,
          kind: "live_tutor_acceptance",
          status: "passed",
          startedAtUnixMs: startedAt,
          finishedAtUnixMs: Date.now(),
          configuredModel: result.model,
          toolCalls: result.toolCalls,
          stageSelections: result.stageSelections,
          llmDeclaration: result.declaration,
          finalResponseWasJsonOnly: result.finalResponseWasJsonOnly,
          receiptSchemas: result.receiptSchemas,
          pluginDecisionFields: result.pluginDecisionFields,
          journalAttribution: result.journalAttribution,
          resumedProcess: {
            configuredModel: resumed.model,
            toolCalls: resumed.toolCalls,
            revision: resumed.snapshot.revision,
            pluginDecisionFields: resumed.snapshot.pluginDecisionFields,
            exactSnapshotMatch: true,
            sessionId,
            persistedCustomEntries: persistedSession.customEntries,
          },
        },
        null,
        2,
      ),
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function liveFixture(journalPath, receiptSet) {
  const definitionHash = sha256("live-tutor-swing-definition-v1");
  const context = {
    listing: {
      track: "us",
      instrument_id: "fixture:us:AAPL",
      symbol: "AAPL",
      mic: "XNAS",
    },
    signal_session: { year: 2026, month: 8, day: 7 },
    evaluated_at_unix_ms: "1786093200000",
    source_cutoff_unix_ms: "1786092300000",
    dependencies: [],
    evidence_roots: [],
  };
  const inputHash = sha256(
    JSON.stringify({ definition_hash: definitionHash, context, features: [] }),
  );
  const strategyPayload = JSON.stringify({
    schema: "finance_strategy_evidence",
    schema_version: 1,
    definition_id: "live_tutor_completed_daily_swing",
    definition_version: "1.0.0",
    definition_hash: definitionHash,
    input_hash: inputHash,
    context,
    scope_issues: [],
    setup_dependencies: [],
    acceptance_dependencies: [],
    predicate_facts: [],
    unmatched_features: [],
    evidence_roots: [],
  });
  const strategyHash = sha256(strategyPayload);
  const workflowId = "live-tutor-us-aapl";
  const receiptReferences = Object.fromEntries(
    receiptNames.map((name) => [name, receiptSet[name].canonicalContentHash]),
  );
  const candidate = candidateInput({
    workflowId,
    strategyHash,
    strategyPayload,
    receiptReferences,
    stage: "after_close",
    attachedAtUnixMs: 1786093200000,
  });
  const preflightCandidate = candidateInput({
    workflowId,
    strategyHash,
    strategyPayload,
    receiptReferences,
    stage: "preflight",
    attachedAtUnixMs: 1786174200000,
  });
  const monitorCandidate = candidateInput({
    workflowId,
    strategyHash,
    strategyPayload,
    receiptReferences,
    stage: "monitor",
    attachedAtUnixMs: 1786203000000,
  });
  const planBase = {
    workflowId,
    sourceStrategyReceiptHash: strategyHash,
    origin: "llm_authored",
    riskReceiptReferences: [receiptReferences.risk],
    ruleReceiptReferences: [receiptReferences.rule],
    executionReceiptReferences: [receiptReferences.execution],
    createdAtUnixMs: 1786093201000,
  };
  const planChoices = decisionChoices("plan", [
    [
      "request_risk_result_before_any_order_work",
      "The exact risk request is retained but its requested calculation result is not obtained.",
    ],
    [
      "inspect_execution_branch_inputs",
      "The execution receipt retains three compatible daily-bar branches without selecting one.",
    ],
    [
      "request_additional_account_and_market_facts",
      "The bounded packet does not contain a calculated risk result or newer account facts.",
    ],
  ]).map((choice) => ({
    ...choice,
    input: {
      ...planBase,
      planReceiptHash: choice.payloadHash,
      planPayload: choice.payload,
    },
  }));
  const reviewStages = {
    preflight: reviewStage({
      workflowId,
      recordId: "live-tutor-preflight-1",
      recordKind: "llm_preflight_declaration",
      observedAtUnixMs: 1786174201000,
      evidenceReferences: Object.values(receiptReferences),
      choices: decisionChoices("preflight", [
        [
          "request_risk_result",
          "Preflight still exposes the exact risk request without a supplied calculation result.",
        ],
        [
          "inspect_effective_rule_projection",
          "The track-owned rule projection is present and explicitly non-authenticating.",
        ],
        [
          "inspect_all_execution_branches",
          "Stop-first, target-first, and unknown-ordering branches remain available together.",
        ],
      ]),
    }),
    monitor: reviewStage({
      workflowId,
      recordId: "live-tutor-monitor-1",
      recordKind: "llm_monitor_declaration",
      observedAtUnixMs: 1786203001000,
      evidenceReferences: [
        receiptReferences.market,
        receiptReferences.execution,
      ],
      choices: decisionChoices("monitor", [
        [
          "request_new_monitoring_observation",
          "No newer monitoring observation is supplied in the bounded packet.",
        ],
        [
          "inspect_plan_against_known_market_receipt",
          "The plan and completed-daily acquisition handles remain available for comparison.",
        ],
        [
          "inspect_execution_ambiguity",
          "The daily bar cannot establish stop-versus-target ordering.",
        ],
      ]),
    }),
    replay: reviewStage({
      workflowId,
      recordId: "live-tutor-replay-1",
      recordKind: "llm_replay_declaration",
      observedAtUnixMs: 1786203002000,
      evidenceReferences: Object.values(receiptReferences),
      choices: decisionChoices("replay", [
        [
          "compare_plan_with_each_execution_branch",
          "The same immutable plan can be inspected against every retained execution branch.",
        ],
        [
          "request_sequence_evidence",
          "The semantic receipt explicitly retains unknown ordering when sequence evidence is absent.",
        ],
        [
          "inspect_replay_inputs",
          "The receipt-backed workflow facts and declarations are available without a plugin verdict.",
        ],
      ]),
    }),
    review: reviewStage({
      workflowId,
      recordId: "live-tutor-review-1",
      recordKind: "llm_review_declaration",
      observedAtUnixMs: 1786203003000,
      evidenceReferences: Object.values(receiptReferences),
      choices: decisionChoices("review", [
        [
          "request_missing_risk_calculation",
          "The final packet still distinguishes a risk request from an obtained result.",
        ],
        [
          "inspect_strategy_and_receipt_lineage",
          "The workbench retains the strategy payload and every canonical receipt handle.",
        ],
        [
          "end_bounded_review",
          "The bounded acceptance exercise can end without a plugin deciding a trade or next step.",
        ],
      ]),
    }),
  };
  return {
    workflowId,
    receiptCatalog: receiptSet,
    candidate,
    preflightCandidate,
    monitorCandidate,
    planChoices,
    reviewStages,
    journal: {
      journalPath,
      expectedRevision: 0,
      maximumJournalBytes: 1_000_000,
      journalId: "live-tutor-journal-us-aapl",
      eventId: "live-tutor-decision-1",
      eventKind: "declaration",
      identityScope: "exact_listing",
      track: "us",
      listingId: "fixture:us:AAPL",
      mic: "XNAS",
      symbol: "AAPL",
      workflowId,
      attributionKind: "llm_declared",
      authorOrSourceId: "configured-tutor-model",
      stage: "review",
      recordingTimeUnixMs: 1786203004000,
      timezone: "America/New_York",
      privacy: "private",
      references: [
        { kind: "strategy", hash: strategyHash },
        ...Object.entries(receiptReferences).map(([kind, hash]) => ({
          kind,
          hash,
        })),
      ],
      idempotencyKey: "live-tutor-us-aapl-decision-1",
    },
  };
}

function candidateInput({
  workflowId,
  strategyHash,
  strategyPayload,
  receiptReferences,
  stage,
  attachedAtUnixMs,
}) {
  const facts = [
    {
      factId: "market.completed_daily",
      role: "required",
      state: "known",
      detail: "copied canonical completed-daily acquisition receipt",
      receiptReferences: [receiptReferences.market],
    },
    {
      factId: "calculation.requested_feature",
      role: "required",
      state: "known",
      detail:
        "LLM-requested Wilder RSI calculation contract; result not asserted",
      receiptReferences: [receiptReferences.indicator],
    },
    {
      factId: "risk.requested_projection",
      role: "required",
      state: "not_obtained",
      detail:
        "exact risk request receipt exists; requested result has not been supplied",
      receiptReferences: [receiptReferences.risk],
    },
    {
      factId: "rule.effective_projection",
      role: "required",
      state: "known",
      detail:
        "track-owned effective rule projection; content hash is not a provider signature",
      receiptReferences: [receiptReferences.rule],
    },
    {
      factId: "execution.branch_population",
      role: "context",
      state: "conflicting",
      detail:
        "exact semantic receipt retains stop-first, target-first, and unknown-ordering branches",
      receiptReferences: [receiptReferences.execution],
    },
    {
      factId: "workflow.stage",
      role: "context",
      state: "declared",
      detail: `LLM-requested acceptance stage: ${stage}`,
      receiptReferences: [],
    },
  ];
  if (stage === "monitor") {
    facts.push({
      factId: "monitor.new_observation",
      role: "context",
      state: "not_obtained",
      detail:
        "no newer monitoring observation was supplied to this bounded fixture",
      receiptReferences: [],
    });
  }
  return {
    workflowId,
    strategyReceiptHash: strategyHash,
    strategyReceiptPayload: strategyPayload,
    facts,
    attachedAtUnixMs,
  };
}

function decisionChoices(stage, values) {
  return values.map(([selectedOperation, basis]) => {
    const payload = JSON.stringify({
      decisionOwner: "llm",
      stage,
      selectedOperation,
      basis,
    });
    return { selectedOperation, basis, payload, payloadHash: sha256(payload) };
  });
}

function reviewStage({
  workflowId,
  recordId,
  recordKind,
  observedAtUnixMs,
  evidenceReferences,
  choices,
}) {
  return {
    inputTemplate: {
      workflowId,
      recordId,
      recordKind,
      planReceiptReference: "COPY_THE_SELECTED_PLAN_RECEIPT_HASH",
      evidenceReferences,
      observedAtUnixMs,
    },
    choices,
  };
}

function livePrompt(fixture) {
  const stageInstruction = (number, stage) => {
    const value = fixture.reviewStages[stage];
    return `${number}. Independently select one ${stage} choice from ${JSON.stringify(value.choices)}. Call swing_review exactly once using ${JSON.stringify(value.inputTemplate)}, replacing planReceiptReference with the selected plan's planReceiptHash and adding the selected choice's payloadHash and payload unchanged.`;
  };
  return [
    "This is a bounded live acceptance journey for an information-only trading workflow.",
    "The plugins never decide correctness, sufficiency, interpretation, or next action. You are the LLM and own every such decision.",
    `These are copied canonical receipt payloads constructed by the real finance packages; inspect them as information and retain their stated limitations: ${JSON.stringify(fixture.receiptCatalog)}`,
    "The choice arrays below are neutral content-bound alternatives prepared only so hashes can be verified. A plugin did not select or recommend any alternative; you must select each one from the information you inspect.",
    "Perform these operations in this exact order:",
    `1. Call swing_candidates exactly once with this exact JSON object: ${JSON.stringify(fixture.candidate)}`,
    `2. Call swing_snapshot exactly once with ${JSON.stringify({ workflowId: fixture.workflowId })}.`,
    `3. Independently select one plan choice from ${JSON.stringify(fixture.planChoices)} and call swing_plan exactly once with its input object unchanged.`,
    `4. Call swing_candidates exactly once with this exact preflight JSON object: ${JSON.stringify(fixture.preflightCandidate)}`,
    `5. Call swing_snapshot exactly once with ${JSON.stringify({ workflowId: fixture.workflowId })}.`,
    stageInstruction(6, "preflight"),
    `7. Call swing_candidates exactly once with this exact monitor JSON object: ${JSON.stringify(fixture.monitorCandidate)}`,
    `8. Call swing_snapshot exactly once with ${JSON.stringify({ workflowId: fixture.workflowId })}.`,
    stageInstruction(9, "monitor"),
    stageInstruction(10, "replay"),
    stageInstruction(11, "review"),
    `12. Call swing_snapshot exactly once with ${JSON.stringify({ workflowId: fixture.workflowId })}.`,
    `13. Call journal_entry exactly once with the fields in this JSON object: ${JSON.stringify(fixture.journal)}. Add payload as a compact JSON string with exactly seven keys: decisionOwner set to llm; planOperation, preflightOperation, monitorOperation, replayOperation, and reviewOperation set to the corresponding selectedOperation values; and basis set to your concise overall interpretation of the supplied information.`,
    "14. Answer with only the same compact JSON object stored as the journal payload. Do not use a Markdown fence or add prose.",
  ].join("\n");
}

function resumePrompt(fixture) {
  return [
    "This is the second process of the bounded information-only acceptance journey.",
    "The plugins still never decide correctness, sufficiency, interpretation, or next action. The prior extension state must come only from the reopened Pi session.",
    `Call swing_snapshot exactly once with ${JSON.stringify({ workflowId: fixture.workflowId })}.`,
    `Then answer with only this compact JSON object, replacing the integer resumedRevision with the exact returned revision: ${JSON.stringify({ decisionOwner: "llm", workflowId: fixture.workflowId, resumedRevision: 0 })}`,
  ].join("\n");
}

async function executePi(pi, prompt, { sessionDirectory, sessionId, tools }) {
  const process = Bun.spawn(
    [
      pi,
      "--mode",
      "json",
      "--print",
      "--session-dir",
      sessionDirectory,
      "--session-id",
      sessionId,
      "--no-context-files",
      "--no-skills",
      "--no-prompt-templates",
      "--no-extensions",
      "--extension",
      join(DIST_DIR, "swing_workbench"),
      "--extension",
      join(DIST_DIR, "trade_journal"),
      "--no-builtin-tools",
      "--tools",
      tools,
      prompt,
    ],
    {
      cwd: ROOT,
      stdout: "pipe",
      stderr: "pipe",
    },
  );
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    process.kill();
  }, maximumDurationMs);
  try {
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ]);
    invariant(!timedOut, `Live tutor exceeded ${maximumDurationMs}ms`);
    invariant(
      Buffer.byteLength(stdout) <= maximumOutputBytes,
      `Live tutor output exceeded ${maximumOutputBytes} bytes`,
    );
    invariant(exitCode === 0, `Pi exited with code ${exitCode}: ${stderr}`);
    return { stdout, stderr };
  } finally {
    clearTimeout(timeout);
  }
}

function inspectExecution(stdout, fixture, journalPath) {
  const events = stdout
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line, index) => parseEvent(line, index));
  const executions = events.filter(
    (event) => event.type === "tool_execution_end",
  );
  const expectedTools = [
    "swing_candidates",
    "swing_snapshot",
    "swing_plan",
    "swing_candidates",
    "swing_snapshot",
    "swing_review",
    "swing_candidates",
    "swing_snapshot",
    "swing_review",
    "swing_review",
    "swing_review",
    "swing_snapshot",
    "journal_entry",
  ];
  invariant(
    JSON.stringify(executions.map((event) => event.toolName)) ===
      JSON.stringify(expectedTools),
    `Expected tool order ${expectedTools.join(", ")}`,
  );
  for (const execution of executions) {
    invariant(
      execution.result?.isError !== true,
      `${execution.toolName} failed: ${JSON.stringify(execution.result?.content ?? [])}`,
    );
  }

  const candidate = executions[0].result.details;
  const firstSnapshot = executions[1].result.details;
  const snapshot = executions[11].result.details;
  const journal = executions[12].result.details;
  invariant(
    candidate.workflowId === fixture.workflowId,
    "Candidate workflow changed",
  );
  invariant(candidate.track === "us", "Candidate track changed");
  invariant(firstSnapshot.revision === 1, "Initial snapshot revision changed");
  invariant(
    snapshot.decisionOwner === "llm",
    "Snapshot changed decision owner",
  );
  invariant(
    Array.isArray(snapshot.pluginDecisionFields) &&
      snapshot.pluginDecisionFields.length === 0,
    "Snapshot exposed plugin decision fields",
  );
  invariant(journal.outcome === "stored", "LLM declaration was not stored");
  invariant(snapshot.revision === 8, "Multi-stage workbench revision changed");
  invariant(snapshot.workflows.length === 1, "Expected one live workflow");
  const workflow = snapshot.workflows[0];
  invariant(workflow.snapshots.length === 3, "Expected three candidate stages");
  invariant(workflow.reviewRecords.length === 4, "Expected four stage records");
  const selectedPlan = selectedChoice(
    fixture.planChoices,
    workflow.plan.planPayload,
    "plan",
  );
  invariant(
    workflow.plan.planReceiptHash === selectedPlan.payloadHash,
    "Selected plan hash changed",
  );
  invariant(
    workflow.plan.origin === "llm_authored",
    "Plan is not LLM-authored",
  );
  const stageSelections = { plan: selectedPlan.selectedOperation };
  for (const [index, stage] of [
    "preflight",
    "monitor",
    "replay",
    "review",
  ].entries()) {
    const record = workflow.reviewRecords[index];
    const expectedStage = fixture.reviewStages[stage];
    invariant(
      record.recordId === expectedStage.inputTemplate.recordId,
      `${stage} record changed`,
    );
    invariant(
      record.planReceiptReference === selectedPlan.payloadHash,
      `${stage} record lost the selected plan reference`,
    );
    const selected = selectedChoice(
      expectedStage.choices,
      record.payload,
      stage,
    );
    invariant(
      record.payloadHash === selected.payloadHash,
      `${stage} hash changed`,
    );
    stageSelections[stage] = selected.selectedOperation;
  }
  const expectedReceiptHashes = receiptNames.map(
    (name) => fixture.receiptCatalog[name].canonicalContentHash,
  );
  const attachedReceiptHashes = workflow.snapshots.flatMap((stage) =>
    stage.facts.flatMap((fact) => fact.receiptReferences),
  );
  for (const receiptHash of expectedReceiptHashes) {
    invariant(
      attachedReceiptHashes.includes(receiptHash),
      `Copied receipt ${receiptHash} was not retained by the workbench`,
    );
  }

  const finalText = events
    .filter(
      (event) =>
        event.type === "message_end" && event.message?.role === "assistant",
    )
    .flatMap((event) => event.message.content ?? [])
    .filter((content) => content.type === "text")
    .at(-1)?.text;
  invariant(finalText, "Tutor produced no final declaration");
  const parsedFinal = parseAssistantDeclaration(finalText);
  const declaration = parsedFinal.value;
  invariant(declaration.decisionOwner === "llm", "Tutor did not own decision");
  for (const stage of ["plan", "preflight", "monitor", "replay", "review"]) {
    invariant(
      declaration[`${stage}Operation`] === stageSelections[stage],
      `Journal declaration differs from the ${stage} selection`,
    );
  }
  invariant(
    typeof declaration.basis === "string" && declaration.basis.length > 0,
    "Tutor did not state the information basis for its operation",
  );

  const envelope = JSON.parse(readFileSync(journalPath, "utf8").trim());
  const stored = JSON.parse(envelope.payload.event_payload);
  invariant(
    JSON.stringify(stored) === JSON.stringify(declaration),
    "Final declaration differs from the LLM-authored journal payload",
  );
  invariant(
    envelope.payload.attribution.kind === "llm_declared",
    "Journal attribution is not LLM-declared",
  );

  const modelMessage = events.find(
    (event) =>
      event.type === "message_end" && event.message?.role === "assistant",
  )?.message;
  return {
    model: modelMessage
      ? `${modelMessage.provider}/${modelMessage.model}`
      : "configured-default",
    toolCalls: expectedTools,
    stageSelections,
    declaration,
    snapshot,
    finalResponseWasJsonOnly: parsedFinal.jsonOnly,
    receiptSchemas: Object.fromEntries(
      receiptNames.map((name) => [name, fixture.receiptCatalog[name].schema]),
    ),
    pluginDecisionFields: snapshot.pluginDecisionFields,
    journalAttribution: envelope.payload.attribution.kind,
  };
}

function inspectResume(stdout, fixture, expectedSnapshot) {
  const events = stdout
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line, index) => parseEvent(line, index));
  const executions = events.filter(
    (event) => event.type === "tool_execution_end",
  );
  invariant(
    executions.length === 1,
    "Resume process made unexpected tool calls",
  );
  invariant(
    executions[0].toolName === "swing_snapshot",
    "Resume process did not inspect the swing snapshot",
  );
  invariant(
    executions[0].result?.isError !== true,
    "Resumed swing snapshot returned an error",
  );
  const snapshot = executions[0].result.details;
  invariant(
    JSON.stringify(snapshot) === JSON.stringify(expectedSnapshot),
    "Second Pi process did not restore the exact workbench snapshot",
  );
  invariant(
    snapshot.pluginDecisionFields.length === 0,
    "Resumed snapshot exposed plugin decision fields",
  );
  const finalText = events
    .filter(
      (event) =>
        event.type === "message_end" && event.message?.role === "assistant",
    )
    .flatMap((event) => event.message.content ?? [])
    .filter((content) => content.type === "text")
    .at(-1)?.text;
  invariant(finalText, "Resume process produced no final declaration");
  const declaration = parseAssistantDeclaration(finalText).value;
  invariant(declaration.decisionOwner === "llm", "Resume owner changed");
  invariant(
    declaration.workflowId === fixture.workflowId,
    "Resume workflow changed",
  );
  invariant(
    declaration.resumedRevision === snapshot.revision,
    "Tutor did not report the restored revision",
  );
  const modelMessage = events.find(
    (event) =>
      event.type === "message_end" && event.message?.role === "assistant",
  )?.message;
  return {
    model: modelMessage
      ? `${modelMessage.provider}/${modelMessage.model}`
      : "configured-default",
    toolCalls: ["swing_snapshot"],
    snapshot,
  };
}

function inspectPersistedSession(directory, sessionId) {
  const files = readdirSync(directory).filter((name) =>
    name.endsWith(".jsonl"),
  );
  invariant(files.length === 1, "Expected one persisted Pi session file");
  const entries = readFileSync(join(directory, files[0]), "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  invariant(entries[0]?.type === "session", "Pi session header is missing");
  invariant(entries[0].id === sessionId, "Persisted Pi session ID changed");
  const custom = entries.filter(
    (entry) =>
      entry.type === "custom" &&
      entry.customType === "pi_sparkles_swing_workbench.event.v1",
  );
  invariant(custom.length === 8, "Persisted workbench event count changed");
  invariant(
    JSON.stringify(custom.map((entry) => JSON.parse(entry.data).revision)) ===
      JSON.stringify([1, 2, 3, 4, 5, 6, 7, 8]),
    "Persisted workbench revisions are not contiguous",
  );
  return { customEntries: custom.length };
}

function parseEvent(line, index) {
  try {
    return JSON.parse(line);
  } catch (error) {
    throw new Error(
      `Pi JSON event line ${index + 1} was malformed: ${line.slice(0, 200)}; ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function parseAssistantDeclaration(text) {
  const trimmed = text.trim();
  try {
    return { value: JSON.parse(trimmed), jsonOnly: true };
  } catch (_) {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    invariant(
      start >= 0 && end > start,
      "Tutor final response contained no JSON object",
    );
    try {
      return {
        value: JSON.parse(trimmed.slice(start, end + 1)),
        jsonOnly: false,
      };
    } catch (error) {
      throw new Error(
        `Tutor final JSON object was malformed: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}

function selectedChoice(choices, payload, stage) {
  const selected = choices.find((choice) => choice.payload === payload);
  invariant(selected, `Tutor supplied an unknown ${stage} payload`);
  const decoded = JSON.parse(payload);
  invariant(decoded.decisionOwner === "llm", `${stage} payload owner changed`);
  invariant(decoded.stage === stage, `${stage} payload stage changed`);
  invariant(
    decoded.selectedOperation === selected.selectedOperation,
    `${stage} operation changed`,
  );
  return selected;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}
