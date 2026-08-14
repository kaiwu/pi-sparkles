import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/cn_broker_readonly/index.js");
const hash = (character) => character.repeat(64);

async function harness() {
  const tools = new Map();
  const module = await import(`${artifact}?cn-broker=${Date.now()}-${Math.random()}`);
  await module.default({
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  });
  return tools;
}

function fact(name, value, unit) {
  return { name, state: "known", value, unit, sourceReference: hash("c") };
}

function input(overrides = {}) {
  return {
    provider: "futu_opend",
    operationId: "cn-readonly-test",
    mode: "read_only_capability",
    environment: "external_live",
    accountReference: hash("a"),
    track: "cn",
    listingId: "listing:600000:XSHG",
    mic: "XSHG",
    sourceContentHash: hash("b"),
    facts: [
      fact("broker_provider", "futu_opend", "provider_identifier"),
      fact("listing_board", "main_board", "exchange_board"),
      fact("share_class", "a_share", "share_class"),
      fact("native_currency", "CNY", "iso_4217"),
      fact("settlement_cycle", "T+1", "provider_observation"),
      fact("capability_scope", "account,position,order,fill", "capability_set"),
      fact("entitlement_scope", "caller_owned_read_only", "entitlement_declaration"),
      fact("read_only_authority", "read_only", "authority_scope"),
    ],
    events: [
      {
        eventReference: hash("d"),
        statusLexeme: "filled",
        occurredAtUnixMilliseconds: 1_786_656_000_000,
        sourceReference: hash("b"),
      },
    ],
    missingCapabilities: [],
    ...overrides,
  };
}

async function execute(tool, value, signal = new AbortController().signal) {
  return tool.execute("cn-broker-review", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("explicit CN read-only broker capability", () => {
  test("is network-free, provider-explicit, and non-executing", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("cn_broker_readonly must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["review_cn_broker_activity"]);
      const result = await execute(tools.get("review_cn_broker_activity"), input());
      expect(requests).toBe(0);
      expect(result.details).toMatchObject({
        maturity: "experimental",
        provider: "futu_opend",
        track: "cn",
        networkPerformed: false,
        providerAuthenticated: false,
        brokerAuthorityAccepted: false,
        executable: false,
        missingCapabilities: [],
      });
      expect(result.details.providerDependency).toEqual({
        mode: "explicit_external_capability",
        requiredAtRuntime: true,
        adapterBundled: false,
        sdkBundled: false,
        credentialAcceptedByPlugin: false,
        openDRequiredByPackage: false,
      });
      expect(result.details.semanticReceipt).toHaveLength(64);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("fails closed on provider mismatch, cross-track identity, and cancellation", async () => {
    const tools = await harness();
    const tool = tools.get("review_cn_broker_activity");
    await expect(execute(tool, input({ provider: "other" }))).rejects.toThrow(
      "broker_provider must bind exactly other",
    );
    await expect(execute(tool, input({ track: "hk", mic: "XHKG" }))).rejects.toThrow();
    const controller = new AbortController();
    controller.abort();
    await expect(execute(tool, input(), controller.signal)).rejects.toThrow("cancelled");
  });
});
