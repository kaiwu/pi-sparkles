import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import {
  mkdtempSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/trade_journal/index.js");

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function harness() {
  const commands = new Map();
  const tools = new Map();
  const api = {
    registerCommand(name, definition) {
      commands.set(name, definition);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(`${artifact}?journal=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return { commands, tools };
}

async function execute(tool, input) {
  return tool.execute(
    "journal-call",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function entry(path, overrides = {}) {
  return {
    journalPath: path,
    expectedRevision: 0,
    maximumJournalBytes: 1_000_000,
    journalId: "journal-main",
    eventId: "event-1",
    eventKind: "declaration",
    identityScope: "exact_listing",
    track: "cn",
    listingId: "cn-listing-1",
    mic: "XSHG",
    symbol: "600000",
    workflowId: "workflow-1",
    attributionKind: "user_declared",
    authorOrSourceId: "user-local",
    stage: "pre_plan",
    payload: JSON.stringify({ labels: ["anxious"], note: "private prose" }),
    occurrenceTimeUnixMs: 100,
    recordingTimeUnixMs: 200,
    timezone: "Asia/Shanghai",
    privacy: "private",
    references: [],
    idempotencyKey: "key-1",
    ...overrides,
  };
}

function search(path, includePrivatePayloads) {
  return {
    journalPath: path,
    journalId: "journal-main",
    eventKinds: [],
    attributionKinds: [],
    privacyClassifications: [],
    includeSuperseded: true,
    includePrivatePayloads,
    maximumEvents: 100,
    maximumJournalBytes: 1_000_000,
  };
}

describe("LLM-owned local journal boundary", () => {
  test("stores exact events and makes lost-ack retries idempotent", async () => {
    const directory = mkdtempSync(join(tmpdir(), "pi-journal-binding-"));
    const path = join(directory, "journal.jsonl");
    try {
      const instance = await harness();
      const first = await execute(instance.tools.get("journal_entry"), entry(path));
      expect(first.details.outcome).toBe("stored");
      expect(first.details.revision).toBe(1);
      expect(first.details.decision_owner).toBe("llm");
      expect(first.details.plugin_decision_fields).toEqual([]);
      expect(first.content[0].text).toContain("journal-main");
      expect(first.content[0].text).toContain("workflow-1");
      expect(first.content[0].text).toContain("event-1");
      expect(first.content[0].text).toContain(
        first.details.event.canonical_content_hash,
      );
      expect(first.content[0].text).not.toContain("private prose");
      expect(first.details.storage_capabilities.backend).toBe("local_jsonl_v1");
      expect(first.details.storage_capabilities.encryption_at_rest.state).toBe(
        "not_obtained",
      );
      const persisted = readFileSync(path, "utf8");
      expect(persisted.endsWith("\n")).toBe(true);
      expect(persisted).toContain("private prose");

      const retry = await execute(
        instance.tools.get("journal_entry"),
        entry(path, { eventId: "event-retry" }),
      );
      expect(retry.details.outcome).toBe("already_stored");
      expect(retry.details.revision).toBe(1);
      expect(readFileSync(path, "utf8")).toBe(persisted);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("omits private content unless explicitly requested and returns compact context", async () => {
    const directory = mkdtempSync(join(tmpdir(), "pi-journal-binding-"));
    const path = join(directory, "journal.jsonl");
    try {
      const instance = await harness();
      await execute(instance.tools.get("journal_entry"), entry(path));

      const omitted = await execute(
        instance.tools.get("journal_search"),
        search(path, false),
      );
      expect(omitted.details.events[0]).toMatchObject({
        journal_id: "journal-main",
        event_id: "event-1",
        workflow_id: "workflow-1",
        privacy: "private",
        payload_omitted: true,
      });
      expect(JSON.stringify(omitted.details)).not.toContain("private prose");
      expect(omitted.content[0].text).toContain("journal-main");
      expect(omitted.content[0].text).toContain("workflow-1");
      expect(omitted.content[0].text).toContain("event-1");
      expect(omitted.content[0].text).toContain(
        omitted.details.events[0].canonical_content_hash,
      );
      expect(omitted.content[0].text).not.toContain("private prose");

      const explicit = await execute(
        instance.tools.get("journal_search"),
        search(path, true),
      );
      expect(JSON.stringify(explicit.details)).toContain("private prose");
      expect(explicit.content[0].text).toContain("private prose");

      const context = await execute(instance.tools.get("journal_context"), {
        journalPath: path,
        journalId: "journal-main",
        includeSuperseded: true,
        maximumJournalBytes: 1_000_000,
      });
      expect(context.details.payload.decision_owner).toBe("llm");
      expect(context.details.payload.omitted_counts.private_payloads).toBe(1);
      expect(JSON.stringify(context.details)).not.toContain("private prose");

      const notifications = [];
      await instance.commands.get("journal").handler(path, {
        hasUI: true,
        ui: {
          notify(message, kind) {
            notifications.push({ message, kind });
          },
        },
      });
      expect(notifications[0].message).toContain("payload prose omitted");
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("reports revision conflicts without choosing a resolution", async () => {
    const directory = mkdtempSync(join(tmpdir(), "pi-journal-binding-"));
    const path = join(directory, "journal.jsonl");
    try {
      const instance = await harness();
      await execute(instance.tools.get("journal_entry"), entry(path));
      const persisted = readFileSync(path, "utf8");
      const conflict = await execute(
        instance.tools.get("journal_entry"),
        entry(path, {
          eventId: "event-2",
          idempotencyKey: "key-2",
          payload: "second exact declaration",
          recordingTimeUnixMs: 300,
        }),
      );
      expect(conflict.details).toMatchObject({
        outcome: "conflict",
        reason: "expected_revision_mismatch",
        current_revision: 1,
        decision_owner: "llm",
      });
      expect(conflict.details.available_operations).toEqual([
        "reload_journal",
        "inspect_conflict",
      ]);
      expect(readFileSync(path, "utf8")).toBe(persisted);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });

  test("round-trips canonical JSONL and calculates only requested facts", async () => {
    const directory = mkdtempSync(join(tmpdir(), "pi-journal-binding-"));
    const sourcePath = join(directory, "source.jsonl");
    const targetPath = join(directory, "target.jsonl");
    try {
      const instance = await harness();
      await execute(instance.tools.get("journal_entry"), entry(sourcePath));
      const exported = await execute(instance.tools.get("journal_export"), {
        journalPath: sourcePath,
        journalId: "journal-main",
        includePrivate: true,
        includeReviewVisible: false,
        includeExportable: false,
        includeSuperseded: true,
        maximumEvents: 100,
        maximumJournalBytes: 1_000_000,
      });
      expect(exported.details.event_count).toBe(1);
      expect(exported.details.content_hash).toBe(
        sha256(exported.details.jsonl),
      );
      const imported = await execute(instance.tools.get("journal_import"), {
        journalPath: targetPath,
        expectedRevision: 0,
        jsonl: exported.details.jsonl,
        maximumImportEvents: 100,
        maximumJournalBytes: 1_000_000,
      });
      expect(imported.details.outcomes[0].outcome).toBe("stored");
      expect(readFileSync(targetPath, "utf8")).toBe(exported.details.jsonl);

      const source = sha256("source receipt");
      const metric = await execute(instance.tools.get("journal_stats"), {
        instructionReceipt: sha256("metric instruction"),
        currency: "CNY",
        scale: 2,
        rounding: "half_up",
        fills: [
          {
            fillId: "entry",
            role: "entry",
            quantityLexeme: "100",
            priceLexeme: "10.00",
            sourceReceipt: source,
          },
          {
            fillId: "exit",
            role: "exit",
            quantityLexeme: "100",
            priceLexeme: "11.00",
            sourceReceipt: source,
          },
        ],
        costs: [
          { costId: "commission", amountLexeme: "2.00", sourceReceipt: source },
        ],
      });
      expect(metric.details.payload.components.net_pnl).toBe("98.00");
      expect(metric.details.payload.decision_owner).toBe("llm");
      expect(metric.details.payload.plugin_decision_fields).toEqual([]);

      const comparison = await execute(instance.tools.get("journal_compare"), {
        instructionReceipt: sha256("comparison instruction"),
        planReceipt: sha256("plan"),
        observationReceipts: [sha256("observation")],
        missingPolicy: "preserve",
        conflictPolicy: "preserve_all",
        fields: [
          {
            field: "entry_price",
            planned: { state: "known", value: "10.00" },
            observed: { state: "known", value: "10.25" },
            mode: { kind: "decimal_delta", scale: 2, rounding: "half_up" },
            unit: "CNY/share",
          },
        ],
      });
      expect(comparison.details.payload.comparisons[0].delta.value).toBe("0.25");
      expect(comparison.details.payload.plugin_decision_fields).toEqual([]);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});
