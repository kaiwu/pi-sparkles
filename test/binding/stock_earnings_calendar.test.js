import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(
  import.meta.dir,
  "../../dist/stock_earnings_calendar/index.js",
);
const originalFetch = globalThis.fetch;
const originalContact = process.env.HKEX_USER_AGENT_CONTACT;
const originalProduct = process.env.HKEX_USER_AGENT_PRODUCT;

beforeEach(() => {
  process.env.HKEX_USER_AGENT_CONTACT = "research@example.com";
  process.env.HKEX_USER_AGENT_PRODUCT = "pi-sparkles-test/0.1";
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  if (originalContact === undefined) {
    delete process.env.HKEX_USER_AGENT_CONTACT;
  } else {
    process.env.HKEX_USER_AGENT_CONTACT = originalContact;
  }
  if (originalProduct === undefined) {
    delete process.env.HKEX_USER_AGENT_PRODUCT;
  } else {
    process.env.HKEX_USER_AGENT_PRODUCT = originalProduct;
  }
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifact}?stock-earnings-calendar=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tool, input, signal = new AbortController().signal) {
  return tool.execute(
    "earnings-calendar-query",
    input,
    signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function input(overrides = {}) {
  return {
    track: "hk",
    venue: "XHKG",
    board: "main",
    code: "00743",
    startDate: "2026-08-01",
    endDate: "2026-09-30",
    ...overrides,
  };
}

function fixture(rows = defaultRows()) {
  return `<html><span>Board Meeting Notifications</span>
<font class=textfont><br/>Date : 06/08/2026<br/><br/>
The following table is a consolidated list of board meeting dates<br/>announced by listed issuers.  This list may not be exhaustive<br/>and is for reference only.<br/>
Note: only the start date of the board meeting will be updated</font>
<table class=textfont><tr><td><font>BM Date</font></td><td><font></font></td><td><font>Stock Short Name<td><font>&nbsp;Code</font></td><td><font>Purpose</font></td><td><font>Period</font></td></font></td></tr>${rows}</table></html>`;
}

function defaultRows() {
  return [
    row("07/08/2026", "ASIA CEMENT CH", "743", "INT RES/DIV", "6-MTH-ENDED30/06/26"),
    row("08/08/2026", "ASIA CEMENT CH", "743", "SPECIAL DIVIDEND", ""),
    row("09/08/2026", "TENCENT", "700", "INT RES", "6-MTH-ENDED30/06/26"),
  ].join("");
}

function row(date, name, code, purpose, period) {
  return `<tr><td width=75 valign=top><font>${date}</font></td><td width=30 valign=top align=right><font></font></td><td width=120 valign=top><font>${name}</font></td><td width=50 valign=top><font>&nbsp;${code}</font></td><td width=140 valign=top><font>${purpose}</font></td><td valign=top><font>${period}</font></td></tr>`;
}

function mockPage(body, requests = []) {
  globalThis.fetch = async (url, options) => {
    requests.push({ url: String(url), options });
    return new Response(body, {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  };
}

describe("stock earnings calendar boundary", () => {
  test("registers only the read-only earnings_calendar tool", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual(["earnings_calendar"]);
  });

  test("fetches the exact Main Board page and retains result and excluded rows", async () => {
    const requests = [];
    mockPage(fixture(), requests);
    const tools = await harness();
    const result = await execute(tools.get("earnings_calendar"), input());

    expect(requests).toHaveLength(1);
    expect(requests[0].url).toBe(
      "https://www3.hkexnews.hk/reports/bmn/ebmn.htm",
    );
    expect(requests[0].options.method).toBe("GET");
    expect(requests[0].options.headers.get("user-agent")).toBe(
      "pi-sparkles-test/0.1 research@example.com",
    );
    expect(result.details).toMatchObject({
      operation: "earnings_calendar",
      track: "hk",
      venue: "XHKG",
      query: { board: "main", code: "00743" },
      resolution: "unique",
      nextBoardMeetingDate: "2026-08-07",
      matchedCount: 1,
      excludedSourceRowCount: 1,
      events: [
        {
          boardMeetingDate: "2026-08-07",
          sourceCode: "743",
          code: "00743",
          purpose: "INT RES/DIV",
          publicationTimestamp: null,
        },
      ],
      excludedSourceRows: [
        {
          purpose: "SPECIAL DIVIDEND",
          reason: "purpose_marker_not_recognized_as_results",
        },
      ],
      scope: {
        eventKind: "issuer_announced_board_meeting",
        completeness: "not_exhaustive_reference_only",
        absenceClaim: false,
      },
    });
    expect(result.details.source.contentSha256).toHaveLength(64);
    expect(result.details.source.canonicalDigest).toHaveLength(64);
    expect(result.content[0].text).toContain("not publication timestamps");
  });

  test("uses the exact GEM page and does not claim absence on no-match", async () => {
    const requests = [];
    mockPage(
      fixture(row("07/08/2026", "AHSAY BACKUP", "8290", "INT RES/DIV", "6-MTH-ENDED30/06/26")),
      requests,
    );
    const tools = await harness();
    const result = await execute(
      tools.get("earnings_calendar"),
      input({ board: "gem", code: "08291" }),
    );

    expect(requests[0].url).toBe(
      "https://www3.hkexnews.hk/reports/bmn/ebmngem.htm",
    );
    expect(result.details).toMatchObject({
      resolution: "no_match_on_non_exhaustive_page",
      nextBoardMeetingDate: null,
      matchedCount: 0,
      scope: { absenceClaim: false },
    });
  });

  test("rejects semantic page drift before returning any event", async () => {
    mockPage(fixture().replace(">Purpose</font>", ">Agenda</font>"));
    const tools = await harness();

    await expect(
      execute(tools.get("earnings_calendar"), input()),
    ).rejects.toThrow("InvalidPage(HeaderMismatch)");
  });

  test("honors cancellation before transport", async () => {
    let called = false;
    globalThis.fetch = async () => {
      called = true;
      return new Response(fixture(), {
        headers: { "content-type": "text/html" },
      });
    };
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();

    await expect(
      execute(tools.get("earnings_calendar"), input(), controller.signal),
    ).rejects.toThrow("Cancelled");
    expect(called).toBe(false);
  });
});
