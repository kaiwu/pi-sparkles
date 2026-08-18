import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

const artifacts = {
  cn: resolve(import.meta.dir, "../../dist/cn_disclosures/index.js"),
  hk: resolve(import.meta.dir, "../../dist/hk_disclosures/index.js"),
};

const saved = {};

beforeEach(() => {
  saved.fetch = globalThis.fetch;
  for (const name of [
    "AGENT_CONTACT",
  ]) {
    saved[name] = process.env[name];
  }
  process.env.AGENT_CONTACT = "fixtures@example.com";
});

afterEach(() => {
  globalThis.fetch = saved.fetch;
  for (const name of [
    "AGENT_CONTACT",
  ]) {
    restore(name, saved[name]);
  }
});

describe("CN/HK official disclosure boundaries", () => {
  test("CN resolves catalogue identity before bounded announcement discovery", async () => {
    const calls = [];
    const securityFixture = JSON.stringify({
      stockList: [
        {
          code: "000001",
          pinyin: "payh",
          category: "A股",
          orgId: "gssz0000001",
          zwjc: "平安银行",
        },
      ],
    });
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      const body = String(url).includes("szse_stock.json")
        ? securityFixture
        : JSON.stringify({
            totalAnnouncement: 1,
            totalpages: 1,
            hasMore: false,
            announcements: [
              {
                secCode: "000001",
                secName: "平安银行",
                orgId: "gssz0000001",
                announcementId: "1225022887",
                announcementTitle: "2025年年度报告",
                announcementTime: 1774022400000,
                adjunctUrl: "finalpage/2026-03-21/1225022887.PDF",
                adjunctSize: 1930,
                announcementType: "01010503||010112||010301",
              },
            ],
          });
      return new Response(body, {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    };

    const tools = await loadTools("cn");
    expect([...tools.keys()]).toEqual([
      "cn_security_search",
      "cn_disclosure_search",
    ]);
    const security = await execute(tools, "cn_security_search", {
      code: "000001",
    });
    expectTrack(security.details, "cn", "cn_cninfo_security_reference");
    expect(security.details.resolution).toBe("unique");
    expect(security.details.candidates[0]).toMatchObject({
      code: "000001",
      organizationId: "gssz0000001",
      shortName: "平安银行",
      venueMic: null,
    });
    const receipt = security.details.currentSecurityReceipt;
    expect(receipt).toMatchObject({
      schema: "pi-sparkles/cninfo-current-security-receipt",
      schemaVersion: 1,
      digestAlgorithm: "sha256",
      track: "cn",
      authorityId: "cn_cninfo_security_catalogue",
      provider: "CNINFO",
      queryCode: "000001",
      catalogueScope: "public_repository_catalogue_snapshot_exact_code_only",
      resolution: "unique",
      claims: {
        repositoryCatalogueResponseAtRetrieval: true,
        venueMic: null,
        board: null,
        shareClass: null,
        currency: null,
        listingEffectiveFrom: null,
        listingEffectiveTo: null,
        tradingStatus: null,
      },
      integrity: {
        state: "sha256_content_bound",
        providerAuthenticated: false,
      },
    });
    expect(receipt.retrievedAtUnixMilliseconds).toBeGreaterThan(0);
    expect(receipt.observedAtUnixMilliseconds).toBe(
      receipt.retrievedAtUnixMilliseconds,
    );
    expect(receipt.evidence.responseByteLength).toBe(
      Buffer.byteLength(securityFixture),
    );
    expect(receipt.evidence.contentSha256).toBe(sha256(securityFixture));
    expect(receipt.evidence.evidenceId).toMatch(/^[0-9a-f]{64}$/);
    expect(receipt.evidence.sourceFingerprint).toMatch(/^[0-9a-f]{64}$/);
    expect(receipt.canonicalDigest).toBe(sha256(canonicalCnReceipt(receipt)));

    calls.length = 0;
    const disclosures = await execute(tools, "cn_disclosure_search", {
      code: "000001",
      startDate: "2025-01-01",
      endDate: "2026-08-05",
      category: "annual",
      pageSize: 3,
    });
    expectTrack(disclosures.details, "cn", "cn_cninfo_disclosure_search");
    expect(disclosures.details.announcements[0]).toMatchObject({
      announcementId: "1225022887",
      title: "2025年年度报告",
      documentUrl:
        "https://static.cninfo.com.cn/finalpage/2026-03-21/1225022887.PDF",
      providerTimeMeaning: "unverified_cninfo_source_field",
    });
    expect(disclosures.details.currentSecurityReceipt).toMatchObject({
      schema: "pi-sparkles/cninfo-current-security-receipt",
      queryCode: "000001",
      resolution: "unique",
    });
    expect(calls.map(({ url }) => url)).toEqual([
      "https://www.cninfo.com.cn/new/data/szse_stock.json",
      "https://www.cninfo.com.cn/new/hisAnnouncement/query",
    ]);
    expect(String(calls[1].init.body)).toContain(
      "stock=000001%2Cgssz0000001",
    );
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-cn-disclosures/0.1 fixtures@example.com",
      );
    }
  });

  test("HK resolves stock ID before preserving bounded title rows", async () => {
    const calls = [];
    const securityFixture =
      'callback({"more":"1","stockInfo":[{"stockId":7609,"code":"00700","name":"TENCENT"}]});';
    const fullListFixture = hkexFullListFixture();
    const recentListingFixture = hkexRecentListingFixture();
    globalThis.fetch = async (url, init) => {
      calls.push({ url: String(url), init });
      if (String(url).includes("ListOfSecurities.xlsx")) {
        return new Response(fullListFixture, {
          status: 200,
          headers: {
            "content-type":
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          },
        });
      }
      if (String(url).includes("Newly-Listed-Securities")) {
        return new Response(recentListingFixture, {
          status: 200,
          headers: { "content-type": "text/html; charset=utf-8" },
        });
      }
      const body = String(url).includes("prefix.do")
        ? securityFixture
        : '<html><input id="stockId" type="hidden" value="7609" /><input id="stockCode" type="hidden" value="00700 TENCENT" /><div class="total-records">Total records found: 259 </div><table><tr><td><span>Release Time: </span>09/07/2026 17:58</td><td><span>Stock Code: </span>00700<br/>80700</td><td><span>Stock Short Name: </span>TENCENT<br/>TENCENT-R</td><td><div class="headline">Next Day Disclosure Returns - [Share Buyback]<br/></div><div class="doc-link"><a href="/listedco/listconews/sehk/2026/0709/2026070900827.pdf" target="_blank">Next Day Disclosure Return</a> (<span class="attachment_filesize">89KB</span>)</div></td></tr></table></html>';
      return new Response(body, {
        status: 200,
        headers: {
          "content-type": String(url).includes("prefix.do")
            ? "application/javascript"
            : "text/html",
        },
      });
    };

    const tools = await loadTools("hk");
    expect([...tools.keys()]).toEqual([
      "hk_security_search",
      "hk_security_profile",
      "hk_recent_listing_event",
      "hk_disclosure_search",
    ]);
    const security = await execute(tools, "hk_security_search", {
      code: "00700",
    });
    expectTrack(security.details, "hk", "hk_hkexnews_security_reference");
    expect(security.details.candidates[0]).toEqual({
      stockId: 7609,
      code: "00700",
      name: "TENCENT",
      venueMic: "XHKG",
    });
    const receipt = security.details.currentSecurityReceipt;
    expect(receipt).toMatchObject({
      schema: "pi-sparkles/hkex-current-security-receipt",
      schemaVersion: 1,
      digestAlgorithm: "sha256",
      track: "hk",
      authorityId: "hk_hkexnews_current_security_catalogue",
      provider: "HKEXnews",
      queryCode: "00700",
      catalogueScope: "current_security_prefix_exact_code_only",
      providerMoreMarker: "1",
      resolution: "unique",
      claims: {
        currentCatalogueResponseAtRetrieval: true,
        venueMic: "XHKG",
        board: null,
        shareClass: null,
        currency: null,
        listingEffectiveFrom: null,
        listingEffectiveTo: null,
        tradingStatus: null,
      },
      integrity: {
        state: "sha256_content_bound",
        providerAuthenticated: false,
      },
    });
    expect(receipt.retrievedAtUnixMilliseconds).toBeGreaterThan(0);
    expect(receipt.observedAtUnixMilliseconds).toBe(
      receipt.retrievedAtUnixMilliseconds,
    );
    expect(receipt.evidence.responseByteLength).toBe(
      Buffer.byteLength(securityFixture),
    );
    expect(receipt.evidence.contentSha256).toBe(sha256(securityFixture));
    expect(receipt.evidence.evidenceId).toMatch(/^[0-9a-f]{64}$/);
    expect(receipt.evidence.sourceFingerprint).toMatch(/^[0-9a-f]{64}$/);
    expect(receipt.canonicalDigest).toBe(sha256(canonicalHkReceipt(receipt)));

    const profile = await execute(tools, "hk_security_profile", {
      code: "00700",
    });
    expectTrack(profile.details, "hk", "hk_hkex_current_security_profile");
    expect(profile.details).toMatchObject({
      provider: "HKEX",
      source:
        "https://www.hkex.com.hk/eng/services/trading/securities/securitieslists/ListOfSecurities.xlsx",
      workbookUpdatedAs: "2026-08-06",
      resolution: "unique",
    });
    expect(profile.details.candidates[0]).toEqual({
      code: "00700",
      name: "TENCENT",
      venueMic: "XHKG",
      category: "Equity",
      subCategory: "Equity Securities (Main Board)",
      board: "main_board",
      boardLot: "100",
      isin: "KYG875721634",
      expiryDate: "",
      subjectToStampDuty: "Y",
      shortsellEligible: "Y",
      casEligible: "Y",
      vcmEligible: "Y",
      admittedToCcass: "Y",
      debtBoardLotNominal: "",
      debtInvestorType: "",
      posEligible: "Y",
      spreadTable: "1 ",
      tradingCurrency: "HKD",
      rmbCounter: "80700",
      listingEffectiveFrom: null,
      listingEffectiveTo: null,
      tradingStatus: null,
    });
    const profileReceipt = profile.details.currentSecurityProfileReceipt;
    expect(profileReceipt).toMatchObject({
      schema: "pi-sparkles/hkex-current-security-profile-receipt",
      schemaVersion: 1,
      digestAlgorithm: "sha256",
      track: "hk",
      authorityId: "hk_hkex_full_list_of_securities",
      provider: "HKEX",
      queryCode: "00700",
      workbookUpdatedAs: "2026-08-06",
      catalogueScope: "current_full_list_exact_code_only",
      resolution: "unique",
      claims: {
        currentFullListProfile: true,
        venueMic: "XHKG",
        listingEffectiveFrom: null,
        listingEffectiveTo: null,
        tradingStatus: null,
      },
      integrity: {
        state: "sha256_content_bound_crc32_entries",
        providerAuthenticated: false,
      },
    });
    expect(profileReceipt.evidence.responseByteLength).toBe(
      fullListFixture.length,
    );
    expect(profileReceipt.evidence.contentSha256).toBe(sha256(fullListFixture));
    expect(profileReceipt.archive.entryCount).toBe(5);
    expect(profileReceipt.archive.extractedEntries).toHaveLength(5);
    for (const entry of profileReceipt.archive.extractedEntries) {
      expect(entry.crc32).toMatch(/^[0-9a-f]{8}$/);
    }
    expect(profileReceipt.canonicalDigest).toBe(
      sha256(canonicalHkProfileReceipt(profileReceipt)),
    );
    expect(calls.at(-1).url).toBe(
      "https://www.hkex.com.hk/eng/services/trading/securities/securitieslists/ListOfSecurities.xlsx",
    );

    const listing = await execute(tools, "hk_recent_listing_event", {
      code: "03308",
    });
    expectTrack(listing.details, "hk", "hk_hkex_recent_listing_event");
    expect(listing.details).toMatchObject({
      provider: "HKEX",
      source:
        "https://www.hkex.com.hk/Services/Trading/Securities/Trading-News/Newly-Listed-Securities?sc_lang=en",
      queryCode: "03308",
      pageUpdatedAs: "2026-08-06",
      windowScope: "rolling_current_two_weeks_only",
      resolution: "unique",
    });
    expect(listing.details.candidates[0]).toEqual({
      eventDate: "2026-07-30",
      tentative: false,
      shortName: "ZJ INNOLIGHT",
      code: "03308",
      venueMic: "XHKG",
      boardLot: "50",
      ccassMarker: "#",
      shortSellMarker: "H",
      stampDutyMarker: "S",
      auctionMarker: "%",
      corporateAction: "New Listing",
      relatedCode: "",
      listingEffectiveFrom: "2026-07-30",
      listingEffectiveTo: null,
      tradingStatus: null,
    });
    const listingReceipt = listing.details.recentListingEventReceipt;
    expect(listingReceipt).toMatchObject({
      schema: "pi-sparkles/hkex-recent-listing-event-receipt",
      schemaVersion: 1,
      digestAlgorithm: "sha256",
      track: "hk",
      authorityId: "hk_hkex_recent_listing_events",
      provider: "HKEX",
      queryCode: "03308",
      pageUpdatedAs: "2026-08-06",
      windowScope: "rolling_current_two_weeks_only",
      resolution: "unique",
      claims: {
        recentListingEvent: true,
        venueMic: "XHKG",
        listingEffectiveFrom: "2026-07-30",
        listingEffectiveTo: null,
        tradingStatus: null,
      },
      integrity: {
        state: "sha256_content_bound",
        providerAuthenticated: false,
      },
    });
    expect(listingReceipt.evidence.responseByteLength).toBe(
      Buffer.byteLength(recentListingFixture),
    );
    expect(listingReceipt.evidence.contentSha256).toBe(
      sha256(recentListingFixture),
    );
    expect(listingReceipt.canonicalDigest).toBe(
      sha256(canonicalHkRecentListingReceipt(listingReceipt)),
    );
    expect(calls.at(-1).url).toBe(
      "https://www.hkex.com.hk/Services/Trading/Securities/Trading-News/Newly-Listed-Securities?sc_lang=en",
    );

    calls.length = 0;
    const disclosures = await execute(tools, "hk_disclosure_search", {
      code: "00700",
      limit: 20,
    });
    expectTrack(disclosures.details, "hk", "hk_hkexnews_disclosure_search");
    expect(disclosures.details.totalRecords).toBe(259);
    expect(disclosures.details.truncated).toBeTrue();
    expect(disclosures.details.documents[0]).toMatchObject({
      codes: ["00700", "80700"],
      names: ["TENCENT", "TENCENT-R"],
      releaseTimezone: "Asia/Hong_Kong",
      documentUrl:
        "https://www1.hkexnews.hk/listedco/listconews/sehk/2026/0709/2026070900827.pdf",
    });
    expect(disclosures.details.currentSecurityReceipt).toMatchObject({
      schema: "pi-sparkles/hkex-current-security-receipt",
      queryCode: "00700",
      resolution: "unique",
    });
    expect(calls).toHaveLength(2);
    expect(calls[0].url).toContain("/search/prefix.do?");
    expect(calls[0].url).toContain("callback=callback");
    expect(calls[1].url).toContain("/search/titlesearch.xhtml?");
    for (const call of calls) {
      expect(call.init.headers.get("user-agent")).toBe(
        "pi-sparkles-hk-disclosures/0.1 fixtures@example.com",
      );
    }
  });
});

