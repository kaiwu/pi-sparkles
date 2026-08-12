import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

let directory;
const sha = (value) => createHash("sha256").update(value).digest("hex");
const receipt = (name) => sha(`t5:${name}`);

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "pi-sparkles-t5-"));
});

afterAll(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
});

async function harness(name) {
  const tools = new Map();
  const api = { registerTool(definition) { tools.set(definition.name, definition); } };
  const artifact = resolve(import.meta.dir, `../../../dist/${name}/index.js`);
  const module = await import(`${artifact}?t5=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return tools;
}

function execute(tool, input, id = "t5-role") {
  return tool.execute(id, input, new AbortController().signal, undefined, { hasUI: false, ui: {} });
}

async function invoke(plugin, toolName, packet, id = toolName) {
  const text = JSON.stringify(packet);
  const path = join(directory, `${id}.json`);
  await writeFile(path, text, "utf8");
  const tools = await harness(plugin);
  expect([...tools.keys()]).toEqual([toolName]);
  return execute(tools.get(toolName), {
    path,
    expectedSha256: sha(text),
    maximumBytes: 5_000_000,
  }, id);
}

function source(id, kind = "scripted_fixture") {
  return {
    sourceId: id,
    sourceKind: kind,
    sourceUri: `fixture://t5/${id}`,
    observedAtUnixMilliseconds: 1_000,
    retrievedAtUnixMilliseconds: 1_100,
    entitlement: "local acceptance analysis",
    licence: "rights-safe deterministic fixture",
    coverage: "bounded complete acceptance sample",
    correctionState: "original",
    receipt: receipt(`source:${id}`),
  };
}

function fact(raw, unit, id, observed = 1_000) {
  return {
    state: "known",
    raw: String(raw),
    unit,
    observedAtUnixMilliseconds: observed,
    reason: null,
    alternatives: [],
    receipts: [receipt(`fact:${id}`)],
  };
}

function packet(contractId, operation, fields) {
  return { schemaVersion: 1, contractId, operation, ...fields };
}

function ipoPacket() {
  return packet("cn_ipo_v1", "analyze", {
    source: source("cn-ipo", "official_public"),
    identity: {
      issuerNameCn: "示例科技股份有限公司", stockCodeProposed: "688999", stockCodeFinal: "688999",
      board: "star", mic: "XSHG", shareClass: "A-share", sponsor: "示例证券",
      accountingFirm: "示例会计师事务所", lawFirm: "示例律师事务所",
    },
    stateHistory: [
      { eventId: "accepted-1", state: "accepted", effectiveDate: "2026-01-02", publicationDate: "2026-01-02", sequence: 1, receipt: receipt("ipo-state-1"), correctsReceipt: null },
      { eventId: "listed-2", state: "listed", effectiveDate: "2026-08-01", publicationDate: "2026-08-01", sequence: 2, receipt: receipt("ipo-state-2"), correctsReceipt: null },
    ],
    offer: {
      currency: "CNY",
      preIpoShares: fact("300000000", "shares", "ipo-pre"),
      newShares: fact("100000000", "shares", "ipo-new"),
      totalOffered: fact("100000000", "shares", "ipo-total"),
      offerPrice: fact("20", "CNY_per_share", "ipo-price"),
      listingClose: fact("25", "CNY_per_share", "ipo-close"),
    },
  });
}

