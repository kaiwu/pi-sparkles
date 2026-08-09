import { createHash } from "node:crypto";
import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/finance_dataset/index.js");

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?finance-dataset=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

const sha = (value) =>
  createHash("sha256").update(value, "utf8").digest("hex");
const date = (year, month, day) => ({ year, month, day });
const known = (value) => ({ state: "known", value });
const unknown = (reason) => ({ state: "unknown", reason });
const notObtained = (reason) => ({ state: "not_obtained", reason });
const conflicting = (alternatives, reason) => ({
  state: "conflicting",
  alternatives,
  reason,
});

function observation({
  id,
  day,
  availability,
  knowledge,
  vintage,
  lineage = [],
  state = known("reported"),
  track = "us",
}) {
  return {
    observation_id: id,
    listing_id: "listing:A",
    mic: "XNAS",
    track,
    observation_date: date(2026, 2, day),
    observation_time: known(90),
    publication_time: known(95),
    availability_time: availability,
    knowledge_time: knowledge,
    retrieval_time_unix_ms: 300,
    source_cutoff: known(250),
    correction_vintage: vintage,
    correction_lineage: lineage,
    session_type: known("regular_full"),
    calendar_ref: known(sha("calendar")),
    status_ref: known(sha("status")),
    unit: known("price"),
    currency: known("USD"),
    scale: known(4),
    timezone: known("America/New_York"),
    adjustment_basis: known("raw"),
    quantity_semantics: known("shares"),
    entitlement: known("fixture-access"),
    licence: unknown("licence terms not supplied"),
    state,
    content_hash: sha(id),
    corporate_action_refs: [sha("corporate-action")],
    transformation_refs: [sha("transformation")],
  };
}

function manifestFixture({
  source = "fixture://daily-bars",
  observationTrack = "us",
} = {}) {
  const originalHash = sha("obs-original");
  const payload = {
    schema: "finance_replay_dataset_manifest",
    schema_version: 1,
    decision_owner: "llm",
    manifest_id: "dataset-us",
    version: "1.0.0",
    provider: "fixture-provider",
    source_or_import_provenance: source,
    track: "us",
    coverage: { start: date(2026, 2, 1), end: date(2026, 2, 28) },
    observations: [
      observation({
        id: "obs-original",
        day: 24,
        availability: known(100),
        knowledge: known(110),
        vintage: known("original"),
        track: observationTrack,
      }),
      observation({
        id: "obs-corrected",
        day: 24,
        availability: known(200),
        knowledge: known(210),
        vintage: known("corrected"),
        lineage: [originalHash],
        state: known("corrected"),
        track: observationTrack,
      }),
      observation({
        id: "obs-uncertain",
        day: 26,
        availability: unknown("provider availability time absent"),
        knowledge: notObtained("knowledge receipt absent"),
        vintage: conflicting(
          ["original", "corrected"],
          "two supplied vintage labels",
        ),
        state: unknown("provider row state unavailable"),
        track: observationTrack,
      }),
    ],
    limitations: ["fixture includes one supplied omission projection"],
    plugin_decision_fields: [],
  };
  const digest = sha(JSON.stringify(payload));
  const envelope = {
    payload: { content: payload, content_hash: digest },
    canonical_content_hash: digest,
  };
  return { manifestJson: JSON.stringify(envelope), manifestHash: digest };
}

function datasetFixture(options = {}) {
  const manifest = manifestFixture(options);
  return {
    ...manifest,
    omissions: [
      {
        listingId: "listing:A",
        observationDate: "2026-02-25",
        state: "provider_omission",
        evidenceReference:
          options.evidenceReference ?? sha("gap-evidence"),
      },
    ],
    receiptRoots: [sha("receipt-root")],
  };
}

