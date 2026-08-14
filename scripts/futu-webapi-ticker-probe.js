import { lstat, readFile } from "node:fs/promises";

const apiOrigin = "https://webapi.futunn.com";
const tokenFile = "/tmp/pi-sparkles-futu-webapi-quote-token.json";
const confirmation = "I_ACCEPT_ONE_FUTU_DIRECT_TICKER_REQUEST";
const tickerCount = 10;
const maximumResponseBytes = 256 * 1024;
const requestTimeoutMs = 10_000;

const anchors = Object.freeze({
  "cn:XSHG": Object.freeze({ symbol: "SH.600519", timezone: "Asia/Shanghai" }),
  "cn:XSHE": Object.freeze({ symbol: "SZ.000001", timezone: "Asia/Shanghai" }),
  "hk:XHKG": Object.freeze({ symbol: "HK.00700", timezone: "Asia/Hong_Kong" }),
  "us:XNAS": Object.freeze({ symbol: "US.AAPL", timezone: "America/New_York" }),
  "us:XNYS": Object.freeze({ symbol: "US.IBM", timezone: "America/New_York" }),
});

class SafeProbeFailure extends Error {
  constructor(code, stage, details = {}) {
    super(code);
    this.name = "SafeProbeFailure";
    this.code = code;
    this.stage = stage;
    this.details = details;
  }
}

export const directTickerLimits = Object.freeze({
  requests: 1,
  retries: 0,
  redirects: 0,
  tickerCount,
  maximumResponseBytes,
  requestTimeoutMs,
});

export function validateDirectTickerConfig(argv, environment, now = new Date()) {
  if (argv.length === 0) return { live: false, now };
  if (argv.length !== 5 || argv[0] !== "--live") {
    throw new SafeProbeFailure("unsupported_arguments", "configuration");
  }

  const fields = new Map();
  for (let index = 1; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!new Set(["--track", "--mic"]).has(flag) || fields.has(flag) || !value) {
      throw new SafeProbeFailure("unsupported_arguments", "configuration");
    }
    fields.set(flag, value);
  }

  const track = fields.get("--track");
  const mic = fields.get("--mic");
  const anchor = anchors[`${track}:${mic}`];
  if (!anchor) throw new SafeProbeFailure("unreviewed_track_anchor", "configuration");
  if (environment.FUTU_WEBAPI_CONFIRM !== confirmation) {
    throw new SafeProbeFailure("live_confirmation_missing", "configuration");
  }
  if (
    environment.FUTU_WEBAPI_TOKEN_FILE !== undefined ||
    environment.FUTU_WEBAPI_BASE_URL !== undefined
  ) {
    throw new SafeProbeFailure("endpoint_or_token_override_forbidden", "configuration");
  }
  for (const key of Object.keys(environment)) {
    if (/^FUTU_.*(?:TOKEN|SECRET|PASSWORD|PWD)$/i.test(key)) {
      throw new SafeProbeFailure("ambient_secret_forbidden", "configuration");
    }
  }

  assertLiveMarketWindow(track, anchor.timezone, now);
  return { live: true, track, mic, anchor, now };
}

function assertLiveMarketWindow(track, timezone, now) {
  const clock = marketClock(timezone, now);
  if (clock.weekday === "Sat" || clock.weekday === "Sun") {
    throw new SafeProbeFailure("weekend_is_not_a_probe_window", "market_window");
  }
  const windows = {
    cn: [
      [9 * 60 + 30, 11 * 60 + 28],
      [13 * 60, 14 * 60 + 55],
    ],
    hk: [
      [9 * 60 + 30, 11 * 60 + 58],
      [13 * 60, 15 * 60 + 58],
    ],
    us: [[9 * 60 + 35, 15 * 60 + 55]],
  };
  if (!windows[track].some(([start, end]) => clock.minuteOfDay >= start && clock.minuteOfDay <= end)) {
    throw new SafeProbeFailure("outside_guarded_live_session_window", "market_window");
  }
}