function fundPacket(contractId, listed) {
  return packet(contractId, "analyze", {
    source: source(listed ? "cn-etf" : "cn-mutual"),
    identity: {
      fundId: listed ? "fund:510300" : "fund:000001",
      shareClassId: listed ? "class:510300" : "class:A",
      fundName: listed ? "沪深300ETF" : "示例混合A",
      fundType: listed ? "ETF" : "MutualFund",
      listingKind: listed ? "listed" : "not_applicable",
      listingId: listed ? "listing:510300:XSHG" : null,
      mic: listed ? "XSHG" : null,
      manager: "示例基金管理人", benchmark: "caller-declared benchmark",
      baseCurrency: "CNY", shareClassCurrency: "CNY", distributionPolicy: "accumulating",
      inceptionDate: "2020-01-02", status: "active", identityReceipt: receipt(`${contractId}:identity`),
    },
    navStart: fact("1.00", "CNY_per_share", `${contractId}:nav-start`),
    navEnd: fact("1.10", "CNY_per_share", `${contractId}:nav-end`),
    distribution: fact("0.02", "CNY_per_share", `${contractId}:distribution`),
    marketPrice: fact("1.111", "CNY_per_share", `${contractId}:market`),
    navAtMarket: fact("1.10", "CNY_per_share", `${contractId}:nav-market`),
    grossReturn: fact("0.12", "fraction", `${contractId}:gross`),
    netReturn: fact("0.115", "fraction", `${contractId}:net`),
    holdings: {
      holdingsDate: "2026-06-30", publicationDate: "2026-07-20", topNComplete: false,
      disclosedCount: 10, totalCount: null, rights: "local display only", receipt: receipt(`${contractId}:holdings`),
    },
    dealingPolicy: listed ? "exchange_traded" : "daily_nav_subscription_redemption",
  });
}

function convertiblePacket() {
  const scenario = (id, kind, price) => ({ scenarioId: id, kind, underlyingPrice: fact(price, "CNY_per_share", `cb:${id}`), receipt: receipt(`cb:${id}`) });
  return packet("cn_convertible_bonds_v1", "analyze", {
    source: source("cn-convertible"),
    identity: {
      instrumentId: "bond:113999:XSHG", issuerId: "issuer:demo", underlyingListingId: "listing:688999:XSHG",
      underlyingMic: "XSHG", currency: "CNY", issueDate: "2025-01-02", maturityDate: "2031-01-02",
      termsVersion: "2026-07-01", termsReceipt: receipt("cb:terms"),
    },
    faceValue: fact("100", "CNY_per_bond", "cb:face"),
    conversionPrice: fact("10", "CNY_per_share", "cb:conversion"),
    underlyingPrice: fact("12", "CNY_per_share", "cb:underlying"),
    bondPrice: fact("125", "CNY_per_bond", "cb:bond"),
    bondFloor: fact("95", "CNY_per_bond", "cb:floor"),
    callPrice: fact("102", "CNY_per_bond", "cb:call"),
    putPrice: fact("100", "CNY_per_bond", "cb:put"),
    maturityRedemption: fact("110", "CNY_per_bond", "cb:maturity"),
    scenarios: [scenario("call", "call", "12"), scenario("convert", "convert", "14"), scenario("hold", "hold", "12"), scenario("put", "put", "9")],
    adjustmentReceipts: [receipt("cb:adjustment")],
  });
}

function cnMacroPacket() {
  return packet("cn_macro_v1", "analyze", {
    source: source("nbs", "official_public"), publisher: "NBS", seriesId: "NBS:CPI:MONTHLY",
    titleCn: "居民消费价格指数", geography: "CN", unit: "index", scale: "1",
    frequency: "monthly", seasonalAdjustment: "not_seasonally_adjusted",
    currentPeriod: "2026-07", previousPeriod: "2026-06", knowledgeCutoffUnixMilliseconds: 2_000,
    observations: [
      { period: "2026-06", rawValue: "100.1", publicationUnixMilliseconds: 900, vintageUnixMilliseconds: 900, revision: "original", receipt: receipt("cn-macro:june") },
      { period: "2026-07", rawValue: "100.4", publicationUnixMilliseconds: 1_000, vintageUnixMilliseconds: 1_000, revision: "original", receipt: receipt("cn-macro:july") },
      { period: "2026-07", rawValue: "100.5", publicationUnixMilliseconds: 1_100, vintageUnixMilliseconds: 2_500, revision: "later_revision", receipt: receipt("cn-macro:july-later") },
    ],
  });
}

function policyPacket() {
  return packet("cn_policy_monitor_v1", "inspect", {
    source: source("state-council", "official_public"),
    documents: [{
      documentId: "policy:2026:1", publisher: "StateCouncil", authorityRole: "issuing_authority",
      titleCn: "关于示例政策的通知", language: "zh-CN", documentType: "notice", documentNumber: "国发〔2026〕1号",
      publicationDate: "2026-08-01", effectiveDate: "2026-09-01", jurisdictionScope: "CN",
      marketScope: "multi-asset research context", status: "final", correctionLineage: [],
      sourceUrl: "https://www.gov.cn/example", receipt: receipt("policy:document"),
    }],
  });
}

