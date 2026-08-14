import { describe, expect, test } from "bun:test";

import {
  allowlistedTrackRightsEvidence,
  validateTrackRightsConfig,
} from "../../scripts/futu-track-rights-probe.js";

describe("Futu track quote-right probe", () => {
  test("requires one explicit localhost-only live query", () => {
    const environment = {
      FUTU_RIGHTS_CONFIRM: "I_ACCEPT_ONE_FUTU_TRACK_RIGHTS_QUERY",
      FUTU_OPEND_HOST: "127.0.0.1",
      FUTU_OPEND_WEBSOCKET_PORT: "33333",
    };
    expect(() => validateTrackRightsConfig(["--live"], environment)).not.toThrow();
    expect(() =>
      validateTrackRightsConfig(["--live"], {
        ...environment,
        FUTU_OPEND_HOST: "192.0.2.1",
      }),
    ).toThrow("non_localhost_endpoint_forbidden");
  });

  test("emits only the four current track-owned right fields", () => {
    const evidence = allowlistedTrackRightsEvidence({
      s2c: {
        shQotRight: 2,
        szQotRight: 2,
        hkQotRight: 3,
        usQotRight: 3,
        cnQotRight: 5,
        userID: { toString: () => "secret-user-id" },
        nickName: "secret-name",
        webKey: "secret-key",
        subQuota: 100,
      },
    });
    expect(evidence.quoteRights.map(({ track, mic, value, meaning }) => ({
      track,
      mic,
      value,
      meaning,
    }))).toEqual([
      { track: "cn", mic: "XSHG", value: 2, meaning: "level_1" },
      { track: "cn", mic: "XSHE", value: 2, meaning: "level_1" },
      { track: "hk", mic: "XHKG", value: 3, meaning: "level_2" },
      { track: "us", mic: "futu_generic_us_market", value: 3, meaning: "level_2" },
    ]);
    const serialized = JSON.stringify(evidence);
    expect(serialized).not.toContain("cnQotRight");
    expect(serialized).not.toContain("secret-user-id");
    expect(serialized).not.toContain("secret-name");
    expect(serialized).not.toContain("secret-key");
    expect(serialized).not.toContain("subQuota");
  });

  test("hard-codes one rights protocol and no subscription or trade method", async () => {
    const source = await Bun.file(
      new URL("../../scripts/futu-track-rights-probe.js", import.meta.url),
    ).text();
    expect(source).toContain("const getUserInfoCommand = 1005;");
    expect(source).toContain("const quoteRightsOnlyFlag = 4;");
    expect(source).not.toMatch(/client\.(?:Sub|UnlockTrade|PlaceOrder|ModifyOrder|GetTicker)/);
  });
});