function marketClock(timezone, now) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(now)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  return {
    weekday: parts.weekday,
    minuteOfDay: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

export function tickerRequestUrl(symbol) {
  if (!/^(?:SH|SZ|HK|US)\.[A-Z0-9][A-Z0-9.-]{0,19}$/.test(symbol)) {
    throw new SafeProbeFailure("invalid_reviewed_symbol", "request_plan");
  }
  const url = new URL(
    `/api/v1.0/quote/${encodeURIComponent(symbol)}/rt-ticker`,
    apiOrigin,
  );
  url.searchParams.set("num", String(tickerCount));
  assertTickerOnlyUrl(url);
  return url;
}

export function assertTickerOnlyUrl(value) {
  const url = value instanceof URL ? value : new URL(value);
  if (
    url.origin !== apiOrigin ||
    !/^\/api\/v1\.0\/quote\/(?:SH|SZ|HK|US)\.[A-Z0-9][A-Z0-9.%+-]{0,59}\/rt-ticker$/.test(
      url.pathname,
    ) ||
    url.searchParams.size !== 1 ||
    url.searchParams.get("num") !== String(tickerCount)
  ) {
    throw new SafeProbeFailure("non_ticker_endpoint_forbidden", "request_plan");
  }
  return true;
}

export async function readShortLivedToken(now) {
  let stat;
  try {
    stat = await lstat(tokenFile);
  } catch {
    throw new SafeProbeFailure("token_file_unavailable", "token");
  }
  if (
    !stat.isFile() ||
    stat.isSymbolicLink() ||
    (stat.mode & 0o777) !== 0o600 ||
    (typeof process.getuid === "function" && stat.uid !== process.getuid()) ||
    stat.size <= 0 ||
    stat.size > 4_096
  ) {
    throw new SafeProbeFailure("unsafe_token_file", "token");
  }

  let value;
  try {
    value = JSON.parse(await readFile(tokenFile, "utf8"));
  } catch {
    throw new SafeProbeFailure("invalid_token_file", "token");
  }
  if (
    !value ||
    Object.keys(value).sort().join(",") !== "access_token,expires_at_ms,scope" ||
    typeof value.access_token !== "string" ||
    value.access_token.length === 0 ||
    value.scope !== "quote:read" ||
    !Number.isSafeInteger(value.expires_at_ms) ||
    value.expires_at_ms < now.getTime() + 60_000
  ) {
    throw new SafeProbeFailure("invalid_or_expiring_quote_token", "token");
  }
  return value.access_token;
}

async function boundedBody(response) {
  const declared = response.headers.get("content-length");
  if (declared !== null && Number(declared) > maximumResponseBytes) {
    await response.body?.cancel();
    throw new SafeProbeFailure("response_budget_exceeded", "response");
  }
  if (!response.body) throw new SafeProbeFailure("missing_response_body", "response");

  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximumResponseBytes) {
        await reader.cancel();
        throw new SafeProbeFailure("response_budget_exceeded", "response");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return { text: new TextDecoder("utf-8", { fatal: true }).decode(bytes), bytes: total };
}

export function parseJsonWithExactSequences(text) {
  let output = "";
  let index = 0;
  while (index < text.length) {
    if (text[index] !== '"') {
      output += text[index];
      index += 1;
      continue;
    }

    const start = index;
    index += 1;
    let escaped = false;
    while (index < text.length) {
      const character = text[index];
      index += 1;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        break;
      }
    }
    const literal = text.slice(start, index);
    output += literal;

    let key;
    try {
      key = JSON.parse(literal);
    } catch {
      throw new SafeProbeFailure("malformed_json", "decode");
    }
    if (key !== "sequence") continue;

    let cursor = index;
    while (/\s/.test(text[cursor] ?? "")) cursor += 1;
    if (text[cursor] !== ":") continue;
    cursor += 1;
    while (/\s/.test(text[cursor] ?? "")) cursor += 1;
    const match = text.slice(cursor).match(/^-?\d+/);
    if (!match) continue;
    const end = cursor + match[0].length;
    if (!/[\s,}\]]/.test(text[end] ?? "")) continue;

    output += text.slice(index, cursor);
    output += JSON.stringify(match[0]);
    index = end;
  }

  try {
    return JSON.parse(output);
  } catch {
    throw new SafeProbeFailure("malformed_json", "decode");
  }
}