function treasuryPacket() {
  return packet("rates_treasury_v1", "inspect", {
    source: source("us-treasury", "official_public"), observationKind: "cmt_rate",
    instrumentId: null, seriesId: "DGS10", securityType: "CMT", maturity: "10Y",
    currency: "USD", rateKind: "constant_maturity", frequency: "daily", unit: "percent",
    rawValue: "4.125", observationDate: "2026-08-11", publicationUnixMilliseconds: 1_000,
    vintageDate: "2026-08-11", onTheRun: null, auctionDate: null,
    observationReceipt: receipt("treasury:observation"),
  });
}

function fxPacket() {
  return packet("fx_ecb_v1", "calculate", {
    source: source("ecb", "official_public"), effectiveDate: "2026-08-11",
    publicationAtUnixMilliseconds: 1_000, targetCalendarReceipt: receipt("target-calendar"),
    pivotCurrency: "EUR", baseCurrency: "USD", quoteCurrency: "CNY",
    amount: fact("100", "USD", "fx:amount"),
    basePerPivot: fact("1.25", "USD_per_EUR", "fx:usd", 1_000),
    quotePerPivot: fact("7.50", "CNY_per_EUR", "fx:cny", 1_000),
  });
}

function bondPacket() {
  return packet("fixed_income_v1", "analyze", {
    source: source("bond-terms"),
    identity: {
      instrumentId: "bond:US-DEMO-2031", issuerId: "issuer:demo", issuerName: "Demo Issuer", currency: "USD",
      couponType: "fixed", couponFrequency: 2, dayCountConvention: "ACT/ACT", paymentConvention: "following",
      holidayCalendar: "US-FEDERAL-v1", issueDate: "2026-01-01", maturityDate: "2031-01-01",
      status: "active", termsReceipt: receipt("bond:terms"),
    },
    settlementDate: "2026-08-12", faceValue: fact("100", "USD", "bond:face"),
    couponRate: fact("0.05", "fraction_per_year", "bond:coupon"), cleanPrice: fact("98", "USD", "bond:clean"),
    accruedInterest: fact("1", "USD", "bond:accrued"),
    cashFlows: [
      { paymentDate: "2027-08-12", amount: "5.0", yearsFromSettlement: "1.0", state: "known", receipt: receipt("bond:flow1") },
      { paymentDate: "2028-08-12", amount: "5.0", yearsFromSettlement: "2.0", state: "known", receipt: receipt("bond:flow2") },
      { paymentDate: "2031-01-01", amount: "105.0", yearsFromSettlement: "4.4", state: "known", receipt: receipt("bond:flow3") },
    ],
    solver: { method: "bisection_v1", lowerYield: "-0.1", upperYield: "1.0", tolerance: "0.000001", maximumIterations: 100, compoundingFrequency: 2, shock: "0.0001" },
    benchmark: { instrumentId: "UST:CMT:5Y", yield: "0.04", dayCountConvention: "ACT/ACT", compoundingFrequency: 2, receipt: receipt("bond:benchmark") },
    curveId: "UST-zero-2026-08-12", curveMethod: "linear_zero_v1", extrapolation: "none",
    curveKnots: [
      { tenorYears: "1.0", zeroRate: "0.035", receipt: receipt("curve:1") },
      { tenorYears: "5.0", zeroRate: "0.045", receipt: receipt("curve:5") },
    ],
    requestedTenorYears: "3.0",
  });
}

