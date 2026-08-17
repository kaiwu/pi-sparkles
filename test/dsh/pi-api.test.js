import { describe, expect, test } from "bun:test";
import { assertRawSubset } from "../../dsh/schema-translate.mjs";
import {
  createPiApi,
  DSH_CUSTOM_EVENT,
  DSH_STATUS_EVENT,
  financeChartPresentationMeta,
} from "../../dsh/pi-api.mjs";
import { createPlugin } from "../../dsh/plugin.mjs";
import { dshClientFactorySource } from "../../dsh/client.js";
import {
  STATUS_PROJECTION_KEY,
  statusProjection,
} from "../../dsh/plugins/finance_track_overlay.mjs";

function fakeCtx({ guardInjectedServices = false } = {}) {
  const tools = [];
  const commands = [];
  const promptSections = [];
  const listeners = new Map();
  const services = {
    tools: {
      register(definition) {
        tools.push(definition);
      },
    },
    commands: {
      register(definition) {
        commands.push(definition);
      },
    },
    logger: { info() {}, warn() {} },
    systemPrompt: {
      section(value) {
        promptSections.push(value);
        return () => {};
      },
    },
  };
  const context = {
    on(event, handler) {
      if (!listeners.has(event)) listeners.set(event, new Set());
      listeners.get(event).add(handler);
      return () => listeners.get(event)?.delete(handler);
    },
    async plugin(extension, config) {
      if (typeof extension === "function") await extension(this, config);
      else await extension.apply(this, config);
    },
    async __emit(event, payload) {
      for (const handler of listeners.get(event) ?? []) await handler(payload);
    },
    get(name) {
      return services[name];
    },
    __tools: tools,
    __commands: commands,
    __promptSections: promptSections,
  };
  if (guardInjectedServices) {
    for (const name of Object.keys(services)) {
      Object.defineProperty(context, name, {
        get() {
          throw new Error(`cannot get property "${name}" without inject`);
        },
      });
    }
  } else {
    Object.assign(context, services);
  }
  return context;
}

function fakeAgent(id = "agent-1") {
  const events = [];
  const followups = [];
  const steers = [];
  return {
    id,
    session: {
      id: `session-${id}`,
      header: { cwd: `/work/${id}` },
      events,
      append(type, data) {
        const event = { type, data, seq: events.length, time: Date.now() };
        events.push(event);
        return event;
      },
    },
    followup(message) {
      followups.push(message);
    },
    steer(message) {
      steers.push(message);
    },
    __followups: followups,
    __steers: steers,
  };
}

function toolRunContext(agent = fakeAgent(), callId = "call-1") {
  return {
    agent,
    callId,
    signal: new AbortController().signal,
    concludeTurn() {},
  };
}

