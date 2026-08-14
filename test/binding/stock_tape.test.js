import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/stock_tape/index.js");
const hash = (character) => character.repeat(64);

async function harness() {
  const tools = new Map();
  const module = await import(`${artifact}?stock-tape=${Date.now()}-${Math.random()}`);
  await module.default({
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  });
  return tools;
}

function event(eventId, sequence, overrides = {}) {
  return {
    eventId,
    tradeId: `trade-${eventId}`,
    kind: { state: "original", referenceEventId: null, referenceTradeId: null },
    price: { state: "known", value: "10.5000", values: [], reason: null },
    size: { state: "known", value: "100", values: [], reason: null },
    conditionCodes: ["regular"],
    venueLexeme: "fixture-venue",
    clocks: {
      exchangeUnixMilliseconds: 100,
      providerUnixMilliseconds: 101,
      retrievedUnixMilliseconds: 102,
    },
    sequence: {
      state: "sequenced",
      scope: "listing",
      value: sequence,
      values: [],
      declaredPrevious: null,
      reason: null,
    },
    rawReceiptHash: hash("b"),
    ...overrides,
  };
}

function input(overrides = {}) {
  return {
    track: "us",
    listingId: "listing:AAPL:XNAS",
    mic: "XNAS",
    sessionId: "2026-08-14-rth",
    provider: "explicit-fixture-capability",
    feed: "transaction-ticker",
    entitlement: "caller-owned-read-only",
    licence: "internal-test-only",
    providerReceiptHash: hash("a"),
    coverage: {
      state: "bounded_partial",
      referenceHash: null,
      reason: "bounded fixture window",
    },
    conditionCoverage: {
      state: "documented",
      codes: ["regular"],
      referenceHash: hash("c"),
      reason: null,
    },
    maximumEvents: 100,
    events: [event("e1", "10"), event("e2", "12")],
    page: { offset: 0, limit: 100 },
    ...overrides,
  };
}

async function execute(tool, value, signal = new AbortController().signal) {
  return tool.execute("stock-tape-review", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("explicit-provider transaction tape", () => {
  test("registers one network-free, dependency-explicit tool", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_tape must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["stock_tape"]);
      const result = await execute(tools.get("stock_tape"), input());
      expect(requests).toBe(0);
      expect(result.details.providerCapability).toMatchObject({
        dependencyMode: "explicit_external_capability",
        networkPerformed: false,
        credentialAccepted: false,
        openDRequiredByPackage: false,
        adapterBundled: false,
      });
      expect(result.details.review.sequenceIssues[0]).toMatchObject({
        kind: "gap",
        expected: "11",
        received: "12",
      });
      expect(result.details.tapeReceiptHash).toHaveLength(64);
      expect(result.details.executable).toBeFalse();
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("retains correction lineage and stable paging", async () => {
    const correction = event("e2", "11", {
      kind: {
        state: "correction",
        referenceEventId: "e1",
        referenceTradeId: "trade-e1",
      },
    });
    const tools = await harness();
    const result = await execute(
      tools.get("stock_tape"),
      input({ events: [event("e1", "10"), correction], page: { offset: 1, limit: 1 } }),
    );
    expect(result.details.page).toMatchObject({ returned: 1, total: 2, nextOffset: null });
    expect(result.details.events[0]).toMatchObject({ eventId: "e2", kind: { state: "correction" } });
    expect(result.details.review.lineageIssues).toEqual([]);
  });

  test("fails closed across tracks and on cancellation", async () => {
    const tools = await harness();
    await expect(execute(tools.get("stock_tape"), input({ track: "cn" }))).rejects.toThrow(
      "outside the exact cn tape scope",
    );
    const controller = new AbortController();
    controller.abort();
    await expect(execute(tools.get("stock_tape"), input(), controller.signal)).rejects.toThrow(
      "cancelled",
    );
  });
});
