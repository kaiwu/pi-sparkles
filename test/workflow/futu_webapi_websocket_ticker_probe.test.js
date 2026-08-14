import { describe, expect, test } from "bun:test";

import {
  assertTickerOnlyControlFrame,
  authFrame,
  directWebSocketLimits,
  summarizeWebSocketAggregate,
  tickerControlFrame,
  tickerPushOrdering,
  tickerRows,
  validateWebSocketProbeConfig,
} from "../../scripts/futu-webapi-websocket-ticker-probe.js";
import { parseJsonWithExactSequences } from "../../scripts/futu-webapi-ticker-probe.js";

describe("Futu direct ticker-only WebSocket blocker probe", () => {
  test("allows only the reviewed HK live leg", () => {
    const environment = {
      FUTU_WEBAPI_CONFIRM: "I_ACCEPT_ONE_FUTU_DIRECT_TICKER_WEBSOCKET",
    };
    expect(
      validateWebSocketProbeConfig(
        ["--live", "--track", "hk", "--mic", "XHKG"],
        environment,
        new Date("2026-08-14T02:45:00.000Z"),
      ),
    ).toMatchObject({ live: true, track: "hk", mic: "XHKG" });
    expect(() =>
      validateWebSocketProbeConfig(
        ["--live", "--track", "cn", "--mic", "XSHG"],
        environment,
        new Date("2026-08-14T02:45:00.000Z"),
      ),
    ).toThrow("only_reviewed_hk_leg_allowed");
  });

  test("builds OAuth auth and ticker-only control frames", () => {
    expect(authFrame("ephemeral-token")).toEqual({
      id: "t6-auth-1",
      action: "auth",
      data: {
        auth_type: "oauth2",
        authorization: "Bearer ephemeral-token",
      },
    });
    expect(tickerControlFrame("subscribe")).toEqual({
      id: "t6-sub-1",
      action: "subscribe",
      ticker: ["HK.00700"],
    });
    expect(tickerControlFrame("unsubscribe")).toEqual({
      id: "t6-unsub-1",
      action: "unsubscribe",
      ticker: ["HK.00700"],
    });
    expect(() =>
      assertTickerOnlyControlFrame({
        id: "bad",
        action: "subscribe",
        ticker: ["HK.00700"],
        order_book: ["HK.00700"],
      }),
    ).toThrow("non_ticker_control_forbidden");
  });

  test("decodes exact ticker rows without retaining price or size", () => {
    const message = parseJsonWithExactSequences(
      '{"type":"TICKER","symbol":"HK.00700","data":{"ticker_list":[{"time_ms":1710000000123,"sequence":7647056964060558023,"direction":"BUY","price":320.2,"volume":100,"turnover":32020,"type":"AUTO_MATCH"}]}}',
    );
    const rows = tickerRows(message);
    expect(rows).toEqual([
      {
        sequence: 7_647_056_964_060_558_023n,
        timeMs: 1_710_000_000_123,
        direction: "BUY",
        tickerType: "AUTO_MATCH",
      },
    ]);
    expect(JSON.stringify(rows, (_, value) => typeof value === "bigint" ? String(value) : value)).not.toContain("320.2");
  });

  test("accepts a push after request but before acknowledgement", () => {
    expect(tickerPushOrdering(true, false)).toBe("before_ack");
    expect(tickerPushOrdering(true, true)).toBe("after_ack");
    expect(() => tickerPushOrdering(false, false)).toThrow(
      "ticker_before_subscription",
    );
  });

  test("summarizes stream evidence without raw sequences or times", () => {
    const summary = summarizeWebSocketAggregate(
      {
        events: 2,
        sequences: [100n, 102n],
        eventTimes: [1_000, 1_001],
        directions: { BUY: 1, SELL: 1, NEUTRAL: 0, UNKNOWN: 0, other: 0 },
        knownTickerTypes: 2,
        unknownTickerTypes: 0,
      },
      1_100,
    );
    expect(summary.sequence.receiveOrderIncreases).toBe(1);
    expect(summary.sequence.maximumAbsoluteDelta).toBe("2");
    expect(JSON.stringify(summary)).not.toContain("102");
  });

  test("has one connection and no retry or reconnect", () => {
    expect(directWebSocketLimits.connections).toBe(1);
    expect(directWebSocketLimits.symbols).toBe(1);
    expect(directWebSocketLimits.dataTypes).toEqual(["ticker"]);
    expect(directWebSocketLimits.retries).toBe(0);
    expect(directWebSocketLimits.reconnects).toBe(0);
    expect(directWebSocketLimits.queueCapacity).toBe(512);
  });
});
