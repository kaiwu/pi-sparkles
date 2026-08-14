import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

import { probeLimits, runLiveProbe } from "./futu-us-ticker-probe.js";

const sdkVersion = "10.10.7008";
const websocketHost = "127.0.0.1";
const websocketPort = 33333;
const liveConfirmation = "I_ACCEPT_ONE_FUTU_CN_TICKER_SUBSCRIPTION";
const reviewedAnchors = Object.freeze({
  XSHG: Object.freeze({ symbol: "SH.600519", providerMarket: 21 }),
  XSHE: Object.freeze({ symbol: "SZ.000001", providerMarket: 22 }),
});

export function validateCnProbeConfig(argv, environment, now = new Date()) {
  const live = argv.includes("--live");
  const unexpected = argv.filter((argument) => argument !== "--live");
  if (unexpected.length > 0) {
    throw new Error("unsupported_argument");
  }
  if (!live) {
    return {
      live: false,
      symbol: null,
      mic: null,
      expectedDate: null,
      now,
    };
  }

  const symbol = environment.FUTU_PROBE_SYMBOL ?? "";
  const mic = environment.FUTU_PROBE_MIC ?? "";
  const expectedDate = environment.FUTU_PROBE_EXPECTED_CN_DATE ?? "";
  const anchor = reviewedAnchors[mic];

  if (!anchor || anchor.symbol !== symbol) {
    throw new Error("unreviewed_cn_anchor");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(expectedDate)) {
    throw new Error("missing_reviewed_cn_date");
  }
  if (environment.FUTU_LIVE_CONFIRM !== liveConfirmation) {
    throw new Error("live_confirmation_missing");
  }
  if (
    environment.FUTU_OPEND_HOST !== undefined &&
    environment.FUTU_OPEND_HOST !== websocketHost
  ) {
    throw new Error("non_localhost_endpoint_forbidden");
  }
  if (
    environment.FUTU_OPEND_WEBSOCKET_PORT !== undefined &&
    environment.FUTU_OPEND_WEBSOCKET_PORT !== String(websocketPort)
  ) {
    throw new Error("unexpected_websocket_port");
  }

  const marketClock = shanghaiClock(now);
  if (marketClock.date !== expectedDate) {
    throw new Error("reviewed_date_does_not_match");
  }
  if (marketClock.weekday === "Sat" || marketClock.weekday === "Sun") {
    throw new Error("weekend_is_not_a_probe_window");
  }
  const guardedMorning =
    marketClock.minuteOfDay >= 9 * 60 + 30 &&
    marketClock.minuteOfDay <= 11 * 60 + 28;
  const guardedAfternoon =
    marketClock.minuteOfDay >= 13 * 60 &&
    marketClock.minuteOfDay <= 14 * 60 + 55;
  if (!guardedMorning && !guardedAfternoon) {
    throw new Error("outside_guarded_cn_continuous_session_window");
  }

  return {
    live,
    symbol,
    mic,
    expectedDate,
    now,
    providerMarket: anchor.providerMarket,
    track: "cn",
    evidenceKind: "futu_cn_ticker_blocker_probe",
    eventTimeTimezone: "Asia/Shanghai",
    includeSessionFields: false,
    sessionKind: "continuous",
    sessionDescription: "mainland_continuous_auction_session",
    micAuthority:
      "futu_vendor_market_code_mapped_to_caller_reviewed_mic_not_exchange_identity_proof",
    listingScope: "ordinary_main_board_a_share",
    unsupportedVenues: ["XBSE"],
    feedClaim:
      "account_reported_mainland_stocks_lv1_not_authenticated_by_ticker_protocol",
    probeHashScope: "cn_wrapper_plus_shared_quote_lifecycle",
  };
}

async function runCli() {
  const startedAt = new Date();
  const probeHash = await sha256Files([
    fileURLToPath(import.meta.url),
    fileURLToPath(new URL("./futu-us-ticker-probe.js", import.meta.url)),
  ]);
  let config;
  try {
    config = validateCnProbeConfig(process.argv.slice(2), process.env, startedAt);
  } catch (error) {
    return failedEvidence(startedAt, probeHash, error);
  }

  if (!config.live) {
    return {
      schemaVersion: 1,
      kind: "futu_cn_ticker_blocker_probe",
      status: "dry_run",
      probeSha256: probeHash,
      probeHashScope: "cn_wrapper_plus_shared_quote_lifecycle",
      sdkVersion,
      endpoint: `${websocketHost}:${websocketPort}`,
      quoteOnly: true,
      tradeCalls: 0,
      reconnectPolicy: "disabled",
      reviewedAnchors: [
        { track: "cn", mic: "XSHG", providerCodeRetained: false },
        { track: "cn", mic: "XSHE", providerCodeRetained: false },
      ],
      executionRule: "one_venue_per_run_review_release_then_next_venue",
      requestPlan: [
        "all_connection_subscription_status",
        "subscribe_one_cn_ticker",
        "subscription_status",
        "unsubscribe_exact_ticker",
        "release_status",
      ],
      limits: probeLimits,
      requiredEnvironment: [
        "FUTU_PROBE_SYMBOL=<reviewed anchor>",
        "FUTU_PROBE_MIC=XSHG|XSHE",
        "FUTU_PROBE_EXPECTED_CN_DATE=YYYY-MM-DD",
        `FUTU_LIVE_CONFIRM=${liveConfirmation}`,
      ],
    };
  }

  return runLiveProbe(config, probeHash);
}

function shanghaiClock(now) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Shanghai",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
      weekday: "short",
    })
      .formatToParts(now)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    weekday: parts.weekday,
    minuteOfDay: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

function failedEvidence(startedAt, probeHash, error) {
  const allowedCodes = new Set([
    "unsupported_argument",
    "unreviewed_cn_anchor",
    "missing_reviewed_cn_date",
    "live_confirmation_missing",
    "non_localhost_endpoint_forbidden",
    "unexpected_websocket_port",
    "reviewed_date_does_not_match",
    "weekend_is_not_a_probe_window",
    "outside_guarded_cn_continuous_session_window",
  ]);
  const candidate = error instanceof Error ? error.message : "internal_probe_failure";
  return {
    schemaVersion: 1,
    kind: "futu_cn_ticker_blocker_probe",
    status: "failed",
    failure: {
      code: allowedCodes.has(candidate) ? candidate : "internal_probe_failure",
      stage: "configuration",
      providerTextRetained: false,
    },
    probe: {
      sha256: probeHash,
      hashScope: "cn_wrapper_plus_shared_quote_lifecycle",
      startedAt: startedAt.toISOString(),
      rawMarketRowsRetained: false,
      credentialMaterialRead: false,
      accountIdentifiersRetained: false,
    },
  };
}

async function sha256Files(paths) {
  const hasher = createHash("sha256");
  for (const path of paths) {
    const bytes = Buffer.from(await Bun.file(path).arrayBuffer());
    hasher.update("futu-cn-probe-component-v1\0");
    hasher.update(String(bytes.length));
    hasher.update("\0");
    hasher.update(bytes);
  }
  return hasher.digest("hex");
}

if (import.meta.main) {
  const evidence = await runCli();
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
  if (evidence.status === "failed") {
    process.exitCode = 1;
  }
}
