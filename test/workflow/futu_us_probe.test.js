import { describe, expect, test } from "bun:test";
import {
  createTickerCollector,
  observedEnumSemantics,
  probeLimits,
  recoveryEvidence,
  summarizeSubscriptionStatus,
  validatePreflight,
  validateProbeConfig,
  validateReleasedStatus,
  validateSubscribedStatus,
} from "../../scripts/futu-us-ticker-probe.js";

const openUsSession = new Date("2026-08-13T16:00:00.000Z");

describe("Futu US blocker probe configuration", () => {
  test("contains only the two allowed quote methods and no trade or history calls", async () => {
    const source = await Bun.file(
      new URL("../../scripts/futu-us-ticker-probe.js", import.meta.url),
    ).text();
    expect(source).toContain("client.GetSubInfo(");
    expect(source).toContain("client.Sub(");
    expect(source).not.toMatch(/client\.(?:UnlockTrade|PlaceOrder|ModifyOrder|GetTicker|RequestHistory)/);
    expect(source).not.toContain("child_process");
  });

  test("is inert without the explicit live argument", () => {
    expect(validateProbeConfig([], {}, openUsSession)).toEqual({
      live: false,
      symbol: null,
      mic: null,
      expectedDate: null,
      sessionKind: null,
      now: openUsSession,
    });
  });

  test("requires a reviewed date, exact confirmation, US identity, and localhost", () => {
    const environment = {
      FUTU_PROBE_SYMBOL: "US.AAPL",
      FUTU_PROBE_MIC: "XNAS",
      FUTU_PROBE_EXPECTED_US_DATE: "2026-08-13",
      FUTU_LIVE_CONFIRM: "I_ACCEPT_ONE_FUTU_US_TICKER_SUBSCRIPTION",
      FUTU_OPEND_HOST: "127.0.0.1",
      FUTU_OPEND_WEBSOCKET_PORT: "33333",
    };

    expect(validateProbeConfig(["--live"], environment, openUsSession)).toMatchObject({
      live: true,
      symbol: "US.AAPL",
      mic: "XNAS",
      expectedDate: "2026-08-13",
      sessionKind: "regular",
    });
    expect(() =>
      validateProbeConfig(
        ["--live"],
        { ...environment, FUTU_OPEND_HOST: "192.0.2.10" },
        openUsSession,
      ),
    ).toThrow("non_localhost_endpoint_forbidden");
    expect(() =>
      validateProbeConfig(
        ["--live"],
        { ...environment, FUTU_LIVE_CONFIRM: "yes" },
        openUsSession,
      ),
    ).toThrow("live_confirmation_missing");
  });

  test("fails closed outside the guarded regular-session window", () => {
    expect(() =>
      validateProbeConfig(
        ["--live"],
        {
          FUTU_PROBE_SYMBOL: "US.IBM",
          FUTU_PROBE_MIC: "XNYS",
          FUTU_PROBE_EXPECTED_US_DATE: "2026-08-13",
          FUTU_LIVE_CONFIRM: "I_ACCEPT_ONE_FUTU_US_TICKER_SUBSCRIPTION",
        },
        new Date("2026-08-13T13:30:00.000Z"),
      ),
    ).toThrow("outside_guarded_regular_session_window");
  });

  test("allows only a reviewed pre/post-market window for extended mode", () => {
    const environment = {
      FUTU_PROBE_SYMBOL: "US.AAPL",
      FUTU_PROBE_MIC: "XNAS",
      FUTU_PROBE_EXPECTED_US_DATE: "2026-08-13",
      FUTU_PROBE_SESSION: "extended",
      FUTU_LIVE_CONFIRM: "I_ACCEPT_ONE_FUTU_US_TICKER_SUBSCRIPTION",
    };
    expect(
      validateProbeConfig(
        ["--live"],
        environment,
        new Date("2026-08-13T22:10:00.000Z"),
      ),
    ).toMatchObject({ sessionKind: "extended" });
    expect(() =>
      validateProbeConfig(
        ["--live"],
        environment,
        new Date("2026-08-13T16:00:00.000Z"),
      ),
    ).toThrow("outside_guarded_extended_session_window");
  });
});