export function summarizeTickerResponse(body, expectedSymbol, finishedAtMs) {
  if (!body || !Number.isInteger(body.ret_code)) {
    throw new SafeProbeFailure("malformed_provider_envelope", "decode");
  }
  if (body.ret_code !== 0) {
    throw new SafeProbeFailure("provider_rejected_request", "provider", {
      retCode: body.ret_code,
      errorCategory: providerErrorCategory(body.error?.code),
      providerErrorCodePresent:
        typeof body.error?.code === "string" && body.error.code.length > 0,
      providerMessagePresent:
        typeof body.ret_msg === "string" && body.ret_msg.length > 0,
    });
  }
  const rows = body.data?.ticker_list;
  if (body.data?.code !== expectedSymbol || !Array.isArray(rows)) {
    throw new SafeProbeFailure("wrong_identity_or_shape", "decode");
  }
  if (rows.length < 1 || rows.length > tickerCount) {
    throw new SafeProbeFailure("unexpected_ticker_count", "decode");
  }

  const sequences = [];
  const times = [];
  const directions = { BUY: 0, SELL: 0, NEUTRAL: 0, UNKNOWN: 0, other: 0 };
  const periods = { BEFORE: 0, NORMAL: 0, AFTER: 0, OVERNIGHT: 0, other: 0 };
  let knownTickType = 0;
  let unknownTickType = 0;
  let cancelTradeType = 0;
  let blankTradeType = 0;
  let otherTradeType = 0;

  for (const row of rows) {
    if (
      !row ||
      typeof row.sequence !== "string" ||
      !/^[0-9]{1,19}$/.test(row.sequence) ||
      !Number.isSafeInteger(row.time) ||
      typeof row.ticker_direction !== "string" ||
      typeof row.tick_type !== "string" ||
      typeof row.period_type !== "string" ||
      typeof row.trade_type !== "string"
    ) {
      throw new SafeProbeFailure("malformed_ticker_row", "decode");
    }
    const sequence = BigInt(row.sequence);
    if (sequence > 9_223_372_036_854_775_807n) {
      throw new SafeProbeFailure("sequence_outside_int64", "decode");
    }
    sequences.push(sequence);
    times.push(row.time);
    if (Object.hasOwn(directions, row.ticker_direction)) {
      directions[row.ticker_direction] += 1;
    } else {
      directions.other += 1;
    }
    if (Object.hasOwn(periods, row.period_type)) {
      periods[row.period_type] += 1;
    } else {
      periods.other += 1;
    }
    if (row.tick_type === "UNKNOWN") unknownTickType += 1;
    else knownTickType += 1;
    const tradeType = row.trade_type.trim();
    if (tradeType === "") blankTradeType += 1;
    else if (tradeType === "U") cancelTradeType += 1;
    else otherTradeType += 1;
  }

  let increases = 0;
  let decreases = 0;
  let duplicates = 0;
  let maximumAbsoluteDelta = 0n;
  for (let index = 1; index < sequences.length; index += 1) {
    const delta = sequences[index] - sequences[index - 1];
    if (delta > 0n) increases += 1;
    else if (delta < 0n) decreases += 1;
    else duplicates += 1;
    const absolute = delta < 0n ? -delta : delta;
    if (absolute > maximumAbsoluteDelta) maximumAbsoluteDelta = absolute;
  }

  return {
    eventCount: rows.length,
    sequence: {
      exactInt64LexemesPreserved: true,
      distinctCount: new Set(sequences.map(String)).size,
      responseOrderIncreases: increases,
      responseOrderDecreases: decreases,
      responseOrderDuplicates: duplicates,
      maximumAbsoluteDelta: maximumAbsoluteDelta.toString(),
    },
    eventClock: {
      millisecondTimestampCount: times.filter((time) => time % 1_000 !== 0).length,
      secondAlignedTimestampCount: times.filter((time) => time % 1_000 === 0).length,
      minimumReceiptMinusEventMs: Math.min(...times.map((time) => finishedAtMs - time)),
      maximumReceiptMinusEventMs: Math.max(...times.map((time) => finishedAtMs - time)),
      interpretation: "unsynchronized_clock_offset_not_latency",
    },
    directionCounts: directions,
    periodCounts: periods,
    tickTypeCounts: { known: knownTickType, unknown: unknownTickType },
    tradeTypeCounts: {
      documentedUsCancelU: cancelTradeType,
      blank: blankTradeType,
      otherNonBlank: otherTradeType,
    },
  };
}

export function providerErrorCategory(value) {
  if (typeof value !== "string" || value.length === 0) return "unavailable";
  const normalized = value.toLowerCase();
  if (/auth|token|unauthor/.test(normalized)) return "authentication";
  if (/permission|scope|forbid|entitle/.test(normalized)) return "permission";
  if (/rate|limit|thrott|too[_-]?many/.test(normalized)) return "rate_limit";
  if (/parameter|argument/.test(normalized)) return "parameter";
  if (/symbol|security/.test(normalized)) return "symbol";
  if (/internal|server|backend/.test(normalized)) return "internal";
  return "other";
}