function optionsPacket() {
  return packet("options_v1", "analyze", {
    source: source("options-chain"),
    identity: {
      optionId: "OCC:DEMO:20270115:C:100", underlyingListingId: "listing:DEMO:XNAS", underlyingMic: "XNAS",
      underlyingTrack: "us", optionVenue: "XNAS", rootSymbol: "DEMO", callPut: "call", style: "european",
      strike: "100.0", expirationDate: "2027-01-15", multiplier: 100, settlement: "physical",
      deliverableKind: "standard", currency: "USD", contractVersion: "2026-08-12",
      identityReceipt: receipt("option:identity"), adjustmentLineage: [],
    },
    quote: { bid: "9.8", bidSize: 10, ask: "10.2", askSize: 12, observedPrice: "10.0", observedPriceKind: "mid", quoteUnixMilliseconds: 1_000, receiptUnixMilliseconds: 1_100, entitlement: "delayed fixture", state: "known", receipt: receipt("option:quote") },
    legs: [{ optionId: "OCC:DEMO:20270115:C:100", callPut: "call", strike: "100.0", multiplier: 100, direction: "long", quantity: 1, entryPremium: "10.0", receipt: receipt("option:leg") }],
    underlyingGrid: ["80.0", "100.0", "120.0"],
    pricing: {
      model: "black_scholes_v1", spot: "105.0", timeYears: "0.5", volatility: "0.25", riskFreeRate: "0.04", dividendYield: "0.01",
      steps: 100, sigmaLower: "0.01", sigmaUpper: "2.0", tolerance: "0.000001", maximumIterations: 100,
      spotBump: "0.01", volatilityBump: "0.001", rateBump: "0.0001", timeBump: "0.0001",
      inputReceipts: [receipt("option:model-inputs")],
    },
  });
}

function commodityContract(id, product, ordinal, settle) {
  return {
    contractId: id, productCode: product, exchange: "XCBT", deliveryMonth: ordinal === 1 ? "2026-09" : "2026-12",
    deliveryOrdinal: ordinal, contractSize: "5000", sizeUnit: "bushels", multiplier: "5000",
    quotationUnit: "USD_per_bushel", tickSize: "0.0025", tickValue: "12.5", currency: "USD",
    settlementType: "physical", lastTradeDate: ordinal === 1 ? "2026-09-14" : "2026-12-14",
    firstNoticeDate: ordinal === 1 ? "2026-08-31" : "2026-11-30", specificationVersion: "2026",
    specificationReceipt: receipt(`${id}:spec`), settle: fact(settle, "USD_per_bushel", `${id}:settle`),
    volume: fact(ordinal === 1 ? "1000" : "800", "contracts", `${id}:volume`),
    openInterest: fact(ordinal === 1 ? "5000" : "4000", "contracts", `${id}:oi`),
    observationReceipt: receipt(`${id}:observation`),
  };
}

function commoditiesPacket() {
  const near = commodityContract("ZC-U26", "ZC", 1, "4.20");
  const far = commodityContract("ZC-Z26", "ZC", 2, "4.40");
  return packet("commodities_v1", "analyze", {
    source: source("cme-settlements"), asOfDate: "2026-08-11", sessionType: "settlement",
    calendarReceipt: receipt("xcbt-calendar"), contracts: [near, far], nearContractId: near.contractId,
    farContractId: far.contractId, interCommodityContractA: near.contractId, interCommodityContractB: far.contractId,
    rollMethod: "roll_fixed_date_v1", rollParameters: "five business days before first notice",
    rollEvents: [{ rollDate: "2026-08-24", fromContractId: near.contractId, toContractId: far.contractId,
      fromSettle: near.settle, toSettle: far.settle, weighting: "100_percent_on_roll_date", receipt: receipt("roll:event") }],
  });
}

function cotPacket() {
  return packet("cftc_cot_v1", "analyze", {
    source: source("cftc", "official_public"), reportId: "CFTC:ZC:2026-08-04", reportType: "cftc_disaggregated",
    marketCode: "002602", marketName: "CORN - CHICAGO BOARD OF TRADE", futuresOnly: true,
    reportDate: "2026-08-04", releaseDate: "2026-08-07", reportLagDays: 3,
    taxonomyVersion: "disaggregated-2026", revision: "original",
    categories: [{ name: "managed_money", long: fact("200000", "contracts", "cot:long"), short: fact("120000", "contracts", "cot:short"), spreading: fact("10000", "contracts", "cot:spread"), priorNet: fact("70000", "contracts", "cot:prior") }],
    selectedCategory: "managed_money",
    historicalWindow: [
      { reportDate: "2026-07-21", net: fact("60000", "contracts", "cot:h1") },
      { reportDate: "2026-07-28", net: fact("70000", "contracts", "cot:h2") },
      { reportDate: "2026-08-04", net: fact("80000", "contracts", "cot:h3") },
    ],
    crosswalkState: "probable", knownContracts: ["ZC-U26"], reportReceipt: receipt("cot:report"),
  });
}

