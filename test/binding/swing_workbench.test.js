import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/swing_workbench/index.js",
);
const eventType = "pi_sparkles_swing_workbench.event.v1";

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function strategyReceipt() {
  const definitionHash = "1".repeat(64);
  const context = {
    listing: {
      track: "us",
      instrument_id: "figi:BBG000B9XRY4",
      symbol: "AAPL",
      mic: "XNAS",
    },
    signal_session: { year: 2026, month: 8, day: 6 },
    evaluated_at_unix_ms: "300",
    source_cutoff_unix_ms: "200",
    dependencies: [],
    evidence_roots: [],
  };
  const inputHash = sha256(
    JSON.stringify({
      definition_hash: definitionHash,
      context,
      features: [],
    }),
  );
  return JSON.stringify({
    schema: "finance_strategy_evidence",
    schema_version: 1,
    definition_id: "fixture_swing",
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

function entry(id, data, customType = eventType) {
  return {
    type: "custom",
    id,
    parentId: null,
    timestamp: "2026-08-07T00:00:00.000Z",
    customType,
    data,
  };
}

function context(branch, notifications = []) {
  return {
    mode: "tui",
    hasUI: true,
    sessionManager: {
      getBranch: () => branch,
    },
    ui: {
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

async function harness(entries = []) {
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
      entries.push(entry(`swing-${nextId}`, data, customType));
    },
  };
  const module = await import(`${artifact}?swing=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return { commands, entries, handlers, tools };
}

async function execute(tool, input) {
  return tool.execute(
    "swing-call",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function candidateInput() {
  const payload = strategyReceipt();
  return {
    workflowId: "wf-aapl",
    strategyReceiptHash: sha256(payload),
    strategyReceiptPayload: payload,
    facts: [
      {
        factId: "risk_information",
        role: "required",
        state: "unknown",
        detail: "No risk receipt supplied",
        receiptReferences: [],
      },
      {
        factId: "execution_information",
        role: "required",
        state: "unsupported",
        detail: "No broker mapping supplied",
        receiptReferences: [],
      },
    ],
    attachedAtUnixMs: 300,
  };
}

describe("LLM-owned swing workbench boundary", () => {
  test("retains exact facts and opaque declarations without deciding", async () => {
    const instance = await harness();
    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      context(instance.entries),
    );

    const candidate = candidateInput();
    const attached = await execute(
      instance.tools.get("swing_candidates"),
      candidate,
    );
    expect(attached.details.workflowId).toBe("wf-aapl");
    expect(attached.details.track).toBe("us");
    expect(attached.details.listingKey).toContain("figi:BBG000B9XRY4");
    expect(attached.details.snapshots[0].strategyReceiptPayload).toBe(
      candidate.strategyReceiptPayload,
    );
    expect(attached.details.snapshots[0].facts).toEqual([
      {
        factId: "risk_information",
        role: "required",
        state: "unknown",
        detail: "No risk receipt supplied",
        receiptReferences: [],
      },
      {
        factId: "execution_information",
        role: "required",
        state: "unsupported",
        detail: "No broker mapping supplied",
        receiptReferences: [],
      },
    ]);

    const planPayload = JSON.stringify({ instruction: "LLM declaration" });
    const planHash = sha256(planPayload);
    const riskHash = sha256("risk receipt");
    const ruleHash = sha256("rule receipt");
    const executionHash = sha256("execution receipt");
    const planned = await execute(instance.tools.get("swing_plan"), {
      workflowId: "wf-aapl",
      sourceStrategyReceiptHash: candidate.strategyReceiptHash,
      planReceiptHash: planHash,
      planPayload,
      origin: "llm_authored",
      riskReceiptReferences: [riskHash],
      ruleReceiptReferences: [ruleHash],
      executionReceiptReferences: [executionHash],
      createdAtUnixMs: 310,
    });
    expect(planned.details.plan).toMatchObject({
      planReceiptHash: planHash,
      planPayload,
      origin: "llm_authored",
      riskReceiptReferences: [riskHash],
      ruleReceiptReferences: [ruleHash],
      executionReceiptReferences: [executionHash],
    });

    const reviewPayload = JSON.stringify({ observation: "price crossed level" });
    const reviewed = await execute(instance.tools.get("swing_review"), {
      workflowId: "wf-aapl",
      recordId: "observation-1",
      recordKind: "market_observation",
      payloadHash: sha256(reviewPayload),
      payload: reviewPayload,
      planReceiptReference: planHash,
      evidenceReferences: [executionHash],
      observedAtUnixMs: 320,
    });
    expect(reviewed.details.reviewRecords[0]).toMatchObject({
      recordId: "observation-1",
      recordKind: "market_observation",
      payload: reviewPayload,
      planReceiptReference: planHash,
      evidenceReferences: [executionHash],
    });

    const snapshot = await execute(
      instance.tools.get("swing_snapshot"),
      {},
    );
    expect(snapshot.details).toMatchObject({
      revision: 3,
      persistence: "session_branch_versioned_event_log",
      crossSessionPersistence: "not_provided",
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(snapshot.details.availableOperations).toContain("inspect_fact");
    expect(snapshot.details.workflows).toHaveLength(1);
    for (const forbidden of [
      "qualified",
      "accepted",
      "recommended",
      "selectedOperation",
      "nextAction",
      "verdict",
    ]) {
      expect(JSON.stringify(snapshot.details)).not.toContain(`\"${forbidden}\"`);
    }
    expect(instance.entries).toHaveLength(3);
    expect(instance.entries.map(({ data }) => JSON.parse(data).revision)).toEqual([
      1,
      2,
      3,
    ]);
  });

  test("replays only the active branch across resume and tree changes", async () => {
    const original = await harness();
    await original.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      context(original.entries),
    );
    const candidate = candidateInput();
    await execute(original.tools.get("swing_candidates"), candidate);
    const reviewPayload = "observed";
    await execute(original.tools.get("swing_review"), {
      workflowId: "wf-aapl",
      recordId: "observation-1",
      recordKind: "observation",
      payloadHash: sha256(reviewPayload),
      payload: reviewPayload,
      evidenceReferences: [],
      observedAtUnixMs: 320,
    });

    const resumed = await harness([...original.entries]);
    await resumed.handlers.get("session_start")(
      { type: "session_start", reason: "resume" },
      context(resumed.entries),
    );
    let snapshot = await execute(resumed.tools.get("swing_snapshot"), {});
    expect(snapshot.details.revision).toBe(2);
    expect(snapshot.details.workflows[0].reviewRecords).toHaveLength(1);

    const inheritedBranch = [resumed.entries[0]];
    await resumed.handlers.get("session_tree")(
      {
        type: "session_tree",
        newLeafId: "swing-1",
        oldLeafId: "swing-2",
        fromExtension: false,
      },
      context(inheritedBranch),
    );
    snapshot = await execute(resumed.tools.get("swing_snapshot"), {});
    expect(snapshot.details.revision).toBe(1);
    expect(snapshot.details.workflows[0].reviewRecords).toEqual([]);
  });

  test("locks malformed branch history instead of overwriting it", async () => {
    const entries = [entry("swing-bad", "not-json")];
    const instance = await harness(entries);
    const notifications = [];
    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "resume" },
      context(entries, notifications),
    );

    expect(notifications.at(-1).kind).toBe("error");
    expect(notifications.at(-1).message).toContain("mutation is disabled");
    await expect(
      execute(instance.tools.get("swing_candidates"), candidateInput()),
    ).rejects.toThrow("mutation is disabled");
    expect(entries).toHaveLength(1);
  });
});