async function loadTools(track) {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(
    `${artifacts[track]}?disclosures=${Date.now()}-${Math.random()}`
  );
  await module.default(api);
  return tools;
}

function execute(tools, name, input) {
  return tools.get(name).execute(
    `${name}-test`,
    input,
    new AbortController().signal,
    undefined,
    { hasUI: false, ui: {} },
  );
}

function expectTrack(details, track, marketScope) {
  expect(details.track).toBe(track);
  expect(details.trackContext).toMatchObject({
    schemaVersion: 1,
    track,
    marketScope,
  });
}

function restore(name, value) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}

function canonicalCnReceipt(receipt) {
  return JSON.stringify({
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: receipt.track,
    authority_id: receipt.authorityId,
    provider: receipt.provider,
    source_reference: receipt.sourceReference,
    query_code: receipt.queryCode,
    observed_at_unix_ms: String(receipt.observedAtUnixMilliseconds),
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    catalogue_scope: receipt.catalogueScope,
    evidence_id: receipt.evidence.evidenceId,
    source_fingerprint: receipt.evidence.sourceFingerprint,
    media_type: receipt.evidence.mediaType,
    response_byte_length: String(receipt.evidence.responseByteLength),
    content_sha256: receipt.evidence.contentSha256,
    resolution: receipt.resolution,
    candidates: receipt.candidates.map((candidate) => ({
      code: candidate.code,
      organization_id: candidate.organizationId,
      short_name: candidate.shortName,
      category: candidate.category,
      pinyin: candidate.pinyin,
      venue_mic: candidate.venueMic,
      board: candidate.board,
    })),
    venue_mic: receipt.claims.venueMic,
    board: receipt.claims.board,
    share_class: receipt.claims.shareClass,
    currency: receipt.claims.currency,
    listing_effective_from: receipt.claims.listingEffectiveFrom,
    listing_effective_to: receipt.claims.listingEffectiveTo,
    trading_status: receipt.claims.tradingStatus,
  });
}

