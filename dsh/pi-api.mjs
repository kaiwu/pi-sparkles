// Pi ExtensionApi facade over DeepSeek Harness services.
//
// Every pi-sparkles plugin bundle is a self-contained Pi extension whose
// `extension(api)` factory calls a small, bounded Pi API surface (verified
// across all 135 ledger artifacts):
//
//   registerTool, registerCommand, on, appendEntry, getActiveTools,
//   registerFlag, getFlag, sendUserMessage, events
//
// plus the remainder of the pi_gleam binding (sendMessage, setSessionName,
// setLabel, exec, setModel, ...) that no current plugin calls at runtime but
// the facade still implements so the full binding can never throw.
//
// This module maps that surface onto DeepSeek Harness Cordis services
// (`ctx.tools`, `ctx.commands`) and degrades the rest to bounded,
// documented behavior:
//
//   - tools      -> ctx.tools.register(defineTool-shape definition) with the
//                   Pi parameters schema translated to the DSH author dialect
//                   (schema-translate.mjs) and results rendered to text;
//   - commands   -> ctx.commands.register with Pi handlers wrapped to return
//                   the DSH CommandResult contract; sendUserMessage calls made
//                   inside the handler become the command's success text;
//   - flags      -> registered defaults, overridable via the bundle config
//                   `flags` map (and the PI_SPARKLES_FLAG_<NAME> env var);
//   - events     -> a local bus; `session_start` fires once at plugin apply so
//                   plugins initialize with defaults, `session_shutdown` fires
//                   when the root context is disposed, `before_agent_start` is
//                   never fired (DSH owns its system prompt);
//   - appendEntry -> a shared in-memory custom-entry store that the synthetic
//                   sessionManager exposes (getBranch/getEntries), so
//                   append/read stays coherent inside one process; persistence
//                   across restarts is not claimed;
//   - ui/session/prompt surfaces -> explicit no-ops (hasUI is false).

import {
  OUTPUT_SCHEMA,
  renderToolValue,
  translateParameters,
} from "./schema-translate.mjs";

const SESSION_START = "session_start";
const SESSION_SHUTDOWN = "session_shutdown";
const BEFORE_AGENT_START = "before_agent_start";

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

/** Build the synthetic Pi Context handed to plugin callbacks. */
function syntheticContext({ signal, sessionStore, bus } = {}) {
  const sessionManager = {
    getCwd: () => process.cwd(),
    getSessionDir: () => process.cwd(),
    getSessionId: () => "dsh-sparkles",
    getSessionFile: () => null,
    getLeafId: () => null,
    getEntries: () => sessionStore.getEntries(),
    getBranch: () => sessionStore.getBranch(),
    buildContextEntries: () => sessionStore.getBranch(),
  };
  return {
    cwd: process.cwd(),
    mode: "dsh",
    hasUI: false,
    ui: undefined,
    signal,
    sessionManager,
    events: bus,
    isIdle: () => true,
    isProjectTrusted: () => true,
    hasPendingMessages: () => false,
    getSystemPrompt: () => "",
    getContextUsage: () => null,
    scopedModels: undefined,
    abort: () => {},
    shutdown: () => {},
    compact: () => {},
    waitForIdle: async () => {},
    newSession: async () => {},
    fork: async () => {},
    navigateTree: async () => {},
    switchSession: async () => {},
    reload: async () => {},
  };
}

/** Shared in-memory custom-entry store (entry shape matches Pi's decoder). */
class SessionStore {
  #entries = [];

  append(customType, data) {
    const id = `pi-sparkles-${this.#entries.length + 1}`;
    const entry = {
      type: "custom",
      id,
      parentId: null,
      timestamp: new Date().toISOString(),
      customType,
      data,
    };
    this.#entries.push(entry);
    return entry;
  }

