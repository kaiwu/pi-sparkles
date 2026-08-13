import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const originalFetch = globalThis.fetch;
const originalContact = process.env.AGENT_CONTACT;
let directory;

const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const marker = (character) => character.repeat(64);

const submissions = {
  cik: 320193,
  name: "Apple Inc.",
  tickers: ["AAPL"],
  exchanges: ["Nasdaq"],
  filings: {
    recent: {
      accessionNumber: ["0000320193-25-000080", "0000320193-25-000079"],
      filingDate: ["2025-02-02", "2025-02-01"],
      reportDate: ["2024-12-31", "2024-12-31"],
      form: ["10-K/A", "10-K"],
      primaryDocument: ["aapl-2024-amended.htm", "aapl-2024.htm"],
    },
  },
};

const companyFacts = `{
  "cik": 320193,
  "entityName": "Apple Inc.",
  "facts": {"us-gaap": {
    "RevenueFromContractWithCustomerExcludingAssessedTax": {
      "label": "Revenue", "description": "Revenue", "units": {"USD": [
        {"start":"2024-01-01","end":"2024-12-31","val":1000.00,"accn":"0000320193-25-000079","fy":2024,"fp":"FY","form":"10-K","filed":"2025-02-01"},
        {"start":"2024-01-01","end":"2024-12-31","val":1100.00,"accn":"0000320193-25-000080","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
      ]}
    },
    "NetIncomeLoss": {
      "label": "Net income", "description": "Net income", "units": {"USD": [
        {"start":"2024-01-01","end":"2024-12-31","val":110.00,"accn":"0000320193-25-000080","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
      ]}
    }
  }}
}`;

const companyConcept = `{
  "cik":320193,"taxonomy":"us-gaap",
  "tag":"RevenueFromContractWithCustomerExcludingAssessedTax",
  "label":"Revenue","description":"Revenue","entityName":"Apple Inc.",
  "units":{"USD":[
    {"start":"2024-01-01","end":"2024-12-31","val":1000.00,"accn":"0000320193-25-000079","fy":2024,"fp":"FY","form":"10-K","filed":"2025-02-01"},
    {"start":"2024-01-01","end":"2024-12-31","val":1100.00,"accn":"0000320193-25-000080","fy":2024,"fp":"FY","form":"10-K/A","filed":"2025-02-02"}
  ]}
}`;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "pi-sparkles-t2-"));
  process.env.AGENT_CONTACT = "t2-investor@example.test";
  globalThis.fetch = async (input) => {
    const url = String(input);
    let body;
    if (url.endsWith("/files/company_tickers.json")) {
      body = JSON.stringify({
        0: { cik_str: 320193, ticker: "AAPL", title: "Apple Inc." },
      });
    } else if (url.includes("/submissions/")) {
      body = JSON.stringify(submissions);
    } else if (url.includes("/companyconcept/")) {
      body = companyConcept;
    } else if (url.includes("/companyfacts/")) {
      body = companyFacts;
    } else {
      throw new Error(`unexpected T2 provider request: ${url}`);
    }
    return new Response(body, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
});

