import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/trade_compliance/index.js");
const hash = (character) => character.repeat(64);

async function harness() {
  const tools = new Map();
  const module = await import(`${artifact}?trade-compliance=${Date.now()}-${Math.random()}`);
  await module.default({
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  });
  return tools;
}

async function execute(tool, input, signal = new AbortController().signal) {
  return tool.execute("compliance-test", input, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

const predicate = (name, expected) => ({
  kind: "predicate",
  childCount: 0,
  factName: name,
  expected,
});

const known = (name, value) => ({
  name,
  state: "known",
  value,
  values: [],
  reason: null,
  sourceReference: hash("c"),
});

function rule(overrides = {}) {
  return {
    ruleId: "cn-session-rule",
    version: "v1",
    track: "cn",
    jurisdiction: "caller-selected-cn-authority",
    accountScope: hash("a"),
    effectiveFromUnixMilliseconds: 10,
    effectiveUntilUnixMilliseconds: null,
    expressionNodes: [
      { kind: "all", childCount: 2, factName: null, expected: null },
      predicate("account_enabled", true),
      { kind: "not", childCount: 1, factName: null, expected: null },
      predicate("restricted", true),
    ],
    severity: "caller_high",
    authorityReference: hash("d"),
    corrections: [],
    ...overrides,
  };
}

describe("typed supplied trade compliance", () => {
  test("exposes evaluation, explanation, and version comparison without network or authority", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("trade_compliance must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual([
        "evaluate_supplied_trade_rules",
        "explain_supplied_trade_predicate",
        "compare_supplied_trade_rule_versions",
      ]);
      const result = await execute(tools.get("evaluate_supplied_trade_rules"), {
        operationId: "evaluate-cn-rule",
        track: "cn",
        accountReference: hash("a"),
        asOfUnixMilliseconds: 20,
        ruleSetContentHash: hash("b"),
        completeness: "caller_declared_complete",
        completenessReason: "exact caller-selected source surface",
        facts: [known("account_enabled", true), known("restricted", false)],
        rules: [rule()],
      });
      expect(requests).toBe(0);
      expect(result.details.maturity).toBe("experimental");
      expect(result.details.result.outcomes[0]).toMatchObject({
        state: "True",
        explanation: { kind: "all", state: "True" },
      });
      expect(result.details.result.completeness).toMatchObject({
        state: "caller_declared_complete",
        authenticated: false,
      });
      expect(result.details.authorityDependency).toMatchObject({
        requiredAtRuntime: true,
        providerBundled: false,
      });
      expect(result.details.aggregateVerdict).toBeNull();
      expect(result.details.networkPerformed).toBeFalse();
      expect(result.details.executable).toBeFalse();
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("explains conflicts and compares declared corrections", async () => {
    const tools = await harness();
    const explained = await execute(tools.get("explain_supplied_trade_predicate"), {
      operationId: "explain-conflict",
      expressionNodes: [predicate("restricted", true)],
      facts: [
        {
          name: "restricted",
          state: "conflicting",
          value: null,
          values: [true, false],
          reason: null,
          sourceReference: hash("c"),
        },
      ],
    });
    expect(explained.details.result.explanation.state).toBe("Conflict");

    const compared = await execute(tools.get("compare_supplied_trade_rule_versions"), {
      operationId: "compare-v1-v2",
      before: rule({ effectiveUntilUnixMilliseconds: 19 }),
      after: rule({
        version: "v2",
        effectiveFromUnixMilliseconds: 20,
        severity: "caller_critical",
        corrections: [
          {
            fromVersion: "v1",
            authorityReference: hash("e"),
            reason: "caller-supplied correction notice",
          },
        ],
      }),
    });
    expect(compared.details.result.declaresCorrectionFromBefore).toBeTrue();
    expect(compared.details.result.changes.map((change) => change.field)).toContain("severity");
    expect(compared.details.result.changes.map((change) => change.field)).toContain(
      "correction_added",
    );
  });

  test("fails closed on malformed prefix expressions, market depth, and cancellation", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("explain_supplied_trade_predicate"), {
        operationId: "bad-prefix",
        expressionNodes: [
          { kind: "all", childCount: 2, factName: null, expected: null },
          predicate("account_enabled", true),
        ],
        facts: [],
      }),
    ).rejects.toThrow("ended before the expression");
    await expect(
      execute(tools.get("explain_supplied_trade_predicate"), {
        operationId: "depth",
        expressionNodes: [predicate("best_bid_price", true)],
        facts: [],
      }),
    ).rejects.toThrow("market-depth facts are outside scope");
    const controller = new AbortController();
    controller.abort();
    await expect(
      execute(
        tools.get("explain_supplied_trade_predicate"),
        { operationId: "cancelled", expressionNodes: [predicate("ok", true)], facts: [] },
        controller.signal,
      ),
    ).rejects.toThrow("cancelled");
  });
});