  getBranch() {
    return [...this.#entries];
  }

  getEntries() {
    return [...this.#entries];
  }
}

/** Track one in-flight sendUserMessage capture inside a command/tool call. */
class MessageCapture {
  #messages = [];

  push(content) {
    this.#messages.push(content);
  }

  take() {
    const text = this.#messages.join("\n");
    this.#messages = [];
    return text.length === 0 ? undefined : text;
  }
}

/**
 * Create the Pi ExtensionApi facade backed by a DSH Cordis context.
 * @param {object} options
 * @param {object} options.ctx - the Cordis context (services: tools, commands).
 * @param {object} [options.config] - bundle config ({ flags?: Record<string,string> }).
 * @param {(message: string) => void} [options.log] - diagnostic sink.
 */
export function createPiApi({ ctx, config = {}, log = console.warn }) {
  const flags = new Map();
  const configFlags = isRecord(config.flags) ? config.flags : {};
  const registeredToolNames = [];
  const bus = new EventBus();
  const sessionStore = new SessionStore();
  const capture = new MessageCapture();
  const sessionStart = new Set();
  const sessionShutdown = new Set();
  const beforeAgentStart = new Set();
  const otherEvents = new Map();

  const flagNameEnv = (name) =>
    `PI_SPARKLES_FLAG_${name.replace(/[^a-zA-Z0-9]/g, "_").toUpperCase()}`;

  const api = {
    // ── tools ───────────────────────────────────────────────────────────────
    registerTool(definition) {
      if (!isRecord(definition) || typeof definition.name !== "string") {
        throw new TypeError("dsh-sparkles: registerTool requires a definition with a name");
      }
      const { name, description = "", promptSnippet = "", parameters, execute } = definition;
      const params = translateParameters(parameters);
      const tool = {
        name,
        description:
          typeof promptSnippet === "string" && promptSnippet.length > 0
            ? `${description}\n\n${promptSnippet}`
            : description,
        parameters: params,
        output: {
          schema: OUTPUT_SCHEMA,
          render: (args, value) => renderToolValue(value),
        },
        ...definition.executionMode === "parallel"
          ? { isConcurrencySafe: () => true }
          : {},
        async execute(args, exec) {
          if (typeof execute !== "function") {
            throw new Error(`dsh-sparkles: tool ${name} has no execute callback`);
          }
          const context = syntheticContext({
            signal: exec?.signal,
            sessionStore,
            bus,
          });
          const value = await execute("", args, exec?.signal, noopUpdates, context);
          const sent = capture.take();
          if (sent !== undefined && isRecord(value)) {
            return { ...value, content: [...(value.content ?? []), { type: "text", text: sent }] };
          }
          return value;
        },
      };
      ctx.tools.register(tool);
      registeredToolNames.push(name);
    },

    // ── commands ────────────────────────────────────────────────────────────
    registerCommand(name, { description, handler } = {}) {
      ctx.commands.register({
        name,
        description,
        handler: async (invocation) => {
          let text;
          try {
            await handler(invocation?.rawInput ?? "", syntheticContext({ signal: invocation?.signal, sessionStore, bus }));
            text = capture.take();
          } catch (error) {
            return {
              kind: "error",
              text: error instanceof Error ? error.message : String(error),
            };
          }
          return { kind: "success", ...(text !== undefined ? { text } : {}) };
        },
      });
    },

    registerShortcut() {},

    // ── flags ───────────────────────────────────────────────────────────────
    registerFlag(name, { description, type = "string", default: defaultValue } = {}) {
      flags.set(name, { description, type, default: defaultValue });
    },

    getFlag(name) {
      const envName = flagNameEnv(name);
      if (typeof process !== "undefined" && process.env?.[envName] !== undefined) {
        return process.env[envName];
      }
      if (Object.hasOwn(configFlags, name)) return configFlags[name];
      const flag = flags.get(name);
      return flag?.default;
    },

    // ── session / entries ───────────────────────────────────────────────────
    appendEntry(customType, data) {
      sessionStore.append(customType, data);
    },

    sendUserMessage(content, { deliverAs } = {}) {
      capture.push(String(content));
    },

    sendMessage() {},

    setSessionName() {},
    getSessionName() {
      return undefined;
    },
    setLabel() {},
    clearLabel() {},

    getActiveTools() {
      return [...registeredToolNames];
    },
    setActiveTools() {},
    getAllTools() {
      return [];
    },
    getCommands() {
      return [];
    },

    getThinkingLevel() {
      return "medium";
    },
    setThinkingLevel() {},
    setModel() {
      return Promise.resolve(true);
    },

    // ── events ──────────────────────────────────────────────────────────────
    events: bus,

    on(event, handler) {
      if (typeof handler !== "function") return () => {};
      if (event === SESSION_START) sessionStart.add(handler);
      else if (event === SESSION_SHUTDOWN) sessionShutdown.add(handler);
      else if (event === BEFORE_AGENT_START) beforeAgentStart.add(handler);
      else {
        if (!otherEvents.has(event)) otherEvents.set(event, new Set());
        otherEvents.get(event).add(handler);
      }
      return () => {
        sessionStart.delete(handler);
        sessionShutdown.delete(handler);
        beforeAgentStart.delete(handler);
        otherEvents.get(event)?.delete(handler);
      };
    },

    registerProvider() {},
    unregisterProvider() {},

    registerMessageRenderer() {},
    registerEntryRenderer() {},
    registerMarkdownTransformer() {},

    exec() {
      return Promise.resolve({ stdout: "", stderr: "", code: 0, killed: false });
    },

    // ── plugin-controlled startup/shutdown hooks ────────────────────────────
    _fireSessionStart() {
      const context = syntheticContext({ sessionStore, bus });
      for (const handler of sessionStart) {
        runEventHook("session_start", handler, { reason: "startup" }, context, log);
      }
    },

    _fireSessionShutdown() {
      const context = syntheticContext({ sessionStore, bus });
      for (const handler of sessionShutdown) {
        runEventHook("session_shutdown", handler, { reason: "shutdown" }, context, log);
      }
    },
  };

  return api;
}

/** Invoke one Pi event hook, absorbing both sync throws and promise rejections. */
function runEventHook(event, handler, payload, context, log) {
  try {
    const result = handler(payload, context);
    if (result !== undefined && typeof result?.then === "function") {
      result.catch((error) => {
        log(`[dsh-sparkles] ${event} handler rejected:`, error);
      });
    }
  } catch (error) {
    log(`[dsh-sparkles] ${event} handler threw:`, error);
  }
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function noopUpdates() {}
