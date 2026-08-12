import { afterEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

let directory;
const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const marker = (value) => value.repeat(64);

afterEach(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
  directory = undefined;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerCommand() {},
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    on() {},
  };
  const artifact = resolve(import.meta.dir, "../../dist/finance_alerts/index.js");
  const module = await import(`${artifact}?alerts=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return tools;
}

async function execute(tool, input, id = "alerts") {
  return tool.execute(
    id,
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

async function packet(name, value) {
  const text = JSON.stringify(value);
  const path = join(directory, name);
  await writeFile(path, text, "utf8");
  return { path, text, hash: sha256(text) };
}

function eventInput(journalPath, extra = {}) {
  return {
    journalPath,
    maximumJournalBytes: 1_000_000,
    expectedRevision: 0,
    eventId: "definition-1",
    idempotencyKey: "define-monitor-v1",
    occurredAtUnixMilliseconds: 1_000,
    privacy: "review_visible",
    ...extra,
  };
}

describe("durable finance alerts boundary", () => {
  test("defines, evaluates, notifies, and resumes from a fresh instance", async () => {
    directory = await mkdtemp(join(tmpdir(), "pi-sparkles-alerts-"));
    const journalPath = join(directory, "alerts.jsonl");
    const definition = await packet("definition.json", {
      schemaVersion: 1,
      contractId: "finance_alerts_definition_v1",
      monitorId: "portfolio-monitor",
      version: 1,
      ownerKind: "user",
      ownerId: "manager-1",
      scope: {
        kind: "portfolio",
        track: "us",
        listingIds: [],
        mic: "XNAS",
        sourceScope: ["portfolio_risk"],
        eventKinds: ["PortfolioRiskFact"],
        portfolioReceipt: marker("a"),
      },
      predicate: {
        kind: "caller_supplied",
        field: "risk_state",
        operator: "exact_equals",
        value: "review_required",
      },
      temporal: {
        freshnessCutoffSeconds: 3600,
        startAtUnixMilliseconds: 1_000,
        endAtUnixMilliseconds: null,
      },
      dedupe: {
        kind: "by_content_hash",
        windowSeconds: 86400,
        cooldownSeconds: 0,
        scope: "per_monitor",
      },
      budgets: {
        maxEventsPerBatch: 100,
        maxMatchesPerBatch: 10,
        maxConsecutiveFailures: 5,
      },
      notificationAuthorization: {
        authorized: true,
        authorizationId: "auth-1",
        channel: "scripted_local",
        destinationRef: "opaque-manager-inbox",
        maximumAttempts: 2,
      },
      retentionPolicy: "caller_owned_append_only",
      parentEventId: null,
      sourceEntitlementReceipts: [marker("b")],
    });
    const tools = await harness();
    const defined = await execute(
      tools.get("alert_define"),
      eventInput(journalPath, {
        packetPath: definition.path,
        expectedSha256: definition.hash,
        maximumPacketBytes: 1_000_000,
      }),
      "define",
    );
    expect(defined.content[0].text).toContain("journalRevision=1");

    const batch = await packet("batch.json", {
      schemaVersion: 1,
      contractId: "finance_alerts_batch_v1",
      batchId: "batch-1",
      monitorId: "portfolio-monitor",
      evaluatedAtUnixMilliseconds: 2_000,
      observations: [{
        observationId: "risk-1",
        eventIdentity: "portfolio-risk-receipt-1",
        contentHash: marker("c"),
        observedAtUnixMilliseconds: 1_900,
        knowledgeAtUnixMilliseconds: 1_900,
        corrects: null,
        fields: [{ name: "risk_state", state: "known", value: "review_required" }],
      }],
      sourceReceipts: [marker("d")],
    });
    const evaluated = await execute(
      tools.get("alert_evaluate"),
      eventInput(journalPath, {
        expectedRevision: 1,
        eventId: "evaluation-1",
        idempotencyKey: "evaluate-batch-1",
        occurredAtUnixMilliseconds: 2_000,
        packetPath: batch.path,
        expectedSha256: batch.hash,
        maximumPacketBytes: 1_000_000,
      }),
      "evaluate",
    );
    expect(evaluated.details.matchCount).toBe(1);
    const matchId = evaluated.details.results[0].matchId;

    const notifyInput = {
      ...eventInput(journalPath, {
        expectedRevision: 2,
        eventId: "notification-1",
        idempotencyKey: "notify-match-1-attempt-1",
        occurredAtUnixMilliseconds: 2_100,
      }),
      monitorId: "portfolio-monitor",
      matchId,
      authorizationId: "auth-1",
      channel: "scripted_local",
      destinationRef: "opaque-manager-inbox",
      attempt: 1,
      scriptedOutcome: "delivered",
    };
    const notified = await execute(tools.get("alert_notify"), notifyInput);
    expect(notified.details).toMatchObject({
      matchId,
      status: "delivered",
      destinationPrivacy: "opaque_reference_only",
    });
    const retried = await execute(tools.get("alert_notify"), notifyInput);
    expect(retried.details).toMatchObject({
      matchId,
      effectRepeated: false,
      journalRevision: 3,
    });
    await expect(
      execute(tools.get("alert_notify"), {
        ...notifyInput,
        matchId: "changed-match",
      }),
    ).rejects.toThrow("idempotency conflict");

    const resumed = await harness();
    const inspected = await execute(resumed.get("alert_inspect"), {
      journalPath,
      maximumJournalBytes: 1_000_000,
      monitorId: "portfolio-monitor",
      includePrivate: false,
      maximumEvents: 20,
    });
    expect(inspected.details.monitor).toMatchObject({
      journalRevision: 3,
      monitorId: "portfolio-monitor",
      disabled: false,
      returnedEventCount: 3,
    });
  });

  test("rejects notification before any effect when authorization differs", async () => {
    directory = await mkdtemp(join(tmpdir(), "pi-sparkles-alerts-"));
    const tools = await harness();
    await expect(
      execute(tools.get("alert_notify"), {
        ...eventInput(join(directory, "missing.jsonl")),
        monitorId: "missing",
        matchId: "missing",
        authorizationId: "wrong",
        channel: "scripted_local",
        destinationRef: "opaque",
        attempt: 1,
        scriptedOutcome: "delivered",
      }),
    ).rejects.toThrow("not found");
  });
});