describe("pi-api facade", () => {
  test("registerTool bridges parameters and output through the DSH contract", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    let seen = null;
    api.registerTool({
      name: "stock_quote",
      label: "Quote",
      description: "Inspect one quote",
      promptSnippet: "Supply every fact explicitly",
      parameters: {
        type: "object",
        properties: { ticker: { type: "string" }, limit: { type: "integer", minimum: 1 } },
        required: ["ticker"],
        additionalProperties: false,
      },
      executionMode: "parallel",
      execute: async (toolCallId, input, signal, updates, context) => {
        seen = { toolCallId, input, hasSignal: signal !== undefined, context };
        return { content: [{ type: "text", text: `quote for ${input.ticker}` }], details: { x: 1 } };
      },
    });

    expect(ctx.__tools).toHaveLength(1);
    const tool = ctx.__tools[0];
    expect(tool.name).toBe("stock_quote");
    expect(tool.parameters).toEqual({
      type: "object",
      additionalProperties: false,
      properties: {
        ticker: { type: "string" },
        limit: {
          type: "integer",
          description: "Call constraints: value >= 1.",
        },
      },
      required: ["ticker"],
    });
    expect(tool.isConcurrencySafe).toBeTypeOf("function");
    expect(assertRawSubset(tool.output.schema)).toEqual([]);
    expect(tool.description).toContain("Supply every fact explicitly");
    expect(
      tool.output.render(
        { ticker: "AAPL" },
        { content: [{ type: "text", text: "hi" }] },
      ),
    ).toEqual([{ type: "text", text: "hi" }]);

    const value = await tool.execute(
      { ticker: "AAPL" },
      toolRunContext(fakeAgent(), "quote-call-1"),
    );
    expect(value.content[0].text).toBe("quote for AAPL");
    expect(seen.input).toEqual({ ticker: "AAPL" });
    expect(seen.toolCallId).toBe("quote-call-1");
    expect(seen.hasSignal).toBeTrue();
    expect(seen.context.cwd).toBe("/work/agent-1");
  });

  test("tool rejection propagates as a thrown error", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "bad_tool",
      description: "fails",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => {
        throw new Error("nope");
      },
    });
    await expect(
      ctx.__tools[0].execute({}, toolRunContext()),
    ).rejects.toThrow("nope");
  });

  test("chart tool alone projects bounded DSH browser metadata", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "chart_ohlcv",
      description: "chart",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({
        content: [{ type: "text", text: "exact fallback" }],
        details: {
          schema: "pi-sparkles/finance-chart-result",
          schemaVersion: 2,
          track: "us",
          instrumentId: "US-AAPL",
          mic: "XNAS",
          timezone: "America/New_York",
          priceUnit: "USD",
          volumeUnit: "shares",
          adjustment: { kind: "raw", label: null },
          presentation: { kind: "responsive_ohlcv_view" },
          bars: [{
            date: "2026-02-02",
            sessionType: "regular",
            open: "10.00",
            high: "11.00",
            low: "9.00",
            close: "10.50",
            volume: "100",
          }],
          indicators: [],
          trades: [],
          gaps: [],
          inputOmissions: [],
        },
      }),
    });
    expect(ctx.__tools[0].output.presentationMeta).toBeTypeOf("function");
    const value = await ctx.__tools[0].execute({}, toolRunContext());
    expect(ctx.__tools[0].output.presentationMeta({}, value)).toEqual(
      financeChartPresentationMeta(value),
    );
    expect(financeChartPresentationMeta(value)).toMatchObject({
      schema: "pi-sparkles/dsh-finance-chart-meta",
      schemaVersion: 1,
      valid: true,
      chart: {
        instrumentId: "US-AAPL",
        bars: [{ open: "10.00", close: "10.50" }],
      },
    });
    const oversized = structuredClone(value);
    oversized.details.indicators = Array.from({ length: 4 }, (_, series) => ({
      indicatorId: `large-${series}`,
      label: `Large ${series}`,
      panel: "lower_panel",
      unit: "ratio",
      points: Array.from({ length: 240 }, (_, index) => ({
        state: "unperformed",
        date: `D${index}`,
        reason: "x".repeat(1000),
      })),
    }));
    const bounded = financeChartPresentationMeta(oversized);
    expect(bounded).toMatchObject({
      valid: true,
      annotationsTruncated: true,
      chart: { indicators: [], bars: [{ close: "10.50" }] },
    });
    expect(Buffer.byteLength(JSON.stringify(bounded), "utf8")).toBeLessThanOrEqual(
      512 * 1024,
    );

    const ordinaryCtx = fakeCtx();
    createPiApi({ ctx: ordinaryCtx }).registerTool({
      name: "ordinary",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({ content: [{ type: "text", text: "ok" }] }),
    });
    expect(ordinaryCtx.__tools[0].output.presentationMeta).toBeUndefined();
  });

  test("registerCommand maps Pi handlers to the DSH CommandResult contract", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerCommand("finance-track", {
      description: "switch track",
      handler: async (_args, context) => {
        context.ui.notify("switched to cn", "info");
      },
    });

    expect(ctx.__commands).toHaveLength(1);
    const command = ctx.__commands[0];
    expect(command.name).toBe("finance-track");
    expect(command.description).toBe("switch track");

    const result = await command.handler({
      agent: fakeAgent(),
      rawInput: "cn",
      signal: new AbortController().signal,
    });
    expect(result).toEqual({ kind: "success", text: "switched to cn" });
  });

  test("command handler errors become error results", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerCommand("boom", {
      description: "throws",
      handler: async () => {
        throw new Error("broken");
      },
    });
    const result = await ctx.__commands[0].handler({
      agent: fakeAgent(),
      rawInput: "",
      signal: new AbortController().signal,
    });
    expect(result).toEqual({ kind: "error", text: "broken" });
  });

  test("flags: registered default, config override, env override", () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx, config: { flags: { "finance-track": "hk" } } });
    api.registerFlag("finance-track", { description: "track", type: "string", default: "us" });
    expect(api.getFlag("finance-track")).toBe("hk");

    const api2 = createPiApi({ ctx });
    api2.registerFlag("finance-track", { description: "track", type: "string", default: "us" });
    expect(api2.getFlag("finance-track")).toBe("us");

    const previous = process.env.PI_SPARKLES_FLAG_FINANCE_TRACK;
    process.env.PI_SPARKLES_FLAG_FINANCE_TRACK = "cn";
    try {
      expect(api2.getFlag("finance-track")).toBe("cn");
    } finally {
      if (previous === undefined) delete process.env.PI_SPARKLES_FLAG_FINANCE_TRACK;
      else process.env.PI_SPARKLES_FLAG_FINANCE_TRACK = previous;
    }
  });

  test("appendEntry uses the invoking DSH session; getActiveTools lists tools", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "alpha",
      description: "first",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({ content: [{ type: "text", text: "ok" }], details: {} }),
    });
    expect(api.getActiveTools()).toEqual(["alpha"]);

    const agent = fakeAgent();
    let captured;
    api.registerCommand("probe", {
      description: "probe",
      handler: async (_, commandContext) => {
        api.appendEntry("finance_cache.receipt", { track: "cn" });
        captured = commandContext;
      },
    });
    await ctx.__commands.at(-1).handler({
      agent,
      rawInput: "",
      signal: new AbortController().signal,
    });
    const entries = captured.sessionManager.getBranch();
    expect(entries).toHaveLength(1);
    expect(entries[0].customType).toBe("finance_cache.receipt");
    expect(entries[0].data).toEqual({ track: "cn" });
    expect(entries[0].type).toBe("custom");
    expect(agent.session.events[0].type).toBe("pi-sparkles/custom");
    expect(captured.cwd).toBe("/work/agent-1");
  });

  test("scoped status UI writes whole-value DSH session events", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({
      ctx,
      scopedState: true,
      activeTools: () => ["global_tool"],
    });
    api.registerTool({
      name: "scoped_tool",
      description: "scoped",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({ content: [{ type: "text", text: "ok" }], details: {} }),
    });
    expect(api.getActiveTools()).toEqual(["global_tool", "scoped_tool"]);
    api.registerCommand("status-probe", {
      description: "status",
      handler: async (_args, context) => {
        context.ui.setStatus("finance-track", "CN · CNY");
        context.ui.clearStatus("finance-track");
      },
    });
    const agent = fakeAgent("status");
    await ctx.__commands[0].handler({
      agent,
      rawInput: "",
      signal: new AbortController().signal,
    });
    expect(agent.session.events.map((event) => event.type)).toEqual([
      "pi-sparkles/status",
      "pi-sparkles/status",
    ]);
    expect(agent.session.events.map((event) => event.data)).toEqual([
      { key: "finance-track", text: "CN · CNY" },
      { key: "finance-track", text: null },
    ]);
  });

  test("sendUserMessage queues on the exact invocation agent", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerCommand("queue", {
      description: "queue work",
      handler: async () => {
        api.sendUserMessage("later", { deliverAs: "followUp" });
        api.sendUserMessage("now", { deliverAs: "steer" });
      },
    });
    const agent = fakeAgent("queue-agent");
    const result = await ctx.__commands[0].handler({
      agent,
      rawInput: "",
      signal: new AbortController().signal,
    });
    expect(result).toEqual({ kind: "success" });
    expect(agent.__followups[0]).toMatchObject({
      role: "user",
      content: [{ type: "text", text: "later" }],
      source: { kind: "plugin", plugin: "dsh-sparkles" },
    });
    expect(agent.__steers[0].content[0].text).toBe("now");
  });

  test("parallel tool notifications remain invocation-local", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    let releaseFirst;
    const firstPaused = new Promise((resolve) => {
      releaseFirst = resolve;
    });
    api.registerTool({
      name: "parallel_probe",
      description: "parallel",
      parameters: { type: "object", properties: {}, additionalProperties: true },
      executionMode: "parallel",
      execute: async (_id, input, _signal, _updates, context) => {
        context.ui.notify(input.label, "info");
        if (input.wait) await firstPaused;
        return { content: [{ type: "text", text: input.label }], details: {} };
      },
    });
    const first = ctx.__tools[0].execute(
      { label: "first", wait: true },
      toolRunContext(fakeAgent("first"), "first-call"),
    );
    const second = await ctx.__tools[0].execute(
      { label: "second", wait: false },
      toolRunContext(fakeAgent("second"), "second-call"),
    );
    releaseFirst();
    const firstResult = await first;
    expect(second.content.map((block) => block.text)).toEqual(["second", "second"]);
    expect(firstResult.content.map((block) => block.text)).toEqual(["first", "first"]);
  });

  test("Pi inline images are omitted instead of forged as DSH image blocks", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "chart",
      description: "chart",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({
        content: [
          { type: "text", text: "chart rows" },
          { type: "image", data: "ZmFrZQ==", mimeType: "image/png" },
        ],
        details: { points: [1, 2] },
      }),
    });
    const result = await ctx.__tools[0].execute({}, toolRunContext());
    expect(result).toEqual({
      content: [{ type: "text", text: "chart rows" }],
      details: { points: [1, 2] },
    });
  });

  test("Pi terminate results conclude the DSH turn without leaking schema fields", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "terminal",
      description: "terminal",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({
        content: [{ type: "text", text: "done" }],
        details: {},
        terminate: true,
      }),
    });
    let concluded = false;
    const run = toolRunContext();
    run.concludeTurn = () => {
      concluded = true;
    };
    const result = await ctx.__tools[0].execute({}, run);
    expect(concluded).toBeTrue();
    expect(result.terminate).toBeUndefined();
    expect(result.content).toEqual([{ type: "text", text: "done" }]);
  });

  test("createPlugin guards duplicate named registrations", async () => {
    const ctx = fakeCtx();
    const extension = (name) => (api) => {
      api.registerTool({
        name,
        description: "dup",
        parameters: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => ({ content: [{ type: "text", text: "ok" }], details: {} }),
      });
      return Promise.resolve(undefined);
    };
    const plugin = createPlugin(
      [["first", extension("same_tool")], ["second", extension("same_tool")]],
      [],
      "dsh-sparkles",
      [],
      new Set(),
    );
    await expect(plugin.apply(ctx, {})).rejects.toThrow(/Registration collision for registerTool 'same_tool'/);
  });

  test("createPlugin follows DSH agent session lifecycle", async () => {
    const ctx = fakeCtx();
    const started = [];
    const knownSessionEventTypes = new Set(["turn/start"]);
    const extension = (api) => {
      api.on("session_start", () => started.push("started"));
      api.registerTool({
        name: "only",
        description: "only tool",
        parameters: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => ({ content: [{ type: "text", text: "ok" }], details: {} }),
      });
      return Promise.resolve(undefined);
    };
    const plugin = createPlugin(
      [["only", extension]],
      [],
      "dsh-sparkles",
      [],
      knownSessionEventTypes,
    );
    expect(plugin.inject).toEqual(["tools", "commands", "agents", "systemPrompt"]);
    await plugin.apply(ctx, {});
    expect(knownSessionEventTypes).toEqual(
      new Set(["turn/start", DSH_CUSTOM_EVENT, DSH_STATUS_EVENT]),
    );
    expect(ctx.__tools).toHaveLength(1);
    expect(started).toEqual([]);
    await ctx.__emit("agent/session-start", {
      agent: fakeAgent(),
      source: "startup",
    });
    expect(started).toEqual(["started"]);
  });

  test("scoped Pi counterparts get isolated registrations, state, lifecycle, and prompt", async () => {
    const root = fakeCtx();
    const starts = [];
    const extension = (api) => {
      let count = 0;
      api.on("before_agent_start", () => Promise.resolve({ systemPrompt: "shared" }));
      api.on("session_tree", () => Promise.resolve());
      api.on("session_start", (_event, context) => {
        count += 1;
        starts.push(context.sessionManager.getSessionId());
        context.ui.setStatus("finance-track", `count:${count}`);
        return Promise.resolve();
      });
      api.registerTool({
        name: "scoped_counter",
        description: "counter",
        parameters: { type: "object", properties: {}, additionalProperties: false },
        execute: async () => ({
          content: [{ type: "text", text: String(count) }],
          details: { count },
        }),
      });
      return Promise.resolve();
    };
    const plugin = createPlugin(
      [],
      [],
      "dsh-sparkles",
      [["state", extension, { systemPrompt: "shared", promptName: "shared-state" }]],
      new Set(),
    );
    await plugin.apply(root, {});

    const first = fakeAgent("first");
    first.ctx = fakeCtx({ guardInjectedServices: true });
    const second = fakeAgent("second");
    second.ctx = fakeCtx({ guardInjectedServices: true });
    await root.__emit("agent/created", { agent: first });
    await root.__emit("agent/created", { agent: second });
    expect(root.__tools).toHaveLength(0);
    expect(first.ctx.__tools.map((tool) => tool.name)).toEqual(["scoped_counter"]);
    expect(second.ctx.__tools.map((tool) => tool.name)).toEqual(["scoped_counter"]);
    expect(first.ctx.__promptSections).toHaveLength(1);
    expect(first.ctx.__promptSections[0]).toMatchObject({
      name: "shared-state",
      order: 99,
    });
    expect(first.ctx.__promptSections[0].text).toMatch(
      /^shared\nDSH runtime date: \d{4}-\d{2}-\d{2}\./,
    );
    expect(first.ctx.__promptSections[0].text).toContain(
      "never invoke a shell merely to discover today's date",
    );

    await root.__emit("agent/session-start", { agent: first, source: "startup" });
    await root.__emit("agent/session-start", { agent: second, source: "resume" });
    expect(starts).toEqual(["session-first", "session-second"]);
    expect(first.session.events.at(-1).data.text).toBe("count:1");
    expect(second.session.events.at(-1).data.text).toBe("count:1");
    const firstResult = await first.ctx.__tools[0].execute(
      {},
      toolRunContext(first, "first-counter"),
    );
    const secondResult = await second.ctx.__tools[0].execute(
      {},
      toolRunContext(second, "second-counter"),
    );
    expect(firstResult.details.count).toBe(1);
    expect(secondResult.details.count).toBe(1);
  });

  test("status projection folds updates and the client registers shell.overlay", () => {
    const projection = statusProjection();
    expect(projection.key).toBe(STATUS_PROJECTION_KEY);
    let state = projection.init();
    state = projection.apply(state, {
      type: "pi-sparkles/status",
      data: { key: "finance-track", text: "HK · HKD" },
    });
    expect(projection.view(state)).toEqual({
      values: { "finance-track": "HK · HKD" },
    });
    const unchanged = projection.apply(state, { type: "turn/start", data: {} });
    expect(unchanged).toBe(state);

    let loaded;
    const stateUpdates = [];
    const window = {
      innerWidth: 1280,
      innerHeight: 720,
      __ModuleLoader__: {
        load(definition) {
          loaded = definition.factory((name) => {
            if (name === "react") {
              return {
                createElement(type, props, ...children) {
                  return {
                    type,
                    props,
                    child: children.length <= 1 ? children[0] : children,
                  };
                },
                useRef(value) {
                  return { current: value };
                },
                useState(value) {
                  return [value, (next) => stateUpdates.push(next)];
                },
              };
            }
            throw new Error(`unexpected client module: ${name}`);
          });
        },
      },
    };
    new Function("window", dshClientFactorySource("@fixture/dsh"))(window);
    const registered = new Map();
    const injected = [];
    loaded.apply({
      slots: {
        inject(name, callback) {
          injected.push(name);
          callback();
        },
        register(definition, component) {
          registered.set(definition.name, { definition, component });
          return () => {};
        },
      },
    });
    expect(injected).toEqual(["shell.overlay", "tool.call.toolview"]);
    const overlay = registered.get("shell.overlay");
    expect(overlay.definition).toMatchObject({
      name: "shell.overlay",
      id: "pi-sparkles-finance-track",
    });
    expect(registered.get("tool.call.toolview").definition).toMatchObject({
      name: "tool.call.toolview",
      key: "chart_ohlcv",
    });
    const rendered = overlay.component({
      useSessions: (selector) => selector({
        current: "s1",
        byId: {
          s1: {
            projectionValues: {
              piSparklesStatus: { values: { "finance-track": "US · USD" } },
            },
          },
        },
      }),
    });
    expect(rendered).toMatchObject({
      type: "div",
      props: {
        role: "status",
        tabIndex: 0,
        "data-dsh-sparkles-overlay": "finance-track",
        style: { cursor: "grab", touchAction: "none" },
      },
      child: "US · USD",
    });
    let captured = false;
    const overlayNode = {
      offsetParent: {
        getBoundingClientRect: () => ({ left: 100, top: 50, width: 1000, height: 700 }),
      },
      getBoundingClientRect: () => ({ left: 900, top: 700, width: 200, height: 30 }),
      setPointerCapture(pointerId) {
        expect(pointerId).toBe(7);
        captured = true;
      },
      hasPointerCapture: () => captured,
      releasePointerCapture(pointerId) {
        expect(pointerId).toBe(7);
        captured = false;
      },
    };
    let prevented = 0;
    rendered.props.onPointerDown({
      button: 0,
      pointerId: 7,
      clientX: 900,
      clientY: 700,
      currentTarget: overlayNode,
      preventDefault: () => prevented += 1,
    });
    rendered.props.onPointerMove({
      pointerId: 7,
      clientX: 650,
      clientY: 500,
      currentTarget: overlayNode,
      preventDefault: () => prevented += 1,
    });
    expect(stateUpdates).toContainEqual({ left: 550, top: 450 });
    rendered.props.onPointerUp({ pointerId: 7, currentTarget: overlayNode });
    expect(captured).toBe(false);
    expect(prevented).toBe(2);
    rendered.props.onDoubleClick();
    expect(stateUpdates.at(-1)).toBeNull();
  });

  test("unsupported Pi host effects fail explicitly", () => {
    const api = createPiApi({ ctx: fakeCtx() });
    expect(() => api.registerShortcut("x", {})).toThrow(
      "Pi API registerShortcut is not supported",
    );
    expect(() => api.on("before_agent_start", () => {})).toThrow(
      "Pi API on('before_agent_start') is not supported",
    );
    expect(() => api.appendEntry("outside", {})).toThrow(
      "requires an active DSH agent/session invocation",
    );
  });
});