describe("Futu subscription quota guards", () => {
  test("requires zero existing subscriptions and at least ninety units", () => {
    const status = summarizeSubscriptionStatus(subscriptionStatus(0, 100, []));
    expect(() => validatePreflight(status)).not.toThrow();
    const omittedEmptyConnection = summarizeSubscriptionStatus({
      s2c: { totalUsedQuota: 0, remainQuota: 100, connSubInfoList: [] },
    });
    expect(() => validatePreflight(omittedEmptyConnection)).not.toThrow();

    expect(() =>
      validatePreflight(
        summarizeSubscriptionStatus(
          subscriptionStatus(1, 99, [{ market: 11, code: "REDACTED", subtype: 4 }]),
        ),
      ),
    ).toThrow("existing_subscription_detected");
    expect(() =>
      validatePreflight(summarizeSubscriptionStatus(subscriptionStatus(0, 89, []))),
    ).toThrow("remaining_quota_below_guard");
  });

  test("proves exactly one owned ticker subscription and exact release", () => {
    const before = summarizeSubscriptionStatus(subscriptionStatus(0, 100, []));
    const during = summarizeSubscriptionStatus(
      subscriptionStatus(1, 99, [{ market: 11, code: "AAPL", subtype: 4 }]),
    );
    const after = summarizeSubscriptionStatus(subscriptionStatus(0, 100, []));

    expect(() => validateSubscribedStatus(before, during, "AAPL")).not.toThrow();
    expect(() => validateSubscribedStatus(before, during, "IBM")).toThrow(
      "subscription_not_exactly_one_ticker",
    );
    expect(validateReleasedStatus(before, after)).toBeTrue();
  });
});