async function execute(tool, input) {
  return tool.execute(
    "finance-dataset-query",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

describe("finance dataset bundled boundary", () => {
  test("supports the compact manifest to observation to vintage routine", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "inspect_dataset",
      "drill_observation",
      "list_vintages",
    ]);
    const dataset = datasetFixture();

    const inspected = await execute(tools.get("inspect_dataset"), { dataset });
    expect(inspected.details).toMatchObject({
      operation: "inspect_dataset",
      manifest: {
        manifestId: "dataset-us",
        track: "us",
        coverage: { start: "2026-02-01", end: "2026-02-28" },
        sourceReferenceRedacted: false,
      },
      manifestHandle: dataset.manifestHash,
      counts: {
        observations: 3,
        distinctListingIds: 1,
        distinctObservationDates: 2,
        suppliedOmissions: 1,
        correctionLineageLinks: 1,
        factStates: {
          observationState: { known: 2, unknown: 1 },
          availabilityTime: { known: 2, unknown: 1 },
          knowledgeTime: { known: 2, notObtained: 1 },
          correctionVintage: { known: 2, conflicting: 1 },
        },
      },
      omissionSummary: { total: 1, providerOmission: 1 },
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });

    const drilled = await execute(tools.get("drill_observation"), {
      dataset,
      listingId: "listing:A",
      observationDate: "2026-02-24",
      offset: 0,
      limit: 10,
    });
    expect(drilled.details.manifestHandle).toBe(inspected.details.manifestHandle);
    expect(drilled.details.inspectionProjectionHandle).toBe(
      inspected.details.inspectionProjectionHandle,
    );
    expect(drilled.details.entries.map((entry) => entry.kind)).toEqual([
      "observation",
      "observation",
    ]);
    expect(
      drilled.details.entries.map((entry) => entry.observation.observationId),
    ).toEqual(["obs-original", "obs-corrected"]);
    expect(drilled.details.entries[1].observation).toMatchObject({
      correctionVintage: { state: "known", value: "corrected" },
      correctionLineage: [sha("obs-original")],
      contentHash: sha("obs-corrected"),
    });

    const omission = await execute(tools.get("drill_observation"), {
      dataset,
      listingId: "listing:A",
      observationDate: "2026-02-25",
      offset: 0,
      limit: 10,
    });
    expect(omission.details.entries).toEqual([
      {
        kind: "omission",
        omission: {
          listingId: "listing:A",
          observationDate: "2026-02-25",
          state: "provider_omission",
          evidenceReference: sha("gap-evidence"),
          evidenceReferenceRedacted: false,
          provenance: "caller_supplied_finance_ohlcv_gap_projection",
        },
      },
    ]);

    const firstVintage = await execute(tools.get("list_vintages"), {
      dataset,
      listingId: "listing:A",
      observationDate: "2026-02-24",
      offset: 0,
      limit: 1,
    });
    expect(firstVintage.details).toMatchObject({
      matchedCount: 2,
      returnedCount: 1,
      omittedCount: 1,
      nextOffset: 1,
    });
    expect(firstVintage.details.vintages[0].observationId).toBe("obs-original");
    const secondVintage = await execute(tools.get("list_vintages"), {
      dataset,
      listingId: "listing:A",
      observationDate: "2026-02-24",
      offset: 1,
      limit: 1,
    });
    expect(secondVintage.details.vintages[0].observationId).toBe(
      "obs-corrected",
    );
    expect(secondVintage.details.nextOffset).toBeNull();
    expect(JSON.stringify(inspected.details)).not.toMatch(
      /"(verdict|preferredVintage|latestVintage|selectedVintage|recommended|nextAction)"/,
    );
  });

  test("redacts URL secrets and fails hashes, tracks, ranges, selectors, and schemas exactly", async () => {
    const tools = await harness();
    const secret = "do-not-leak";
    const unsafe = datasetFixture({
      source: `https://user:password@example.test/data?api_key=${secret}#fragment`,
      evidenceReference: `https://example.test/gap?token=${secret}#fragment`,
    });
    const inspected = await execute(tools.get("inspect_dataset"), {
      dataset: unsafe,
    });
    expect(inspected.details.manifest.sourceReferenceRedacted).toBe(true);
    expect(JSON.stringify(inspected.details)).not.toContain(secret);
    expect(JSON.stringify(inspected.details)).not.toContain("user:password");
    expect(JSON.stringify(inspected.details)).not.toContain("#fragment");
    const omission = await execute(tools.get("drill_observation"), {
      dataset: unsafe,
      listingId: "listing:A",
      observationDate: "2026-02-25",
      offset: 0,
      limit: 10,
    });
    expect(omission.details.entries[0].omission).toMatchObject({
      evidenceReferenceRedacted: true,
    });
    expect(JSON.stringify(omission.details)).not.toContain(secret);

    const mismatch = datasetFixture();
    mismatch.manifestHash = "f".repeat(64);
    await expect(
      execute(tools.get("inspect_dataset"), { dataset: mismatch }),
    ).rejects.toThrow("does not match the canonical dataset handle");

    const noncanonical = datasetFixture();
    noncanonical.manifestJson += " ";
    await expect(
      execute(tools.get("inspect_dataset"), { dataset: noncanonical }),
    ).rejects.toThrow("not the exact canonical");

    const wrongTrack = datasetFixture({ observationTrack: "hk" });
    await expect(
      execute(tools.get("inspect_dataset"), { dataset: wrongTrack }),
    ).rejects.toThrow("failed the finance_replay contract");

    const outside = datasetFixture();
    outside.omissions[0].observationDate = "2026-03-01";
    await expect(
      execute(tools.get("inspect_dataset"), { dataset: outside }),
    ).rejects.toThrow("inside the exact manifest coverage interval");

    await expect(
      execute(tools.get("drill_observation"), {
        dataset: datasetFixture(),
        listingId: "listing:missing",
        observationDate: "2026-02-24",
        offset: 0,
        limit: 10,
      }),
    ).rejects.toThrow("no fallback was used");

    await expect(
      execute(tools.get("list_vintages"), {
        listingId: "listing:A",
        offset: 0,
        limit: 10,
      }),
    ).rejects.toThrow("Invalid parameters for tool list_vintages");
  });
});
