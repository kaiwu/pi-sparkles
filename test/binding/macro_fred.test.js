import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/macro_fred/index.js");
const originalFetch = globalThis.fetch;
const originalApiKey = process.env.FRED_API_KEY;
const requests = [];

const metadataBody = JSON.stringify({
  realtime_start: "2026-01-15",
  realtime_end: "2026-01-15",
  seriess: [
    {
      id: "CPIAUCSL",
      realtime_start: "2026-01-15",
      realtime_end: "2026-01-15",
      title: "Consumer Price Index for All Urban Consumers",
      observation_start: "1947-01-01",
      observation_end: "2025-12-01",
      frequency: "Monthly",
      frequency_short: "M",
      units: "Index 1982-1984=100",
      units_short: "Index 1982-1984=100",
      seasonal_adjustment: "Seasonally Adjusted",
      seasonal_adjustment_short: "SA",
      last_updated: "2026-01-14 07:42:02-06",
      popularity: 95,
      notes: "Source note retained exactly.",
    },
  ],
});

function observationsBody(count = 3, limit = 24) {
  return JSON.stringify({
    realtime_start: "2026-01-15",
    realtime_end: "2026-01-15",
    observation_start: "2025-01-01",
    observation_end: "2025-12-31",
    units: "lin",
    output_type: 1,
    file_type: "json",
    order_by: "observation_date",
    sort_order: "asc",
    count,
    offset: 0,
    limit,
    observations: [
      {
        realtime_start: "2026-01-15",
        realtime_end: "2026-01-15",
        date: "2025-01-01",
        value: "320.500",
      },
      {
        realtime_start: "2026-01-15",
        realtime_end: "2026-01-15",
        date: "2025-02-01",
        value: "321.10",
      },
      {
        realtime_start: "2026-01-15",
        realtime_end: "2026-01-15",
        date: "2025-03-01",
        value: "322.025",
      },
    ],
  });
}

