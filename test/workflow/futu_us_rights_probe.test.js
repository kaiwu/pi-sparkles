import { describe, expect, test } from "bun:test";
import {
  allowlistedRightsEvidence,
  validateRightsConfig,
} from "../../scripts/futu-us-rights-probe.js";

describe("Futu US quote-right probe", () => {
  test("requires explicit confirmation and localhost", () => {
    const environment = {
      FUTU_RIGHTS_CONFIRM: "I_ACCEPT_ONE_FUTU_US_RIGHTS_QUERY",
      FUTU_OPEND_HOST: "127.0.0.1",
      FUTU_OPEND_WEBSOCKET_PORT: "33333",
    };
    expect(() => validateRightsConfig(["--live"], environment)).not.toThrow();
    expect(() =>
      validateRightsConfig(["--live"], {
        ...environment,
        FUTU_OPEND_HOST: "192.0.2.1",
      }),
    ).toThrow("non_localhost_endpoint_forbidden");
  });

  test("emits only an allowlisted quote-right enum", () => {
    const evidence = allowlistedRightsEvidence({
      s2c: {
        usQotRight: 3,
        userID: { toString: () => "secret-user-id" },
        nickName: "secret-name",
        webKey: "secret-key",
        subQuota: 100,
      },
    });
    expect(evidence.usQuoteRight).toEqual({
      value: 3,
      meaning: "level_2",
      authority: "OpenD GetUserInfo QotRight enum",
      feedCompositionAuthenticated: false,
    });
    const serialized = JSON.stringify(evidence);
    expect(serialized).not.toContain("secret-user-id");
    expect(serialized).not.toContain("secret-name");
    expect(serialized).not.toContain("secret-key");
    expect(serialized).not.toContain("subQuota");
  });

  test("hard-codes one non-trading protocol and no subscription methods", async () => {
    const source = await Bun.file(
      new URL("../../scripts/futu-us-rights-probe.js", import.meta.url),
    ).text();
    expect(source).toContain("const getUserInfoCommand = 1005;");
    expect(source).toContain("const quoteRightsOnlyFlag = 4;");
    expect(source).not.toMatch(/client\.(?:Sub|UnlockTrade|PlaceOrder|ModifyOrder|GetTicker)/);
  });
});
