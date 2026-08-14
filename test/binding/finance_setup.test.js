import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/finance_setup/index.js");

async function harness(activeTools = []) {
  const commands = new Map();
  const tools = new Map();
  const flags = new Map();
  const api = {
    registerFlag(name, options) {
      flags.set(name, options.default);
    },
    getFlag(name) {
      return flags.get(name);
    },
    getActiveTools() {
      return activeTools;
    },
    registerCommand(name, options) {
      commands.set(name, options);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-setup=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { commands, flags, tools };
}

async function execute(tool, input) {
  return tool.execute(
    "finance-setup",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("finance setup provider-surface discovery", () => {
  test("labels reporting defaults separately and recognizes Eastmoney", async () => {
    const instance = await harness([
      "finance_capabilities",
      "finance_provider_health",
      "cn_market_overview",
    ]);
    const capabilities = await execute(
      instance.tools.get("finance_capabilities"),
      {},
    );
    expect(capabilities.content[0].text).toContain(
      "Finance reporting defaults (not the active market track)",
    );
    expect(capabilities.details).toMatchObject({
      defaultsScope: "global_reporting_defaults_not_active_track",
      currency: "USD",
      timezone: "UTC",
    });
    expect(capabilities.details.capabilities[3]).toMatchObject({
      name: "provider adapter surfaces",
      state: "available",
    });

    const eastmoney = await execute(
      instance.tools.get("finance_provider_health"),
      { provider: "eastmoney" },
    );
    expect(eastmoney.details).toMatchObject({
      name: "Eastmoney",
      state: "available",
    });
    expect(eastmoney.content[0].text).toContain("installation state only");
    expect(eastmoney.content[0].text).toContain("live health remain unprobed");
  });

  test("does not claim an absent adapter is connected", async () => {
    const instance = await harness([]);
    const eastmoney = await execute(
      instance.tools.get("finance_provider_health"),
      { provider: "eastmoney" },
    );
    expect(eastmoney.details.state).toBe("missing_dependency");
  });
});
