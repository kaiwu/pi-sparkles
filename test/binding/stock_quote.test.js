import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/stock_quote/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-quote=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function input(overrides = {}) {
  return {
    track: "hk",
    listing: {
      listingId: "listing:00700:XHKG",
      mic: "XHKG",
      symbol: "00700",
    },
    quote: {
      providerTimestamp: "2026-08-10T10:00:00.123456789+08:00",
      asOfUnixMilliseconds: 1_786_332_000_123,
      retrievedAtUnixMilliseconds: 1_786_332_001_000,
      currency: "HKD",
      bid: { exchange: "XHKG", rawPrice: "612.5000", rawSize: "100.00" },
      ask: { exchange: "XHKG", rawPrice: "613.0000", rawSize: "200" },
      conditionCodes: ["NORMAL"],
      tape: "MAIN",
      sizeUnit: "provider_reported_unverified",
    },
    source: {
      provider: "licensed-fixture-adapter",
      reference: "https://example.test/hk/quote?symbol=00700",
      kind: "licensed_vendor",
      otherKind: null,
      feed: "fixture-level-one",
      entitlement: { state: "delayed", delayMilliseconds: 900_000 },
      licence: {
        label: "fixture-local-analysis",
        redistribution: "no_redistribution",
        notes: "caller supplied",
      },
      receiptHash: "a".repeat(64),
    },
    ...overrides,
  };
}

async function execute(tool, value) {
  return tool.execute(
    "stock-quote-inspection",
    value,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("provider-neutral stock quote boundary", () => {
  test("registers one stateless tool and retains exact three-track quote facts", async () => {
    const originalFetch = globalThis.fetch;
    let requests = 0;
    globalThis.fetch = async () => {
      requests += 1;
      throw new Error("stock_quote must not fetch");
    };
    try {
      const tools = await harness();
      expect([...tools.keys()]).toEqual(["stock_quote"]);

      const result = await execute(tools.get("stock_quote"), input());
      expect(result.details.track).toBe("hk");
      expect(result.details.trackContext).toMatchObject({
        marketScope: "hk_stock_quote",
        venueMic: "XHKG",
        timezone: "Asia/Hong_Kong",
        entitlement: "declared_delayed",
      });
      expect(result.details.listing).toEqual({
        listingId: "listing:00700:XHKG",
        mic: "XHKG",
        symbol: "00700",
        identityStatus: "caller_supplied_unverified",
      });
      expect(result.details.observation.bid).toEqual({
        exchange: "XHKG",
        rawPrice: "612.5000",
        normalizedPrice: "612.5",
        rawSize: "100.00",
        normalizedSize: "100",
      });
      expect(result.details.observation.entitlement).toEqual({
        state: "delayed",
        delayMilliseconds: 900_000,
        status: "caller_or_provider_adapter_declared_unverified",
      });
      expect(result.details.observation.evidenceId).toBe("a".repeat(64));
      expect(result.details.source).toMatchObject({
        provider: "licensed-fixture-adapter",
        feed: "fixture-level-one",
        receiptHash: "a".repeat(64),
        receiptBinding: "caller_supplied_unverified",
      });
      expect(result.details.licence.redistribution).toBe("no_redistribution");
      expect(result.details.unknownFacts).toContain("freshness");
      expect(result.details.conflictAssessment).toBe(
        "not_performed_single_observation",
      );
      expect(result.details.decisionOwner).toBe("llm");
      expect(result.details.pluginDecisionFields).toEqual([]);
      expect(requests).toBe(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("fails closed on track-MIC mismatch and invalid entitlement shape", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("stock_quote"), input({
        track: "us",
      })),
    ).rejects.toThrow("listing.mic");

    const value = input();
    value.source.entitlement = { state: "delayed", delayMilliseconds: null };
    await expect(execute(tools.get("stock_quote"), value)).rejects.toThrow(
      "source.entitlement",
    );
  });

  test("redacts source secrets before returning details", async () => {
    const tools = await harness();
    const value = input();
    value.source.reference =
      "https://user:password@example.test/quote?api_key=do-not-leak#fragment";
    const result = await execute(tools.get("stock_quote"), value);
    const details = JSON.stringify(result.details);
    expect(details).not.toContain("do-not-leak");
    expect(details).not.toContain("user:password");
    expect(details).not.toContain("#fragment");
    expect(result.details.source.referenceRedacted).toBe(true);
  });
});
