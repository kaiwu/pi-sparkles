import { describe, expect, test } from "bun:test";
import { assertRawSubset } from "../../dsh/schema-translate.mjs";
import { createPiApi } from "../../dsh/pi-api.mjs";
import { createPlugin } from "../../dsh/plugin.mjs";

function fakeCtx() {
  const tools = [];
  const commands = [];
  return {
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
    on() {
      return () => {};
    },
    __tools: tools,
    __commands: commands,
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
        limit: { type: "integer" },
      },
      required: ["ticker"],
    });
    expect(tool.isConcurrencySafe).toBeTypeOf("function");
    expect(assertRawSubset(tool.output.schema)).toEqual([]);
    expect(tool.description).toContain("Supply every fact explicitly");
    expect(tool.output.render({ ticker: "AAPL" }, { content: [{ type: "text", text: "hi" }] })).toBe("hi");

    const value = await tool.execute({ ticker: "AAPL" }, { signal: undefined });
    expect(value.content[0].text).toBe("quote for AAPL");
    expect(seen.input).toEqual({ ticker: "AAPL" });
    expect(seen.toolCallId).toBe("");
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
    await expect(ctx.__tools[0].execute({}, {})).rejects.toThrow("nope");
  });

  test("registerCommand maps Pi handlers to the DSH CommandResult contract", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerCommand("finance-track", { description: "switch track", handler: async (args) => {} });
    api.sendUserMessage("switched to cn", { deliverAs: "steer" });

    expect(ctx.__commands).toHaveLength(1);
    const command = ctx.__commands[0];
    expect(command.name).toBe("finance-track");
    expect(command.description).toBe("switch track");

    const result = await command.handler({ rawInput: "cn", signal: undefined });
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
    const result = await ctx.__commands[0].handler({ rawInput: "" });
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

  test("appendEntry feeds the synthetic sessionManager; getActiveTools lists tools", async () => {
    const ctx = fakeCtx();
    const api = createPiApi({ ctx });
    api.registerTool({
      name: "alpha",
      description: "first",
      parameters: { type: "object", properties: {}, additionalProperties: false },
      execute: async () => ({ content: [{ type: "text", text: "ok" }], details: {} }),
    });
    expect(api.getActiveTools()).toEqual(["alpha"]);

    api.appendEntry("finance_track_status.active_track", { track: "cn" });
    // Read the shared store back through the synthetic session manager that
    // command/tool callbacks receive.
    let captured;
    api.registerCommand("probe", {
      description: "probe",
      handler: async (_, commandContext) => {
        captured = commandContext;
      },
    });
    await ctx.__commands.at(-1).handler({ rawInput: "" });
    const entries = captured.sessionManager.getBranch();
    expect(entries).toHaveLength(1);
    expect(entries[0].customType).toBe("finance_track_status.active_track");
    expect(entries[0].data).toEqual({ track: "cn" });
    expect(entries[0].type).toBe("custom");
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
    const plugin = createPlugin([["first", extension("same_tool")], ["second", extension("same_tool")]]);
    await expect(plugin.apply(ctx, {})).rejects.toThrow(/Registration collision for registerTool 'same_tool'/);
  });

  test("createPlugin runs extensions and fires session_start", async () => {
    const ctx = fakeCtx();
    const started = [];
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
    const plugin = createPlugin([["only", extension]]);
    await plugin.apply(ctx, {});
    expect(ctx.__tools).toHaveLength(1);
    expect(started).toEqual(["started"]);
  });
});