function cryptoQuote(id, venue, bid, ask, time, sequence) {
  return {
    venue, venueInstrumentId: "BTC-USDC", bid: fact(bid, "USDC_per_BTC", `${id}:bid`, time),
    bidSize: fact("1.5", "BTC", `${id}:bid-size`, time), ask: fact(ask, "USDC_per_BTC", `${id}:ask`, time),
    askSize: fact("1.2", "BTC", `${id}:ask-size`, time), venueUnixMilliseconds: time,
    receiptUnixMilliseconds: time + 50, sequence, receipt: receipt(`${id}:quote`),
  };
}

function cryptoPacket() {
  const level = (side, price, size) => ({ price: fact(price, "USDC_per_BTC", `book:${side}:price`), size: fact(size, "BTC", `book:${side}:size`) });
  return packet("crypto_market_v1", "inspect", {
    source: source("crypto-venue"),
    identity: {
      assetId: "asset:bitcoin", network: "bitcoin-mainnet", tokenStandard: "native", contractAddress: null,
      tokenSymbol: "BTC", venue: "DemoExchange", venueInstrumentId: "BTC-USDC", baseAssetId: "asset:bitcoin",
      quoteAssetId: "asset:usdc", instrumentType: "spot", venueType: "CEX", stablecoinQuote: true,
      wrappedAssetId: null, identityReceipt: receipt("crypto:identity"),
    },
    quote: cryptoQuote("primary", "DemoExchange", "60000", "60010", 10_000, 100),
    comparisonQuote: cryptoQuote("comparison", "OtherExchange", "59990", "60020", 10_100, 200),
    maximumTimeDeltaMilliseconds: 500,
    trades: [{ tradeId: "trade-1", price: fact("60005", "USDC_per_BTC", "trade:price", 10_050),
      size: fact("0.1", "BTC", "trade:size", 10_050), venueUnixMilliseconds: 10_050,
      sequence: 101, side: "buy", correctionLineage: [], receipt: receipt("trade:1") }],
    candle: { interval: "1m", boundaryConvention: "utc_half_open", openUnixMilliseconds: 10_000,
      closeUnixMilliseconds: 70_000, open: fact("60000", "USDC_per_BTC", "candle:open"),
      high: fact("60020", "USDC_per_BTC", "candle:high"), low: fact("59990", "USDC_per_BTC", "candle:low"),
      close: fact("60005", "USDC_per_BTC", "candle:close"), volume: fact("25", "BTC", "candle:volume"),
      receipt: receipt("candle:1") },
    orderBook: { venueUnixMilliseconds: 10_000, sequence: 100, bids: [level("bid", "60000", "1.5")],
      asks: [level("ask", "60010", "1.2")], receipt: receipt("book:1") },
    venueStatus: { status: "operational", reason: "venue self-reported normal operation", sourceRole: "venue_self_reported",
      jurisdiction: "unknown", custodyModel: "custodial", unknownFacts: ["reserve completeness unknown"],
      effectiveDate: "2026-08-12", receipt: receipt("venue:status") },
    fundingContext: { derivativeInstrumentId: "BTC-USDC-PERP", rate: fact("0.0001", "fraction_per_8h", "funding:rate"),
      interval: "8h", markPrice: fact("60008", "USDC_per_BTC", "funding:mark"),
      indexPrice: fact("60004", "USDC_per_BTC", "funding:index"), openInterest: fact("10000", "BTC", "funding:oi"),
      openInterestUnit: "BTC", venueUnixMilliseconds: 10_000, receipt: receipt("funding:1") },
    events: [{ eventId: "migration-1", eventType: "token_migration", effectiveUnixMilliseconds: 5_000,
      legacyAssetId: "asset:usdc-old", newAssetId: "asset:usdc", sourceDescription: "issuer-published migration fixture",
      receipt: receipt("crypto:event") }],
    entitlement: "local fixture analysis", licence: "rights-safe deterministic fixture",
  });
}