function canonicalHkReceipt(receipt) {
  return JSON.stringify({
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: receipt.track,
    authority_id: receipt.authorityId,
    provider: receipt.provider,
    source_reference: receipt.sourceReference,
    query_code: receipt.queryCode,
    observed_at_unix_ms: String(receipt.observedAtUnixMilliseconds),
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    catalogue_scope: receipt.catalogueScope,
    provider_more_marker: receipt.providerMoreMarker,
    evidence_id: receipt.evidence.evidenceId,
    source_fingerprint: receipt.evidence.sourceFingerprint,
    media_type: receipt.evidence.mediaType,
    response_byte_length: String(receipt.evidence.responseByteLength),
    content_sha256: receipt.evidence.contentSha256,
    resolution: receipt.resolution,
    candidates: receipt.candidates.map((candidate) => ({
      stock_id: candidate.stockId,
      code: candidate.code,
      name: candidate.name,
      venue_mic: candidate.venueMic,
    })),
    venue_mic: receipt.claims.venueMic,
    board: receipt.claims.board,
    share_class: receipt.claims.shareClass,
    currency: receipt.claims.currency,
    listing_effective_from: receipt.claims.listingEffectiveFrom,
    listing_effective_to: receipt.claims.listingEffectiveTo,
    trading_status: receipt.claims.tradingStatus,
  });
}

