import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { loadReceiptFixture } from "./receipt-fixture.js";

const copiedReceiptFixture = await loadReceiptFixture();

const swingArtifact = resolve(
  import.meta.dir,
  "../../dist/swing_workbench/index.js",
);
const journalArtifact = resolve(
  import.meta.dir,
  "../../dist/trade_journal/index.js",
);
const swingEventType = "pi_sparkles_swing_workbench.event.v1";
const marketToolByTrack = {
  cn: "cn_stock_ohlcv",
  hk: "hk_stock_ohlcv",
  us: "us_stock_ohlcv",
};

const tracks = [
  {
    track: "cn",
    symbol: "600000",
    mic: "XSHG",
    instrumentId: "fixture:cn:600000",
    timezone: "Asia/Shanghai",
    exceptionState: "unknown",
    exceptionDetail: "reported quantity semantics unavailable",
    receipts: copiedReceiptFixture.tracks.cn,
  },
  {
    track: "hk",
    symbol: "00700",
    mic: "XHKG",
    instrumentId: "fixture:hk:00700",
    timezone: "Asia/Hong_Kong",
    exceptionState: "unsupported",
    exceptionDetail:
      "daily row does not establish half-day intraday completeness",
    receipts: copiedReceiptFixture.tracks.hk,
  },
  {
    track: "us",
    symbol: "AAPL",
    mic: "XNAS",
    instrumentId: "fixture:us:AAPL",
    timezone: "America/New_York",
    exceptionState: "not_obtained",
    exceptionDetail: "realtime entitlement not obtained",
    receipts: copiedReceiptFixture.tracks.us,
  },
];

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function strategyReceipt(spec) {
  const definitionHash = sha256("fixture-swing-definition-v1");
  const context = {
    listing: {
      track: spec.track,
      instrument_id: spec.instrumentId,
      symbol: spec.symbol,
      mic: spec.mic,
    },
    signal_session: { year: 2026, month: 8, day: 7 },
    evaluated_at_unix_ms: "1000",
    source_cutoff_unix_ms: "900",
    dependencies: [],
    evidence_roots: [],
  };
  const inputHash = sha256(
    JSON.stringify({ definition_hash: definitionHash, context, features: [] }),
  );
  return JSON.stringify({
    schema: "finance_strategy_evidence",
    schema_version: 1,
    definition_id: "fixture_completed_daily_swing",
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
}

function swingEntry(id, data, customType = swingEventType) {
  return {
    type: "custom",
    id,
    parentId: null,
    timestamp: "2026-08-07T00:00:00.000Z",
    customType,
    data,
  };
}

function swingContext(branch) {
  return {
    mode: "tui",
    hasUI: true,
    sessionManager: { getBranch: () => branch },
    ui: { notify() {} },
  };
}

async function swingHarness(entries = []) {
  const commands = new Map();
  const handlers = new Map();
  const tools = new Map();
  let nextId = entries.length;
  const api = {
    registerCommand(name, definition) {
      commands.set(name, definition);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    on(name, handler) {
      handlers.set(name, handler);
    },
    appendEntry(customType, data) {
      nextId += 1;
      entries.push(swingEntry(`acceptance-${nextId}`, data, customType));
    },
  };
  const module = await import(
    `${swingArtifact}?acceptance-swing=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { commands, entries, handlers, tools };
}

async function journalHarness() {
  const tools = new Map();
  const api = {
    registerCommand() {},
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${journalArtifact}?acceptance-journal=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { tools };
}

async function execute(tool, input, callId) {
  return tool.execute(callId, input, new AbortController().signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

function evidence(spec) {
  return {
    market: spec.receipts.market.canonicalContentHash,
    indicator: spec.receipts.indicator.canonicalContentHash,
    risk: spec.receipts.risk.canonicalContentHash,
    rule: spec.receipts.rule.canonicalContentHash,
    execution: spec.receipts.execution.canonicalContentHash,
    trackException: spec.receipts.market.canonicalContentHash,
  };
}

function candidateInput(spec, stage, strategyPayload, receipts) {
  const workflowId = `workflow-${spec.track}-${spec.symbol}`;
  const common = {
    workflowId,
    strategyReceiptHash: sha256(strategyPayload),
    strategyReceiptPayload: strategyPayload,
  };
  if (stage === "after_close") {
    return {
      ...common,
      attachedAtUnixMs: 1000,
      facts: [
        fact(
          "market.completed_daily",
          "required",
          "known",
          "caller-supplied completed daily observation",
          [receipts.market],
        ),
        fact(
          "calculation.requested_feature",
          "required",
          "known",
          "caller-requested indicator calculation receipt",
          [receipts.indicator],
        ),
        fact(
          "risk.requested_projection",
          "required",
          "not_obtained",
          "risk calculation not obtained at after-close inspection",
          [],
        ),
      ],
    };
  }
  if (stage === "preflight") {
    return {
      ...common,
      attachedAtUnixMs: 1200,
      facts: [
        fact(
          "market.completed_daily",
          "required",
          "known",
          "same source observation at preflight",
          [receipts.market],
        ),
        fact(
          "execution.branch_population",
          "required",
          "unknown",
          "daily bar ordering branches not yet observed",
          [receipts.execution],
        ),
        trackException(spec, receipts),
      ],
    };
  }
  return {
    ...common,
    attachedAtUnixMs: 1400,
    facts: [
      fact(
        "market.completed_daily",
        "required",
        "known",
        "same source observation during monitoring",
        [receipts.market],
      ),
      fact(
        "execution.branch_population",
        "required",
        "conflicting",
        "all compatible stop-first, target-first, and unknown-ordering alternatives retained in the exact execution receipt",
        [receipts.execution],
      ),
      trackException(spec, receipts),
      fact(
        "journal.prior_review",
        "context",
        "not_obtained",
        "no prior review supplied for this fixture",
        [],
      ),
    ],
  };
}

function fact(factId, role, state, detail, receiptReferences) {
  return { factId, role, state, detail, receiptReferences };
}

function trackException(spec, receipts) {
  return fact(
    "track.exception",
    "required",
    spec.exceptionState,
    spec.exceptionDetail,
    [receipts.trackException],
  );
}

function journalEntry({
  spec,
  path,
  workflowId,
  expectedRevision,
  suffix,
  eventKind,
  attributionKind,
  stage,
  payload,
  occurrenceTimeUnixMs,
  references,
}) {
  return {
    journalPath: path,
    expectedRevision,
    maximumJournalBytes: 1_000_000,
    journalId: `journal-${spec.track}-${spec.symbol}`,
    eventId: `journal-event-${spec.track}-${spec.symbol}-${suffix}`,
    eventKind,
    identityScope: "exact_listing",
    track: spec.track,
    listingId: spec.instrumentId,
    mic: spec.mic,
    symbol: spec.symbol,
    workflowId,
    attributionKind,
    authorOrSourceId:
      attributionKind === "llm_declared" ? "fixture-llm" : "fixture-user",
    stage,
    payload,
    occurrenceTimeUnixMs,
    recordingTimeUnixMs: occurrenceTimeUnixMs + 1,
    timezone: spec.timezone,
    privacy: "private",
    references,
    idempotencyKey: `journal-key-${spec.track}-${spec.symbol}-${suffix}`,
  };
}

async function runJourney(spec) {
  const instance = await swingHarness();
  await instance.handlers.get("session_start")(
    { type: "session_start", reason: "startup" },
    swingContext(instance.entries),
  );
  const strategyPayload = strategyReceipt(spec);
  const receipts = evidence(spec);
  const workflowId = `workflow-${spec.track}-${spec.symbol}`;

  await execute(
    instance.tools.get("swing_candidates"),
    candidateInput(spec, "after_close", strategyPayload, receipts),
    `${workflowId}:after-close`,
  );

  const planPayload = JSON.stringify({
    author: "llm",
    declaration: `next-session plan for ${spec.track}`,
  });
  const planHash = sha256(planPayload);
  await execute(
    instance.tools.get("swing_plan"),
    {
      workflowId,
      sourceStrategyReceiptHash: sha256(strategyPayload),
      planReceiptHash: planHash,
      planPayload,
      origin: "llm_authored",
      riskReceiptReferences: [receipts.risk],
      ruleReceiptReferences: [receipts.rule],
      executionReceiptReferences: [receipts.execution],
      createdAtUnixMs: 1100,
    },
    `${workflowId}:plan`,
  );

  await execute(
    instance.tools.get("swing_candidates"),
    candidateInput(spec, "preflight", strategyPayload, receipts),
    `${workflowId}:preflight`,
  );
  await execute(
    instance.tools.get("swing_candidates"),
    candidateInput(spec, "monitor", strategyPayload, receipts),
    `${workflowId}:monitor`,
  );

  const replayStateHash = sha256(
    instance.entries.map((entry) => entry.data).join("\n"),
  );
  const reviewPayload = JSON.stringify({
    author: "llm",
    observation:
      "stop-first and target-first alternatives plus track exception retained",
  });
  await execute(
    instance.tools.get("swing_review"),
    {
      workflowId,
      recordId: `review-${spec.track}-${spec.symbol}`,
      recordKind: "planned_vs_observed_information",
      payloadHash: sha256(reviewPayload),
      payload: reviewPayload,
      planReceiptReference: planHash,
      evidenceReferences: [replayStateHash],
      observedAtUnixMs: 1600,
    },
    `${workflowId}:review`,
  );
  const snapshot = await execute(
    instance.tools.get("swing_snapshot"),
    { workflowId },
    `${workflowId}:snapshot`,
  );
  return {
    instance,
    planHash,
    planPayload,
    receipts,
    replayStateHash,
    reviewPayload,
    snapshot,
    strategyPayload,
    workflowId,
  };
}

async function persistJournal(spec, journey, path) {
  const instance = await journalHarness();
  const events = [
    journalEntry({
      spec,
      path,
      workflowId: journey.workflowId,
      expectedRevision: 0,
      suffix: "after-close",
      eventKind: "observation_reference",
      attributionKind: "user_declared",
      stage: "after_close",
      payload: "after-close observations inspected",
      occurrenceTimeUnixMs: 1000,
      references: [
        { kind: "strategy", hash: sha256(journey.strategyPayload) },
        { kind: "market", hash: journey.receipts.market },
      ],
    }),
    journalEntry({
      spec,
      path,
      workflowId: journey.workflowId,
      expectedRevision: 1,
      suffix: "plan",
      eventKind: "declaration",
      attributionKind: "llm_declared",
      stage: "plan",
      payload: journey.planPayload,
      occurrenceTimeUnixMs: 1100,
      references: [{ kind: "plan", hash: journey.planHash }],
    }),
    journalEntry({
      spec,
      path,
      workflowId: journey.workflowId,
      expectedRevision: 2,
      suffix: "review",
      eventKind: "review_conclusion",
      attributionKind: "llm_declared",
      stage: "review",
      payload: journey.reviewPayload,
      occurrenceTimeUnixMs: 1600,
      references: [
        { kind: "plan", hash: journey.planHash },
        { kind: "replay_state", hash: journey.replayStateHash },
      ],
    }),
  ];
  for (const [index, input] of events.entries()) {
    const result = await execute(
      instance.tools.get("journal_entry"),
      input,
      `${journey.workflowId}:journal:${index}`,
    );
    expect(result.details.outcome).toBe("stored");
    expect(result.details.revision).toBe(index + 1);
  }
}

describe("automated LLM-owned swing acceptance lane", () => {
  for (const spec of tracks) {
    test(`${spec.track} executes the declared tool journey and resumes exact state`, async () => {
      const directory = mkdtempSync(
        join(tmpdir(), `pi-swing-acceptance-${spec.track}-`),
      );
      const path = join(directory, "journal.jsonl");
      try {
        const journey = await runJourney(spec);
        expect(journey.instance.entries).toHaveLength(5);
        expect(
          journey.instance.entries.map(({ data }) => JSON.parse(data).revision),
        ).toEqual([1, 2, 3, 4, 5]);
        expect(journey.snapshot.details).toMatchObject({
          revision: 5,
          decisionOwner: "llm",
          pluginDecisionFields: [],
        });
        const workflow = journey.snapshot.details.workflows[0];
        expect(workflow.track).toBe(spec.track);
        expect(spec.receipts.market).toMatchObject({
          sourceTool: marketToolByTrack[spec.track],
          integrity: "bundled_tool_gap_projection_sha256",
        });
        const bundledMarketResult = JSON.parse(
          spec.receipts.market.sourceResultPayload,
        );
        expect(bundledMarketResult.track).toBe(spec.track);
        expect(bundledMarketResult.bars).toHaveLength(5);
        expect(bundledMarketResult.gapAssessmentReceipt).toEqual(
          JSON.parse(spec.receipts.market.payload),
        );
        expect(
          bundledMarketResult.gapAssessmentReceipt.integrity
            .providerAuthenticated,
        ).toBe(false);
        expect(workflow.listingKey).toBe(
          `${spec.track}|${spec.mic}|${spec.symbol}|${spec.instrumentId}`,
        );
        expect(workflow.snapshots).toHaveLength(3);
        expect(workflow.plan).toMatchObject({
          riskReceiptReferences: [journey.receipts.risk],
          ruleReceiptReferences: [journey.receipts.rule],
          executionReceiptReferences: [journey.receipts.execution],
        });
        expect(workflow.snapshots[2].facts[1]).toMatchObject({
          factId: "execution.branch_population",
          state: "conflicting",
          receiptReferences: [journey.receipts.execution],
        });
        expect(spec.receipts.execution.schema).toBe(
          "finance_execution/semantic_result_receipt",
        );
        expect(
          JSON.parse(spec.receipts.execution.payload).payload,
        ).toMatchObject({
          schema: "pi-sparkles/execution-information-receipt",
          desired_instruction: { track: spec.track },
        });
        expect(
          JSON.parse(spec.receipts.execution.payload).payload.branches[0].value
            .branches,
        ).toHaveLength(3);
        expect(workflow.snapshots[2].facts[2]).toMatchObject({
          factId: "track.exception",
          state: spec.exceptionState,
          detail: spec.exceptionDetail,
        });

        const restarted = await swingHarness([...journey.instance.entries]);
        await restarted.handlers.get("session_start")(
          { type: "session_start", reason: "resume" },
          swingContext(restarted.entries),
        );
        const resumed = await execute(
          restarted.tools.get("swing_snapshot"),
          { workflowId: journey.workflowId },
          `${journey.workflowId}:resumed-snapshot`,
        );
        expect(resumed.details).toEqual(journey.snapshot.details);

        await persistJournal(spec, journey, path);
        const persisted = readFileSync(path, "utf8");
        expect(persisted.split("\n").filter(Boolean)).toHaveLength(3);
        const restartedJournal = await journalHarness();
        const context = await execute(
          restartedJournal.tools.get("journal_context"),
          {
            journalPath: path,
            journalId: `journal-${spec.track}-${spec.symbol}`,
            includeSuperseded: true,
            maximumJournalBytes: 1_000_000,
          },
          `${journey.workflowId}:journal-context`,
        );
        expect(context.details.payload).toMatchObject({
          decision_owner: "llm",
          event_count: 3,
          omitted_counts: { private_payloads: 3 },
        });

        const eventTimes = [
          workflow.snapshots[0].attachedAtUnixMs,
          workflow.plan.createdAtUnixMs,
          workflow.snapshots[1].attachedAtUnixMs,
          workflow.snapshots[2].attachedAtUnixMs,
          workflow.reviewRecords[0].observedAtUnixMs,
        ];
        expect(eventTimes).toEqual([1000, 1100, 1200, 1400, 1600]);
        expect(
          eventTimes.slice(1).map((time, index) => time - eventTimes[index]),
        ).toEqual([100, 100, 200, 200]);

        const encoded = JSON.stringify({
          swing: journey.snapshot.details,
          journal: context.details,
        });
        for (const forbidden of [
          '"accepted"',
          '"qualified"',
          '"correctness"',
          '"sufficiency"',
          '"nextAction"',
          '"edge"',
          '"robust"',
        ]) {
          expect(encoded).not.toContain(forbidden);
        }
      } finally {
        rmSync(directory, { recursive: true, force: true });
      }
    });
  }
});
