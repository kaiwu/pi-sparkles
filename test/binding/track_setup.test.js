import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_setup/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_setup/index.js"),
};

async function harness(track, activeTools = []) {
  const commands = new Map();
  const tools = new Map();
  const api = {
    registerCommand(name, options) {
      commands.set(name, options);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    getActiveTools() {
      return activeTools;
    },
  };
  const module = await import(
    `${artifacts[track]}?setup=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { commands, tools };
}

function commandContext(notifications) {
  return {
    mode: "tui",
    hasUI: true,
    ui: {
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

describe("isolated CN/HK setup bindings", () => {
  test("capability results expose exact tracks and honest blocked states", async () => {
    for (const [track, currency, timezone] of [
      ["cn", "CNY", "Asia/Shanghai"],
      ["hk", "HKD", "Asia/Hong_Kong"],
    ]) {
      const siblingTools =
        track === "cn"
          ? ["hk_stock_symbols", "sec_company_search"]
          : ["cn_stock_symbols", "sec_company_search"];
      const instance = await harness(track, siblingTools);
      const result = await instance.tools.get(`${track}_capabilities`).execute(
        `${track}-capabilities`,
        {},
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      );

      expect(result.details.track).toBe(track);
      expect(result.details.trackContext.track).toBe(track);
      expect(result.details.currency).toBe(currency);
      expect(result.details.timezone).toBe(timezone);
      expect(result.details.capabilities[0].state).toBe("experimental");
      expect(
        result.details.capabilities.some(
          ({ state }) => state === "missing_dependency",
        ),
      ).toBeTrue();
      expect(
        result.details.capabilities.some(
          ({ state }) => state === "blocked_decision",
        ),
      ).toBeTrue();
      expect([...instance.tools.keys()].sort()).toEqual([
        `${track}_authorities`,
        `${track}_capabilities`,
        `${track}_provider_health`,
      ]);
    }
  });

  test("track-owned discovery tools advance only matching setup capabilities", async () => {
    for (const track of ["cn", "hk"]) {
      const ownTools = [
        `${track}_security_search`,
        `${track}_market_calendar`,
        `${track}_trading_rules`,
        `${track}_disclosure_search`,
        `${track}_stock_quote`,
        `${track}_stock_history`,
        `${track}_financial_statement`,
        `${track}_stock_fundamental`,
        `${track}_stock_fundamental_metric`,
      ];
      const sibling = track === "cn" ? "hk" : "cn";
      const instance = await harness(track, [
        ...ownTools,
        `${sibling}_security_search`,
        `${sibling}_market_calendar`,
        `${sibling}_trading_rules`,
        `${sibling}_disclosure_search`,
        `${sibling}_stock_quote`,
        `${sibling}_stock_history`,
        `${sibling}_financial_statement`,
        `${sibling}_stock_fundamental`,
        `${sibling}_stock_fundamental_metric`,
      ]);
      const result = await instance.tools.get(`${track}_capabilities`).execute(
        `${track}-capabilities-discovery`,
        {},
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      );
      const byTool = new Map(
        result.details.capabilities.map((value) => [value.requiredTool, value]),
      );
      expect(byTool.get(`${track}_security_search`).state).toBe("experimental");
      expect(byTool.get(`${track}_market_calendar`).state).toBe("experimental");
      expect(byTool.get(`${track}_trading_rules`).state).toBe("experimental");
      expect(byTool.get(`${track}_stock_quote`).state).toBe("experimental");
      expect(byTool.get(`${track}_stock_history`).state).toBe("experimental");
      expect(byTool.get(`${track}_disclosure_search`).state).toBe(
        "experimental",
      );
      expect(byTool.get(`${track}_financial_statement`).state).toBe(
        "experimental",
      );
      expect(byTool.get(`${track}_stock_fundamental`).state).toBe(
        "experimental",
      );
      expect(byTool.get(`${track}_stock_fundamental_metric`).state).toBe(
        "experimental",
      );
      expect(byTool.has(`${sibling}_security_search`)).toBeFalse();
      expect(byTool.has(`${sibling}_market_calendar`)).toBeFalse();
      expect(byTool.has(`${sibling}_trading_rules`)).toBeFalse();
      expect(byTool.has(`${sibling}_stock_quote`)).toBeFalse();
      expect(byTool.has(`${sibling}_stock_history`)).toBeFalse();
      expect(byTool.has(`${sibling}_disclosure_search`)).toBeFalse();
      expect(byTool.has(`${sibling}_financial_statement`)).toBeFalse();
      expect(byTool.has(`${sibling}_stock_fundamental`)).toBeFalse();
      expect(byTool.has(`${sibling}_stock_fundamental_metric`)).toBeFalse();
    }
  });

  test("unknown providers remain unknown and blank names reject", async () => {
    const instance = await harness("cn", ["sec_company_search"]);
    const result = await instance.tools.get("cn_provider_health").execute(
      "cn-provider",
      { provider: "unapproved" },
      new AbortController().signal,
      undefined,
      { hasUI: false, ui: {} },
    );
    expect(result.details.track).toBe("cn");
    expect(result.details.provider.state).toBe("unknown");

    await expect(
      instance.tools.get("cn_provider_health").execute(
        "cn-provider-empty",
        { provider: "" },
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      ),
    ).rejects.toThrow("valid provider name");
  });

  test("slash setup output is visibly track-labelled", async () => {
    for (const track of ["cn", "hk"]) {
      const instance = await harness(track);
      const notifications = [];
      await instance.commands
        .get(`${track}-setup`)
        .handler("", commandContext(notifications));
      expect(notifications).toHaveLength(1);
      expect(notifications[0].message.startsWith(track.toUpperCase())).toBeTrue();
    }
  });

  test("authority tools and source commands expose exact isolated official sources", async () => {
    for (const [track, expectedId, siblingPrefix] of [
      ["cn", "cn_csrc", "hk_"],
      ["hk", "hk_sfc", "cn_"],
    ]) {
      const instance = await harness(track);
      const result = await instance.tools.get(`${track}_authorities`).execute(
        `${track}-authorities`,
        {},
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      );
      expect(result.details.track).toBe(track);
      expect(result.details.trackContext.marketScope).toBe(
        `${track}_authorities`,
      );
      expect(result.details.authorities[0].id).toBe(expectedId);
      expect(
        result.details.authorities.every(({ id, officialUrl, access }) =>
          id.startsWith(`${track}_`) &&
          !id.startsWith(siblingPrefix) &&
          officialUrl.startsWith("https://") &&
          typeof access === "string"
        ),
      ).toBeTrue();
      expect(
        result.details.authorities.some(
          ({ access }) => access !== "verified_reference",
        ),
      ).toBeTrue();

      const notifications = [];
      await instance.commands
        .get(`${track}-sources`)
        .handler("", commandContext(notifications));
      expect(notifications).toHaveLength(1);
      expect(notifications[0].message.startsWith(track.toUpperCase())).toBeTrue();
      expect(notifications[0].message).toContain("does not imply unrestricted automation");
    }
  });
});
