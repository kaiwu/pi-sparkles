import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const hash = (character) => character.repeat(64);
const sha = (value) => createHash("sha256").update(value).digest("hex");

const tracks = [
  {
    track: "cn",
    mic: "XSHG",
    listing: "CN.600000",
    venue: "XSHG",
    currency: "CNY",
    timezone: "Asia/Shanghai",
    provider: "futu",
  },
  {
    track: "hk",
    mic: "XHKG",
    listing: "HK.00700",
    venue: "XHKG",
    currency: "HKD",
    timezone: "Asia/Hong_Kong",
    provider: "futu",
  },
  {
    track: "us",
    mic: "XNAS",
    listing: "US.AAPL",
    venue: "XNAS",
    currency: "USD",
    timezone: "America/New_York",
    provider: "alpaca",
  },
];

async function harness(plugin) {
  const tools = new Map();
  const artifact = resolve(import.meta.dir, `../../../dist/${plugin}/index.js`);
  const module = await import(`${artifact}?t6-role=${Date.now()}-${Math.random()}`);
  await module.default({ registerTool: (definition) => tools.set(definition.name, definition) });
  return tools;
}

function execute(tool, input, signal = new AbortController().signal) {
  return tool.execute("t6-role", input, signal, undefined, { hasUI: false, ui: {} });
}

function tapeEvent(definition, id, sequence, overrides = {}) {
  return {
    eventId: id,
    tradeId: `trade-${id}`,
    kind: { state: "original", referenceEventId: null, referenceTradeId: null },
    price: { state: "known", value: "10.25", values: [], reason: null },
    size: { state: "known", value: "60", values: [], reason: null },
    conditionCodes: ["regular"],
    venueLexeme: definition.venue,
    clocks: {
      exchangeUnixMilliseconds: 1000 + Number(sequence),
      providerUnixMilliseconds: 1100 + Number(sequence),
      retrievedUnixMilliseconds: 1200 + Number(sequence),
    },
    sequence: {
      state: "sequenced",
      scope: "listing",
      value: sequence,
      values: [],
      declaredPrevious: null,
      reason: null,
    },
    rawReceiptHash: hash(id === "e1" ? "d" : "e"),
    ...overrides,
  };
}

function tapeInput(definition) {
  return {
    track: definition.track,
    listingId: definition.listing,
    mic: definition.mic,
    sessionId: "2026-08-14-regular",
    provider: definition.provider,
    feed: "external-transaction-tape",
    entitlement: "caller-owned-read-only",
    licence: "rights-safe-acceptance-fixture",
    providerReceiptHash: hash("a"),
    coverage: {
      state: "provider_declared_complete",
      referenceHash: hash("b"),
      reason: null,
    },
    conditionCoverage: {
      state: "documented",
      codes: ["regular"],
      referenceHash: hash("c"),
      reason: null,
    },
    maximumEvents: 100,
    events: [tapeEvent(definition, "e1", "10"), tapeEvent(definition, "e2", "12")],
    page: { offset: 0, limit: 100 },
  };
}

