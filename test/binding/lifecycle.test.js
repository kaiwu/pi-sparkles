import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/lifecycle/index.js");

function entry(id, data, customType = "pi_sparkles_lifecycle.counter") {
  return {
    type: "custom",
    id,
    parentId: null,
    timestamp: "2026-08-04T00:00:00.000Z",
    customType,
    data,
  };
}

function context(
  entries,
  notifications = [],
  branchEntries = entries,
  contextEntries = branchEntries,
) {
  const manager = {
    getCwd: () => "/work/project",
    getSessionDir: () => "/sessions",
    getSessionId: () => "session-1",
    getSessionFile: () => "/sessions/current.jsonl",
    getLeafId: () => entries.at(-1)?.id ?? null,
    getEntries: () => entries,
    getBranch: () => branchEntries,
    buildContextEntries: () => contextEntries,
  };
  return {
    cwd: "/work/project",
    mode: "tui",
    hasUI: true,
    sessionManager: manager,
    ui: {
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

async function harness(entries = []) {
  const handlers = new Map();
  const commands = new Map();
  let nextId = entries.length;
  const api = {
    on(name, handler) {
      handlers.set(name, handler);
    },
    registerCommand(name, options) {
      commands.set(name, options);
    },
    appendEntry(customType, data) {
      nextId += 1;
      entries.push(entry(`state-${nextId}`, data, customType));
    },
  };
  const module = await import(`${artifact}?lifecycle=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return { commands, entries, handlers };
}

async function status(instance, ctx) {
  const notifications = [];
  const statusContext = { ...ctx, ui: context([], notifications).ui };
  await instance.commands.get("lifecycle").handler("", statusContext);
  return notifications.at(-1).message;
}

describe("typed lifecycle binding", () => {
  test("restores custom state and cleans up idempotently", async () => {
    const persisted = [];
    const first = await harness(persisted);
    const firstContext = context(persisted);

    await first.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      firstContext,
    );
    await first.commands.get("lifecycle-bump").handler("", firstContext);
    await first.commands.get("lifecycle-bump").handler("", firstContext);

    expect(persisted.map(({ data }) => data)).toEqual([1, 2]);
    expect(await status(first, firstContext)).toContain(
      "active=true value=2 start=startup",
    );

    const shutdown = first.handlers.get("session_shutdown");
    await shutdown(
      { type: "session_shutdown", reason: "reload" },
      firstContext,
    );
    await shutdown(
      { type: "session_shutdown", reason: "reload" },
      firstContext,
    );
    expect(await status(first, firstContext)).toContain(
      "active=false value=2 start=startup shutdown=reload cleanups=1",
    );

    for (const reason of ["reload", "new", "resume", "fork"]) {
      const replacement = await harness(persisted);
      const replacementContext = context(persisted);
      await replacement.handlers.get("session_start")(
        {
          type: "session_start",
          reason,
          previousSessionFile: "/sessions/previous.jsonl",
        },
        replacementContext,
      );
      expect(await status(replacement, replacementContext)).toContain(
        `active=true value=2 start=${reason}`,
      );
    }
  });

  test("decodes read-only session metadata and entry collections", async () => {
    const entries = [entry("entry-1", 7)];
    const instance = await harness(entries);
    const notifications = [];
    const ctx = context(entries, notifications);

    await instance.commands.get("lifecycle-session").handler("", ctx);

    expect(notifications.at(-1)).toEqual({
      kind: "info",
      message:
        "cwd=/work/project dir=/sessions id=session-1 " +
        "file=/sessions/current.jsonl leaf=entry-1 entries=1 branch=1 context=1",
    });

    ctx.sessionManager.getSessionFile = () => undefined;
    ctx.sessionManager.getLeafId = () => null;
    await instance.commands.get("lifecycle-session").handler("", ctx);
    expect(notifications.at(-1).message).toContain("file=ephemeral leaf=root");
  });

  test("restores state from the active branch rather than an inactive fork", async () => {
    const active = entry("active-state", 3);
    const inactive = entry("inactive-state", 99);
    const allEntries = [active, inactive];
    const instance = await harness(allEntries);
    const ctx = context(allEntries, [], [active]);

    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "resume" },
      ctx,
    );

    expect(await status(instance, ctx)).toContain(
      "active=true value=3 start=resume",
    );
  });

  test("invalidates malformed persisted state instead of resetting silently", async () => {
    const entries = [entry("broken-state", "not-an-integer")];
    const instance = await harness(entries);
    const notifications = [];
    const ctx = context(entries, notifications);

    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      ctx,
    );

    expect(notifications.at(-1)).toEqual({
      kind: "error",
      message: "Lifecycle state could not be restored; mutations are disabled",
    });
    expect(await status(instance, ctx)).toContain(
      "active=false value=0 start=none shutdown=none cleanups=0 last=restore_error",
    );
  });

  test("decodes replacement events and builds cancellation results", async () => {
    const instance = await harness([]);
    const ctx = context([]);

    expect(
      await instance.handlers.get("session_before_switch")(
        {
          type: "session_before_switch",
          reason: "resume",
          targetSessionFile: "/blocked-session.jsonl",
        },
        ctx,
      ),
    ).toEqual({ cancel: true });

    expect(
      await instance.handlers.get("session_before_fork")(
        {
          type: "session_before_fork",
          entryId: "skip-restore",
          position: "at",
        },
        ctx,
      ),
    ).toEqual({ skipConversationRestore: true });
  });

  test("decodes compaction and tree events and builds custom summaries", async () => {
    const instance = await harness([]);
    const ctx = context([]);
    const branchEntry = entry("branch-1", 1, "fixture");
    const signal = new AbortController().signal;

    const compaction = await instance.handlers.get("session_before_compact")(
      {
        type: "session_before_compact",
        preparation: {
          firstKeptEntryId: "branch-1",
          messagesToSummarize: [],
          turnPrefixMessages: [],
          isSplitTurn: false,
          tokensBefore: 4096,
          fileOps: {},
          settings: {},
        },
        branchEntries: [branchEntry],
        customInstructions: "reference-custom",
        reason: "manual",
        willRetry: false,
        signal,
      },
      ctx,
    );
    expect(compaction).toEqual({
      compaction: {
        summary: "Reference custom summary",
        firstKeptEntryId: "branch-1",
        tokensBefore: 4096,
      },
    });

    await instance.handlers.get("session_compact")(
      {
        type: "session_compact",
        compactionEntry: {
          type: "compaction",
          id: "compact-1",
          parentId: "branch-1",
          timestamp: "2026-08-04T00:00:01.000Z",
          summary: "Summary",
          firstKeptEntryId: "branch-1",
          tokensBefore: 4096,
        },
        fromExtension: true,
        reason: "manual",
        willRetry: false,
      },
      ctx,
    );

    const tree = await instance.handlers.get("session_before_tree")(
      {
        type: "session_before_tree",
        preparation: {
          targetId: "branch-1",
          oldLeafId: null,
          commonAncestorId: null,
          entriesToSummarize: [branchEntry],
          userWantsSummary: true,
          label: "reference-custom",
        },
        signal,
      },
      ctx,
    );
    expect(tree).toEqual({
      summary: { summary: "Reference branch summary" },
    });

    await instance.handlers.get("session_tree")(
      {
        type: "session_tree",
        newLeafId: "branch-1",
        oldLeafId: null,
        fromExtension: true,
      },
      ctx,
    );
  });

  test("rejects malformed lifecycle payloads", async () => {
    const instance = await harness([]);
    await expect(
      instance.handlers.get("session_before_compact")(
        { type: "session_before_compact", reason: "manual" },
        context([]),
      ),
    ).rejects.toThrow("Could not decode Pi event");
  });
});
