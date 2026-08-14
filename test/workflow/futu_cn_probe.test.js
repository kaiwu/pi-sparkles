import { describe, expect, test } from "bun:test";

import { validateCnProbeConfig } from "../../scripts/futu-cn-ticker-probe.js";
import {
  buildSubscriptionRequest,
  createTickerCollector,
  summarizeSubscriptionStatus,
  validateSubscribedStatus,
} from "../../scripts/futu-us-ticker-probe.js";

const openCnSession = new Date("2026-08-14T01:30:00.000Z");
const baseEnvironment = Object.freeze({
  FUTU_PROBE_SYMBOL: "SH.600519",
  FUTU_PROBE_MIC: "XSHG",
  FUTU_PROBE_EXPECTED_CN_DATE: "2026-08-14",
  FUTU_LIVE_CONFIRM: "I_ACCEPT_ONE_FUTU_CN_TICKER_SUBSCRIPTION",
  FUTU_OPEND_HOST: "127.0.0.1",
  FUTU_OPEND_WEBSOCKET_PORT: "33333",
});

describe("Futu CN blocker probe configuration", () => {
  test("is inert without the explicit live argument", () => {
    expect(validateCnProbeConfig([], {}, openCnSession)).toEqual({
      live: false,
      symbol: null,
      mic: null,
      expectedDate: null,
      now: openCnSession,
    });
  });

  test("accepts only the two repository-reviewed venue anchors", () => {
    expect(
      validateCnProbeConfig(["--live"], baseEnvironment, openCnSession),
    ).toMatchObject({
      track: "cn",
      mic: "XSHG",
      symbol: "SH.600519",
      providerMarket: 21,
      includeSessionFields: false,
      eventTimeTimezone: "Asia/Shanghai",
      listingScope: "ordinary_main_board_a_share",
      unsupportedVenues: ["XBSE"],
    });
    expect(
      validateCnProbeConfig(
        ["--live"],
        {
          ...baseEnvironment,
          FUTU_PROBE_SYMBOL: "SZ.000001",
          FUTU_PROBE_MIC: "XSHE",
        },
        openCnSession,
      ),
    ).toMatchObject({ mic: "XSHE", providerMarket: 22 });
    expect(() =>
      validateCnProbeConfig(
        ["--live"],
        { ...baseEnvironment, FUTU_PROBE_SYMBOL: "SH.601398" },
        openCnSession,
      ),
    ).toThrow("unreviewed_cn_anchor");
  });

  test("fails closed before continuous trading, at lunch, and off localhost", () => {
    expect(() =>
      validateCnProbeConfig(
        ["--live"],
        baseEnvironment,
        new Date("2026-08-14T01:29:00.000Z"),
      ),
    ).toThrow("outside_guarded_cn_continuous_session_window");
    expect(() =>
      validateCnProbeConfig(
        ["--live"],
        baseEnvironment,
        new Date("2026-08-14T04:00:00.000Z"),
      ),
    ).toThrow("outside_guarded_cn_continuous_session_window");
    expect(() =>
      validateCnProbeConfig(
        ["--live"],
        { ...baseEnvironment, FUTU_OPEND_HOST: "192.0.2.10" },
        openCnSession,
      ),
    ).toThrow("non_localhost_endpoint_forbidden");
  });

  test("contains no provider calls beyond the shared guarded quote lifecycle", async () => {
    const source = await Bun.file(
      new URL("../../scripts/futu-cn-ticker-probe.js", import.meta.url),
    ).text();
    expect(source).not.toMatch(/(?:UnlockTrade|PlaceOrder|ModifyOrder|GetTicker|RequestHistory)/);
    expect(source).not.toContain("child_process");
  });
});

describe("Futu CN venue quota proof", () => {
  test("builds CN requests without US-only session fields", () => {
    expect(
      buildSubscriptionRequest(
        "600519",
        true,
        { includeSessionFields: false },
        21,
      ),
    ).toEqual({
      c2s: {
        securityList: [{ market: 21, code: "600519" }],
        subTypeList: [4],
        isSubOrUnSub: true,
        isRegOrUnRegPush: true,
        isFirstPush: false,
      },
    });
  });

  test("matches the exact provider market for each venue", () => {
    const before = summarizeSubscriptionStatus(subscriptionStatus(0, 100, []));
    const shanghai = summarizeSubscriptionStatus(
      subscriptionStatus(1, 99, [{ market: 21, code: "600519", subtype: 4 }]),
    );
    const shenzhen = summarizeSubscriptionStatus(
      subscriptionStatus(1, 99, [{ market: 22, code: "000001", subtype: 4 }]),
    );
    expect(() =>
      validateSubscribedStatus(before, shanghai, "600519", 21),
    ).not.toThrow();
    expect(() =>
      validateSubscribedStatus(before, shenzhen, "000001", 22),
    ).not.toThrow();
    expect(() =>
      validateSubscribedStatus(before, shenzhen, "000001", 21),
    ).toThrow("subscription_not_exactly_one_ticker");
  });

  test("rejects cross-venue pushes and labels the CN event clock", () => {
    const collector = createTickerCollector(
      "600519",
      { wallMs: () => 1_723_737_600_000, monotonicMs: () => 1 },
      21,
      "Asia/Shanghai",
    );
    collector.start();
    collector.ingest(3011, {
      retType: 0,
      s2c: {
        security: { market: 22, code: "600519" },
        tickerList: [],
      },
    });
    collector.stopAccepting();
    expect(collector.summary()).toMatchObject({
      clocks: { eventTimeTimezone: "Asia/Shanghai" },
      pushSafety: { wrongIdentityPushes: 1 },
      fatalCode: "push_identity_mismatch",
    });
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
