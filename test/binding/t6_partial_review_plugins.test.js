import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const partials = [
  {
    plugin: "cn_broker_paper",
    tool: "review_cn_paper_evidence",
    mode: "deterministic_scenario",
    environment: "local_simulation",
    track: "cn",
    mic: "XSHG",
  },
  {
    plugin: "broker_readonly_alpaca",
    tool: "review_alpaca_activity_import",
    mode: "account_activity_import",
    environment: "paper",
    track: "us",
    mic: "XNAS",
  },
  {
    plugin: "broker_readonly_ibkr",
    tool: "review_ibkr_activity_import",
    mode: "account_activity_import",
    environment: "paper",
    track: "us",
    mic: "XNAS",
  },
  {
    plugin: "broker_paper_alpaca",
    tool: "review_alpaca_paper_evidence",
    mode: "external_paper_receipt_import",
    environment: "alpaca_paper",
    track: "us",
    mic: "XNYS",
  },
  {
    plugin: "broker_paper_ibkr",
    tool: "review_ibkr_paper_evidence",
    mode: "external_paper_receipt_import",
    environment: "ibkr_paper",
    track: "us",
    mic: "XNYS",
  },
  {
    plugin: "broker_live",
    tool: "review_external_execution_evidence",
    mode: "non_executable_handoff",
    environment: "external_live",
    track: "cn",
    mic: "XSHE",
  },
];

const hash = (character) => character.repeat(64);

async function load(plugin) {
  const tools = new Map();
  const artifact = resolve(import.meta.dir, `../../dist/${plugin}/index.js`);
  const module = await import(
    `${artifact}?t6-partial=${Date.now()}-${Math.random()}`
  );
  await module.default({
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  });
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "t6-partial-test",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function reviewInput(definition) {
  return {
    operationId: `review-${definition.plugin}`,
    mode: definition.mode,
    environment: definition.environment,
    accountReference: hash("a"),
    track: definition.track,
    listingId: `listing:${definition.plugin}`,
    mic: definition.mic,
    sourceContentHash: hash("b"),
    facts: [
      {
        name: "caller_supplied_activity",
        state: "known",
        value: "present",
        unit: "boolean_lexeme",
        sourceReference: hash("c"),
      },
    ],
    events:
      definition.mode === "non_executable_handoff"
        ? []
        : [
            {
              eventReference: hash("d"),
              statusLexeme: "externally_reported",
              occurredAtUnixMilliseconds: 1_000,
              sourceReference: hash("e"),
            },
          ],
    missingCapabilities: [],
  };
}

describe("T6 track-partial review shells", () => {
  for (const definition of partials) {
    test(
      `${definition.plugin} is bounded, non-networking, and non-executable`,
      async () => {
        const originalFetch = globalThis.fetch;
        let networkCalls = 0;
        globalThis.fetch = async () => {
          networkCalls += 1;
          throw new Error("partial T6 review shells must not fetch");
        };
        try {
          const tools = await load(definition.plugin);
          expect([...tools.keys()]).toEqual([definition.tool]);
          const result = await execute(
            tools.get(definition.tool),
            reviewInput(definition),
          );
          expect(networkCalls).toBe(0);
          expect(result.details).toMatchObject({
            maturity: "track_partial",
            track: definition.track,
            networkPerformed: false,
            brokerAuthorityAccepted: false,
            providerAuthenticated: false,
            sourceContentHashVerifiedAgainstBytes: false,
            executable: false,
          });
          expect(result.details.missingCapabilities.length).toBeGreaterThan(0);
          expect(result.details.semanticReceipt).toHaveLength(64);
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  }

  test("trade compliance reports per-rule state and no aggregate verdict", async () => {
    const tools = await load("trade_compliance");
    expect([...tools.keys()]).toEqual(["evaluate_supplied_trade_rules"]);
    const result = await execute(tools.get("evaluate_supplied_trade_rules"), {
      operationId: "evaluate-cn-rule",
      track: "cn",
      accountReference: hash("a"),
      asOfUnixMilliseconds: 20,
      ruleSetContentHash: hash("b"),
      facts: [
        {
          name: "caller_fact",
          state: "known",
          value: false,
          sourceReference: hash("c"),
        },
      ],
      rules: [
        {
          ruleId: "caller-rule",
          version: "v1",
          effectiveFromUnixMilliseconds: 10,
          factName: "caller_fact",
          expected: true,
          severity: "caller_high",
          authorityReference: hash("d"),
        },
      ],
      missingCapabilities: [],
    });
    expect(result.details.maturity).toBe("track_partial");
    expect(result.details.outcomes[0].state).toBe("False");
    expect(result.details.aggregateVerdict).toBeNull();
    expect(result.details.networkPerformed).toBeFalse();
    expect(result.details.executable).toBeFalse();
  });

  test("generic fact envelopes reject market-depth fields at runtime", async () => {
    const definition = partials[0];
    const tools = await load(definition.plugin);
    const input = reviewInput(definition);
    input.facts[0].name = "best_bid_price";
    await expect(
      execute(tools.get(definition.tool), input),
    ).rejects.toThrow("market-depth fields are outside");
  });
});
