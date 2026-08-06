import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/us_ohlcv_gaps/index.js");
const originalFetch = globalThis.fetch;
let fetchCalls = 0;

const sourceReference =
  "https://data.alpaca.markets/v2/stocks/bars?symbols=IBM&timeframe=1Day&start=2026-06-18&end=2026-06-24&adjustment=raw&feed=sip&currency=USD&sort=asc&asof=2026-06-25";

beforeEach(() => {
  fetchCalls = 0;
  globalThis.fetch = async () => {
    fetchCalls += 1;
    throw new Error("gap assessment must not perform network I/O");
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?us-ohlcv-gaps=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "us-ohlcv-gap-assessment",
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input(overrides = {}) {
  const { providerReceipt: providerOverrides = {}, ...inputOverrides } =
    overrides;
  return {
    venue: "nyse",
    instrumentId: "figi:BBG000BLNNH6",
    listingStartDate: "2026-01-01",
    listingEndDate: null,
    listingEvidenceReference: "authority:listing:IBM:XNYS:2026",
    providerReceipt: providerReceipt(providerOverrides),
    statusReceipts: [
      {
        date: "2026-06-22",
        status: "suspended",
        evidenceReference: "authority:nyse-halt:IBM:2026-06-22",
      },
      {
        date: "2026-06-23",
        status: "trading",
        evidenceReference: "authority:nyse-status:IBM:2026-06-23",
      },
    ],
    ...inputOverrides,
  };
}

function providerReceipt(overrides = {}) {
  const receipt = {
    schema: "pi-sparkles/us-ohlcv-gap-receipt",
    schemaVersion: 1,
    digestAlgorithm: "sha256",
    provider: "alpaca",
    symbol: "IBM",
    startDate: "2026-06-18",
    endDate: "2026-06-24",
    identityAsOf: "2026-06-25",
    feed: "sip",
    sourceReference,
    retrievedAtUnixMilliseconds: 1775000000000,
    pagination: "complete",
    pages: [
      {
        sequence: 1,
        requestId: "request-one",
        byteLength: 100,
        contentSha256: "a".repeat(64),
      },
      {
        sequence: 2,
        requestId: "request-two",
        byteLength: 200,
        contentSha256: "b".repeat(64),
      },
    ],
    barDates: ["2026-06-18", "2026-06-24"],
    ...overrides,
  };
  return { ...receipt, digest: receiptDigest(receipt) };
}

function receiptDigest(receipt) {
  const canonical = {
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: "us",
    provider: receipt.provider,
    symbol: receipt.symbol,
    start_date: receipt.startDate,
    end_date: receipt.endDate,
    identity_as_of: receipt.identityAsOf,
    feed: receipt.feed,
    source_reference: receipt.sourceReference,
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    pagination: receipt.pagination,
    pages: receipt.pages.map((page) => ({
      sequence: page.sequence,
      request_id: page.requestId,
      byte_length: String(page.byteLength),
      content_sha256: page.contentSha256,
    })),
    bar_dates: receipt.barDates,
  };
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}

describe("US OHLCV gap receipt composition", () => {
  test("classifies every absent date while retaining all evidence legs", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["us_ohlcv_gap_assessment"]);

    const result = await execute(tools.get("us_ohlcv_gap_assessment"), input());
    expect(result.details.track).toBe("us");
    expect(result.details.trackContext).toMatchObject({
      marketScope: "us_ohlcv_gap_assessment",
      venueMic: "XNYS",
      board: "nyse",
      timezone: "America/New_York",
    });
    expect(result.details.listing).toMatchObject({
      instrumentId: "figi:BBG000BLNNH6",
      symbol: "IBM",
      mic: "XNYS",
      evidenceStatus: "caller_supplied_unverified",
    });
    expect(result.details.calendarReceipt).toMatchObject({
      provider: "nyse",
      coverage: "2026-01-01/2026-12-31",
    });
    expect(result.details.providerReceipt).toMatchObject({
      provider: "alpaca",
      feed: "sip",
      pagination: "complete",
      requestIds: ["request-one", "request-two"],
      digestAlgorithm: "sha256",
    });
    expect(result.details.providerReceipt.integrity).toMatchObject({
      state: "sha256_content_match",
      scope: "canonical_gap_projection_v1",
      providerAuthenticated: false,
    });
    expect(result.details.assessment).toEqual({
      state: "fully_classified_from_supplied_receipts",
      startDate: "2026-06-18",
      endDate: "2026-06-24",
      datesAssessed: 7,
      barsReturned: 2,
      absentDates: 5,
    });
    expect(result.details.gaps.map((gap) => gap.state)).toEqual([
      "market_closure",
      "market_closure",
      "market_closure",
      "suspension",
      "provider_omission",
    ]);
    expect(result.details.gaps[3].evidence.map((leg) => leg.role)).toEqual([
      "calendar_schedule",
      "listing_interval",
      "market_status",
    ]);
    expect(result.details.gaps[4].evidence.map((leg) => leg.role)).toEqual([
      "calendar_schedule",
      "listing_interval",
      "market_status",
      "provider_coverage",
    ]);
    expect(fetchCalls).toBe(0);
  });

  test("rejects incomplete pagination and unexplained open dates", async () => {
    const tools = await harness();
    await expect(
      execute(
        tools.get("us_ohlcv_gap_assessment"),
        input({
          providerReceipt: { pagination: "truncated_by_page_budget" },
        }),
      ),
    ).rejects.toThrow("complete provider pagination");

    await expect(
      execute(
        tools.get("us_ohlcv_gap_assessment"),
        input({ statusReceipts: [] }),
      ),
    ).rejects.toThrow("2026-06-22");
    expect(fetchCalls).toBe(0);
  });

  test("rejects a copied projection changed after the digest was issued", async () => {
    const tools = await harness();
    const value = input();
    value.providerReceipt.barDates = ["2026-06-18"];
    await expect(
      execute(tools.get("us_ohlcv_gap_assessment"), value),
    ).rejects.toThrow("canonical SHA-256 digest");
    expect(fetchCalls).toBe(0);
  });
});