describe("Futu ticker evidence redaction and bounds", () => {
  test("does not mistake a JavaScript reconnect for provider recovery evidence", () => {
    expect(recoveryEvidence({ enums: { pushDataType: { "1": 5 } } })).toMatchObject({
      reconnectExercised: false,
      providerDisconnectObserved: false,
      supplementedEvents: 0,
      replay: { status: "unavailable_as_complete_replay_contract" },
      resetRule: { status: "unknown" },
      gapRecovery: { status: "not_observed" },
    });
    expect(recoveryEvidence({ enums: { pushDataType: { "2": 7 } } })).toMatchObject({
      providerDisconnectObserved: true,
      supplementedEvents: 7,
      replay: { status: "unavailable_as_complete_replay_contract" },
      resetRule: { status: "unknown" },
      gapRecovery: { status: "partial" },
    });
  });

  test("maps only documented vendor enums and keeps typeSign opaque", () => {
    expect(
      observedEnumSemantics({
        direction: { "1": 3, "9": 1 },
        tickerType: { "1": 2, "6": 4, "24": 1, "99": 1 },
        pushDataType: { "1": 6, "2": 1 },
      }),
    ).toEqual({
      authority: "Futu quotation definitions; vendor classification, not exchange authority",
      direction: { "1": "futu_documented_active_buy", "9": "unknown_lexeme" },
      tickerType: {
        "1": "regular_sale",
        "6": "odd_lot_trade",
        "24": "average_price_trade",
        "99": "unknown_lexeme",
      },
      pushDataType: {
        "1": "realtime",
        "2": "backend_disconnect_supplement_up_to_50",
      },
      tickerTypeSign: "opaque_undocumented_int32_preserved_as_lexeme",
    });
  });

  test("retains only aggregates, sequence digests, enum counts, and clock summaries", () => {
    let wallMs = 1_723_737_600_500;
    let monotonicMs = 10_000;
    const collector = createTickerCollector("AAPL", {
      wallMs: () => wallMs,
      monotonicMs: () => monotonicMs,
    });
    collector.start();
    collector.ingest(3011, tickerPush("AAPL", [ticker("100", 1_723_737_600)]));
    wallMs += 5;
    monotonicMs += 5;
    collector.ingest(3011, tickerPush("AAPL", [ticker("102", 1_723_737_600.001)]));
    wallMs += 5;
    monotonicMs += 5;
    collector.ingest(3011, tickerPush("AAPL", [ticker("102", 1_723_737_600.002)]));
    wallMs += 5;
    monotonicMs += 5;
    collector.ingest(3011, tickerPush("AAPL", [ticker("101", 1_723_737_600.003)]));
    collector.stopAccepting();

    const summary = collector.summary();
    const serialized = JSON.stringify(summary);
    expect(summary.decodedEvents).toBe(4);
    expect(summary.sequence.duplicates).toBe(1);
    expect(summary.sequence.decreases).toBe(1);
    expect(summary.sequence.positiveJumpsGreaterThanOne).toBe(1);
    expect(summary.sequence.largestPositiveDelta).toBe("2");
    expect(summary.sequence.firstDigest).toHaveLength(64);
    expect(summary.enums.direction).toEqual({ "1": 4 });
    expect(summary.enums.pushDataType).toEqual({ "1": 4 });
    expect(serialized).not.toContain("AAPL");
    expect(serialized).not.toContain("189.125");
    expect(serialized).not.toContain('"100"');
  });

  test("uses a bounded queue and fails closed on a mismatched identity", () => {
    let monotonicMs = 0;
    const collector = createTickerCollector("AAPL", {
      wallMs: () => 1_723_737_600_000,
      monotonicMs: () => monotonicMs,
    });
    collector.start();
    const tickers = Array.from({ length: probeLimits.queueCapacity + 1 }, (_, index) =>
      ticker(String(index + 1), 1_723_737_600),
    );
    collector.ingest(3011, tickerPush("AAPL", tickers));
    collector.ingest(3011, tickerPush("IBM", [ticker("900", 1_723_737_600)]));
    monotonicMs += 1;
    collector.stopAccepting();

    const summary = collector.summary();
    expect(summary.queue.highWater).toBe(probeLimits.queueCapacity);
    expect(summary.queue.dropped).toBe(1);
    expect(summary.pushSafety.wrongIdentityPushes).toBe(1);
    expect(summary.fatalCode).toBe("consumer_queue_overflow");

    const identityCollector = createTickerCollector("AAPL", {
      wallMs: () => 1_723_737_600_000,
      monotonicMs: () => monotonicMs,
    });
    identityCollector.start();
    identityCollector.ingest(
      3011,
      tickerPush("IBM", [ticker("900", 1_723_737_600)]),
    );
    identityCollector.stopAccepting();
    expect(identityCollector.summary().fatalCode).toBe("push_identity_mismatch");
  });
});

function subscriptionStatus(used, remaining, pairs) {
  const grouped = new Map();
  for (const pair of pairs) {
    const list = grouped.get(pair.subtype) ?? [];
    list.push({ market: pair.market, code: pair.code });
    grouped.set(pair.subtype, list);
  }
  return {
    s2c: {
      totalUsedQuota: used,
      remainQuota: remaining,
      connSubInfoList: [
        {
          isOwnConnData: true,
          usedQuota: used,
          subInfoList: [...grouped.entries()].map(([subType, securityList]) => ({
            subType,
            securityList,
          })),
        },
      ],
    },
  };
}

function tickerPush(code, tickerList) {
  return {
    retType: 0,
    s2c: {
      security: { market: 11, code },
      tickerList,
    },
  };
}

function ticker(sequence, timestamp) {
  return {
    time: "2026-08-13 12:00:00.001",
    sequence: { toString: () => sequence },
    dir: 1,
    price: 189.125,
    volume: { toString: () => "100" },
    turnover: 18_912.5,
    recvTime: timestamp + 0.01,
    type: 1,
    typeSign: 0,
    pushDataType: 1,
    timestamp,
  };
}
