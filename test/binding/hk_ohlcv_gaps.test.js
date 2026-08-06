import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/hk_ohlcv_gaps/index.js");
const originalFetch = globalThis.fetch;
let fetchCalls = 0;

const sourceReference =
  "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=116.00700&klt=101&fqt=0&beg=20260618&end=20260624&lmt=250";

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
    `${artifact}?hk-ohlcv-gaps=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input) {
  return tool.execute(
    "hk-ohlcv-gap-assessment",
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
    venue: "hk",
    board: "main",
    shareClass: "ordinary_share",
    currency: "HKD",
    code: "00700",
    instrumentId: "hkex:00700",
    listingStartDate: "2026-01-01",
    listingEndDate: null,
    listingEvidenceReference: "authority:listing:00700:XHKG:2026",
    providerReceipt: providerReceipt(providerOverrides),
    statusReceipts: [
      {
        date: "2026-06-22",
        status: "suspended",
        evidenceReference: "authority:hkex-halt:00700:2026-06-22",
      },
      {
        date: "2026-06-23",
        status: "trading",
        evidenceReference: "authority:hkex-status:00700:2026-06-23",
      },
    ],
    ...inputOverrides,
  };
}

function providerReceipt(overrides = {}) {
  const receipt = {
    schema: "pi-sparkles/hk-ohlcv-gap-receipt",
    schemaVersion: 1,
    digestAlgorithm: "sha256",
    provider: "eastmoney",
    venue: "hk",
    board: "main",
    shareClass: "ordinary_share",
    currency: "HKD",
    code: "00700",
    startDate: "2026-06-18",
    endDate: "2026-06-24",
    limit: 250,
    sourceReference,
    retrievedAtUnixMilliseconds: 1775000000000,
    pagination: "complete",
    pages: [
      {
        sequence: 1,
        requestId: "request-one",
        byteLength: 500,
        contentSha256: "a".repeat(64),
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
    track: "hk",
    provider: receipt.provider,
    venue: receipt.venue,
    board: receipt.board,
    share_class: receipt.shareClass,
    currency: receipt.currency,
    code: receipt.code,
    start_date: receipt.startDate,
    end_date: receipt.endDate,
    limit: String(receipt.limit),
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

describe("HK OHLCV gap receipt composition", () => {
  test("classifies every absent date while retaining HK calendar evidence", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["hk_ohlcv_gap_assessment"]);

    const result = await execute(tools.get("hk_ohlcv_gap_assessment"), input());
    expect(result.details.track).toBe("hk");
    expect(result.details.trackContext).toMatchObject({
      marketScope: "hk_ohlcv_gap_assessment",
      venueMic: "XHKG",
      board: "main",
      timezone: "Asia/Hong_Kong",
    });
    expect(result.details.listing).toMatchObject({
      instrumentId: "hkex:00700",
      code: "00700",
      mic: "XHKG",
      evidenceStatus: "caller_supplied_unverified",
    });
    expect(result.details.calendarReceipt).toMatchObject({
      provider: "hkex",
      coverage: "2026-01-01/2026-12-31",
      halfDayDates: ["2026-02-16", "2026-12-24", "2026-12-31"],
    });
    expect(result.details.providerReceipt).toMatchObject({
      provider: "eastmoney",
      pagination: "complete",
      requestIds: ["request-one"],
      digestAlgorithm: "sha256",
    });
    expect(result.details.providerReceipt.integrity).toMatchObject({
      state: "sha256_content_match",
      scope: "canonical_hk_gap_projection_v1",
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

  test("rejects identity drift, incomplete coverage, and unexplained open dates", async () => {
    const tools = await harness();
    await expect(
      execute(tools.get("hk_ohlcv_gap_assessment"), input({ code: "00001" })),
    ).rejects.toThrow("does not match the provider projection");

    await expect(
      execute(
        tools.get("hk_ohlcv_gap_assessment"),
        input({
          providerReceipt: { pagination: "truncated_by_bar_budget" },
        }),
      ),
    ).rejects.toThrow("complete provider coverage");

    await expect(
      execute(
        tools.get("hk_ohlcv_gap_assessment"),
        input({ statusReceipts: [] }),
      ),
    ).rejects.toThrow("2026-06-22");
    expect(fetchCalls).toBe(0);
  });

  test("rejects a copied projection changed after its digest was issued", async () => {
    const tools = await harness();
    const value = input();
    value.providerReceipt.barDates = ["2026-06-18"];
    await expect(
      execute(tools.get("hk_ohlcv_gap_assessment"), value),
    ).rejects.toThrow("canonical SHA-256 digest");
    expect(fetchCalls).toBe(0);
  });
});