function canonicalHkProfileReceipt(receipt) {
  return JSON.stringify({
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: receipt.track,
    authority_id: receipt.authorityId,
    provider: receipt.provider,
    source_reference: receipt.sourceReference,
    query_code: receipt.queryCode,
    workbook_updated_as: receipt.workbookUpdatedAs,
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    catalogue_scope: receipt.catalogueScope,
    evidence_id: receipt.evidence.evidenceId,
    source_fingerprint: receipt.evidence.sourceFingerprint,
    media_type: receipt.evidence.mediaType,
    response_byte_length: String(receipt.evidence.responseByteLength),
    content_sha256: receipt.evidence.contentSha256,
    archive_entry_count: receipt.archive.entryCount,
    total_uncompressed_bytes: receipt.archive.totalUncompressedBytes,
    extracted_entries: receipt.archive.extractedEntries.map((entry) => ({
      name: entry.name,
      byte_length: entry.byteLength,
      crc32: entry.crc32,
    })),
    resolution: receipt.resolution,
    candidates: receipt.candidates.map((candidate) => ({
      code: candidate.code,
      name: candidate.name,
      category: candidate.category,
      subcategory: candidate.subCategory,
      board: candidate.board,
      board_lot: candidate.boardLot,
      isin: candidate.isin,
      expiry_date: candidate.expiryDate,
      stamp_duty: candidate.subjectToStampDuty,
      short_sell: candidate.shortsellEligible,
      cas: candidate.casEligible,
      vcm: candidate.vcmEligible,
      ccass: candidate.admittedToCcass,
      debt_board_lot: candidate.debtBoardLotNominal,
      debt_investor_type: candidate.debtInvestorType,
      pos: candidate.posEligible,
      spread_table: candidate.spreadTable,
      trading_currency: candidate.tradingCurrency,
      rmb_counter: candidate.rmbCounter,
    })),
    venue_mic: receipt.claims.venueMic,
    listing_effective_from: receipt.claims.listingEffectiveFrom,
    listing_effective_to: receipt.claims.listingEffectiveTo,
    trading_status: receipt.claims.tradingStatus,
  });
}

