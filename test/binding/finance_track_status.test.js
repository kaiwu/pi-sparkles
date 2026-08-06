import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/finance_track_status/index.js",
);

function entry(id, track) {
  return {
    type: "custom",
    id,
    parentId: null,
    timestamp: "2026-08-05T00:00:00.000Z",
    customType: "pi_sparkles_finance_track_status.active_track",
    data: track,
  };
}

function context(entries, statuses = [], notifications = []) {
  return {
    mode: "tui",
    hasUI: true,
    sessionManager: {
      getBranch: () => entries,
    },
    ui: {
      setStatus(key, text) {
        statuses.push({ key, text });
      },
      notify(message, kind) {
        notifications.push({ message, kind });
      },
    },
  };
}

async function harness({
  initial = "us",
  contact = "agent@example.test",
  entries = [],
  activeTools = [
    "finance_track_status",
    "finance_capabilities",
    "security_resolve",
    "sec_company_submissions",
    "sec_xbrl_facts",
    "stock_fundamental",
    "stock_fundamental_metric",
    "us_stock_quote",
    "us_stock_ohlcv",
    "us_market_calendar",
    "us_trading_rules",
    "cn_authorities",
    "cn_security_search",
    "cn_market_calendar",
    "cn_trading_rules",
    "cn_disclosure_search",
    "cn_stock_quote",
    "cn_stock_history",
    "cn_financial_statement",
    "cn_stock_fundamental",
    "cn_stock_fundamental_metric",
    "hk_authorities",
    "hk_security_search",
    "hk_market_calendar",
    "hk_trading_rules",
    "hk_disclosure_search",
    "hk_stock_quote",
    "hk_stock_history",
    "hk_financial_statement",
    "hk_stock_fundamental",
    "hk_stock_fundamental_metric",
  ],
} = {}) {
  const commands = new Map();
  const tools = new Map();
  const handlers = new Map();
  const events = [];
  const flags = new Map([
    ["finance-track", initial],
    ["finance-agent-contact", contact],
  ]);
  let nextId = entries.length;
  const api = {
    events: {
      emit(channel, data) {
        events.push({ channel, data });
      },
    },
    registerFlag(name, options) {
      if (!flags.has(name)) flags.set(name, options.default);
    },
    getFlag(name) {
      return flags.get(name);
    },
    getActiveTools() {
      return activeTools;
    },
    registerCommand(name, options) {
      commands.set(name, options);
    },
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    on(name, handler) {
      handlers.set(name, handler);
    },
    appendEntry(customType, data) {
      nextId += 1;
      entries.push(entry(`track-${nextId}`, data));
      entries.at(-1).customType = customType;
    },
  };
  const module = await import(
    `${artifact}?track=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return { commands, entries, events, handlers, tools };
}

describe("finance track status binding", () => {
  test("renders and switches all three isolated track profiles", async () => {
    const instance = await harness();
    const statuses = [];
    const ctx = context(instance.entries, statuses);

    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      ctx,
    );
    expect(statuses.at(-1).text).toBe(
      "US · USD · America/New_York · src:80% · feat:100% · agent:agent@example.test",
    );

    for (const [command, expected] of [
      [
        "cn-track",
        "CN · CNY · Asia/Shanghai · src:65% · feat:100% · agent:agent@example.test",
      ],
      [
        "hk-track",
        "HK · HKD · Asia/Hong_Kong · src:70% · feat:100% · agent:agent@example.test",
      ],
      [
        "us-track",
        "US · USD · America/New_York · src:80% · feat:100% · agent:agent@example.test",
      ],
    ]) {
      await instance.commands.get(command).handler("", ctx);
      expect(statuses.at(-1).text).toBe(expected);
    }

    expect(instance.entries.map(({ data }) => data)).toEqual([
      "cn",
      "hk",
      "us",
    ]);
    expect(instance.events.map(({ data }) => data)).toEqual([
      "us",
      "cn",
      "hk",
      "us",
    ]);
  });

  test("restores the active branch and exposes structured headless status", async () => {
    const entries = [entry("track-1", "cn"), entry("track-2", "hk")];
    const instance = await harness({ entries });
    const ctx = context(entries);
    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "resume" },
      ctx,
    );

    const result = await instance.tools.get("finance_track_status").execute(
      "status-1",
      {},
      new AbortController().signal,
      undefined,
      { hasUI: false, ui: {} },
    );
    expect(result.details.track).toBe("hk");
    expect(result.details.currency).toBe("HKD");
    expect(result.details.timezone).toBe("Asia/Hong_Kong");
    expect(result.details.agentContact).toBe("agent@example.test");
    expect(result.details.trackContext.track).toBe("hk");
    expect(result.details.sourceCredibilityPercentage).toBe(70);
    expect(result.details.featureCoveragePercentage).toBe(100);
    expect(result.details.sourceCredibility.meaning).toBe(
      "evidence_maturity_not_truth_probability",
    );
    expect(result.details.sourceCredibility.scoreBasisPoints).toBe(7000);
    expect(result.details.sourceCredibility.criterionCount).toBe(10);
    expect(result.details.sourceCredibility.calculation).toBe(
      "equal_weight_mean_verified_10000_partial_5000_missing_0",
    );
    expect(result.details.sourceCredibility.readiness).toBe(
      "limited_credibility",
    );
    expect(result.details.sourceCredibility.criticalGaps).toEqual([
      "freshness_receipt",
      "semantic_decoder",
      "entitlement_and_licence",
    ]);
    expect(result.details.featureCoverage.meaning).toBe(
      "installed_end_user_feature_coverage_not_data_completeness",
    );
    expect(result.details.featureCoverage.requirementCount).toBe(10);
    expect(result.details.featureCoverage.coveredCount).toBe(10);
    expect(result.details.featureCoverage.calculation).toBe(
      "set_union_covered_requirements_over_declared_requirements",
    );
    expect(result.details.featureCoverage.missingRequirements).not.toContain(
      "market_calendar",
    );
    expect(result.details.featureCoverage.missingRequirements).not.toContain(
      "effective_rules",
    );
    expect(result.details.featureCoverage.missingRequirements).toEqual([]);
  });

  test("typed tool switching persists and invalid slash input is rejected visibly", async () => {
    const instance = await harness();
    const notifications = [];
    const ctx = context(instance.entries, [], notifications);

    const result = await instance.tools.get("finance_track_switch").execute(
      "switch-1",
      { track: "cn" },
      new AbortController().signal,
      undefined,
      ctx,
    );
    expect(result.details.track).toBe("cn");
    expect(instance.entries.at(-1).data).toBe("cn");

    await expect(
      instance.tools.get("finance_track_switch").execute(
        "switch-bad",
        { track: "global" },
        new AbortController().signal,
        undefined,
        ctx,
      ),
    ).rejects.toThrow("cn, hk, or us track");

    await instance.commands.get("finance-track").handler("CN", ctx);
    expect(notifications.at(-1)).toEqual({
      kind: "error",
      message: "Unknown finance track 'CN'; use cn, hk, or us",
    });
  });

  test("malformed branch state and contact fail visibly", async () => {
    const entries = [entry("track-bad", "global")];
    const instance = await harness({
      initial: "cn",
      contact: "bad\ncontact",
      entries,
    });
    const statuses = [];
    const notifications = [];
    const ctx = context(entries, statuses, notifications);

    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "resume" },
      ctx,
    );
    expect(statuses.at(-1).text).toBe(
      "CN · CNY · Asia/Shanghai · src:65% · feat:100% · agent:invalid-contact",
    );
    expect(notifications.at(-1)).toEqual({
      kind: "warning",
      message:
        "Finance track state could not be restored; using configured cn track",
    });

    const result = await instance.tools.get("finance_track_status").execute(
      "status-invalid",
      {},
      new AbortController().signal,
      undefined,
      { hasUI: false, ui: {} },
    );
    expect(result.details.configurationValid).toBeFalse();
  });

  test("tools from sibling tracks cannot inflate active-track coverage", async () => {
    const instance = await harness({
      initial: "cn",
      activeTools: [
        "finance_track_status",
        "finance_capabilities",
        "security_resolve",
        "sec_company_submissions",
        "sec_xbrl_facts",
        "stock_fundamental",
        "stock_fundamental_metric",
      ],
    });
    const statuses = [];
    const ctx = context(instance.entries, statuses);

    await instance.handlers.get("session_start")(
      { type: "session_start", reason: "startup" },
      ctx,
    );

    expect(statuses.at(-1).text).toBe(
      "CN · CNY · Asia/Shanghai · src:65% · feat:10% · agent:agent@example.test",
    );
    const result = await instance.tools.get("finance_track_status").execute(
      "status-isolated",
      {},
      new AbortController().signal,
      undefined,
      { hasUI: false, ui: {} },
    );
    expect(result.details.featureCoverage.coveredRequirements).toEqual([
      "navigation_context",
    ]);
    expect(result.details.featureCoverage.criticalGaps).toEqual([
      "source_registry",
      "security_identity",
    ]);
  });
});
