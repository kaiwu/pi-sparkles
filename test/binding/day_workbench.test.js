import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/day_workbench/index.js");
const receipt = (character) => character.repeat(64);
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?day-workbench=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tool, value, signal = new AbortController().signal) {
  return tool.execute("day-workbench-call", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

function common(eventId, sequence, type, overrides = {}) {
  return {
    type,
    eventId,
    listingId: "listing-aapl-xnas",
    mic: "XNAS",
    track: "us",
    feed: "caller-feed",
    currency: "USD",
    sizeUnit: "shares",
    exchangeTimeUnixMilliseconds: 1_000 + sequence,
    providerTimeUnixMilliseconds: 1_000 + sequence,
    receiptTimeUnixMilliseconds: 1_010 + sequence,
    sequence,
    entitlement: { kind: "real_time" },
    licenceReceipt: receipt("a"),
    acquisitionReceipt: receipt("b"),
    conditions: [],
    oddLot: false,
    offExchange: false,
    sourceLexemes: { raw: `caller supplied ${eventId}` },
    ...overrides,
  };
}

function quote(eventId, sequence, overrides = {}) {
  return common(eventId, sequence, "quote", {
    bidPrice: "10.00",
    bidSize: "100",
    askPrice: "10.10",
    askSize: "90",
    ...overrides,
  });
}

function trade(eventId, sequence, price, size, overrides = {}) {
  return common(eventId, sequence, "trade", {
    price,
    size,
    correctionLineage: null,
    ...overrides,
  });
}

function packet(events, overrides = {}) {
  const payload = JSON.stringify({
    schemaVersion: "pi_day_intraday_packet_v1",
    packetId: "packet-1",
    track: "us",
    listingId: "listing-aapl-xnas",
    mic: "XNAS",
    sessionDate: "2026-08-07",
    timezone: "America/New_York",
    provider: "caller-provider",
    feed: "caller-feed",
    currency: "USD",
    sizeUnit: "shares",
    entitlement: { kind: "real_time" },
    licence: {
      label: "caller-private-display",
      receipt: receipt("a"),
      venueCoverage: ["XNAS"],
      redistributionPermitted: false,
      retentionLimit: "session_only",
      displayUse: "private",
      nonDisplayUse: null,
      derivedDataPermitted: true,
      cachingPermitted: false,
      loggingPermitted: false,
      fixtureUsePermitted: true,
    },
    acquisitionReceipt: receipt("b"),
    sequenceScope: "per_listing",
    expectedHeartbeatIntervalMilliseconds: null,
    phases: [
      {
        phase: "continuous",
        startUnixMilliseconds: 1_000,
        endUnixMilliseconds: 2_000,
        ruleReceipt: receipt("c"),
      },
    ],
    declaredComplete: true,
    events,
    ...overrides,
  });
  return { packetPayload: payload, packetHash: sha256(payload) };
}

function inspectInput(evidence, overrides = {}) {
  return {
    ...evidence,
    maximumEvents: 100,
    asOfUnixMilliseconds: 1_500,
    freshnessCutoffUnixMilliseconds: 900,
    includeEvents: true,
    includeSourceLexemes: true,
    offset: 0,
    limit: 100,
    ...overrides,
  };
}

function calculationInput(evidence, calculation = "vwap", overrides = {}) {
  return {
    ...evidence,
    maximumEvents: 100,
    calculation,
    windowStartUnixMilliseconds: 0,
    windowEndUnixMilliseconds: 10_000,
    scale: 4,
    rounding: "half_even",
    eventFilter: {
      includeOddLots: false,
      includeOffExchange: false,
      includedConditionCodes: [],
    },
    ...overrides,
  };
}

function transitionInput(eventKind, transitionId, idempotencyKey, overrides = {}) {
  const payload = JSON.stringify({ declaration: eventKind });
  return {
    workflowId: "workflow-1",
    branchId: "branch-a",
    transitionId,
    idempotencyKey,
    eventKind,
    origin: "user_authored",
    occurredAtUnixMilliseconds: Number(transitionId.slice(1)),
    payload,
    payloadHash: sha256(payload),
    evidenceReferences: [],
    executionReceiptReferences: [],
    ...overrides,
  };
}

describe("day workbench Session 22 boundary", () => {
  test("registers only the three stateless read-only tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "day_inspect",
      "day_calculate",
      "day_transition",
    ]);
    for (const tool of tools.values()) {
      expect(tool.executionMode).toBe("parallel");
    }
  });

  test("inspects exact caller-attested evidence without authenticating it", async () => {
    const tools = await harness();
    const evidence = packet([
      quote("q1", 1),
      trade("t1", 2, "10.05", "20"),
      common("d1", 3, "depth_snapshot", {
        levels: [
          { side: "bid", price: "10", visibleSize: "60", orderCount: 3 },
          { side: "ask", price: "10.1", visibleSize: "40", orderCount: 2 },
        ],
      }),
    ]);
    const result = await execute(tools.get("day_inspect"), inspectInput(evidence));
    expect(result.details).toMatchObject({
      schemaVersion: "pi_day_inspection_v1",
      packetId: "packet-1",
      track: "us",
      mic: "XNAS",
      entitlement: { kind: "real_time" },
      claimVerification: "caller_attested_not_verified",
      phase: { state: "known", phase: "continuous" },
      counts: {
        inputEvents: 3,
        retainedEvents: 3,
        integrityIssues: 0,
      },
      integrity: { current: true },
      evidenceMatrix: {
        quote: "available",
        trade: "available",
        depth: "available",
        verdict: "none_llm_or_user_decides",
      },
      decisionOwner: "llm_or_user",
    });
    expect(result.details.page.events[0]).toMatchObject({
      eventId: "q1",
      type: "quote",
      sourceLexemes: { raw: "caller supplied q1" },
    });
    expect(JSON.stringify(result.details)).toContain("ready_to_trade");
  });

  test("performs exactly one source-bound calculation", async () => {
    const tools = await harness();
    const evidence = packet([
      quote("q1", 1),
      trade("t1", 2, "10", "2"),
      trade("t2", 3, "12", "1"),
    ]);
    const result = await execute(
      tools.get("day_calculate"),
      calculationInput(evidence),
    );
    expect(result.details).toMatchObject({
      schemaVersion: "pi_day_calculation_v1",
      calculation: "vwap",
      scale: 4,
      rounding: "half_even",
      result: {
        state: "calculated",
        exactValue: "10.6667",
        unit: "USD",
        formula: "sum(trade_price * trade_size) / sum(trade_size)",
        sourceEventIds: ["t1", "t2"],
      },
      decisionOwner: "llm_or_user",
    });
    expect(result.details.result.operands).toEqual([
      { eventId: "t1", name: "trade_price", sourceLexeme: "10" },
      { eventId: "t1", name: "trade_size", sourceLexeme: "2" },
      { eventId: "t2", name: "trade_price", sourceLexeme: "12" },
      { eventId: "t2", name: "trade_size", sourceLexeme: "1" },
    ]);
    expect(result.content[0].text).toContain("not a signal");
  });

  test("makes a sequence gap and incomplete packet explicitly unperformed", async () => {
    const tools = await harness();
    const gap = packet([
      trade("t1", 1, "10", "2"),
      trade("t2", 3, "11", "2"),
    ]);
    const gapResult = await execute(
      tools.get("day_calculate"),
      calculationInput(gap, "cumulative_volume"),
    );
    expect(gapResult.details.result).toEqual({
      state: "unperformed",
      reason: "packet_integrity_issues_present",
      sourceEventIds: [],
    });

    const incomplete = packet([trade("t1", 1, "10", "2")], {
      declaredComplete: false,
    });
    const incompleteResult = await execute(
      tools.get("day_calculate"),
      calculationInput(incomplete, "cumulative_volume"),
    );
    expect(incompleteResult.details.result.reason).toBe(
      "packet_declared_incomplete",
    );
  });

  test("advances caller-retained branch state and handles exact retries", async () => {
    const tools = await harness();
    const transition = tools.get("day_transition");
    const initialInput = transitionInput("initialize_preparation", "t1", "k1");
    const initial = await execute(transition, initialInput);
    expect(initial.details).toMatchObject({
      revision: 1,
      state: { name: "preparation" },
      storage: {
        kind: "caller_retained_stateless",
        survivesReload: false,
        writesPerformed: false,
      },
    });

    const acquiringInput = transitionInput("begin_acquisition", "t2", "k2", {
      currentStatePayload: initial.details.nextStatePayload,
      currentStateHash: initial.details.nextStateHash,
      origin: "llm_authored",
    });
    const acquiring = await execute(transition, acquiringInput);
    expect(acquiring.details.state.name).toBe("acquiring");

    const readyInput = transitionInput("evidence_available", "t3", "k3", {
      currentStatePayload: acquiring.details.nextStatePayload,
      currentStateHash: acquiring.details.nextStateHash,
      origin: "mechanical_fact",
      evidenceReferences: [receipt("e")],
    });
    const ready = await execute(transition, readyInput);
    expect(ready.details).toMatchObject({
      revision: 3,
      state: {
        name: "ready",
        meaning: "evidence_available mechanical state; not ready_to_trade",
      },
      idempotent: false,
    });

    const retry = await execute(transition, {
      ...readyInput,
      currentStatePayload: ready.details.nextStatePayload,
      currentStateHash: ready.details.nextStateHash,
    });
    expect(retry.details.idempotent).toBe(true);
    expect(retry.details.nextStateHash).toBe(ready.details.nextStateHash);

    await expect(
      execute(transition, {
        ...readyInput,
        branchId: "branch-b",
      }),
    ).rejects.toThrow("branchId does not match current state");
  });

  test("rejects bad content hashes, missing mechanical evidence, and cancellation", async () => {
    const tools = await harness();
    const evidence = packet([quote("q1", 1)]);
    await expect(
      execute(tools.get("day_inspect"), {
        ...inspectInput(evidence),
        packetHash: receipt("f"),
      }),
    ).rejects.toThrow("packetHash does not match packetPayload");

    const initial = await execute(
      tools.get("day_transition"),
      transitionInput("initialize_preparation", "t1", "k1"),
    );
    const acquiring = await execute(
      tools.get("day_transition"),
      transitionInput("begin_acquisition", "t2", "k2", {
        currentStatePayload: initial.details.nextStatePayload,
        currentStateHash: initial.details.nextStateHash,
      }),
    );
    await expect(
      execute(
        tools.get("day_transition"),
        transitionInput("evidence_available", "t3", "k3", {
          currentStatePayload: acquiring.details.nextStatePayload,
          currentStateHash: acquiring.details.nextStateHash,
          origin: "mechanical_fact",
        }),
      ),
    ).rejects.toThrow("mechanical transition requires evidenceReferences");

    const controller = new AbortController();
    controller.abort();
    await expect(
      execute(tools.get("day_inspect"), inspectInput(evidence), controller.signal),
    ).rejects.toThrow("Day evidence inspection was cancelled");
  });
});