function canonicalHkRecentListingReceipt(receipt) {
  return JSON.stringify({
    schema: receipt.schema,
    schema_version: receipt.schemaVersion,
    track: receipt.track,
    authority_id: receipt.authorityId,
    provider: receipt.provider,
    source_reference: receipt.sourceReference,
    query_code: receipt.queryCode,
    page_updated_as: receipt.pageUpdatedAs,
    retrieved_at_unix_ms: String(receipt.retrievedAtUnixMilliseconds),
    window_scope: receipt.windowScope,
    evidence_id: receipt.evidence.evidenceId,
    source_fingerprint: receipt.evidence.sourceFingerprint,
    media_type: receipt.evidence.mediaType,
    response_byte_length: String(receipt.evidence.responseByteLength),
    content_sha256: receipt.evidence.contentSha256,
    resolution: receipt.resolution,
    candidates: receipt.candidates.map((candidate) => ({
      event_date: candidate.eventDate,
      tentative: candidate.tentative,
      short_name: candidate.shortName,
      code: candidate.code,
      board_lot: candidate.boardLot,
      ccass_marker: candidate.ccassMarker,
      short_sell_marker: candidate.shortSellMarker,
      stamp_duty_marker: candidate.stampDutyMarker,
      auction_marker: candidate.auctionMarker,
      corporate_action: candidate.corporateAction,
      related_code: candidate.relatedCode,
      listing_effective_from: candidate.listingEffectiveFrom,
    })),
    venue_mic: receipt.claims.venueMic,
    listing_effective_from: receipt.claims.listingEffectiveFrom,
    listing_effective_to: receipt.claims.listingEffectiveTo,
    trading_status: receipt.claims.tradingStatus,
  });
}

