import { describe, expect, test } from "bun:test";

import {
  assertTickerOnlyUrl,
  directTickerLimits,
  parseJsonWithExactSequences,
  providerErrorCategory,
  summarizeTickerResponse,
  tickerRequestUrl,
  validateDirectTickerConfig,
} from "../../scripts/futu-webapi-ticker-probe.js";

describe("Futu direct transaction-ticker blocker probe", () => {
  test("accepts only reviewed live track anchors and explicit confirmation", () => {
    const environment = {
      FUTU_WEBAPI_CONFIRM: "I_ACCEPT_ONE_FUTU_DIRECT_TICKER_REQUEST",
    };
    const now = new Date("2026-08-14T02:45:00.000Z");
    expect(
      validateDirectTickerConfig(
        ["--live", "--track", "cn", "--mic", "XSHG"],
        environment,
        now,
      ),
    ).toMatchObject({ live: true, track: "cn", mic: "XSHG" });
    expect(() =>
      validateDirectTickerConfig(
        ["--live", "--track", "cn", "--mic", "XBSE"],
        environment,
        now,
      ),
    ).toThrow("unreviewed_track_anchor");
    expect(() =>
      validateDirectTickerConfig(
        ["--live", "--track", "cn", "--mic", "XSHG"],
        { ...environment, FUTU_ACCESS_TOKEN: "ambient-secret" },
        now,
      ),
    ).toThrow("ambient_secret_forbidden");
  });

  test("constructs only the fixed rt-ticker endpoint", () => {
    const url = tickerRequestUrl("HK.00700");
    expect(url.origin).toBe("https://webapi.futunn.com");
    expect(url.pathname).toBe("/api/v1.0/quote/HK.00700/rt-ticker");
    expect(url.search).toBe("?num=10");
    expect(assertTickerOnlyUrl(url)).toBeTrue();
    expect(() =>
      assertTickerOnlyUrl(
        "https://webapi.futunn.com/api/v1.0/quote/HK.00700/order-book?num=10",
      ),
    ).toThrow("non_ticker_endpoint_forbidden");
    expect(() =>
      assertTickerOnlyUrl(
        "https://webapi.futunn.com/api/v1.0/quote/HK.00700/stock-quote?num=10",
      ),
    ).toThrow("non_ticker_endpoint_forbidden");
  });

  test("preserves sequence int64 lexemes without altering string contents", () => {
    const parsed = parseJsonWithExactSequences(
      '{"note":"\\\"sequence\\\":123","ticker_list":[{"sequence":7647056964060558023}]}',
    );
    expect(parsed.note).toBe('"sequence":123');
    expect(parsed.ticker_list[0].sequence).toBe("7647056964060558023");
  });

  test("summarizes ticker evidence without raw market values", () => {
    const body = parseJsonWithExactSequences(JSON.stringify({
      ret_code: 0,
      ret_msg: "success text must not survive",
      data: {
        code: "HK.00700",
        name: "identity must not survive",
        ticker_list: [
          {
            sequence: "7647056964060558023",
            time: 1_000,
            price: 612.5,
            volume: 100,
            turnover: 61_250,
            ticker_direction: "BUY",
            tick_type: "AUTO_MATCH",
            period_type: "NORMAL",
            trade_type: " ",
          },
          {
            sequence: "7647056964060558022",
            time: 1_001,
            price: 612.4,
            volume: 200,
            turnover: 122_480,
            ticker_direction: "SELL",
            tick_type: "AUTO_MATCH",
            period_type: "NORMAL",
            trade_type: "U",
          },
        ],
      },
    }));
    const summary = summarizeTickerResponse(body, "HK.00700", 1_100);
    expect(summary.eventCount).toBe(2);
    expect(summary.sequence.responseOrderDecreases).toBe(1);
    expect(summary.tradeTypeCounts.documentedUsCancelU).toBe(1);
    const serialized = JSON.stringify(summary);
    for (const forbidden of [
      "HK.00700",
      "identity must not survive",
      "success text must not survive",
      "612.5",
      "7647056964060558023",
    ]) {
      expect(serialized).not.toContain(forbidden);
    }
  });

  test("uses one bounded request with no retry or redirect", () => {
    expect(directTickerLimits).toEqual({
      requests: 1,
      retries: 0,
      redirects: 0,
      tickerCount: 10,
      maximumResponseBytes: 256 * 1024,
      requestTimeoutMs: 10_000,
    });
  });

  test("classifies provider failures without retaining provider text", () => {
    expect(providerErrorCategory("invalid_token")).toBe("authentication");
    expect(providerErrorCategory("insufficient_permission")).toBe("permission");
    expect(providerErrorCategory("too_many_requests")).toBe("rate_limit");
    expect(providerErrorCategory("provider-specific-value")).toBe("other");
    expect(providerErrorCategory(undefined)).toBe("unavailable");
    expect(() =>
      summarizeTickerResponse(
        {
          ret_code: -9,
          ret_msg: "sensitive provider message",
          error: { code: "invalid_token" },
        },
        "HK.00700",
        1_000,
      ),
    ).toThrow("provider_rejected_request");
  });
});