function dashboardPacket(cnReceipt, fredReceipt) {
  const observation = (date, raw, id, vintage = 1_000) => ({
    periodDate: date, vintageAtUnixMilliseconds: vintage, correctionState: "original",
    value: fact(raw, "index", `dashboard:${id}`), receipt: receipt(`dashboard:${id}`),
  });
  return packet("macro_dashboard_v1", "compose", {
    knowledgeCutoffUnixMilliseconds: 2_000,
    alignmentPolicy: "intersection_of_selected_period_dates",
    panels: [
      { panelId: "cn-cpi", title: "CN CPI", seriesId: "NBS:CPI", geography: "CN", nativeFrequency: "monthly",
        unit: "index", transform: "period_percent_change", entitlement: "public", licence: "source terms",
        sourceReceipt: cnReceipt, observations: [observation("2026-06-01", "100.1", "cn-1"), observation("2026-07-01", "100.4", "cn-2")] },
      { panelId: "us-cpi", title: "US CPI", seriesId: "FRED:CPIAUCSL", geography: "US", nativeFrequency: "monthly",
        unit: "index", transform: "rebase_100", entitlement: "series dependent", licence: "FRED/source terms",
        sourceReceipt: fredReceipt, observations: [observation("2026-06-01", "320.5", "us-1"), observation("2026-07-01", "321.1", "us-2")] },
    ],
    handoffReceipts: [cnReceipt, fredReceipt],
  });
}

function globalPacket(handoffReceipts) {
  const leg = (legId, track, kind, instrumentId, name, mic, currency, timezone, values) => ({
    legId, track, instrumentKind: kind, instrumentId, displayName: name, mic, currency, timezone,
    calendarReceipt: receipt(`${legId}:calendar`), sourceReceipt: receipt(`${legId}:source`),
    points: values.map(([date, raw, state], index) => ({ localDate: date, sessionState: state,
      value: fact(raw, currency, `${legId}:point:${index}`), observationReceipt: receipt(`${legId}:point:${index}`) })),
  });
  return packet("global_markets_v1", "compare", {
    alignmentPolicy: "intersection_of_open_local_session_dates", returnMethod: "simple_return_in_native_currency",
    legs: [
      leg("cn-index", "cn", "index", "index:000300", "CSI 300", "XSHG", "CNY", "Asia/Shanghai", [["2026-08-07", "4000", "open_complete"], ["2026-08-10", "4020", "open_complete"], ["2026-08-11", "4050", "open_complete"], ["2026-08-12", "4055", "closed"]]),
      leg("hk-etf", "hk", "etf", "listing:02800:XHKG", "Tracker Fund", "XHKG", "HKD", "Asia/Hong_Kong", [["2026-08-07", "24", "open_complete"], ["2026-08-10", "24.2", "open_complete"], ["2026-08-11", "24.1", "open_complete"]]),
      leg("us-index", "us", "index", "index:SPX", "S&P 500", "XNYS", "USD", "America/New_York", [["2026-08-07", "6500", "open_complete"], ["2026-08-10", "6520", "open_complete"], ["2026-08-11", "6510", "open_complete"]]),
    ],
    handoffReceipts,
  });
}

function fredFixtures() {
  const metadata = { realtime_start: "2026-08-12", realtime_end: "2026-08-12", seriess: [{
    id: "CPIAUCSL", realtime_start: "2026-08-12", realtime_end: "2026-08-12",
    title: "Consumer Price Index for All Urban Consumers", observation_start: "1947-01-01", observation_end: "2026-07-01",
    frequency: "Monthly", frequency_short: "M", units: "Index 1982-1984=100", units_short: "Index",
    seasonal_adjustment: "Seasonally Adjusted", seasonal_adjustment_short: "SA", last_updated: "2026-08-11 07:42:02-05", popularity: 95,
  }] };
  const observations = { realtime_start: "2026-08-12", realtime_end: "2026-08-12",
    observation_start: "2026-06-01", observation_end: "2026-07-31", units: "lin", output_type: 1,
    file_type: "json", order_by: "observation_date", sort_order: "asc", count: 2, offset: 0, limit: 24,
    observations: [
      { realtime_start: "2026-08-12", realtime_end: "2026-08-12", date: "2026-06-01", value: "320.500" },
      { realtime_start: "2026-08-12", realtime_end: "2026-08-12", date: "2026-07-01", value: "321.10" },
    ] };
  return { metadata: JSON.stringify(metadata), observations: JSON.stringify(observations) };
}

