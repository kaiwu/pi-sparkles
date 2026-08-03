import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/hello/index.js");

function fakeContext(notifications) {
  return {
    cwd: process.cwd(),
    mode: "tui",
    hasUI: true,
    ui: {
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

describe("Gleam binding", () => {
  test("registers and runs commands and typed tools", async () => {
    const commands = new Map();
    const tools = new Map();
    const api = {
      registerCommand(name, options) {
        commands.set(name, options);
      },
      registerTool(definition) {
        tools.set(definition.name, definition);
      },
    };

    const module = await import(`${artifact}?binding=${Date.now()}`);
    await module.default(api);

    expect([...commands.keys()]).toEqual(["hello"]);
    expect([...tools.keys()]).toEqual(["hello"]);

    const notifications = [];
    await commands.get("hello").handler("Ada", fakeContext(notifications));
    expect(notifications).toEqual([{ message: "Hello, Ada!", kind: "info" }]);

    const tool = tools.get("hello");
    expect(tool.parameters).toEqual({
      type: "object",
      properties: {
        name: { type: "string", description: "Name to greet" },
      },
      required: ["name"],
      additionalProperties: false,
    });
    const result = await tool.execute(
      "call-1",
      { name: "Grace" },
      undefined,
      undefined,
      fakeContext([]),
    );
    expect(result).toEqual({
      content: [{ type: "text", text: "Hello, Grace!" }],
      details: { greeted: "Grace" },
    });

    await expect(
      tool.execute("call-2", {}, undefined, undefined, fakeContext([])),
    ).rejects.toThrow("Invalid parameters for tool hello");
  });
});