beforeEach(() => {
  requests.length = 0;
  process.env.FRED_API_KEY = "abcdefghijklmnopqrstuvwxyz123456";
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    requests.push(url);
    const metadata = url.pathname === "/fred/series";
    return new Response(metadata ? metadataBody : observationsBody(), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": metadata ? "fred-meta-1" : "fred-observations-1",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("FRED_API_KEY", originalApiKey);
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?macro-fred=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function input(overrides = {}) {
  return {
    seriesId: "CPIAUCSL",
    observationStart: "2025-01-01",
    observationEnd: "2025-12-31",
    asOfDate: "2026-01-15",
    maximumObservations: 24,
    ...overrides,
  };
}

function execute(tool, value = input(), signal = new AbortController().signal) {
  return tool.execute("fred-series-query", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("macro FRED boundary", () => {
  test("registers only the read-only fred_series tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["fred_series"]);
  });

  test("makes two exact requests and returns source-bound metadata, observations, latest, and change", async () => {
    const tools = await harness();
    const result = await execute(tools.get("fred_series"));

    expect(requests).toHaveLength(2);
    expect(requests[0].origin).toBe("https://api.stlouisfed.org");
    expect(requests[0].pathname).toBe("/fred/series");
    expect(requests[1].pathname).toBe("/fred/series/observations");
    for (const request of requests) {
      expect(request.searchParams.get("series_id")).toBe("CPIAUCSL");
      expect(request.searchParams.get("file_type")).toBe("json");
      expect(request.searchParams.get("realtime_start")).toBe("2026-01-15");
      expect(request.searchParams.get("realtime_end")).toBe("2026-01-15");
      expect(request.searchParams.get("api_key")).toBe(
        "abcdefghijklmnopqrstuvwxyz123456",
      );
    }
    expect(requests[1].searchParams.get("observation_start")).toBe(
      "2025-01-01",
    );
    expect(requests[1].searchParams.get("observation_end")).toBe(
      "2025-12-31",
    );
    expect(requests[1].searchParams.get("units")).toBe("lin");
    expect(requests[1].searchParams.get("output_type")).toBe("1");
    expect(requests[1].searchParams.get("sort_order")).toBe("asc");
    expect(requests[1].searchParams.get("limit")).toBe("24");
    expect(requests[1].searchParams.get("offset")).toBe("0");

    expect(result.details).toMatchObject({
      operation: "fred_series",
      track: null,
      observationCount: 3,
      metadata: {
        id: "CPIAUCSL",
        units: "Index 1982-1984=100",
        seasonalAdjustment: "Seasonally Adjusted",
        notes: "Source note retained exactly.",
      },
      latest: {
        state: "observed",
        source: { date: "2025-03-01", rawValue: "322.025" },
      },
      change: {
        state: "calculated",
        expression: "latest - previous",
        value: "0.925",
        current: { date: "2025-03-01", rawValue: "322.025" },
        previous: { date: "2025-02-01", rawValue: "321.10" },
      },
      source: {
        termsReference:
          "https://fred.stlouisfed.org/docs/api/terms_of_use.html",
      },
      scope: {
        marketTrack: "not_market_specific",
        freshness: "unknown_without_release_calendar",
        forecast: null,
        economicInterpretation: null,
      },
    });
    expect(result.details.observations[0]).toMatchObject({
      value: {
        sourceDate: "2025-01-01",
        rawValue: "320.500",
        numericValue: "320.5",
      },
      source: {
        provider: "Federal Reserve Bank of St. Louis FRED",
        kind: { tag: "official" },
      },
      freshness: { tag: "unknown" },
      entitlement: { tag: "unknown" },
      quality: { tag: "reported" },
      adjustment: {
        tag: "provider_adjusted",
        provider: "FRED",
        basis: "Seasonally Adjusted",
      },
    });
    expect(result.details.source.metadata).toMatchObject({
      endpoint: "/fred/series",
      requestId: "fred-meta-1",
      responseByteLength: Buffer.byteLength(metadataBody),
      contentSha256: createHash("sha256").update(metadataBody).digest("hex"),
    });
    const observationBody = observationsBody();
    expect(result.details.source.observations).toMatchObject({
      endpoint: "/fred/series/observations",
      requestId: "fred-observations-1",
      responseByteLength: Buffer.byteLength(observationBody),
      contentSha256: createHash("sha256").update(observationBody).digest("hex"),
    });
    expect(JSON.stringify(result.details)).not.toContain(
      "abcdefghijklmnopqrstuvwxyz123456",
    );
  });

  test("rejects a range that exceeds the explicit complete-range cap", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      return new Response(
        url.pathname === "/fred/series"
          ? metadataBody
          : observationsBody(3, 2),
        { headers: { "content-type": "application/json" } },
      );
    };
    const tools = await harness();

    await expect(
      execute(tools.get("fred_series"), input({ maximumObservations: 2 })),
    ).rejects.toThrow("Truncated(maximum: 2, available: 3)");
  });

  test("rejects provider metadata for a different series", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      return new Response(
        url.pathname === "/fred/series"
          ? metadataBody.replaceAll("CPIAUCSL", "UNRATE")
          : observationsBody(),
        { headers: { "content-type": "application/json" } },
      );
    };
    const tools = await harness();

    await expect(execute(tools.get("fred_series"))).rejects.toThrow(
      "SeriesMismatch",
    );
    expect(requests).toHaveLength(0);
  });

  test("requires the caller's FRED API key", async () => {
    delete process.env.FRED_API_KEY;
    const tools = await harness();

    await expect(execute(tools.get("fred_series"))).rejects.toThrow(
      "requires FRED_API_KEY",
    );
  });

  test("honors cancellation before provider transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(metadataBody);
    };
    const controller = new AbortController();
    controller.abort();
    const tools = await harness();

    await expect(
      execute(tools.get("fred_series"), input(), controller.signal),
    ).rejects.toThrow("failed safely");
    expect(called).toBeFalse();
  });
});

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