describe("T5 macro and multi-asset researcher product", () => {
  test("completes one global role journey across all 16 proposals with typed receipts and honest boundaries", async () => {
    const originalFetch = globalThis.fetch;
    const originalKey = process.env.FRED_API_KEY;
    const fixtures = fredFixtures();
    process.env.FRED_API_KEY = "abcdefghijklmnopqrstuvwxyz123456";
    globalThis.fetch = async (url) => {
      const path = new URL(url).pathname;
      const body = path.endsWith("/series") ? fixtures.metadata : fixtures.observations;
      return new Response(body, { status: 200, headers: { "content-type": "application/json", "x-request-id": `t5-${path}` } });
    };

    try {
      const ipo = await invoke("cn_ipo", "cn_ipo_research", ipoPacket());
      expect(ipo.details.result).toMatchObject({ track: "cn", currentState: "listed" });
      expect(ipo.details.result.calculations.dilutionPercent.state).toBe("calculated");

      const convertible = await invoke("cn_convertible_bonds", "cn_convertible_analyze", convertiblePacket());
      expect(convertible.details.result.scenarios).toHaveLength(4);
      expect(convertible.details.result.calculations.conversionPremiumPercent.state).toBe("calculated");

      const etf = await invoke("cn_funds_etf", "cn_fund_etf_analyze", fundPacket("cn_funds_etf_v1", true));
      const mutual = await invoke("cn_mutual_funds", "cn_mutual_fund_analyze", fundPacket("cn_mutual_funds_v1", false));
      expect(etf.details.result.identity).toMatchObject({ listingKind: "listed", mic: "XSHG" });
      expect(etf.details.result.calculations.premiumDiscountPercent.state).toBe("calculated");
      expect(mutual.details.result.identity).toMatchObject({ listingKind: "not_applicable", mic: null });
      expect(mutual.details.result.calculations.feeDrag.state).toBe("calculated");

      const cnMacro = await invoke("cn_macro", "cn_macro_series", cnMacroPacket());
      expect(cnMacro.details.result.selectedCurrent.rawValue).toBe("100.4");
      expect(cnMacro.details.result.allVintages).toHaveLength(3);

      const policy = await invoke("cn_policy_monitor", "cn_policy_documents", policyPacket());
      expect(policy.details.result.documents[0]).toMatchObject({ language: "zh-CN", publisher: "StateCouncil" });

      const fredTools = await harness("macro_fred");
      const fred = await execute(fredTools.get("fred_series"), {
        seriesId: "CPIAUCSL", observationStart: "2026-06-01", observationEnd: "2026-07-31",
        asOfDate: "2026-08-12", maximumObservations: 24,
      }, "fred-anchor");
      expect(fred.details).toMatchObject({ track: null, observationCount: 2 });
      expect(fred.details.change.value).toBe("0.6");
      const fredReceipt = fred.details.source.observations.contentSha256;
      expect(fredReceipt).toHaveLength(64);

      const treasury = await invoke("rates_treasury", "treasury_rate_inspect", treasuryPacket());
      expect(treasury.details.result).toMatchObject({ observationKind: "cmt_rate", tradable: false, seriesId: "DGS10" });

      const fxText = JSON.stringify(fxPacket());
      const fxPath = join(directory, "fx-recovery.json");
      await writeFile(fxPath, fxText, "utf8");
      const fxTools = await harness("fx_ecb");
      await expect(execute(fxTools.get("ecb_fx_calculate"), { path: fxPath, expectedSha256: receipt("wrong-fx"), maximumBytes: 5_000_000 }, "fx-rejected")).rejects.toThrow("expectedSha256");
      const fx = await execute(fxTools.get("ecb_fx_calculate"), { path: fxPath, expectedSha256: sha(fxText), maximumBytes: 5_000_000 }, "fx-recovered");
      expect(fx.details.result.crossRate.value).toBe("6");
      expect(fx.details.result.rateKind).toBe("ecb_reference_not_executable_quote");

      const bond = await invoke("fixed_income", "fixed_income_analyze", bondPacket());
      expect(bond.details.result.curve).toMatchObject({ method: "linear_zero_v1", extrapolation: "none" });
      expect(bond.details.result.dirtyPrice.value).toBe("99");

      const options = await invoke("options", "options_analyze", optionsPacket());
      expect(options.details.result.identity).toMatchObject({ style: "european", underlyingTrack: "us" });
      expect(options.details.result.payoffGrid).toHaveLength(3);
      expect(options.details.result.pricing.price.state).toBe("calculated");

      const cot = await invoke("cftc_cot", "cot_analyze", cotPacket());
      expect(cot.details.result).toMatchObject({ crosswalk: { state: "probable" }, selectedCategory: "managed_money" });
      expect(cot.details.result.calculations.netPosition.value).toBe("80000");

      const commodities = await invoke("commodities", "commodities_analyze", commoditiesPacket());
      expect(commodities.details.result.curve).toHaveLength(2);
      expect(commodities.details.result.rollArtifact.continuousSeriesKind).toContain("calculated");

      const crypto = await invoke("crypto_market", "crypto_market_inspect", cryptoPacket());
      expect(crypto.details.result).toMatchObject({ track: null, instrumentLeg: "crypto_non_equity", identity: { stablecoinIsFiat: false } });
      expect(crypto.details.result.crossVenueComparison.alignedUnderCallerPolicy).toBe(true);

      const dashboard = await invoke("macro_dashboard", "macro_dashboard_compose", dashboardPacket(cnMacro.details.resultReceipt, fredReceipt));
      expect(dashboard.details.result).toMatchObject({ directAcquisition: false, alignmentPolicy: "intersection_of_selected_period_dates" });
      expect(dashboard.details.result.matchedDates).toEqual(["2026-06-01", "2026-07-01"]);
      expect(dashboard.details.result.handoffReceipts).toEqual([cnMacro.details.resultReceipt, fredReceipt]);

      const handoffs = [ipo.details.resultReceipt, etf.details.resultReceipt, treasury.details.resultReceipt, fx.details.resultReceipt, crypto.details.resultReceipt, dashboard.details.resultReceipt];
      const global = await invoke("global_markets", "global_markets_compare", globalPacket(handoffs));
      expect(global.details.result.matchedDates).toEqual(["2026-08-07", "2026-08-10", "2026-08-11"]);
      expect(global.details.result.currencyPolicy).toBe("native_no_fx_conversion");
      expect(global.details.result.legs.map((leg) => [leg.track, leg.instrumentKind])).toEqual([["cn", "index"], ["hk", "etf"], ["us", "index"]]);
      expect(global.details.result.legs[0].unmatchedPoints).toHaveLength(1);
      expect(global.details.result.handoffReceipts).toEqual(handoffs);

      const complete = { ipo, convertible, etf, mutual, cnMacro, policy, fred, treasury, fx, bond, options, cot, commodities, crypto, dashboard, global };
      const text = JSON.stringify(complete);
      expect(text).toContain("content_binding_only_not_origin_authentication");
      expect(text).not.toMatch(/"(recommendation|fairValue|preferredLeg|nextAction)"\s*:/);
      expect(fred.details.scope.forecast).toBeNull();
      expect(crypto.details.result.venueStatus.safetyVerdict).toBeNull();
      expect(new Set(Object.values(complete).map((value) => value.details.contractId ?? value.details.schema)).size).toBe(16);
    } finally {
      globalThis.fetch = originalFetch;
      if (originalKey === undefined) delete process.env.FRED_API_KEY;
      else process.env.FRED_API_KEY = originalKey;
    }
  });
});
