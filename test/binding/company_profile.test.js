import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/company_profile/index.js");
const originalFetch = globalThis.fetch;
const originalApiKey = process.env.TWELVE_DATA_API_KEY;
const requests = [];

const profileBody =
  '{"symbol":"AAPL","name":"Apple Inc.","exchange":"NASDAQ","mic_code":"XNGS","sector":"Technology","industry":"Consumer Electronics","employees":150000,"website":"https://www.apple.com","description":"Designs devices and services.","type":"Common Stock","CEO":"Mr. Timothy D. Cook","address":"One Apple Park Way","address2":null,"city":"Cupertino","zip":"95014","state":"CA","country":"United States","phone":"408-996-1010"}';

const statisticsBody =
  '{"meta":{"symbol":"AAPL","name":"Apple Inc.","currency":"USD","exchange":"NASDAQ","mic_code":"XNGS","exchange_timezone":"America/New_York"},"statistics":{"stock_statistics":{"shares_outstanding":14687356000,"float_shares":14569223952}}}';

beforeEach(() => {
  requests.length = 0;
  process.env.TWELVE_DATA_API_KEY = "test-twelve-data-api-key";
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    const headers = new Headers(init?.headers);
    requests.push({ url, headers });
    const profile = url.pathname === "/profile";
    return new Response(profile ? profileBody : statisticsBody, {
      status: 200,
      headers: {
        "content-type": "application/json",
        "api-credits-used": profile ? "10" : "60",
        "api-credits-left": profile ? "550" : "500",
        "api-credits-request": profile ? "10" : "50",
      },
    });
  };
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  restore("TWELVE_DATA_API_KEY", originalApiKey);
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?company-profile=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(
  tool,
  value = { symbol: "AAPL", mic: "XNGS" },
  signal = new AbortController().signal,
) {
  return tool.execute("company-profile-query", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

describe("company profile boundary", () => {
  test("registers only the read-only company_profile tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["company_profile"]);
  });

  test("joins two exact MIC-scoped snapshots and exposes content and credit receipts", async () => {
    const tools = await harness();
    const result = await execute(tools.get("company_profile"));

    expect(requests).toHaveLength(2);
    expect(requests[0].url.origin).toBe("https://api.twelvedata.com");
    expect(requests[0].url.pathname).toBe("/profile");
    expect(requests[1].url.pathname).toBe("/statistics");
    for (const request of requests) {
      expect(request.url.searchParams.get("symbol")).toBe("AAPL");
      expect(request.url.searchParams.get("mic_code")).toBe("XNGS");
      expect(request.url.searchParams.get("country")).toBe("US");
      expect(request.headers.get("authorization")).toBe(
        "apikey test-twelve-data-api-key",
      );
    }

    expect(result.details).toMatchObject({
      operation: "company_profile",
      track: "us",
      listing: {
        symbol: "AAPL",
        mic: "XNGS",
        exchange: "NASDAQ",
        identityState: "exact_provider_match_not_exchange_authority_proof",
      },
      profile: {
        value: {
          name: "Apple Inc.",
          sector: "Technology",
          industry: "Consumer Electronics",
          employeesRaw: "150000",
          chiefExecutive: "Mr. Timothy D. Cook",
        },
        freshness: { tag: "unknown" },
        entitlement: { tag: "unknown" },
        source: { kind: { tag: "licensed_vendor" } },
      },
      shares: {
        value: {
          outstanding: {
            state: "observed",
            rawValue: "14687356000",
            unit: "shares",
          },
          float: {
            state: "observed",
            rawValue: "14569223952",
          },
        },
        unit: { tag: "shares" },
      },
      scope: {
        providerSnapshotAsOf: "retrieval_time_only",
        fieldEffectiveAt: null,
        classificationTaxonomy: null,
        chiefExecutiveEffectiveAt: null,
        sharesMeasurementAt: null,
        crossListingFallback: null,
        qualityRating: null,
        investmentJudgment: null,
      },
      decisionOwner: "llm",
      pluginDecisionFields: [],
    });
    expect(result.details.trackContext).toMatchObject({
      track: "us",
      venueMic: "XNGS",
      providers: ["Twelve Data"],
      entitlement: "caller_twelve_data_subscription",
    });
    expect(result.details.source.profile).toMatchObject({
      endpoint: "/profile",
      responseByteLength: Buffer.byteLength(profileBody),
      contentSha256: createHash("sha256").update(profileBody).digest("hex"),
      apiCreditsUsed: "10",
      apiCreditsLeft: "550",
      apiCreditsRequest: "10",
    });
    expect(result.details.source.statistics).toMatchObject({
      endpoint: "/statistics",
      responseByteLength: Buffer.byteLength(statisticsBody),
      contentSha256: createHash("sha256")
        .update(statisticsBody)
        .digest("hex"),
      apiCreditsUsed: "60",
      apiCreditsLeft: "500",
      apiCreditsRequest: "50",
    });
    expect(JSON.stringify(result.details)).not.toContain(
      "test-twelve-data-api-key",
    );
  });

  test("rejects a profile identity mismatch before spending statistics credits", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      requests.push({ url, headers: new Headers() });
      return new Response(profileBody.replace('"mic_code":"XNGS"', '"mic_code":"XNYS"'));
    };
    const tools = await harness();

    await expect(execute(tools.get("company_profile"))).rejects.toThrow(
      "did not match the exact requested symbol and MIC",
    );
    expect(requests).toHaveLength(1);
    expect(requests[0].url.pathname).toBe("/profile");
  });

  test("rejects profile and statistics rows that cannot prove the same provider identity", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      return new Response(
        url.pathname === "/profile"
          ? profileBody
          : statisticsBody.replace("Apple Inc.", "Different Issuer"),
      );
    };
    const tools = await harness();

    await expect(execute(tools.get("company_profile"))).rejects.toThrow(
      "identities did not match exactly",
    );
  });

  test("preserves unavailable share fields without inventing zero", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      return new Response(
        url.pathname === "/profile"
          ? profileBody
          : statisticsBody
              .replace("14687356000", "null")
              .replace("14569223952", "null"),
      );
    };
    const tools = await harness();
    const result = await execute(tools.get("company_profile"));

    expect(result.details.shares.value.outstanding).toEqual({
      state: "not_supplied",
      providerField: "shares_outstanding",
      rawValue: null,
      unit: "shares",
    });
    expect(result.details.shares.value.float.rawValue).toBeNull();
    expect(result.details.shares.quality).toEqual({
      tag: "missing",
      reason: "unavailable",
    });
  });

  test("reports subscription denial without retrying the 50-credit endpoint", async () => {
    globalThis.fetch = async (input) => {
      const url = new URL(String(input));
      requests.push({ url, headers: new Headers() });
      return url.pathname === "/profile"
        ? new Response(profileBody)
        : new Response('{"status":"error"}', { status: 403 });
    };
    const tools = await harness();

    await expect(execute(tools.get("company_profile"))).rejects.toThrow(
      "subscription does not permit",
    );
    expect(requests).toHaveLength(2);
  });

  test("requires the caller's Twelve Data API key", async () => {
    delete process.env.TWELVE_DATA_API_KEY;
    const tools = await harness();

    await expect(execute(tools.get("company_profile"))).rejects.toThrow(
      "requires the caller's TWELVE_DATA_API_KEY",
    );
    expect(requests).toHaveLength(0);
  });

  test("honors cancellation before provider transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(profileBody);
    };
    const controller = new AbortController();
    controller.abort();
    const tools = await harness();

    await expect(
      execute(
        tools.get("company_profile"),
        { symbol: "AAPL", mic: "XNGS" },
        controller.signal,
      ),
    ).rejects.toThrow("failed safely");
    expect(called).toBeFalse();
  });
});

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
