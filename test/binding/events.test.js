import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/safety_gate/index.js");

async function loadHandler() {
  const handlers = new Map();
  const api = {
    on(event, handler) {
      handlers.set(event, handler);
    },
  };
  const module = await import(`${artifact}?events=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return handlers.get("tool_call");
}

describe("typed event binding", () => {
  test("decodes tool calls and converts block results", async () => {
    const handler = await loadHandler();
    const result = await handler(
      {
        type: "tool_call",
        toolCallId: "call-1",
        toolName: "bash",
        input: { command: "rm -rf build" },
      },
      { hasUI: false, ui: {} },
    );
    expect(result).toEqual({
      block: true,
      reason: "Dangerous command blocked because no UI is available",
    });
  });

  test("maps no decision to JavaScript undefined", async () => {
    const handler = await loadHandler();
    const result = await handler(
      {
        type: "tool_call",
        toolCallId: "call-2",
        toolName: "bash",
        input: { command: "rg TODO src" },
      },
      { hasUI: false, ui: {} },
    );
    expect(result).toBeUndefined();
  });

  test("awaits an interactive decision", async () => {
    const handler = await loadHandler();
    const prompts = [];
    const result = await handler(
      {
        type: "tool_call",
        toolCallId: "call-3",
        toolName: "bash",
        input: { command: "sudo reboot" },
      },
      {
        hasUI: true,
        ui: {
          async confirm(title, message) {
            prompts.push({ title, message });
            return true;
          },
        },
      },
    );
    expect(result).toBeUndefined();
    expect(prompts).toHaveLength(1);
  });
});
