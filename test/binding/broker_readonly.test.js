import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const hash = (character) => character.repeat(64);
const definitions = [
  { plugin: "broker_readonly_alpaca", provider: "alpaca", tool: "review_alpaca_activity_import" },
  { plugin: "broker_readonly_ibkr", provider: "ibkr", tool: "review_ibkr_activity_import" },
];

async function harness(plugin) {
  const tools = new Map();
  const artifact = resolve(import.meta.dir, `../../dist/${plugin}/index.js`);
  const module = await import(`${artifact}?broker-readonly=${Date.now()}-${Math.random()}`);
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

function input(provider, overrides = {}) {
  return {
    provider,
    operationId: `review-${provider}`,
    mode: "read_only_capability",
    environment: "external_live",
    accountReference: hash("a"),
    track: "us",
    listingId: "listing:AAPL:XNAS",
    mic: "XNAS",
    sourceContentHash: hash("b"),
    facts: [
      fact("broker_provider", provider, "provider_identifier"),
      fact("capability_scope", "account,position,order,fill", "capability_set"),
      fact("entitlement_scope", "caller_owned_read_only", "entitlement_declaration"),
      fact("read_only_authority", "read_only", "authority_scope"),
    ],
    events: [
      {
        eventReference: hash("d"),
        statusLexeme: "externally_reported",
        occurredAtUnixMilliseconds: 1000,
        sourceReference: hash("e"),
      },
    ],
    missingCapabilities: [],
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute("broker-readonly", value, new AbortController().signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("explicit external read-only brokers", () => {
  for (const definition of definitions) {
    test(`${definition.provider} is an explicit unbundled dependency`, async () => {
      const originalFetch = globalThis.fetch;
      let requests = 0;
      globalThis.fetch = async () => {
        requests += 1;
        throw new Error(`${definition.plugin} must not fetch`);
      };
      try {
        const tools = await harness(definition.plugin);
        expect([...tools.keys()]).toEqual([definition.tool]);
        const result = await execute(tools.get(definition.tool), input(definition.provider));
        expect(requests).toBe(0);
        expect(result.details).toMatchObject({
          maturity: "experimental",
          provider: definition.provider,
          track: "us",
          networkPerformed: false,
          providerAuthenticated: false,
          brokerAuthorityAccepted: false,
          executable: false,
          missingCapabilities: [],
        });
        expect(result.details.providerDependency).toMatchObject({
          mode: "explicit_external_capability",
          requiredAtRuntime: true,
          adapterBundled: false,
          sdkBundled: false,
          credentialAcceptedByPlugin: false,
        });
        await expect(
          execute(tools.get(definition.tool), input("wrong-provider")),
        ).rejects.toThrow(`must be ${definition.provider}`);
      } finally {
        globalThis.fetch = originalFetch;
      }
    });
  }
});
