import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/broker_live/index.js");
const hash = (character) => character.repeat(64);

async function harness() {
  const tools = new Map();
  const module = await import(`${artifact}?broker-live=${Date.now()}-${Math.random()}`);
  await module.default({ registerTool: (definition) => tools.set(definition.name, definition) });
  return tools;
}

function fact(name, value = `caller:${name}`, unit = "caller_lexeme") {
  return { name, state: "known", value, unit, sourceReference: hash("c") };
}

function base(mode, overrides = {}) {
  const common = [
    fact("broker_provider", "futu", "provider_identifier"),
    fact("read_only_authority", "read_only", "authority_scope"),
  ];
  const modeFacts =
    mode === "non_executable_handoff"
      ? [
          fact("provider_capability_receipt"),
          fact("instruction_side"),
          fact("instruction_kind"),
          fact("quantity"),
          fact("quantity_unit"),
          fact("time_in_force"),
          fact("plan_fingerprint"),
          fact("rule_reference"),
        ]
      : [
          fact("entitlement_scope"),
          fact("capability_scope"),
          fact("handoff_receipt"),
          fact("external_execution_receipt"),
        ];
  return {
    provider: "futu",
    operationId: `broker-live-${mode}`,
    mode,
    environment: "external_live",
    accountReference: hash("a"),
    track: "hk",
    listingId: "HK.00700",
    mic: "XHKG",
    sourceContentHash: hash("b"),
    facts: [...common, ...modeFacts],
    events:
      mode === "non_executable_handoff"
        ? []
        : [
            {
              eventReference: hash("d"),
              statusLexeme: "externally_filled",
              occurredAtUnixMilliseconds: 2000,
              sourceReference: hash("e"),
            },
          ],
    missingCapabilities: [],
    ...overrides,
  };
}

async function execute(tool, input, signal = new AbortController().signal) {
  return tool.execute("broker-live", input, signal, undefined, { hasUI: false, ui: {} });
}

describe("non-executable external handoff and receipt reconciliation", () => {
  test("binds one explicit external provider without network or mutation", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("broker_live must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["review_external_execution_evidence"]);
      const handoff = await execute(
        tools.get("review_external_execution_evidence"),
        base("non_executable_handoff"),
      );
      expect(requests).toBe(0);
      expect(handoff.details).toMatchObject({
        maturity: "experimental",
        provider: "futu",
        mode: "non_executable_handoff",
        track: "hk",
        missingCapabilities: [],
        networkPerformed: false,
        providerAuthenticated: false,
        brokerAuthorityAccepted: false,
        executable: false,
      });
      expect(handoff.details.providerDependency).toMatchObject({
        requiredAtRuntime: true,
        adapterBundled: false,
        sdkBundled: false,
        credentialAcceptedByPlugin: false,
      });
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("reconciles bounded external lifecycle facts and fails closed on missing linkage", async () => {
    const tools = await harness();
    const tool = tools.get("review_external_execution_evidence");
    const receipt = await execute(tool, base("external_execution_receipt_import"));
    expect(receipt.details).toMatchObject({
      state: "reviewed",
      lastInputStatusLexeme: "externally_filled",
      eventTimeOrder: "not_applicable",
    });
    const missing = base("external_execution_receipt_import");
    missing.facts = missing.facts.filter((value) => value.name !== "handoff_receipt");
    await expect(execute(tool, missing)).rejects.toThrow("handoff_receipt");
    const mismatched = base("external_execution_receipt_import", { provider: "other" });
    await expect(execute(tool, mismatched)).rejects.toThrow(
      "broker_provider must bind exactly other",
    );
  });

  test("rejects events in handoffs and honors cancellation", async () => {
    const tools = await harness();
    const tool = tools.get("review_external_execution_evidence");
    await expect(
      execute(
        tool,
        base("non_executable_handoff", {
          events: [
            {
              eventReference: hash("d"),
              statusLexeme: "impossible",
              occurredAtUnixMilliseconds: 1,
              sourceReference: hash("e"),
            },
          ],
        }),
      ),
    ).rejects.toThrow("cannot contain external lifecycle observations");
    const controller = new AbortController();
    controller.abort();
    await expect(
      execute(tool, base("non_executable_handoff"), controller.signal),
    ).rejects.toThrow("cancelled");
  });
});