function hkexFullListFixture() {
  const contentTypes =
    '<Types><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/></Types>';
  const workbook =
    '<x:workbook><x:sheets><x:sheet name="ListOfSecurities" sheetId="1" r:id="rId1" /></x:sheets></x:workbook>';
  const relationships =
    '<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>';
  const sharedStrings =
    "<x:sst><x:si><x:t>Spread Table</x:t></x:si></x:sst>";
  const headers = [
    ["A", "Stock Code"],
    ["B", "Name of Securities"],
    ["C", "Category"],
    ["D", "Sub-Category"],
    ["E", "Board Lot"],
    ["F", "ISIN"],
    ["G", "Expiry Date"],
    ["H", "Subject to Stamp Duty"],
    ["I", "Shortsell Eligible"],
    ["J", "CAS Eligible"],
    ["K", "VCM Eligible"],
    ["L", "Admitted to CCASS"],
    ["M", "Debt Securities Board Lot (Nominal)"],
    ["N", "Debt Securities Investor Type"],
    ["O", "POS Eligible"],
    ["P", "4"],
    ["Q", "Trading Currency"],
    ["R", "RMB Counter"],
  ];
  const values = [
    ["A", "00700"],
    ["B", "TENCENT"],
    ["C", "Equity"],
    ["D", "Equity Securities (Main Board)"],
    ["E", "100"],
    ["F", "KYG875721634"],
    ["G", ""],
    ["H", "Y"],
    ["I", "Y"],
    ["J", "Y"],
    ["K", "Y"],
    ["L", "Y"],
    ["M", ""],
    ["N", ""],
    ["O", "Y"],
    ["P", "1 "],
    ["Q", "HKD"],
    ["R", "80700"],
  ];
  const worksheet =
    "<x:worksheet><x:sheetData>" +
    xmlRow(2, [["A", "Updated as at 06/08/2026"]]) +
    xmlRow(3, headers) +
    xmlRow(4, values) +
    "</x:sheetData></x:worksheet>";
  return zip([
    ["[Content_Types].xml", contentTypes],
    ["xl/workbook.xml", workbook],
    ["xl/_rels/workbook.xml.rels", relationships],
    ["xl/sharedStrings.xml", sharedStrings],
    ["xl/worksheets/sheet1.xml", worksheet],
  ]);
}