function scenarioInput(definition, provider = definition.provider) {
  const event = (id, sequence, size) => ({
    eventId: id,
    tradeId: `trade-${id}`,
    price: "10.25",
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
    operationId: `simulate-${definition.track}`,
    provider,
    track: definition.track,
    listingId: definition.listing,
    mic: definition.mic,
    sessionId: "2026-08-14-regular",
    currency: definition.currency,
    timezone: definition.timezone,
    entitlement: "caller-owned-read-only",
    licence: "rights-safe-acceptance-fixture",
    providerReceiptHash: hash("a"),
    coverage: "provider_declared_complete",
    coverageReason: null,
    documentedConditionCodes: ["regular"],
    conditionReferenceHash: hash("b"),
    instructionId: `instruction-${definition.track}`,
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
    events: [event("e1", "10", "60"), event("e2", "12", "90")],
  };
}

function fact(name, value, unit = "caller_lexeme") {
  return { name, state: "known", value, unit, sourceReference: hash("c") };
}

function brokerReviewInput(definition, provider, mode, paper = false) {
  const facts = [
    fact("broker_provider", provider, "provider_identifier"),
    fact("capability_scope", "account,position,order,fill", "capability_set"),
    fact("entitlement_scope", "caller-owned-read-only", "entitlement_declaration"),
    fact("read_only_authority", "read_only", "authority_scope"),
  ];
  if (paper) facts.push(fact("paper_environment", "external_paper", "environment_identifier"));
  return {
    provider,
    operationId: `review-${definition.track}-${provider}`,
    mode,
    environment: paper ? "external_paper" : "external_live",
    accountReference: hash("a"),
    track: definition.track,
    listingId: definition.listing,
    mic: definition.mic,
    sourceContentHash: hash("b"),
    facts,
    events: [
      {
        eventReference: hash("d"),
        statusLexeme: paper ? "paper_fill_reported" : "read_only_snapshot",
        occurredAtUnixMilliseconds: 2000,
        sourceReference: hash("e"),
      },
    ],
    missingCapabilities: [],
  };
}

function transitionInput(kind, number, overrides = {}) {
  const payload = JSON.stringify({ kind });
  return {
    currentStatePayload: null,
    currentStateHash: null,
    workflowId: "t6-day-role",
    branchId: "main",
    transitionId: `transition-${number}`,
    idempotencyKey: `key-${number}`,
    eventKind: kind,
    origin: "user_authored",
    occurredAtUnixMilliseconds: number,
    payload,
    payloadHash: sha(payload),
    evidenceReferences: [],
    executionReceiptReferences: [],
    ...overrides,
  };
}

function complianceRule(definition) {
  return {
    ruleId: `${definition.track}-session-rule`,
    version: "v1",
    track: definition.track,
    jurisdiction: `caller-selected-${definition.track}-authority`,
    accountScope: hash("a"),
    effectiveFromUnixMilliseconds: 1,
    effectiveUntilUnixMilliseconds: null,
    expressionNodes: [
      { kind: "all", childCount: 2, factName: null, expected: null },
      { kind: "predicate", childCount: 0, factName: "account_enabled", expected: true },
      { kind: "not", childCount: 1, factName: null, expected: null },
      { kind: "predicate", childCount: 0, factName: "restricted", expected: true },
    ],
    severity: "caller_high",
    authorityReference: hash("d"),
    corrections: [],
  };
}

function knownBoolean(name, value) {
  return {
    name,
    state: "known",
    value,
    values: [],
    reason: null,
    sourceReference: hash("c"),
  };
}

describe("T6 composed three-track day-trader review journey", () => {
  test("cn, hk, and us capability-packet legs remain separate and provider-free at load", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("T6 role acceptance must not fetch");
    };
    try {
      const tapeTools = await harness("stock_tape");
      const receipts = new Map();
      for (const definition of tracks) {
        const result = await execute(tapeTools.get("stock_tape"), tapeInput(definition));
        expect(result.details).toMatchObject({
          track: definition.track,
          listingId: definition.listing,
          mic: definition.mic,
          executable: false,
          providerCapability: {
            provider: definition.provider,
            dependencyMode: "explicit_external_capability",
            networkPerformed: false,
            credentialAccepted: false,
            adapterBundled: false,
          },
        });
        expect(result.details.review.sequenceIssues[0]).toMatchObject({
          kind: "gap",
          expected: "11",
          received: "12",
        });
        expect(result.details.review.providerDeclaredComplete).toBeTrue();
        receipts.set(definition.track, result.details.tapeReceiptHash);
      }
      expect(new Set(receipts.values()).size).toBe(3);
      expect(requests).toBe(0);

      await expect(
        execute(
          tapeTools.get("stock_tape"),
          tapeInput({ ...tracks[0], track: "hk" }),
        ),
      ).rejects.toThrow("outside the exact hk tape scope");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("shared workflow composes receipts, named simulations, read-only brokers, and compliance", async () => {
    const tapeTools = await harness("stock_tape");
    const tapeReceipts = [];
    for (const definition of tracks) {
      const result = await execute(tapeTools.get("stock_tape"), tapeInput(definition));
      tapeReceipts.push(result.details.tapeReceiptHash);
    }

    const dayTools = await harness("day_workbench");
    const transition = dayTools.get("day_transition");
    const initialized = await execute(transition, transitionInput("initialize_preparation", 1));
    const acquiring = await execute(
      transition,
      transitionInput("begin_acquisition", 2, {
        currentStatePayload: initialized.details.nextStatePayload,
        currentStateHash: initialized.details.nextStateHash,
        origin: "llm_authored",
      }),
    );
    const ready = await execute(
      transition,
      transitionInput("evidence_available", 3, {
        currentStatePayload: acquiring.details.nextStatePayload,
        currentStateHash: acquiring.details.nextStateHash,
        origin: "mechanical_fact",
        evidenceReferences: tapeReceipts,
      }),
    );
    expect(ready.details.state).toMatchObject({
      name: "ready",
      meaning: "evidence_available mechanical state; not ready_to_trade",
    });

    const simulationDefinitions = [
      { plugin: "cn_broker_paper", tool: "simulate_cn_tape_possible_fill", track: tracks[0] },
      { plugin: "broker_paper_alpaca", tool: "simulate_alpaca_tape_possible_fill", track: tracks[2] },
      {
        plugin: "broker_paper_ibkr",
        tool: "simulate_ibkr_tape_possible_fill",
        track: { ...tracks[2], provider: "ibkr", listing: "US.IBM", mic: "XNYS", venue: "XNYS" },
      },
    ];
    for (const definition of simulationDefinitions) {
      const tools = await harness(definition.plugin);
      const result = await execute(
        tools.get(definition.tool),
        scenarioInput(definition.track),
      );
      expect(result.details.result).toMatchObject({
        model: "transaction_tape_possible_fill_v1",
        compatibleFillQuantity: "100",
        sequenceIssueCount: 1,
        fillObserved: false,
        queuePositionKnown: false,
      });
      expect(result.details.result.branches.map((branch) => branch.kind)).toEqual([
        "compatible_non_fill",
        "compatible_fill_up_to",
      ]);
    }

    const readonlyDefinitions = [
      { plugin: "cn_broker_readonly", tool: "review_cn_broker_activity", track: tracks[0], provider: "futu" },
      { plugin: "broker_readonly_alpaca", tool: "review_alpaca_activity_import", track: tracks[2], provider: "alpaca" },
      {
        plugin: "broker_readonly_ibkr",
        tool: "review_ibkr_activity_import",
        track: { ...tracks[2], listing: "US.IBM", mic: "XNYS", venue: "XNYS" },
        provider: "ibkr",
      },
    ];
    for (const definition of readonlyDefinitions) {
      const tools = await harness(definition.plugin);
      const input = brokerReviewInput(
        definition.track,
        definition.provider,
        "read_only_capability",
      );
      if (definition.track.track === "cn") {
        input.facts.push(
          fact("listing_board", "main_board", "exchange_board"),
          fact("share_class", "a_share", "share_class"),
          fact("native_currency", "CNY", "iso_4217"),
          fact("settlement_cycle", "T+1", "provider_observation"),
        );
      }
      const result = await execute(tools.get(definition.tool), input);
      expect(result.details).toMatchObject({
        maturity: "experimental",
        provider: definition.provider,
        track: definition.track.track,
        missingCapabilities: [],
        networkPerformed: false,
        executable: false,
      });
    }

    const complianceTools = await harness("trade_compliance");
    for (const definition of tracks) {
      const result = await execute(
        complianceTools.get("evaluate_supplied_trade_rules"),
        {
          operationId: `compliance-${definition.track}`,
          track: definition.track,
          accountReference: hash("a"),
          asOfUnixMilliseconds: 20,
          ruleSetContentHash: hash("b"),
          completeness: "unproved",
          completenessReason: "caller-selected acceptance rule surface",
          facts: [knownBoolean("account_enabled", true), knownBoolean("restricted", false)],
          rules: [complianceRule(definition)],
        },
      );
      expect(result.details.result.outcomes[0]).toMatchObject({
        state: "True",
        explanation: { kind: "all", state: "True" },
      });
      expect(result.details.aggregateVerdict).toBeNull();
    }
  });

  test("external handoff/reconciliation and top-of-book remain bounded and non-executing", async () => {
    const brokerTools = await harness("broker_live");
    const brokerTool = brokerTools.get("review_external_execution_evidence");
    const common = [
      fact("broker_provider", "futu", "provider_identifier"),
      fact("read_only_authority", "read_only", "authority_scope"),
    ];
    const handoff = await execute(brokerTool, {
      provider: "futu",
      operationId: "handoff-hk",
      mode: "non_executable_handoff",
      environment: "external_live",
      accountReference: hash("a"),
      track: "hk",
      listingId: "HK.00700",
      mic: "XHKG",
      sourceContentHash: hash("b"),
      facts: [
        ...common,
        ...[
          "provider_capability_receipt",
          "instruction_side",
          "instruction_kind",
          "quantity",
          "quantity_unit",
          "time_in_force",
          "plan_fingerprint",
          "rule_reference",
        ].map((name) => fact(name, `caller:${name}`)),
      ],
      events: [],
      missingCapabilities: [],
    });
    const receipt = await execute(brokerTool, {
      provider: "futu",
      operationId: "reconcile-hk",
      mode: "external_execution_receipt_import",
      environment: "external_live",
      accountReference: hash("a"),
      track: "hk",
      listingId: "HK.00700",
      mic: "XHKG",
      sourceContentHash: hash("b"),
      facts: [
        ...common,
        fact("entitlement_scope", "caller-owned", "entitlement_declaration"),
        fact("capability_scope", "order,fill", "capability_set"),
        fact("handoff_receipt", handoff.details.semanticReceipt, "sha256_reference"),
        fact("external_execution_receipt", hash("e"), "sha256_reference"),
      ],
      events: [
        {
          eventReference: hash("d"),
          statusLexeme: "externally_filled",
          occurredAtUnixMilliseconds: 2000,
          sourceReference: hash("e"),
        },
      ],
      missingCapabilities: [],
    });
    expect(receipt.details).toMatchObject({
      state: "reviewed",
      provider: "futu",
      track: "hk",
      lastInputStatusLexeme: "externally_filled",
      brokerAuthorityAccepted: false,
      executable: false,
    });

    const orderBookTools = await harness("stock_order_book");
    const top = await execute(orderBookTools.get("stock_top_of_book"), {
      track: "hk",
      listing: {
        listingId: "listing:00700:XHKG",
        mic: "XHKG",
        symbol: "00700",
        currency: "HKD",
      },
      sources: [
        {
          sourceId: "caller-top",
          provider: "external-fixture",
          reference: "fixture://t6/hk/top",
          kind: "user_supplied",
          otherKind: null,
          feed: "caller-top-only",
          entitlement: { state: "unknown", delayMilliseconds: null },
          licence: {
            label: "rights-safe-acceptance-fixture",
            redistribution: "no_redistribution",
            notes: null,
          },
          receiptHash: hash("a"),
        },
      ],
      reports: [
        {
          reportId: "top-1",
          sourceId: "caller-top",
          currency: "HKD",
          providerTimestamp: "2026-08-14T10:00:00+08:00",
          providerTimeUnixMilliseconds: 100,
          receivedAtUnixMilliseconds: 110,
          exchangeTime: {
            state: "unknown",
            unixMilliseconds: null,
            sourceLexeme: null,
            reason: "not supplied",
          },
          sequence: { state: "unknown", value: null, scope: "unknown", reason: "not supplied" },
          gap: { state: "unknown", fromSequence: null, toSequence: null, reason: "not supplied" },
          aggregation: {
            kind: "single_venue",
            venues: [{ kind: "mic", code: "XHKG" }],
            coverage: "unknown",
            methodLabel: null,
            reason: null,
          },
          sizeUnit: { kind: "shares", label: null, reason: null },
          conditionCodes: [],
          bid: { state: "unavailable", candidate: null, reason: "not supplied", alternatives: [] },
          ask: { state: "unavailable", candidate: null, reason: "not supplied", alternatives: [] },
        },
      ],
      page: { offset: 0, limit: 10 },
    });
    expect(top.details).toMatchObject({
      track: "hk",
      calculation: {
        reportMerge: "not_performed",
        sourceSelection: "not_performed",
        gapRepair: "not_performed",
        depthReconstruction: "not_performed",
      },
      decisionOwner: "llm",
    });
  });
});
