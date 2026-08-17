// Pi ExtensionApi facade over DeepSeek Harness services.
//
// This is deliberately a compatibility shell, not a second implementation of
// finance behavior. Included Pi extensions keep using their compiled Gleam
// functional cores while host-owned effects are mapped onto the exact DSH
// invocation, agent, and session. Pi-only effects fail explicitly so a future
// plugin cannot appear to work by falling through a synthetic no-op.

import { AsyncLocalStorage } from "node:async_hooks";
import { randomUUID } from "node:crypto";
import {
  OUTPUT_SCHEMA,
  renderToolValue,
  translateParameters,
} from "./schema-translate.mjs";

const SESSION_START = "session_start";
const SESSION_SHUTDOWN = "session_shutdown";
const DSH_CUSTOM_EVENT = "pi-sparkles/custom";

/** A minimal EventBus matching pi_gleam's `events(api)` contract. */
class EventBus {
  #listeners = new Map();

  on(channel, handler) {
    if (typeof handler !== "function") return () => {};
    if (!this.#listeners.has(channel)) this.#listeners.set(channel, new Set());
    this.#listeners.get(channel).add(handler);
    return () => this.#listeners.get(channel)?.delete(handler);
  }

  emit(channel, data) {
    for (const handler of [...(this.#listeners.get(channel) ?? [])]) {
      try {
        handler(data);
      } catch (error) {
        console.warn(`[dsh-sparkles] event ${channel} handler threw:`, error);
      }
    }
  }

  get size() {
    return this.#listeners.size;
  }
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function unsupported(name) {
  throw new Error(`dsh-sparkles: Pi API ${name} is not supported by the DSH adapter`);
}

function currentAgent(storage, operation) {
  const agent = storage.getStore()?.agent;
  if (!agent?.session) {
    throw new Error(
      `dsh-sparkles: ${operation} requires an active DSH agent/session invocation`,
    );
  }
  return agent;
}

function customEntries(agent) {
  const events = Array.isArray(agent?.session?.events)
    ? agent.session.events
    : [...(agent?.session?.events ?? [])];
  return events
    .filter(
      (event) =>
        event?.type === DSH_CUSTOM_EVENT &&
        isRecord(event.data) &&
        typeof event.data.customType === "string",
    )
    .map((event) => ({
      type: "custom",
      id: `dsh:${String(agent.session.id)}:${String(event.seq)}`,
      parentId: null,
      timestamp: new Date(event.time).toISOString(),
      customType: event.data.customType,
      data: event.data.data,
    }));
}

function invocationUi(storage) {
  const notify = (message, kind = "info") => {
    const invocation = storage.getStore();
    if (!invocation) {
      throw new Error("dsh-sparkles: UI notification occurred outside a DSH invocation");
    }
    invocation.notifications.push({ message: String(message), kind: String(kind) });
  };
  const reject = (name) => () => unsupported(`ui.${name}`);
  return {
    notify,
    select: reject("select"),
    confirm: reject("confirm"),
    input: reject("input"),
    setStatus: reject("setStatus"),
    setWorkingMessage: reject("setWorkingMessage"),
    setWorkingVisible: reject("setWorkingVisible"),
    setHiddenThinkingLabel: reject("setHiddenThinkingLabel"),
    setWidget: reject("setWidget"),
    setTitle: reject("setTitle"),
    pasteToEditor: reject("pasteToEditor"),
    setEditorText: reject("setEditorText"),
    getEditorText: reject("getEditorText"),
    editor: reject("editor"),
    setTheme: reject("setTheme"),
    getAllThemes: reject("getAllThemes"),
    getToolsExpanded: reject("getToolsExpanded"),
    setToolsExpanded: reject("setToolsExpanded"),
  };
}

/** Build the Pi Context handed to one exact DSH invocation or lifecycle hook. */
function bridgedContext({ storage, signal, bus }) {
  const agent = storage.getStore()?.agent;
  const session = agent?.session;
  const cwd = session?.header?.cwd ?? process.cwd();
  const sessionManager = {
    getCwd: () => cwd,
    getSessionDir: () => cwd,
    getSessionId: () => (session ? String(session.id) : "dsh-unbound"),
    getSessionFile: () => null,
    getLeafId: () => (session?.events?.length ? `dsh:${String(session.id)}:${session.events.at(-1).seq}` : null),
    getEntries: () => (agent ? customEntries(agent) : []),
    getBranch: () => (agent ? customEntries(agent) : []),
    buildContextEntries: () => (agent ? customEntries(agent) : []),
  };
  return {
    cwd,
    mode: "dsh",
    hasUI: true,
    ui: invocationUi(storage),
    signal,
    sessionManager,
    events: bus,
    isIdle: () => unsupported("context.isIdle"),
    isProjectTrusted: () => false,
    hasPendingMessages: () => unsupported("context.hasPendingMessages"),
    getSystemPrompt: () => unsupported("context.getSystemPrompt"),
    getContextUsage: () => null,
    scopedModels: [],
    abort: () => unsupported("context.abort"),
    shutdown: () => unsupported("context.shutdown"),
    compact: () => unsupported("context.compact"),
    waitForIdle: async () => unsupported("context.waitForIdle"),
    newSession: async () => unsupported("context.newSession"),
    fork: async () => unsupported("context.fork"),
    navigateTree: async () => unsupported("context.navigateTree"),
    switchSession: async () => unsupported("context.switchSession"),
    reload: async () => unsupported("context.reload"),
  };
}

function messageForDsh(content) {
  return Object.freeze({
    id: randomUUID(),
    role: "user",
    content: Object.freeze([{ type: "text", text: String(content) }]),
    source: Object.freeze({ kind: "plugin", plugin: "dsh-sparkles" }),
  });
}

function notificationText(notifications) {
  const text = notifications.map(({ message }) => message).join("\n");
  return text.length > 0 ? text : undefined;
}

/**
 * Normalize a Pi ToolResult to the JSON value owned by the DSH tool schema.
 * Pi's inline base64 image blocks are not DSH ImageBlocks (which reference a
 * host attachment), so they are intentionally omitted. The accompanying text
 * and structured details remain available; a native DSH chart shell can add
 * attachment-backed presentation later.
 */
export function normalizeToolResult(value, notifications = []) {
  if (!isRecord(value) || !Array.isArray(value.content)) {
    throw new TypeError("dsh-sparkles: Pi tool returned an invalid ToolResult");
  }
  const content = [];
  for (const block of value.content) {
    if (!isRecord(block) || typeof block.type !== "string") {
      throw new TypeError("dsh-sparkles: Pi tool returned an invalid content block");
    }
    if (block.type === "text" && typeof block.text === "string") {
      content.push({ type: "text", text: block.text });
    } else if (
      block.type !== "image" ||
      typeof block.data !== "string" ||
      typeof block.mimeType !== "string"
    ) {
      throw new TypeError(
        `dsh-sparkles: Pi content block '${block.type}' has no safe DSH projection`,
      );
    }
  }
  for (const { message } of notifications) {
    content.push({ type: "text", text: message });
  }
  return {
    content,
    ...(Object.hasOwn(value, "details") ? { details: value.details } : {}),
  };
}

/**
 * Create the Pi ExtensionApi facade backed by a DSH Cordis context.
 * @param {object} options
 * @param {object} options.ctx - Cordis context with tools and commands.
 * @param {object} [options.config] - bundle config ({ flags?: Record<string,string> }).
 * @param {(message: string, error?: unknown) => void} [options.log] - diagnostics.
 */
export function createPiApi({ ctx, config = {}, log = console.warn }) {
  const flags = new Map();
  const configFlags = isRecord(config.flags) ? config.flags : {};
  const registeredToolNames = [];
  const bus = new EventBus();
  const invocations = new AsyncLocalStorage();
  const sessionStart = new Set();
  const sessionShutdown = new Set();

  const flagNameEnv = (name) =>
    `PI_SPARKLES_FLAG_${name.replace(/[^a-zA-Z0-9]/g, "_").toUpperCase()}`;
  const invocationContext = (signal) =>
    bridgedContext({ storage: invocations, signal, bus });
  const runWithAgent = (agent, signal, action) =>
    invocations.run({ agent, signal, notifications: [] }, action);

  const api = {
    registerTool(definition) {
      if (!isRecord(definition) || typeof definition.name !== "string") {
        throw new TypeError("dsh-sparkles: registerTool requires a definition with a name");
      }
      const { name, description = "", promptSnippet = "", parameters, execute } = definition;
      const tool = {
        name,
        description:
          typeof promptSnippet === "string" && promptSnippet.length > 0
            ? `${description}\n\n${promptSnippet}`
            : description,
        parameters: translateParameters(parameters),
        output: {
          schema: OUTPUT_SCHEMA,
          render: (_args, value) => renderToolValue(value),
        },
        ...(definition.executionMode === "parallel"
          ? { isConcurrencySafe: () => true }
          : {}),
        async execute(args, exec) {
          if (typeof execute !== "function") {
            throw new Error(`dsh-sparkles: tool ${name} has no execute callback`);
          }
          if (exec?.callId === undefined || exec?.signal === undefined) {
            throw new Error(`dsh-sparkles: tool ${name} requires a DSH ToolRunContext`);
          }
          return runWithAgent(exec.agent, exec.signal, async () => {
            const value = await execute(
              String(exec.callId),
              args,
              exec.signal,
              noopUpdates,
              invocationContext(exec.signal),
            );
            if (value?.terminate === true) exec.concludeTurn?.();
            return normalizeToolResult(value, invocations.getStore().notifications);
          });
        },
      };
      ctx.tools.register(tool);
      registeredToolNames.push(name);
    },

    registerCommand(name, { description, handler } = {}) {
      if (typeof handler !== "function") {
        throw new TypeError(`dsh-sparkles: command ${name} has no handler`);
      }
      ctx.commands.register({
        name,
        description,
        handler: async (invocation) => {
          try {
            return await runWithAgent(invocation?.agent, invocation?.signal, async () => {
              await handler(
                invocation?.rawInput ?? "",
                invocationContext(invocation?.signal),
              );
              const text = notificationText(invocations.getStore().notifications);
              return { kind: "success", ...(text !== undefined ? { text } : {}) };
            });
          } catch (error) {
            return {
              kind: "error",
              text: error instanceof Error ? error.message : String(error),
            };
          }
        },
      });
    },

    registerShortcut() {
      unsupported("registerShortcut");
    },

    registerFlag(name, { description, type = "string", default: defaultValue } = {}) {
      flags.set(name, { description, type, default: defaultValue });
    },

    getFlag(name) {
      const envName = flagNameEnv(name);
      if (process.env?.[envName] !== undefined) return process.env[envName];
      if (Object.hasOwn(configFlags, name)) return configFlags[name];
      return flags.get(name)?.default;
    },

    appendEntry(customType, data) {
      const agent = currentAgent(invocations, "appendEntry");
      agent.session.append(DSH_CUSTOM_EVENT, { customType, data });
    },

    sendUserMessage(content, { deliverAs = "followUp" } = {}) {
      const agent = currentAgent(invocations, "sendUserMessage");
      const message = messageForDsh(content);
      if (deliverAs === "followUp") agent.followup(message);
      else if (deliverAs === "steer") agent.steer(message);
      else throw new Error(`dsh-sparkles: unsupported Pi delivery mode '${deliverAs}'`);
    },

    sendMessage() {
      unsupported("sendMessage");
    },
    setSessionName() {
      unsupported("setSessionName");
    },
    getSessionName() {
      unsupported("getSessionName");
    },
    setLabel() {
      unsupported("setLabel");
    },
    clearLabel() {
      unsupported("clearLabel");
    },

    getActiveTools() {
      return [...registeredToolNames];
    },
    setActiveTools() {
      unsupported("setActiveTools");
    },
    getAllTools() {
      unsupported("getAllTools");
    },
    getCommands() {
      unsupported("getCommands");
    },
    getThinkingLevel() {
      unsupported("getThinkingLevel");
    },
    setThinkingLevel() {
      unsupported("setThinkingLevel");
    },
    async setModel() {
      unsupported("setModel");
    },

    events: bus,

    on(event, handler) {
      if (typeof handler !== "function") return () => {};
      let listeners;
      if (event === SESSION_START) listeners = sessionStart;
      else if (event === SESSION_SHUTDOWN) listeners = sessionShutdown;
      else unsupported(`on('${event}')`);
      listeners.add(handler);
      return () => listeners.delete(handler);
    },

    registerProvider() {
      unsupported("registerProvider");
    },
    unregisterProvider() {
      unsupported("unregisterProvider");
    },
    registerMessageRenderer() {
      unsupported("registerMessageRenderer");
    },
    registerEntryRenderer() {
      unsupported("registerEntryRenderer");
    },
    registerMarkdownTransformer() {
      unsupported("registerMarkdownTransformer");
    },
    exec() {
      unsupported("exec");
    },

    async _fireSessionStart(agent, reason = "startup") {
      await runWithAgent(agent, undefined, async () => {
        const context = invocationContext(undefined);
        for (const handler of sessionStart) {
          await runEventHook("session_start", handler, { reason }, context, log);
        }
      });
    },

    async _fireSessionShutdown(agent, reason = "quit") {
      await runWithAgent(agent, undefined, async () => {
        const context = invocationContext(undefined);
        for (const handler of sessionShutdown) {
          await runEventHook("session_shutdown", handler, { reason }, context, log);
        }
      });
    },
  };

  return api;
}

async function runEventHook(event, handler, payload, context, log) {
  try {
    await handler(payload, context);
  } catch (error) {
    log(`[dsh-sparkles] ${event} handler failed:`, error);
  }
}

function noopUpdates() {}
