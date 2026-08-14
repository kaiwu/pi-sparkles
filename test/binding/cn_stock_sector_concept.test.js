import { afterEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/cn_stock_sector_concept/index.js",
);
const originalFetch = globalThis.fetch;

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
    `${artifact}?cn-stock-sector-concept=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tool, input, signal = new AbortController().signal) {
  return tool.execute(
    "capco-classification-query",
    input,
    signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input(overrides = {}) {
  return {
    track: "cn",
    resultPeriod: "2025-H2",
    listingCode: "000001",
    ...overrides,
  };
}

function changedPdf(byteLength = 772_144) {
  const bytes = Buffer.alloc(byteLength, 0x20);
  bytes.write("%PDF-1.4\n", 0, "ascii");
  bytes.write("\n%%EOF\n", byteLength - 7, "ascii");
  return bytes;
}

function mockPdf(bytes, requests = [], status = 200) {
  globalThis.fetch = async (url, options) => {
    requests.push({ url: String(url), options });
    return new Response(bytes, {
      status,
      headers: {
        "content-type": "application/pdf",
        "content-length": String(bytes.byteLength),
      },
    });
  };
}

describe("CAPCO CN industry-classification boundary", () => {
  test("registers only the read-only cn_industry_classification tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["cn_industry_classification"]);
    const tool = tools.get("cn_industry_classification");
    expect(tool.description).toContain(
      "One call downloads and parses the complete bounded PDF for one code",
    );
    expect(tool.promptSnippet).toContain(
      "not as automatic per-row enrichment",
    );
    expect(tool.promptSnippet).toContain("Do not fan out parallel calls");
  });

  test("requests only the reviewed immutable CAPCO PDF", async () => {
    const requests = [];
    mockPdf(changedPdf(), requests);
    const tools = await harness();

    await expect(
      execute(tools.get("cn_industry_classification"), input()),
    ).rejects.toThrow("UnreviewedContentHash");
    expect(requests).toHaveLength(1);
    expect(requests[0].url).toBe(
      "https://sp.capco.org.cn:82/file/202604/hangyefenlei/2025xiaban/2025xiabangupiaodaima.pdf",
    );
    expect(requests[0].options.method).toBe("GET");
    expect(requests[0].options.headers.get("accept")).toBe("application/pdf");
    expect(requests[0].options.redirect).toBe("error");
  });

  test("rejects changed length before attempting PDF text extraction", async () => {
    mockPdf(changedPdf(1_000));
    const tools = await harness();

    await expect(
      execute(tools.get("cn_industry_classification"), input()),
    ).rejects.toThrow(
      "UnexpectedByteLength(expected: 772144, received: 1000)",
    );
  });

  test("rejects unsupported track, period, and malformed codes before I/O", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(changedPdf(), {
        headers: { "content-type": "application/pdf" },
      });
    };
    const tools = await harness();
    const tool = tools.get("cn_industry_classification");

    await expect(execute(tool, input({ track: "hk" }))).rejects.toThrow(
      "supports exact track cn",
    );
    await expect(
      execute(tool, input({ resultPeriod: "latest" })),
    ).rejects.toThrow("supports reviewed resultPeriod 2025-H2");
    await expect(
      execute(tool, input({ listingCode: "00001A" })),
    ).rejects.toThrow("six ASCII digits");
    expect(called).toBe(false);
  });

  test("honors cancellation before provider transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(changedPdf(), {
        headers: { "content-type": "application/pdf" },
      });
    };
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();

    await expect(
      execute(
        tools.get("cn_industry_classification"),
        input(),
        controller.signal,
      ),
    ).rejects.toThrow("Cancelled");
    expect(called).toBe(false);
  });
});