afterAll(async () => {
  globalThis.fetch = originalFetch;
  restore("AGENT_CONTACT", originalContact);
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function harness(name) {
  const tools = new Map();
  const api = {
    registerCommand() {},
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
    on() {},
    getActiveTools() {
      return [
        "sec_company_submissions",
        "stock_fundamental_period",
        "company_governance",
        "inspect_valuation",
        "us_company_brief",
      ];
    },
  };
  const artifact = resolve(import.meta.dir, `../../../dist/${name}/index.js`);
  const module = await import(
    `${artifact}?t2-role=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

async function execute(tool, input, id = "t2") {
  return tool.execute(
    id,
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

async function packetFile(name, packet) {
  const text = JSON.stringify(packet);
  const path = join(directory, name);
  await writeFile(path, text, "utf8");
  return { path, text, sha256: sha256(text) };
}

function operand(
  name,
  exactLexeme,
  unit,
  sourceReceipt,
  contextKey = "FY2024:amended",
) {
  return {
    name,
    exactLexeme,
    marketTrack: "us",
    mic: "XNAS",
    unit,
    currency: unit === "shares" ? null : "USD",
    periodStart: "2024-01-01",
    periodEnd: "2024-12-31",
    accession: "0000320193-25-000080",
    taxonomy: "us-gaap",
    tag: name,
    contextKey,
    sourceReceipt,
  };
}

async function calculationFile(contractId, operation, operands, outputUnit) {
  return packetFile(`${contractId}.json`, {
    schemaVersion: 1,
    contractId,
    track: "us",
    requestId: `${contractId}-request`,
    subject: {
      issuerId: "CIK0000320193",
      listingId: "US0378331005",
      mic: "XNAS",
      shareClass: "common",
    },
    operation,
    outputUnit,
    outputScale: 6,
    rounding: "half_even",
    coherenceKey: "FY2024:amended",
    operands,
    assumptions: ["caller selected the amended annual filing"],
  });
}

function calcInput(file) {
  return {
    path: file.path,
    expectedSha256: file.sha256,
    maximumBytes: 1_000_000,
  };
}

describe("T2 US long-term-investor role journey", () => {
  test("moves from original SEC evidence through normalized facts, comparison, governance, valuation, and cited report", async () => {
    const edgar = await harness("sec_edgar");
    const company = await execute(
      edgar.get("sec_company_search"),
      { query: "AAPL", limit: 5 },
      "company",
    );
    expect(company.details.candidates[0]).toMatchObject({
      cik: "0000320193",
      ticker: "AAPL",
      match: "exact_ticker",
    });
    const filingList = await execute(
      edgar.get("sec_company_submissions"),
      { cik: "320193", limit: 10 },
      "submissions",
    );
    expect(filingList.details.filings.map(({ accession, form }) => ({
      accession,
      form,
    }))).toEqual([
      { accession: "0000320193-25-000080", form: "10-K/A" },
      { accession: "0000320193-25-000079", form: "10-K" },
    ]);

    const xbrl = await harness("sec_xbrl");
    const rawFacts = await execute(
      xbrl.get("sec_xbrl_facts"),
      {
        cik: "320193",
        taxonomy: "us-gaap",
        tag: "RevenueFromContractWithCustomerExcludingAssessedTax",
        unit: "USD",
      },
      "raw-facts",
    );
    expect(rawFacts.details.duplicatesPreserved).toBeTrue();
    expect(rawFacts.details.facts.map(({ value, accession }) => ({
      value,
      accession,
    }))).toEqual([
      { value: "1100.00", accession: "0000320193-25-000080" },
      { value: "1000.00", accession: "0000320193-25-000079" },
    ]);

    const fundamentals = await harness("stock_fundamentals");
    const revenue = await execute(
      fundamentals.get("stock_fundamental_period"),
      {
        cik: "320193",
        metric: "revenue",
        unit: "USD",
        period: "annual",
        end: "2024-12-31",
        filingPolicy: "latest_filed",
      },
      "normalized-revenue",
    );
    expect(revenue.details).toMatchObject({
      resolution: "unique",
      periodClass: "annual",
      filingPolicy: "latest_filed",
    });
    expect(revenue.details.candidates[0]).toMatchObject({
      value: "1100.00",
      accession: "0000320193-25-000080",
      amendment: true,
    });
    const margin = await execute(
      fundamentals.get("stock_fundamental_metric"),
      {
        cik: "320193",
        metric: "net_margin",
        currencyUnit: "USD",
        period: "annual",
        end: "2024-12-31",
        sourceAccessions: { net_income: "0000320193-25-000080", revenue: "0000320193-25-000080" },
        scale: 6,
      },
      "net-margin",
    );
    expect(margin.details).toMatchObject({
      status: "calculated",
      value: "10",
      unit: "percentage_points",
    });

    const leftText = "Revenue 1000.00";
    const rightText = "Revenue 1100.00";
    const diffFile = await packetFile("filing-diff.json", {
      schemaVersion: 1,
      contractId: "filing_diff_v1",
      track: "us",
      subject: {
        issuerId: "CIK0000320193",
        listingId: "US0378331005",
        mic: "XNAS",
      },
      view: "raw",
      algorithmVersion: "exact_section_v1",
      left: {
        documentId: "original-document",
        form: "10-K",
        accessionOrEventId: "original",
        publishedAt: "2025-02-01T00:00:00Z",
        effectiveDate: "2024-12-31",
        correctionOf: null,
        language: "en",
        sourceUrl: "https://www.sec.gov/Archives/original",
        rights: "public_filing",
        contentSha256: sha256(leftText),
        sections: [{
          sectionId: "income-statement",
          kind: "table",
          title: "Income statement",
          ordinal: 0,
          startOffset: 0,
          endOffset: leftText.length,
          rawText: leftText,
        }],
        omissions: [],
      },
      right: {
        documentId: "amended-document",
        form: "10-K/A",
        accessionOrEventId: "amended",
        publishedAt: "2025-02-02T00:00:00Z",
        effectiveDate: "2024-12-31",
        correctionOf: "original-document",
        language: "en",
        sourceUrl: "https://www.sec.gov/Archives/amended",
        rights: "public_filing",
        contentSha256: sha256(rightText),
        sections: [{
          sectionId: "income-statement",
          kind: "table",
          title: "Income statement",
          ordinal: 0,
          startOffset: 0,
          endOffset: rightText.length,
          rawText: rightText,
        }],
        omissions: [],
      },
    });
    const diff = await execute(
      (await harness("filing_diff")).get("diff_filings"),
      { ...calcInput(diffFile), offset: 0, limit: 20 },
      "filing-diff",
    );
    expect(diff.details.changes).toEqual([
      expect.objectContaining({
        changeId: "replace:income-statement",
        kind: "replace",
      }),
    ]);
    expect(diff.details.rightDocument).toMatchObject({
      correctionOf: "original-document",
      accessionOrEventId: "amended",
    });

    const sourceReceipt = marker("9");
    const growthFile = await calculationFile(
      "stock_growth_v1",
      "percent_change",
      [
        operand("current", "1100.00", "USD", sourceReceipt),
        operand("prior", "1000.00", "USD", marker("1")),
      ],
      "ratio",
    );
    const growth = await execute(
      (await harness("stock_growth")).get("growth_metrics"),
      calcInput(growthFile),
      "growth",
    );
    expect(growth.details.canonicalCalculation).toMatchObject({
      operation: "percent_change",
      resultExact: "0.1",
      decisionOwner: "llm",
    });

    const qualityFile = await calculationFile(
      "stock_quality_v1",
      "ratio",
      [
        operand("numerator", "110.00", "USD", sourceReceipt),
        operand("denominator", "1100.00", "USD", sourceReceipt),
      ],
      "ratio",
    );
    const quality = await execute(
      (await harness("stock_quality")).get("quality_dimensions"),
      calcInput(qualityFile),
      "quality",
    );
    expect(quality.details.canonicalCalculation.resultExact).toBe("0.1");

    const valuationFile = await calculationFile(
      "stock_valuation_v1",
      "enterprise_to_equity_per_share",
      [
        operand("enterprise_value", "12000", "USD", marker("2")),
        operand("net_debt", "2000", "USD", marker("3")),
        operand("diluted_shares", "1000", "shares", marker("4")),
      ],
      "USD/share",
    );
    const valuation = await execute(
      (await harness("stock_valuation")).get("inspect_valuation"),
      calcInput(valuationFile),
      "valuation",
    );
    expect(valuation.details.canonicalCalculation).toMatchObject({
      resultExact: "10",
      outputUnit: "USD/share",
    });

    const governanceFile = await packetFile("governance.json", {
      schemaVersion: 1,
      contractId: "company_governance_v1",
      track: "us",
      subject: {
        issuerId: "CIK0000320193",
        listingId: "US0378331005",
        mic: "XNAS",
        shareClass: "common",
      },
      source: {
        provider: "SEC EDGAR",
        authorityRole: "official_filing_repository",
        documentId: "proxy-2025",
        publishedAt: "2025-03-01T00:00:00Z",
        retrievedAt: "2026-08-11T00:00:00Z",
        language: "en",
        rights: "public_filing",
        sourceUrl: "https://www.sec.gov/Archives/proxy-2025",
      },
      records: [{
        recordId: "board-1",
        kind: "board",
        effectiveAt: "2025-03-01",
        publishedAt: "2025-03-01T00:00:00Z",
        correctionOf: null,
        fields: [
          { name: "source_document", state: "known", valueLexeme: "proxy-2025", unit: null, sourceSpan: "cover" },
          { name: "period", state: "known", valueLexeme: "2025", unit: null, sourceSpan: "cover" },
          { name: "information_state", state: "known", valueLexeme: "reported", unit: null, sourceSpan: "board" },
        ],
      }],
      omissions: ["committee expertise interpretation not performed"],
    });
    const governance = await execute(
      (await harness("company_governance")).get("company_governance"),
      { ...calcInput(governanceFile), offset: 0, limit: 20 },
      "governance",
    );
    expect(governance.details).toMatchObject({
      track: "us",
      recordCount: 1,
      omissionCount: 1,
      decisionOwner: "llm",
    });

    const peersFile = await packetFile("peers.json", {
      schemaVersion: 1,
      contractId: "stock_peers_v1",
      track: "us",
      target: {
        issuerId: "CIK0000320193",
        listingId: "US0378331005",
        mic: "XNAS",
        shareClass: "common",
      },
      evidenceDate: "2026-08-11",
      predicates: [{
        predicateId: "reporting-currency",
        label: "Same reporting currency",
        rule: "exact ISO currency equality",
      }],
      candidates: [
        {
          candidateId: "peer-accepted",
          subject: { issuerId: "CIK2", listingId: "US2", mic: "XNYS", shareClass: "common" },
          classifications: ["technology"],
          currency: "USD",
          fiscalPeriod: "2024-FY",
          facts: [{ predicateId: "reporting-currency", state: "observed_true", observedValue: "USD", sourceReceipt: marker("5") }],
        },
        {
          candidateId: "peer-unresolved",
          subject: { issuerId: "CIK3", listingId: "US3", mic: "XNAS", shareClass: "common" },
          classifications: [],
          currency: "USD",
          fiscalPeriod: "2024-FY",
          facts: [{ predicateId: "reporting-currency", state: "unknown", observedValue: null, sourceReceipt: marker("6") }],
        },
      ],
      omissions: [],
    });
    const peers = await execute(
      (await harness("stock_peers")).get("inspect_peer_set"),
      { ...calcInput(peersFile), offset: 0, limit: 20 },
      "peers",
    );
    expect(peers.details).toMatchObject({
      acceptedCount: 1,
      rejectedCount: 0,
      unresolvedCount: 1,
    });

    const report = await execute(
      (await harness("stock_research_report")).get("us_company_brief"),
      {
        company: "Apple Inc.",
        symbol: "AAPL",
        cik: "0000320193",
        asOfDate: "2026-08-11",
        quotes: [],
        histories: [],
        filings: filingList.details.filings.map((filing) => ({
          accession: filing.accession,
          filingDate: filing.filingDate,
          reportDate: filing.reportDate,
          form: filing.form,
          primaryDocument: filing.primaryDocument,
          sourceReference: "https://data.sec.gov/submissions/CIK0000320193.json",
        })),
        fundamentals: [{
          metric: "revenue",
          value: "1100.00",
          canonicalDecimal: "1100",
          unit: "USD",
          periodClass: "annual",
          start: "2024-01-01",
          end: "2024-12-31",
          tag: "RevenueFromContractWithCustomerExcludingAssessedTax",
          accession: "0000320193-25-000080",
          form: "10-K/A",
          filed: "2025-02-02",
          sourceReference: "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
        }],
        missingCapabilities: ["segment facts not supplied", "portfolio fit not supplied"],
      },
      "report",
    );
    expect(report.details).toMatchObject({
      status: "assembled",
      reportType: "us_company_source_fact_brief",
      interpretation: "not_generated",
    });
    expect(report.content[0].text).toContain("## Evidence roots");
    expect(report.details.filings.map(({ accession }) => accession)).toEqual([
      "0000320193-25-000080",
      "0000320193-25-000079",
    ]);
  });

  test("persists, resumes, compares, and fork-protects an evidence-linked thesis", async () => {
    const path = join(directory, "theses.jsonl");
    const tools = await harness("stock_thesis");
    const subject = {
      track: "us",
      issuerId: "CIK0000320193",
      listingId: "US0378331005",
      mic: "XNAS",
      symbol: "AAPL",
    };
    const claim = (text, sourceState = "current", correctedBy = null) => ({
      claimId: "claim-growth",
      text,
      state: "active",
      evidence: [{
        linkId: "growth-receipt",
        relation: "supporting",
        receiptSha256: marker("7"),
        sourceState,
        correctedBy,
      }],
    });
    const common = {
      path,
      maximumBytes: 1_000_000,
      journalId: "t2-investor-journal",
      thesisId: "aapl-long-term",
      authorKind: "user",
      authorId: "investor-1",
      recordedAt: "2026-08-11T10:00:00Z",
      subject,
      horizon: "3-5 years",
      privacy: "review_visible",
    };
    const created = await execute(
      tools.get("thesis_create"),
      {
        ...common,
        expectedRevision: 0,
        eventId: "thesis-v1",
        kind: "created",
        version: 1,
        parentEventId: null,
        claims: [claim("Revenue growth is durable under the caller's stated horizon")],
        reason: null,
        idempotencyKey: "create-aapl-v1",
      },
      "thesis-create",
    );
    expect(created.content[0].text).toContain("Thesis stored");
    expect(created.details.selected.header).toMatchObject({
      thesisId: "aapl-long-term",
      version: 1,
      kind: "created",
    });

    const amended = await execute(
      tools.get("thesis_amend"),
      {
        ...common,
        expectedRevision: 1,
        eventId: "thesis-v2",
        kind: "amended",
        version: 2,
        parentEventId: "thesis-v1",
        claims: [claim("Revenue growth claim retained after amended filing review", "corrected", marker("8"))],
        reason: "SEC amendment changed the controlling evidence receipt",
        idempotencyKey: "amend-aapl-v2",
      },
      "thesis-amend",
    );
    expect(amended.details.selected.header).toMatchObject({
      version: 2,
      parentEventId: "thesis-v1",
    });
    expect(amended.details.selected.claims[0].evidence[0]).toMatchObject({
      sourceState: "corrected",
      correctedBy: marker("8"),
    });

    const resumedTools = await harness("stock_thesis");
    const resumed = await execute(
      resumedTools.get("thesis_inspect"),
      {
        path,
        maximumBytes: 1_000_000,
        thesisId: "aapl-long-term",
        includeHistory: true,
        includePrivate: false,
        maximumHistory: 10,
      },
      "thesis-resume",
    );
    expect(resumed.details).toMatchObject({
      journalRevision: 2,
      historyCount: 2,
    });
    expect(resumed.details.selected.header.version).toBe(2);

    const comparison = await execute(
      resumedTools.get("thesis_compare"),
      {
        path,
        maximumBytes: 1_000_000,
        thesisId: "aapl-long-term",
        leftVersion: 1,
        rightVersion: 2,
        includePrivate: false,
      },
      "thesis-compare",
    );
    expect(comparison.details.changedClaims).toHaveLength(1);
    expect(comparison.details.comparisonMeaning).toBe(
      "exact_version_snapshot_difference_only",
    );

    await expect(
      execute(
        resumedTools.get("thesis_amend"),
        {
          ...common,
          expectedRevision: 2,
          eventId: "forked-v3",
          kind: "amended",
          version: 3,
          parentEventId: "thesis-v1",
          claims: [claim("Forked claim")],
          reason: "stale branch",
          idempotencyKey: "fork-aapl-v3",
        },
        "thesis-fork",
      ),
    ).rejects.toThrow("parentEventId");
    const stillCurrent = await execute(
      resumedTools.get("thesis_inspect"),
      {
        path,
        maximumBytes: 1_000_000,
        thesisId: "aapl-long-term",
        includeHistory: false,
        includePrivate: false,
        maximumHistory: 0,
      },
      "thesis-after-fork",
    );
    expect(stillCurrent.details.journalRevision).toBe(2);
  });

  test("fails closed on cross-filing calculations, incoherent contexts, and changed import bytes", async () => {
    const fundamentals = await harness("stock_fundamentals");
    await expect(
      execute(
        fundamentals.get("stock_fundamental_metric"),
        {
          cik: "320193",
          metric: "net_margin",
          currencyUnit: "USD",
          period: "annual",
          end: "2024-12-31",
          sourceAccessions: { net_income: "0000320193-25-000080", revenue: "0000320193-25-000079" },
        },
        "cross-filing",
      ),
    ).rejects.toThrow("SourceFilingMismatch");

    const badValuation = await calculationFile(
      "stock_valuation_v1",
      "enterprise_to_equity_per_share",
      [
        operand("enterprise_value", "12000", "USD", marker("2")),
        operand("net_debt", "2000", "USD", marker("3"), "FY2023:original"),
        operand("diluted_shares", "1000", "shares", marker("4")),
      ],
      "USD/share",
    );
    await expect(
      execute(
        (await harness("stock_valuation")).get("inspect_valuation"),
        calcInput(badValuation),
        "bad-context",
      ),
    ).rejects.toThrow("context");

    const governanceFile = await packetFile("changed-governance.json", {
      schemaVersion: 1,
      contractId: "company_governance_v1",
      track: "us",
      subject: { issuerId: "CIK1", listingId: "US1", mic: "XNAS", shareClass: "common" },
      source: { provider: "SEC", authorityRole: "official", documentId: "d1", publishedAt: "2026-01-01", retrievedAt: "2026-01-02", language: "en", rights: "public", sourceUrl: "https://sec/d1" },
      records: [],
      omissions: [],
    });
    await writeFile(governanceFile.path, `${governanceFile.text} `, "utf8");
    await expect(
      execute(
        (await harness("company_governance")).get("company_governance"),
        { ...calcInput(governanceFile), offset: 0, limit: 10 },
        "changed-import",
      ),
    ).rejects.toThrow("expectedSha256");
  });
});

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}