function hkexRecentListingFixture() {
  const header = (value) =>
    `<th style="text-align: center;"><strong><span>${value}</span></strong></th>`;
  const row = ({ date, name, code, action, related = "" }) =>
    `<tr><td style="text-align: center;">${date}</td>` +
    `<td><a href="/quote">${name}</a></td><td>${code}</td><td>50</td>` +
    `<td>#</td><td>H</td><td>S</td><td>%</td><td>${action}</td>` +
    `<td>${related}</td></tr>`;
  return (
    "<html><h2>Newly Listed Securities</h2>" +
    "Newly Listed and/or Traded Securities in the Current&nbsp;Two Weeks" +
    '<table class="table migrate" cellspacing="0"><thead><tr>' +
    [
      "Date of Listing / Traded",
      "Stock Short Name",
      "Stock Code",
      "Board Lot",
      "Remarks",
      "",
      "",
      "",
      "Corresponding Corporate Action",
      "Related Stock Code",
    ]
      .map(header)
      .join("") +
    "</tr></thead><tbody>" +
    row({
      date: "07/08/2026*",
      name: "NASN TECH",
      code: "02261",
      action: "New Listing",
    }) +
    row({
      date: "30/07/2026",
      name: "ZJ INNOLIGHT",
      code: "03308",
      action: "New Listing",
    }) +
    "</tbody></table>* Being the tentative date of&nbsp;listing / traded" +
    '<p class="loadMore__timetag">Updated 06 Aug 2026</p></html>'
  );
}

function xmlRow(number, values) {
  return `<x:row r="${number}">${values
    .map(
      ([column, value]) =>
        `<x:c r="${column}${number}" t="str"><x:v>${value}</x:v></x:c>`,
    )
    .join("")}</x:row>`;
}

function zip(entries) {
  const localParts = [];
  const centralParts = [];
  let localOffset = 0;
  for (const [nameValue, text] of entries) {
    const name = Buffer.from(nameValue, "utf8");
    const body = Buffer.from(text, "utf8");
    const checksum = crc32(body);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(body.length, 22);
    local.writeUInt16LE(name.length, 26);
    localParts.push(local, name, body);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(body.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(localOffset, 42);
    centralParts.push(central, name);
    localOffset += local.length + name.length + body.length;
  }
  const central = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(central.length, 12);
  eocd.writeUInt32LE(localOffset, 16);
  return Buffer.concat([...localParts, central, eocd]);
}

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    }
  }
  return (value ^ 0xffffffff) >>> 0;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}
