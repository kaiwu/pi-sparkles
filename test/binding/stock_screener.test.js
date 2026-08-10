import { createHash } from "node:crypto";
import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/stock_screener/index.js");
const originalFetch = globalThis.fetch;
const requests = [];

const assets =
  '[{"id":"asset-aapl","class":"us_equity","exchange":"NASDAQ","symbol":"AAPL","name":"Apple Inc. Common Stock","status":"active","tradable":true,"marginable":true,"shortable":true,"easy_to_borrow":true,"fractionable":true,"attributes":["has_options"]},{"id":"asset-msft","class":"us_equity","exchange":"NASDAQ","symbol":"MSFT","name":"Microsoft Corporation","status":"inactive","tradable":false,"marginable":true,"shortable":false,"easy_to_borrow":false,"fractionable":true,"attributes":[]}]';

beforeEach(() => {
  requests.length = 0;
  process.env.ALPACA_API_KEY_ID = "test-key-id";
  process.env.ALPACA_API_SECRET_KEY = "test-secret-key";
  process.env.ALPACA_USER_AGENT_CONTACT = "universe@example.test";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    return new Response(assets, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": "assets-request-one",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  delete process.env.ALPACA_API_KEY_ID;
  delete process.env.ALPACA_API_SECRET_KEY;
  delete process.env.ALPACA_USER_AGENT_CONTACT;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-screener=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, maximumAssets = 10) {
  return tool.execute(
    "stock-universe-query",
    {
      environment: "paper",
      status: "active",
      exchange: "NASDAQ",
      maximumAssets,
    },
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("stock universe Alpaca boundary", () => {
  test("copies bounded asset-master rows and makes no screening decision", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "stock_universe",
      "project_universe",
      "screen",
    ]);

    const result = await execute(tools.get("stock_universe"));
    const sourceReference =
      "https://paper-api.alpaca.markets/v2/assets?status=active&asset_class=us_equity&exchange=NASDAQ";

    expect(result.details.track).toBe("us");
    expect(result.details.trackContext.marketScope).toBe("us_stock_universe");
    expect(result.details.provider).toBe("alpaca");
    expect(result.details.environment).toBe("paper");
    expect(result.details.filters).toEqual({
      status: "active",
      assetClass: "us_equity",
      exchange: "NASDAQ",
    });
    expect(result.details.sourceReference).toBe(sourceReference);
    expect(result.details.requestId).toBe("assets-request-one");
    expect(result.details.rowBudget).toEqual({
      maximum: 10,
      received: 2,
      outcome: "within_bound",
    });
    expect(result.details.rows.map((row) => row.symbol)).toEqual([
      "AAPL",
      "MSFT",
    ]);
    expect(result.details.rows[1]).toMatchObject({
      providerMembership: "provider_returned_row",
      status: "inactive",
      tradable: false,
      shortable: false,
    });
    expect(result.details.decisionOwner).toBe("llm");
    expect(result.details.pluginDecisionFields).toEqual([]);
    expect(result.details.sourceReceipt).toBe(sha256(assets));
    expect(result.details.universeReceipt).toBe(
      sha256(`${sourceReference}\n${assets}`),
    );
    expect(JSON.stringify(result.details)).not.toContain("test-secret-key");
    expect(JSON.stringify(result.details)).not.toMatch(
      /"(rank|qualified|selected|recommended)"/,
    );

    expect(requests).toHaveLength(1);
    expect(requests[0].url.hostname).toBe("paper-api.alpaca.markets");
    expect(requests[0].url.pathname).toBe("/v2/assets");
    expect(requests[0].url.searchParams.get("status")).toBe("active");
    expect(requests[0].url.searchParams.get("asset_class")).toBe(
      "us_equity",
    );
    expect(requests[0].url.searchParams.get("exchange")).toBe("NASDAQ");
    expect(requests[0].headers.get("apca-api-key-id")).toBe("test-key-id");
    expect(requests[0].headers.get("apca-api-secret-key")).toBe(
      "test-secret-key",
    );
  });

  test("fails rather than truncating a response beyond the caller row budget", async () => {
    const tools = await harness();
    await expect(execute(tools.get("stock_universe"), 1)).rejects.toThrow(
      "over-budget asset array",
    );
  });

  test("projects exact caller-supplied point-in-time membership without fetching", async () => {
    const tools = await harness();
    const { universe } = canonicalManifests();
    const result = await tools.get("project_universe").execute(
      "project-universe-query",
      {
        track: "us",
        effectiveDate: "2026-02-24",
        knowledgeCutoffUnixMilliseconds: 1000,
        universe,
        page: { partition: "all", offset: 0, limit: 10 },
      },
      new AbortController().signal,
      undefined,
      { hasUI: false, ui: {} },
    );

    expect(result.details.operation).toBe("project_universe");
    expect(result.details.manifest).toMatchObject({
      manifestId: "universe-us",
      track: "us",
      membershipEventCount: 3,
    });
    expect(result.details.query).toMatchObject({
      track: "us",
      effectiveDate: "2026-02-24",
      knowledgeCutoffUnixMilliseconds: 1000,
      membershipEndPolicy: "inclusive_end_v1",
    });
    expect(result.details.relationCounts).toEqual({
      member: 3,
      notMember: 0,
      unresolved: 0,
      total: 3,
    });
    expect(result.details.rows.map((row) => row.listingId)).toEqual([
      "listing:A",
      "listing:B",
      "listing:C",
    ]);
    expect(result.details.rows.every((row) => row.relation === "member")).toBe(
      true,
    );
    expect(result.details.decisionOwner).toBe("llm");
    expect(result.details.pluginDecisionFields).toEqual([]);
    expect(requests).toHaveLength(0);
  });

  test("calculates exact predicates and preserves unresolved rows without fetching", async () => {
    const tools = await harness();
    const { universe, dataset, observationHashes } = canonicalManifests();
    const base = {
      context: {
        instructionRef: sha256("screen instruction"),
        track: "us",
        dateStart: "2026-02-01",
        dateEnd: "2026-02-28",
        sourceCutoffUnixMilliseconds: 1000,
        universe,
        dataset,
        technicalReceiptRoots: [],
      },
      predicates: [
        {
          id: "close-above-10",
          leftOperand: { kind: "field", field: "close", unit: "price" },
          operator: "greater_than",
          rightOperand: { kind: "constant", raw: "10", unit: "price" },
        },
      ],
      rows: [
        screenRow("listing:A", "obs-a", observationHashes["obs-a"], {
          state: "known",
          raw: "12.00",
          alternatives: [],
        }),
        screenRow("listing:B", "obs-b", observationHashes["obs-b"], {
          state: "known",
          raw: "8",
          alternatives: [],
        }),
        screenRow("listing:C", "obs-c", observationHashes["obs-c"], {
          state: "unknown",
          reason: "provider field absent",
          alternatives: [],
        }),
      ],
      relation: {
        matchPolicy: "all_predicates_observed_true_v1",
        unresolvedPolicy: "preserve_unresolved_separately_v1",
      },
      page: { partition: "all", offset: 0, limit: 10 },
    };

    const first = await tools
      .get("screen")
      .execute(
        "screen-query",
        base,
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      );
    expect(first.details.relationCounts).toEqual({
      matched: 1,
      notMatched: 1,
      unresolved: 1,
      total: 3,
    });
    expect(first.details.rows.map((row) => row.relation)).toEqual([
      "matched",
      "not_matched",
      "unresolved",
    ]);
    expect(first.details.rows[0].predicateFacts[0].fact).toMatchObject({
      state: "observed_true",
      raw: "12.00",
      normalized: "12",
    });
    expect(first.details.rows[2].predicateFacts[0].fact).toEqual({
      state: "unavailable",
      reason: "unknown:provider field absent",
    });
    expect(first.details.decisionOwner).toBe("llm");
    expect(first.details.pluginDecisionFields).toEqual([]);
    expect(requests).toHaveLength(0);

    const second = await tools
      .get("screen")
      .execute(
        "screen-query-unresolved",
        { ...base, page: { partition: "unresolved", offset: 0, limit: 10 } },
        new AbortController().signal,
        undefined,
        { hasUI: false, ui: {} },
      );
    expect(second.details.rows).toHaveLength(1);
    expect(second.details.rows[0].listingId).toBe("listing:C");
    expect(second.details.requestReceiptHandle).toBe(
      first.details.requestReceiptHandle,
    );
    expect(second.details.semanticReceiptHandle).toBe(
      first.details.semanticReceiptHandle,
    );
  });
});

function screenRow(listingId, observationId, evidenceRoot, fact) {
  return {
    listingId,
    mic: "XNAS",
    observationDate: "2026-02-24",
    observationId,
    values: [
      {
        field: "close",
        unit: "price",
        sourceKind: "dataset_observation",
        knownAtUnixMilliseconds: 500,
        evidenceRoots: [evidenceRoot],
        fact,
      },
    ],
  };
}

function canonicalManifests() {
  const date = (year, month, day) => ({ year, month, day });
  const start = date(2026, 2, 1);
  const end = date(2026, 2, 28);
  const listingStart = date(2020, 1, 1);
  const observationDate = date(2026, 2, 24);
  const observationHashes = {
    "obs-a": sha256("obs-a"),
    "obs-b": sha256("obs-b"),
    "obs-c": sha256("obs-c"),
  };
  const memberships = ["A", "B", "C"].map((suffix) => ({
    listing_id: `listing:${suffix}`,
    mic: "XNAS",
    track: "us",
    symbol: { state: "known", value: suffix },
    symbol_interval: {
      state: "known",
      value: { start: listingStart, end: null },
    },
    listing_interval: { start: listingStart, end: null },
    security_class: { state: "known", value: "common_stock" },
    status_interval: {
      state: "known",
      value: { start: listingStart, end: null },
    },
    membership_effective: listingStart,
    membership_end: { state: "not_applicable", reason: "open membership" },
    publication_time: { state: "known", value: 90 },
    knowledge_time: { state: "known", value: 100 },
    retrieval_time_unix_ms: 200,
    source_receipt: sha256(`membership:${suffix}`),
    correction_lineage: [],
    state: { state: "known" },
  }));
  const universeContent = {
    schema: "finance_replay_universe_manifest",
    schema_version: 1,
    decision_owner: "llm",
    manifest_id: "universe-us",
    version: "1.0.0",
    track: "us",
    definition_kind: { kind: "exact_enumerated" },
    as_of_time_unix_ms: 900,
    coverage: { start, end },
    source_receipt: sha256("universe-source"),
    provenance: "caller_declared",
    limitations: ["fixture point-in-time membership"],
    memberships,
    plugin_decision_fields: [],
  };
  const universeHash = sha256(JSON.stringify(universeContent));
  const observations = ["a", "b", "c"].map((suffix) => {
    const id = `obs-${suffix}`;
    return {
      observation_id: id,
      listing_id: `listing:${suffix.toUpperCase()}`,
      mic: "XNAS",
      track: "us",
      observation_date: observationDate,
      observation_time: { state: "known", value: 300 },
      publication_time: { state: "known", value: 310 },
      availability_time: { state: "known", value: 320 },
      knowledge_time: { state: "known", value: 330 },
      retrieval_time_unix_ms: 400,
      source_cutoff: { state: "known", value: 1000 },
      correction_vintage: { state: "known", value: "original" },
      correction_lineage: [],
      session_type: { state: "known", value: "regular_full" },
      calendar_ref: { state: "known", value: sha256("calendar") },
      status_ref: { state: "known", value: sha256("status") },
      unit: { state: "known", value: "price" },
      currency: { state: "known", value: "USD" },
      scale: { state: "known", value: 4 },
      timezone: { state: "known", value: "America/New_York" },
      adjustment_basis: { state: "known", value: "raw" },
      quantity_semantics: { state: "known", value: "shares" },
      entitlement: { state: "known", value: "fixture-access" },
      licence: { state: "unknown", reason: "terms not supplied" },
      state: { state: "known", value: "reported" },
      content_hash: observationHashes[id],
      corporate_action_refs: [],
      transformation_refs: [],
    };
  });
  const datasetContent = {
    schema: "finance_replay_dataset_manifest",
    schema_version: 1,
    decision_owner: "llm",
    manifest_id: "dataset-us",
    version: "1.0.0",
    provider: "fixture-provider",
    source_or_import_provenance: "fixture://daily-bars",
    track: "us",
    coverage: { start, end },
    observations,
    limitations: ["fixture observations"],
    plugin_decision_fields: [],
  };
  const datasetHash = sha256(JSON.stringify(datasetContent));
  return {
    universe: {
      manifestJson: JSON.stringify({
        payload: { content: universeContent, content_hash: universeHash },
        canonical_content_hash: universeHash,
      }),
      manifestHash: universeHash,
    },
    dataset: {
      manifestJson: JSON.stringify({
        payload: { content: datasetContent, content_hash: datasetHash },
        canonical_content_hash: datasetHash,
      }),
      manifestHash: datasetHash,
    },
    observationHashes,
  };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}