async function execute(config) {
  const accessToken = await readShortLivedToken(config.now);
  const url = tickerRequestUrl(config.anchor.symbol);
  const startedAtMs = Date.now();
  let response;
  try {
    response = await fetch(url, {
      method: "GET",
      headers: {
        accept: "application/json",
        authorization: `Bearer ${accessToken}`,
      },
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(requestTimeoutMs),
    });
  } catch {
    throw new SafeProbeFailure("request_failed_without_retry", "transport");
  }
  const finishedAtMs = Date.now();
  const contentType = response.headers.get("content-type") ?? "";
  if (!response.ok || !contentType.toLowerCase().includes("application/json")) {
    await response.body?.cancel();
    throw new SafeProbeFailure("http_or_content_type_failure", "response", {
      httpStatus: response.status,
    });
  }
  const payload = await boundedBody(response);
  const decoded = parseJsonWithExactSequences(payload.text);
  const summary = summarizeTickerResponse(
    decoded,
    config.anchor.symbol,
    finishedAtMs,
  );
  return {
    schemaVersion: 1,
    kind: "futu_direct_transaction_ticker_probe",
    status: "observed",
    track: config.track,
    mic: config.mic,
    provider: "Futu direct Web API",
    providerEndpoint: "rt-ticker",
    providerAuthorizationScope: "quote:read",
    quoteSnapshotCalls: 0,
    bidOfferCalls: 0,
    orderBookCalls: 0,
    tradeOrAccountCalls: 0,
    limits: directTickerLimits,
    request: {
      count: 1,
      retries: 0,
      redirects: 0,
      responseBytes: payload.bytes,
      elapsedMs: finishedAtMs - startedAtMs,
    },
    summary,
    authority: {
      mic: "caller_reviewed_mapping_not_provider_authenticated",
      feed: "caller_oauth_entitlement_response_not_feed_completeness_proof",
      rawMarketRowsRetained: false,
      symbolRetained: false,
      pricesSizesTurnoverRetained: false,
      rawSequencesOrTimesRetained: false,
      providerTextRetained: false,
      tokenOrAccountFieldsRetained: false,
    },
  };
}

function failed(error) {
  const allowed = new Set([
    "unsupported_arguments",
    "unreviewed_track_anchor",
    "live_confirmation_missing",
    "endpoint_or_token_override_forbidden",
    "ambient_secret_forbidden",
    "weekend_is_not_a_probe_window",
    "outside_guarded_live_session_window",
    "invalid_reviewed_symbol",
    "non_ticker_endpoint_forbidden",
    "token_file_unavailable",
    "unsafe_token_file",
    "invalid_token_file",
    "invalid_or_expiring_quote_token",
    "request_failed_without_retry",
    "response_budget_exceeded",
    "missing_response_body",
    "malformed_json",
    "http_or_content_type_failure",
    "malformed_provider_envelope",
    "provider_rejected_request",
    "wrong_identity_or_shape",
    "unexpected_ticker_count",
    "malformed_ticker_row",
    "sequence_outside_int64",
  ]);
  const code = error instanceof SafeProbeFailure && allowed.has(error.code)
    ? error.code
    : "internal_probe_failure";
  return {
    schemaVersion: 1,
    kind: "futu_direct_transaction_ticker_probe",
    status: "failed",
    failure: {
      code,
      stage: error instanceof SafeProbeFailure ? error.stage : "internal",
      ...(Number.isInteger(error?.details?.httpStatus)
        ? { httpStatus: error.details.httpStatus }
        : {}),
      ...(Number.isInteger(error?.details?.retCode)
        ? { providerRetCode: error.details.retCode }
        : {}),
      ...(typeof error?.details?.errorCategory === "string"
        ? {
            providerErrorCategory: error.details.errorCategory,
            providerErrorCodePresent:
              error.details.providerErrorCodePresent === true,
            providerMessagePresent: error.details.providerMessagePresent === true,
          }
        : {}),
      providerTextRetained: false,
    },
  };
}

async function run() {
  let config;
  try {
    config = validateDirectTickerConfig(process.argv.slice(2), process.env);
    if (!config.live) {
      return {
        schemaVersion: 1,
        kind: "futu_direct_transaction_ticker_probe",
        status: "dry_run",
        endpoint: "/api/v1.0/quote/{reviewed-symbol}/rt-ticker?num=10",
        allowedTracks: ["cn:XSHG", "cn:XSHE", "hk:XHKG", "us:XNAS", "us:XNYS"],
        requiredConfirmation: confirmation,
        tokenFile,
        tokenFileMode: "0600",
        limits: directTickerLimits,
        forbidden: [
          "stock_quote",
          "bid_offer",
          "order_book",
          "trade_or_account_api",
          "retry",
          "redirect",
          "raw_market_output",
        ],
      };
    }
    return await execute(config);
  } catch (error) {
    return failed(error);
  }
}

if (import.meta.main) {
  const result = await run();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.status === "failed") process.exitCode = 1;
}
