import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const hash = (character) => character.repeat(64);
const definitions = [
  {
    plugin: "cn_broker_paper",
    provider: "futu",
    track: "cn",
    mic: "XSHG",
    listing: "CN.600000",
    venue: "XSHG",
    currency: "CNY",
    timezone: "Asia/Shanghai",
    reviewTool: "review_cn_paper_evidence",
    simulationTool: "simulate_cn_tape_possible_fill",
  },
  {
    plugin: "broker_paper_alpaca",
    provider: "alpaca",
    track: "us",
    mic: "XNAS",
    listing: "US.AAPL",
    venue: "XNAS",
    currency: "USD",
    timezone: "America/New_York",
    reviewTool: "review_alpaca_paper_evidence",
    simulationTool: "simulate_alpaca_tape_possible_fill",
  },
  {
    plugin: "broker_paper_ibkr",
    provider: "ibkr",
    track: "us",
    mic: "XNYS",
    listing: "US.IBM",
    venue: "XNYS",
    currency: "USD",
    timezone: "America/New_York",
    reviewTool: "review_ibkr_paper_evidence",
    simulationTool: "simulate_ibkr_tape_possible_fill",
  },
];

async function harness(plugin) {
  const tools = new Map();
  const artifact = resolve(import.meta.dir, `../../dist/${plugin}/index.js`);
  const module = await import(`${artifact}?broker-paper=${Date.now()}-${Math.random()}`);
  await module.default({ registerTool: (definition) => tools.set(definition.name, definition) });
  return tools;
}

function fact(name, value, unit) {
  return { name, state: "known", value, unit, sourceReference: hash("c") };
}

function reviewInput(definition) {
  return {
    provider: definition.provider,
    operationId: `paper-review-${definition.provider}`,
    mode: "external_paper_receipt",
    environment: "external_paper",
    accountReference: hash("a"),
    track: definition.track,
    listingId: definition.listing,
    mic: definition.mic,
    sourceContentHash: hash("b"),
    facts: [
      fact("broker_provider", definition.provider, "provider_identifier"),
      fact("capability_scope", "paper-order,fill", "capability_set"),
      fact("entitlement_scope", "caller_owned_read_only", "entitlement_declaration"),
      fact("read_only_authority", "read_only", "authority_scope"),
      fact("paper_environment", "external_paper", "environment_identifier"),
    ],
    events: [
      {
        eventReference: hash("d"),
        statusLexeme: "externally_reported_fill",
        occurredAtUnixMilliseconds: 1000,
        sourceReference: hash("e"),
      },
    ],
    missingCapabilities: [],
  };
}

function simulationInput(definition) {
  const event = (id, sequence, price, size) => ({
    eventId: id,
    tradeId: `trade-${id}`,
    price,
    size,
    venueLexeme: definition.venue,
    conditionCodes: ["regular"],
    exchangeUnixMilliseconds: 1000 + Number(sequence),
    providerUnixMilliseconds: 1100 + Number(sequence),
    retrievedUnixMilliseconds: 1200 + Number(sequence),
    sequenceScope: "listing",
    sequence,
    rawReceiptHash: hash(id === "e1" ? "d" : "e"),
  });
  return {
    operationId: `simulate-${definition.provider}`,
    provider: definition.provider,
    track: definition.track,
    listingId: definition.listing,
    mic: definition.mic,
    sessionId: "2026-08-14-regular",
    currency: definition.currency,
    timezone: definition.timezone,
    entitlement: "caller-owned-read-only",
    licence: "rights-safe-test-fixture",
    providerReceiptHash: hash("a"),
    coverage: "provider_declared_complete",
    coverageReason: null,
    documentedConditionCodes: ["regular"],
    conditionReferenceHash: hash("b"),
    instructionId: "instruction-1",
    instructionReceiptHash: hash("c"),
    accountReference: hash("a"),
    side: "buy",
    quantity: "100",
    limitPrice: "10.50",
    activationUnixMilliseconds: null,
    expiryUnixMilliseconds: null,
    ruleReferences: [hash("b")],
    capabilityReferences: [hash("c")],
    eligibleVenueLexemes: [definition.venue],
    eligibleConditionCodes: ["regular"],
    allowUnconditionedEvents: false,
    maximumEvents: 100,
    events: [event("e1", "1", "10.00", "60"), event("e2", "3", "10.25", "90")],
  };
}

async function execute(tool, input) {
  return tool.execute("broker-paper", input, new AbortController().signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("named local paper simulation and external receipt review", () => {
  for (const definition of definitions) {
    test(`${definition.plugin} completes both non-executing modes`, async () => {
      const originalFetch = globalThis.fetch;
      let requests = 0;
      globalThis.fetch = async () => {
        requests += 1;
        throw new Error(`${definition.plugin} must not fetch`);
      };
      try {
        const tools = await harness(definition.plugin);
        expect([...tools.keys()]).toEqual([definition.reviewTool, definition.simulationTool]);

        const reviewed = await execute(tools.get(definition.reviewTool), reviewInput(definition));
        expect(reviewed.details).toMatchObject({
          maturity: "experimental",
          provider: definition.provider,
          track: definition.track,
          networkPerformed: false,
          executable: false,
          missingCapabilities: [],
        });

        const simulated = await execute(
          tools.get(definition.simulationTool),
          simulationInput(definition),
        );
        expect(requests).toBe(0);
        expect(simulated.details).toMatchObject({
          maturity: "experimental",
          networkPerformed: false,
          brokerAuthorityAccepted: false,
          providerAuthenticated: false,
          executable: false,
        });
        expect(simulated.details.result).toMatchObject({
          model: "transaction_tape_possible_fill_v1",
          track: definition.track,
          compatibleFillQuantity: "100",
          sequenceIssueCount: 1,
          resultKind: "hypothetical_non_executing",
          fillObserved: false,
          queuePositionKnown: false,
        });
        expect(simulated.details.result.branches.map((branch) => branch.kind)).toEqual([
          "compatible_non_fill",
          "compatible_fill_up_to",
        ]);
        expect(simulated.details.providerDependency).toMatchObject({
          provider: definition.provider,
          requiredAtRuntime: true,
          adapterBundled: false,
          sdkBundled: false,
          credentialAcceptedByPlugin: false,
        });
      } finally {
        globalThis.fetch = originalFetch;
      }
    });
  }
});
