import { describe, expect, test } from "bun:test";

import { validateHkProbeConfig } from "../../scripts/futu-hk-ticker-probe.js";
import {
  buildSubscriptionRequest,
  createTickerCollector,
  summarizeSubscriptionStatus,
  validateSubscribedStatus,
} from "../../scripts/futu-us-ticker-probe.js";

const openHkSession = new Date("2026-08-14T01:30:00.000Z");
const environment = Object.freeze({
  FUTU_PROBE_SYMBOL: "HK.00700",
  FUTU_PROBE_MIC: "XHKG",
  FUTU_PROBE_EXPECTED_HK_DATE: "2026-08-14",
  FUTU_LIVE_CONFIRM: "I_ACCEPT_ONE_FUTU_HK_TICKER_SUBSCRIPTION",
  FUTU_OPEND_HOST: "127.0.0.1",
  FUTU_OPEND_WEBSOCKET_PORT: "33333",
});

describe("Futu HK blocker probe", () => {
  test("is inert without --live and accepts only the reviewed XHKG anchor", () => {
    expect(validateHkProbeConfig([], {}, openHkSession)).toEqual({
      live: false,
      symbol: null,
      mic: null,
      expectedDate: null,
      now: openHkSession,
    });
    expect(validateHkProbeConfig(["--live"], environment, openHkSession)).toMatchObject({
      track: "hk",
      mic: "XHKG",
      symbol: "HK.00700",
      providerMarket: 1,
      eventTimeTimezone: "Asia/Hong_Kong",
      listingScope: "ordinary_main_board_share",
    });
    expect(() =>
      validateHkProbeConfig(
        ["--live"],
        { ...environment, FUTU_PROBE_SYMBOL: "HK.00941" },
        openHkSession,
      ),
    ).toThrow("unreviewed_hk_anchor");
  });

  test("allows only HKEX continuous hours with time left for cleanup", () => {
    expect(() =>
      validateHkProbeConfig(
        ["--live"],
        environment,
        new Date("2026-08-14T01:29:00.000Z"),
      ),
    ).toThrow("outside_guarded_hk_continuous_session_window");
    expect(() =>
      validateHkProbeConfig(
        ["--live"],
        environment,
        new Date("2026-08-14T04:30:00.000Z"),
      ),
    ).toThrow("outside_guarded_hk_continuous_session_window");
  });

  test("uses one HK ticker pair and omits US session fields", () => {
    expect(
      buildSubscriptionRequest("00700", true, { includeSessionFields: false }, 1),
    ).toEqual({
      c2s: {
        securityList: [{ market: 1, code: "00700" }],
        subTypeList: [4],
        isSubOrUnSub: true,
        isRegOrUnRegPush: true,
        isFirstPush: false,
      },
    });
    const before = summarizeSubscriptionStatus(status(0, 100, []));
    const during = summarizeSubscriptionStatus(
      status(1, 99, [{ market: 1, code: "00700", subtype: 4 }]),
    );
    expect(() => validateSubscribedStatus(before, during, "00700", 1)).not.toThrow();
  });

  test("rejects cross-market pushes and retains only aggregate evidence", () => {
    const collector = createTickerCollector(
      "00700",
      { wallMs: () => 1_723_737_600_000, monotonicMs: () => 1 },
      1,
      "Asia/Hong_Kong",
    );
    collector.start();
    collector.ingest(3011, {
      retType: 0,
      s2c: { security: { market: 11, code: "00700" }, tickerList: [] },
    });
    collector.stopAccepting();
    expect(collector.summary()).toMatchObject({
      clocks: { eventTimeTimezone: "Asia/Hong_Kong" },
      pushSafety: { wrongIdentityPushes: 1 },
      fatalCode: "push_identity_mismatch",
    });
  });

  test("contains no trade, history, snapshot, or child-process call", async () => {
    const source = await Bun.file(
      new URL("../../scripts/futu-hk-ticker-probe.js", import.meta.url),
    ).text();
    expect(source).not.toMatch(/(?:UnlockTrade|PlaceOrder|ModifyOrder|GetTicker|RequestHistory)/);
    expect(source).not.toContain("child_process");
  });
});

function status(used, remaining, pairs) {
  return {
    s2c: {
      totalUsedQuota: used,
      remainQuota: remaining,
      connSubInfoList: [{
        isOwnConnData: true,
        usedQuota: used,
        subInfoList: pairs.length === 0 ? [] : [{
          subType: pairs[0].subtype,
          securityList: pairs.map(({ market, code }) => ({ market, code })),
        }],
      }],
    },
  };
}
