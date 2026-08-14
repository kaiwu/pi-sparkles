import { createHash, randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";

const sdkVersion = "10.10.7008";
const websocketHost = "127.0.0.1";
const websocketPort = 33333;
const usSecurityMarket = 11;
const tickerSubtype = 4;
const tickerPushCommand = 3011;
const sessionCodes = Object.freeze({ regular: 1, extended: 2 });
const liveConfirmation = "I_ACCEPT_ONE_FUTU_US_TICKER_SUBSCRIPTION";
const directionMeanings = Object.freeze({
  "0": "unknown",
  "1": "futu_documented_active_buy",
  "2": "futu_documented_active_sell",
  "3": "futu_documented_neutral",
});
const tickerTypeMeanings = Object.freeze({
  "0": "unknown",
  "1": "regular_sale",
  "2": "pre_market_trade",
  "3": "non_regular_sale",
  "4": "regular_sale_same_broker",
  "5": "non_regular_sale_same_broker",
  "6": "odd_lot_trade",
  "7": "auction_trade",
  "8": "bunched_trade",
  "9": "cash_trade",
  "10": "intermarket_sweep",
  "11": "bunched_sold_trade",
  "12": "price_variation_trade",
  "13": "rule_127_or_155",
  "14": "sold_last",
  "15": "market_center_close_price",
  "16": "next_day",
  "17": "market_center_opening_trade",
  "18": "prior_reference_price",
  "19": "market_center_open_price",
  "20": "seller",
  "21": "form_t_pre_or_post_market",
  "22": "extended_hours_or_sold_out_of_sequence",
  "23": "contingent_trade",
  "24": "average_price_trade",
  "25": "otc_sold_out_of_sequence",
  "26": "odd_lot_cross_trade",
  "27": "derivatively_priced",
  "28": "reopening_price",
  "29": "closing_price",
  "30": "consolidated_late_price_per_listing_packet",
  "31": "overseas_hk_specific",
});
const pushDataTypeMeanings = Object.freeze({
  "0": "unknown",
  "1": "realtime",
  "2": "backend_disconnect_supplement_up_to_50",
  "3": "cache",
});

export const probeLimits = Object.freeze({
  minimumRemainingQuota: 90,
  subscriptionUnits: 1,
  minimumSubscriptionMs: 65_000,
  captureTargetMs: 70_000,
  maximumElapsedMs: 20 * 60_000,
  maximumEvents: 25_000,
  maximumDecodedBytes: 64 * 1024 * 1024,
  queueCapacity: 512,
  slowConsumerStartMs: 10_000,
  slowConsumerEndMs: 12_000,
});

class SafeProbeFailure extends Error {
  constructor(code, stage) {
    super(code);
    this.name = "SafeProbeFailure";
    this.code = code;
    this.stage = stage;
  }
}

export function validateProbeConfig(argv, environment, now = new Date()) {
  const live = argv.includes("--live");
  const unexpected = argv.filter((argument) => argument !== "--live");
  if (unexpected.length > 0) {
    throw new SafeProbeFailure("unsupported_argument", "configuration");
  }

  const symbol = environment.FUTU_PROBE_SYMBOL ?? "";
  const mic = environment.FUTU_PROBE_MIC ?? "";
  const expectedDate = environment.FUTU_PROBE_EXPECTED_US_DATE ?? "";
  const sessionKind = environment.FUTU_PROBE_SESSION ?? "regular";

  if (!live) {
    return {
      live: false,
      symbol: null,
      mic: null,
      expectedDate: null,
      sessionKind: null,
      now,
    };
  }

  if (!/^US\.[A-Z0-9][A-Z0-9.-]{0,19}$/.test(symbol)) {
    throw new SafeProbeFailure("invalid_us_symbol", "configuration");
  }
  if (!new Set(["XNYS", "XNAS"]).has(mic)) {
    throw new SafeProbeFailure("invalid_us_mic", "configuration");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(expectedDate)) {
    throw new SafeProbeFailure("missing_reviewed_us_date", "configuration");
  }
  if (!Object.hasOwn(sessionCodes, sessionKind)) {
    throw new SafeProbeFailure("invalid_us_session", "configuration");
  }
  if (environment.FUTU_LIVE_CONFIRM !== liveConfirmation) {
    throw new SafeProbeFailure("live_confirmation_missing", "configuration");
  }
  if (
    environment.FUTU_OPEND_HOST !== undefined &&
    environment.FUTU_OPEND_HOST !== websocketHost
  ) {
    throw new SafeProbeFailure("non_localhost_endpoint_forbidden", "configuration");
  }
  if (
    environment.FUTU_OPEND_WEBSOCKET_PORT !== undefined &&
    environment.FUTU_OPEND_WEBSOCKET_PORT !== String(websocketPort)
  ) {
    throw new SafeProbeFailure("unexpected_websocket_port", "configuration");
  }

  const marketClock = newYorkClock(now);
  if (marketClock.date !== expectedDate) {
    throw new SafeProbeFailure("reviewed_date_does_not_match", "market_window");
  }
  if (marketClock.weekday === "Sat" || marketClock.weekday === "Sun") {
    throw new SafeProbeFailure("weekend_is_not_a_probe_window", "market_window");
  }
  if (sessionKind === "regular") {
    if (
      marketClock.minuteOfDay < 9 * 60 + 35 ||
      marketClock.minuteOfDay > 15 * 60 + 55
    ) {
      throw new SafeProbeFailure(
        "outside_guarded_regular_session_window",
        "market_window",
      );
    }
  } else {
    const premarket =
      marketClock.minuteOfDay >= 4 * 60 + 5 &&
      marketClock.minuteOfDay <= 9 * 60 + 25;
    const postmarket =
      marketClock.minuteOfDay >= 16 * 60 + 5 &&
      marketClock.minuteOfDay <= 19 * 60 + 55;
    if (!premarket && !postmarket) {
      throw new SafeProbeFailure(
        "outside_guarded_extended_session_window",
        "market_window",
      );
    }
  }

  return { live, symbol, mic, expectedDate, sessionKind, now };
}

export function summarizeSubscriptionStatus(response) {
  const body = response?.s2c;
  if (
    !body ||
    !Number.isInteger(body.totalUsedQuota) ||
    !Number.isInteger(body.remainQuota) ||
    !Array.isArray(body.connSubInfoList)
  ) {
    throw new SafeProbeFailure("malformed_subscription_status", "subscription_status");
  }

  let activePairs = 0;
  let ownActivePairs = 0;
  let ownUsedQuota = 0;
  let ownConnections = 0;
  const ownPairs = [];

  for (const connection of body.connSubInfoList) {
    if (!connection || !Array.isArray(connection.subInfoList)) {
      throw new SafeProbeFailure("malformed_connection_status", "subscription_status");
    }
    const isOwn = connection.isOwnConnData === true;
    if (isOwn) {
      ownConnections += 1;
      if (!Number.isInteger(connection.usedQuota)) {
        throw new SafeProbeFailure("malformed_own_quota", "subscription_status");
      }
      ownUsedQuota += connection.usedQuota;
    }
    for (const subscription of connection.subInfoList) {
      if (!subscription || !Array.isArray(subscription.securityList)) {
        throw new SafeProbeFailure("malformed_subscription_entry", "subscription_status");
      }
      for (const security of subscription.securityList) {
        activePairs += 1;
        if (isOwn) {
          ownActivePairs += 1;
          ownPairs.push({
            market: security?.market,
            code: security?.code,
            subtype: subscription.subType,
          });
        }
      }
    }
  }

  return {
    totalUsedQuota: body.totalUsedQuota,
    remainQuota: body.remainQuota,
    connectionCount: body.connSubInfoList.length,
    activePairs,
    ownConnections,
    ownUsedQuota,
    ownActivePairs,
    ownPairs,
  };
}

export function validatePreflight(status) {
  if (status.totalUsedQuota !== 0 || status.activePairs !== 0) {
    throw new SafeProbeFailure("existing_subscription_detected", "preflight");
  }
  if (status.remainQuota < probeLimits.minimumRemainingQuota) {
    throw new SafeProbeFailure("remaining_quota_below_guard", "preflight");
  }
  if (status.ownConnections > 1 || status.ownUsedQuota !== 0) {
    throw new SafeProbeFailure("unexpected_probe_connection_state", "preflight");
  }
}

export function validateSubscribedStatus(
  before,
  after,
  providerCode,
  providerMarket = usSecurityMarket,
) {
  const expectedPair = after.ownPairs.filter(
    (pair) =>
      pair.market === providerMarket &&
      pair.code === providerCode &&
      pair.subtype === tickerSubtype,
  );
  if (
    after.totalUsedQuota !== before.totalUsedQuota + probeLimits.subscriptionUnits ||
    after.remainQuota !== before.remainQuota - probeLimits.subscriptionUnits ||
    after.activePairs !== 1 ||
    after.ownUsedQuota !== probeLimits.subscriptionUnits ||
    after.ownActivePairs !== 1 ||
    expectedPair.length !== 1
  ) {
    throw new SafeProbeFailure("subscription_not_exactly_one_ticker", "post_subscribe");
  }
}

export function validateReleasedStatus(before, after) {
  return (
    after.totalUsedQuota === before.totalUsedQuota &&
    after.remainQuota === before.remainQuota &&
    after.activePairs === 0 &&
    after.ownUsedQuota === 0 &&
    after.ownActivePairs === 0
  );
}

export function createTickerCollector(
  expectedProviderCode,
  clock = defaultClock,
  providerMarket = usSecurityMarket,
  eventTimeTimezone = "America/New_York",
) {
  const sequenceDigestSalt = randomBytes(32);
  const queue = [];
  const seenSequenceDigests = new Set();
  const directionCounts = new Map();
  const tickerTypeCounts = new Map();
  const tickerTypeSignCounts = new Map();
  const pushDataTypeCounts = new Map();
  const timeResolutionCounts = new Map();
  const receiptMinusEvent = numericSummary();
  const openDReceiveMinusEvent = numericSummary();
  const localDispatch = numericSummary();
  let subscriptionStartedMonoMs = null;
  let drainTimer = null;
  let accepting = true;
  let markedClosed = false;
  let fatalCode = null;
  let receivedPushes = 0;
  let decodedEvents = 0;
  let processedEvents = 0;
  let decodedBytes = 0;
  let queueHighWater = 0;
  let queueDrops = 0;
  let ignoredAfterBudget = 0;
  let callbacksAfterClose = 0;
  let unexpectedPushCommands = 0;
  let malformedPushes = 0;
  let wrongIdentityPushes = 0;
  let slowConsumerTicks = 0;
  let duplicateSequences = 0;
  let sequenceDecreases = 0;
  let positiveSequenceJumps = 0;
  let largestPositiveSequenceDelta = 0n;
  let firstSequenceDigest = null;
  let lastSequenceDigest = null;
  let priorSequence = null;
  let firstReceiptMonoMs = null;
  let lastReceiptMonoMs = null;

  function start() {
    subscriptionStartedMonoMs = clock.monotonicMs();
    drainTimer = setInterval(drain, 10);
  }

  function ingest(command, response) {
    if (markedClosed) {
      callbacksAfterClose += 1;
      return;
    }
    if (command !== tickerPushCommand) {
      unexpectedPushCommands += 1;
      return;
    }
    receivedPushes += 1;
    try {
      if (response?.retType !== 0 || !response.s2c) {
        fatalCode ??= "provider_warning_push";
        return;
      }
      const security = response.s2c.security;
      if (security?.market !== providerMarket || security?.code !== expectedProviderCode) {
        wrongIdentityPushes += 1;
        fatalCode ??= "push_identity_mismatch";
        return;
      }
      if (!Array.isArray(response.s2c.tickerList)) {
        throw new Error("ticker list missing");
      }
      for (const ticker of response.s2c.tickerList) {
        if (!accepting) {
          ignoredAfterBudget += 1;
          continue;
        }
        const materialBytes = estimateDecodedBytes(ticker);
        if (decodedEvents >= probeLimits.maximumEvents) {
          fatalCode ??= "event_budget_reached";
          accepting = false;
          ignoredAfterBudget += 1;
          continue;
        }
        if (decodedBytes + materialBytes > probeLimits.maximumDecodedBytes) {
          fatalCode ??= "decoded_byte_budget_reached";
          accepting = false;
          ignoredAfterBudget += 1;
          continue;
        }

        const receiptWallMs = clock.wallMs();
        const receiptMonoMs = clock.monotonicMs();
        const metadata = decodeTickerMetadata(ticker, receiptWallMs, receiptMonoMs);
        decodedEvents += 1;
        decodedBytes += materialBytes;
        if (queue.length >= probeLimits.queueCapacity) {
          queueDrops += 1;
          fatalCode ??= "consumer_queue_overflow";
          accepting = false;
        } else {
          queue.push(metadata);
          queueHighWater = Math.max(queueHighWater, queue.length);
        }
      }
    } catch {
      malformedPushes += 1;
      fatalCode ??= "malformed_ticker_push";
    }
  }

  function drain() {
    if (subscriptionStartedMonoMs === null) {
      return;
    }
    const elapsed = clock.monotonicMs() - subscriptionStartedMonoMs;
    if (
      elapsed >= probeLimits.slowConsumerStartMs &&
      elapsed < probeLimits.slowConsumerEndMs
    ) {
      slowConsumerTicks += 1;
      return;
    }
    let remaining = 64;
    while (queue.length > 0 && remaining > 0) {
      consume(queue.shift());
      remaining -= 1;
    }
  }

  function consume(event) {
    processedEvents += 1;
    firstReceiptMonoMs ??= event.receiptMonoMs;
    lastReceiptMonoMs = event.receiptMonoMs;
    increment(directionCounts, event.direction);
    increment(tickerTypeCounts, event.tickerType);
    increment(tickerTypeSignCounts, event.tickerTypeSign);
    increment(pushDataTypeCounts, event.pushDataType);
    increment(timeResolutionCounts, event.timeResolution);

    const sequenceDigest = digestLexeme(sequenceDigestSalt, event.sequenceLexeme);
    firstSequenceDigest ??= sequenceDigest;
    lastSequenceDigest = sequenceDigest;
    if (seenSequenceDigests.has(sequenceDigest)) {
      duplicateSequences += 1;
    } else {
      seenSequenceDigests.add(sequenceDigest);
    }
    const sequence = BigInt(event.sequenceLexeme);
    if (priorSequence !== null) {
      const delta = sequence - priorSequence;
      if (delta < 0n) {
        sequenceDecreases += 1;
      } else if (delta > 1n) {
        positiveSequenceJumps += 1;
        largestPositiveSequenceDelta =
          delta > largestPositiveSequenceDelta ? delta : largestPositiveSequenceDelta;
      }
    }
    priorSequence = sequence;

    if (event.eventTimestampMs !== null) {
      receiptMinusEvent.add(event.receiptWallMs - event.eventTimestampMs);
      if (event.openDReceiveTimestampMs !== null) {
        openDReceiveMinusEvent.add(
          event.openDReceiveTimestampMs - event.eventTimestampMs,
        );
      }
    }
    if (event.openDReceiveTimestampMs !== null) {
      localDispatch.add(event.receiptWallMs - event.openDReceiveTimestampMs);
    }
  }

  function stopAccepting() {
    accepting = false;
    while (queue.length > 0) {
      consume(queue.shift());
    }
    if (drainTimer !== null) {
      clearInterval(drainTimer);
      drainTimer = null;
    }
  }

  function markClosed() {
    markedClosed = true;
  }

  function summary() {
    return {
      receivedPushes,
      decodedEvents,
      processedEvents,
      decodedBytesEstimate: decodedBytes,
      queue: {
        capacity: probeLimits.queueCapacity,
        highWater: queueHighWater,
        dropped: queueDrops,
        coalesced: 0,
        slowConsumerTicks,
      },
      budgets: {
        eventLimit: probeLimits.maximumEvents,
        byteLimit: probeLimits.maximumDecodedBytes,
        ignoredAfterBudget,
        budgetOutcome: fatalCode?.endsWith("budget_reached") ? fatalCode : "within_limits",
      },
      sequence: {
        scope: "observed_single_symbol_single_connection_window",
        documentedContract: "unique_identifier_only",
        firstDigest: firstSequenceDigest,
        lastDigest: lastSequenceDigest,
        digestScope: "ephemeral_run_local_salt_not_retained",
        distinctDigests: seenSequenceDigests.size,
        duplicates: duplicateSequences,
        decreases: sequenceDecreases,
        positiveJumpsGreaterThanOne: positiveSequenceJumps,
        largestPositiveDelta:
          largestPositiveSequenceDelta === 0n
            ? null
            : largestPositiveSequenceDelta.toString(),
        contiguityClaimed: false,
        monotonicityClaimed: false,
      },
      enums: {
        direction: countObject(directionCounts),
        tickerType: countObject(tickerTypeCounts),
        tickerTypeSign: countObject(tickerTypeSignCounts),
        pushDataType: countObject(pushDataTypeCounts),
      },
      enumSemantics: observedEnumSemantics({
        direction: directionCounts,
        tickerType: tickerTypeCounts,
        pushDataType: pushDataTypeCounts,
      }),
      clocks: {
        eventTimeTimezone,
        eventTimeResolutionDigits: countObject(timeResolutionCounts),
        receiptClock: "local_wall_clock",
        receiptMonotonicClock: "performance.now",
        observedMonotonicSpanMs:
          firstReceiptMonoMs === null || lastReceiptMonoMs === null
            ? null
            : round(lastReceiptMonoMs - firstReceiptMonoMs),
        receiptMinusEventMs: receiptMinusEvent.render(),
        openDReceiveMinusEventMs: openDReceiveMinusEvent.render(),
        localReceiptMinusOpenDReceiveMs: localDispatch.render(),
        synchronizationMethod: "not_established",
        latencyClaimed: false,
      },
      pushSafety: {
        unexpectedPushCommands,
        malformedPushes,
        wrongIdentityPushes,
        callbacksAfterClose,
      },
      fatalCode,
    };
  }

  return {
    start,
    ingest,
    stopAccepting,
    markClosed,
    summary,
    get fatalCode() {
      return fatalCode;
    },
  };
}

async function runCli() {
  const startedAt = new Date();
  const probeHash = await sha256File(fileURLToPath(import.meta.url));
  let config;
  try {
    config = validateProbeConfig(process.argv.slice(2), process.env, startedAt);
  } catch (error) {
    return failedEvidence(startedAt, probeHash, safeFailure(error));
  }

  if (!config.live) {
    return {
      schemaVersion: 1,
      kind: "futu_us_ticker_blocker_probe",
      status: "dry_run",
      probeSha256: probeHash,
      sdkVersion,
      endpoint: `${websocketHost}:${websocketPort}`,
      quoteOnly: true,
      tradeCalls: 0,
      reconnectPolicy: "disabled",
      requestPlan: [
        "all_connection_subscription_status",
        "subscribe_one_us_ticker",
        "subscription_status",
        "unsubscribe_exact_ticker",
        "release_status",
      ],
      limits: probeLimits,
      requiredEnvironment: [
        "FUTU_PROBE_SYMBOL=US.<symbol>",
        "FUTU_PROBE_MIC=XNYS|XNAS",
        "FUTU_PROBE_EXPECTED_US_DATE=YYYY-MM-DD",
        "FUTU_PROBE_SESSION=regular|extended (default regular)",
        `FUTU_LIVE_CONFIRM=${liveConfirmation}`,
      ],
    };
  }

  return runLiveProbe(config, probeHash);
}

export async function runLiveProbe(config, probeHash) {
  const startedAt = new Date();
  const startedMonoMs = performance.now();
  const providerCode = config.symbol.slice(3);
  const providerMarket = config.providerMarket ?? usSecurityMarket;
  const track = config.track ?? "us";
  const evidenceKind = config.evidenceKind ?? "futu_us_ticker_blocker_probe";
  const eventTimeTimezone = config.eventTimeTimezone ?? "America/New_York";
  const collector = createTickerCollector(
    providerCode,
    defaultClock,
    providerMarket,
    eventTimeTimezone,
  );
  const requests = [];
  const lifecycle = {
    login: false,
    subscribed: false,
    unsubscribeAttempted: false,
    unsubscribeAcknowledged: false,
    releaseVerified: false,
    closed: false,
    reconnectAttemptsSuppressed: 0,
    unexpectedDisconnects: 0,
    bridgeOpenDDisconnectNotifications: 0,
    signalsReceived: 0,
  };
  let client = null;
  let preflight = null;
  let postSubscribe = null;
  let postRelease = null;
  let subscribedAtMonoMs = null;
  let unsubscribeRequestedAtMonoMs = null;
  let failure = null;
  let interrupted = false;
  const bridgeObserver = {};

  const signalHandler = () => {
    lifecycle.signalsReceived += 1;
    interrupted = true;
    failure ??= new SafeProbeFailure("signal_received_cleanup_required", "capture");
  };
  process.on("SIGINT", signalHandler);
  process.on("SIGTERM", signalHandler);
  const restoreConsole = silenceConsole();

  try {
    const sdk = await import("futu-api");
    if (typeof sdk.default !== "function") {
      throw new SafeProbeFailure("javascript_sdk_unavailable", "sdk_import");
    }
    client = new sdk.default();
    client.onPush = (command, response) => collector.ingest(command, response);

    const login = new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new SafeProbeFailure("login_timeout", "login")),
        25_000,
      );
      client.onlogin = (success) => {
        clearTimeout(timer);
        if (success === true) {
          resolve();
        } else {
          reject(new SafeProbeFailure("login_rejected", "login"));
        }
      };
    });

    client.start(websocketHost, websocketPort, false);
    if (!client.websock || typeof client.websock.reconnect !== "function") {
      throw new SafeProbeFailure("sdk_reconnect_guard_unavailable", "login");
    }
    client.websock.reconnect = () => {
      lifecycle.reconnectAttemptsSuppressed += 1;
      client.websock?.killReconnectTimer?.();
    };
    client.websock.regPushCallback(bridgeObserver, (response) => {
      if (response?.cmd === 2) {
        lifecycle.bridgeOpenDDisconnectNotifications += 1;
        failure ??= new SafeProbeFailure(
          "websocket_bridge_lost_opend",
          "capture",
        );
      }
    });
    const sdkOnClose = client.websock.onclose;
    client.websock.onclose = (event) => {
      sdkOnClose?.(event);
      if (!lifecycle.closed) {
        lifecycle.unexpectedDisconnects += 1;
        failure ??= new SafeProbeFailure("unexpected_disconnect", "capture");
      }
    };
    const sdkOnError = client.websock.onerror;
    client.websock.onerror = (event) => {
      sdkOnError?.(event);
      failure ??= new SafeProbeFailure("websocket_error", "capture");
    };

    await login;
    lifecycle.login = true;

    preflight = summarizeSubscriptionStatus(
      await request(client, requests, "preflight_status", () =>
        client.GetSubInfo({ c2s: { isReqAllConn: true } }),
      ),
    );
    validatePreflight(preflight);

    await request(client, requests, "subscribe", () =>
      client.Sub(buildSubscriptionRequest(providerCode, true, config, providerMarket)),
    );
    lifecycle.subscribed = true;
    subscribedAtMonoMs = performance.now();
    collector.start();

    postSubscribe = summarizeSubscriptionStatus(
      await request(client, requests, "post_subscribe_status", () =>
        client.GetSubInfo({ c2s: { isReqAllConn: true } }),
      ),
    );
    validateSubscribedStatus(preflight, postSubscribe, providerCode, providerMarket);

    while (true) {
      const subscriptionElapsed = performance.now() - subscribedAtMonoMs;
      const totalElapsed = performance.now() - startedMonoMs;
      if (totalElapsed >= probeLimits.maximumElapsedMs) {
        throw new SafeProbeFailure("elapsed_budget_reached", "capture");
      }
      const target =
        collector.fatalCode || interrupted
          ? probeLimits.minimumSubscriptionMs
          : probeLimits.captureTargetMs;
      if (subscriptionElapsed >= target) {
        break;
      }
      await delay(25);
    }

    if (collector.fatalCode) {
      throw new SafeProbeFailure(collector.fatalCode, "capture");
    }
  } catch (error) {
    failure ??= safeFailure(error);
  } finally {
    if (lifecycle.subscribed && subscribedAtMonoMs !== null) {
      const remaining =
        probeLimits.minimumSubscriptionMs - (performance.now() - subscribedAtMonoMs);
      if (remaining > 0) {
        await delay(remaining);
      }
      collector.stopAccepting();
      if (client?.websock?.isReadyConnect?.()) {
        lifecycle.unsubscribeAttempted = true;
        unsubscribeRequestedAtMonoMs = performance.now();
        try {
          await request(client, requests, "unsubscribe", () =>
            client.Sub(buildSubscriptionRequest(providerCode, false, config, providerMarket)),
          );
          lifecycle.unsubscribeAcknowledged = true;
          postRelease = summarizeSubscriptionStatus(
            await request(client, requests, "release_status", () =>
              client.GetSubInfo({ c2s: { isReqAllConn: true } }),
            ),
          );
          lifecycle.releaseVerified = validateReleasedStatus(preflight, postRelease);
          if (!lifecycle.releaseVerified) {
            failure ??= new SafeProbeFailure("subscription_release_not_verified", "cleanup");
          }
        } catch (error) {
          failure ??= safeFailure(error, "cleanup_request_failed", "cleanup");
        }
      } else {
        failure ??= new SafeProbeFailure("cleanup_connection_unavailable", "cleanup");
      }
    } else {
      collector.stopAccepting();
    }

    collector.markClosed();
    if (client?.websock) {
      lifecycle.closed = true;
      client.websock.unregPushCallback(bridgeObserver);
      client.stop();
      client.websock.close();
    }
    await delay(250);
    process.off("SIGINT", signalHandler);
    process.off("SIGTERM", signalHandler);
    restoreConsole();
  }

  const eventEvidence = collector.summary();
  if (!failure && eventEvidence.decodedEvents === 0) {
    failure = new SafeProbeFailure("no_ticker_events_observed", "capture");
  }
  if (!failure && eventEvidence.pushSafety.callbacksAfterClose !== 0) {
    failure = new SafeProbeFailure("callback_after_close", "cleanup");
  }

  const finishedAt = new Date();
  return {
    schemaVersion: 1,
    kind: evidenceKind,
    status: failure ? "failed" : "passed",
    failure: failure
      ? { code: failure.code, stage: failure.stage, providerTextRetained: false }
      : null,
    provider: {
      name: "Futu OpenD",
      openDVersion: sdkVersion,
      javascriptSdkVersion: sdkVersion,
      endpoint: `${websocketHost}:${websocketPort}`,
      feedClaim:
        config.feedClaim ??
        "account_reported_us_stocks_lv2_not_authenticated_by_ticker_protocol",
      entitlementScope: "caller_owned",
      price: "unknown",
      licence: "unknown",
      retention: "unknown",
      redistribution: "unknown",
    },
    identity: {
      track,
      mic: config.mic,
      micAuthority:
        config.micAuthority ??
        "caller_declared_not_authenticated_by_futu_ticker",
      providerMarket,
      listingScope: config.listingScope ?? "ordinary_equity_listing",
      unsupportedVenues: config.unsupportedVenues ?? [],
      instrumentCount: 1,
      providerCodeRedacted: true,
      session:
        config.sessionDescription ??
        (config.sessionKind === "regular"
          ? "regular_trading_hours"
          : "pre_or_post_market_plus_regular_subscription_scope"),
      sessionCode:
        config.includeSessionFields === false ? null : sessionCodes[config.sessionKind],
      extendedTime:
        config.includeSessionFields === false
          ? false
          : config.sessionKind === "extended",
    },
    safety: {
      quoteOnly: true,
      tradeCalls: 0,
      historicalCalls: 0,
      snapshotPolls: 0,
      retries: 0,
      reconnectPolicy: "disabled",
      requestCount: requests.length,
      requestStages: requests,
      lifecycle,
      subscriptionLifetimeMs:
        subscribedAtMonoMs === null || unsubscribeRequestedAtMonoMs === null
          ? null
          : round(unsubscribeRequestedAtMonoMs - subscribedAtMonoMs),
    },
    quota: {
      before: publicQuota(preflight),
      subscribed: publicQuota(postSubscribe),
      released: publicQuota(postRelease),
      releaseVerified: lifecycle.releaseVerified,
    },
    events: eventEvidence,
    lineage: {
      original:
        eventEvidence.decodedEvents > 0
          ? "ticker_events_observed_without_lineage_classification"
          : "not_observed",
      correction: capabilityOutcome(
        "unavailable_in_documented_ticker_schema",
        "No correction field or reference identifier is present in Qot_Common.Ticker.",
      ),
      cancel: capabilityOutcome(
        "unavailable_in_documented_ticker_schema",
        "No cancel field or reference identifier is present in Qot_Common.Ticker.",
      ),
      bust: capabilityOutcome(
        "unavailable_in_documented_ticker_schema",
        "No bust field or reference identifier is present in Qot_Common.Ticker.",
      ),
      providerReferenceIdentifier: capabilityOutcome(
        "unavailable_in_documented_ticker_schema",
        "The sequence field is documented only as an identifier, not a correction reference.",
      ),
    },
    recovery: recoveryEvidence(eventEvidence),
    probe: {
      sha256: probeHash,
      hashScope: config.probeHashScope ?? "single_probe_file",
      startedAt: startedAt.toISOString(),
      finishedAt: finishedAt.toISOString(),
      elapsedMs: round(performance.now() - startedMonoMs),
      reviewedMarketDate: config.expectedDate,
      rawMarketRowsRetained: false,
      credentialMaterialRead: false,
      accountIdentifiersRetained: false,
    },
  };
}

export function buildSubscriptionRequest(
  providerCode,
  subscribe,
  config,
  providerMarket,
) {
  const c2s = {
    securityList: [{ market: providerMarket, code: providerCode }],
    subTypeList: [tickerSubtype],
    isSubOrUnSub: subscribe,
    isRegOrUnRegPush: subscribe,
    isFirstPush: false,
  };
  if (config.includeSessionFields !== false) {
    c2s.extendedTime = config.sessionKind === "extended";
    c2s.session = sessionCodes[config.sessionKind];
  }
  return { c2s };
}

async function request(client, requests, stage, operation) {
  if (!client?.websock?.isReadyConnect?.()) {
    throw new SafeProbeFailure("quote_connection_not_ready", stage);
  }
  requests.push(stage);
  try {
    return await operation();
  } catch {
    throw new SafeProbeFailure("provider_request_rejected", stage);
  }
}

function decodeTickerMetadata(ticker, receiptWallMs, receiptMonoMs) {
  const sequenceLexeme = integerLexeme(ticker?.sequence);
  const eventTimestampMs = secondsToMilliseconds(ticker?.timestamp);
  const openDReceiveTimestampMs = secondsToMilliseconds(ticker?.recvTime);
  const time = typeof ticker?.time === "string" ? ticker.time : "";
  const fractional = time.match(/\.(\d+)$/)?.[1]?.length ?? 0;
  return {
    sequenceLexeme,
    direction: enumLexeme(ticker?.dir),
    tickerType: enumLexeme(ticker?.type),
    tickerTypeSign: enumLexeme(ticker?.typeSign),
    pushDataType: enumLexeme(ticker?.pushDataType),
    timeResolution: String(fractional),
    eventTimestampMs,
    openDReceiveTimestampMs,
    receiptWallMs,
    receiptMonoMs,
  };
}

function integerLexeme(value) {
  const lexeme = value?.toString?.() ?? "";
  if (!/^-?\d+$/.test(lexeme)) {
    throw new Error("invalid sequence");
  }
  return lexeme;
}

function enumLexeme(value) {
  return Number.isInteger(value) ? String(value) : "missing";
}

function secondsToMilliseconds(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  return value * 1000;
}

function estimateDecodedBytes(value, seen = new Set()) {
  if (value === null || value === undefined) {
    return 0;
  }
  if (typeof value === "string") {
    return Buffer.byteLength(value);
  }
  if (typeof value === "number" || typeof value === "bigint") {
    return 8;
  }
  if (typeof value === "boolean") {
    return 1;
  }
  if (typeof value !== "object" || seen.has(value)) {
    return 0;
  }
  seen.add(value);
  let bytes = 0;
  for (const [key, entry] of Object.entries(value)) {
    bytes += Buffer.byteLength(key) + estimateDecodedBytes(entry, seen);
  }
  return bytes;
}

function numericSummary() {
  let count = 0;
  let minimum = null;
  let maximum = null;
  let total = 0;
  return {
    add(value) {
      if (!Number.isFinite(value)) {
        return;
      }
      count += 1;
      minimum = minimum === null ? value : Math.min(minimum, value);
      maximum = maximum === null ? value : Math.max(maximum, value);
      total += value;
    },
    render() {
      return count === 0
        ? { count: 0, minimum: null, maximum: null, mean: null }
        : {
            count,
            minimum: round(minimum),
            maximum: round(maximum),
            mean: round(total / count),
          };
    },
  };
}

function increment(map, key) {
  map.set(key, (map.get(key) ?? 0) + 1);
}

function countObject(map) {
  return Object.fromEntries([...map.entries()].sort(([left], [right]) => left.localeCompare(right)));
}

function digestLexeme(salt, lexeme) {
  return createHash("sha256")
    .update("futu-ticker-sequence-v1\0")
    .update(salt)
    .update(lexeme)
    .digest("hex");
}

function newYorkClock(now) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/New_York",
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

function publicQuota(status) {
  if (!status) {
    return null;
  }
  return {
    totalUsed: status.totalUsedQuota,
    remaining: status.remainQuota,
    activePairs: status.activePairs,
    ownUsed: status.ownUsedQuota,
  };
}

export function recoveryEvidence(eventEvidence) {
  const supplementedEvents = eventEvidence?.enums?.pushDataType?.["2"] ?? 0;
  return {
    reconnectExercised: false,
    providerDisconnectObserved: supplementedEvents > 0,
    supplementedEvents,
    documentedSupplementMaximum: 50,
    replay: capabilityOutcome(
      "unavailable_as_complete_replay_contract",
      "Futu documents supplementation of at most 50 recent ticker events, with no completeness guarantee or replay watermark.",
    ),
    resetRule: capabilityOutcome(
      "unknown",
      "No reset or trading-day sequence-domain rule is documented by the ticker contract.",
    ),
    gapRecovery: capabilityOutcome(
      supplementedEvents > 0 ? "partial" : "not_observed",
      supplementedEvents > 0
        ? "A bounded provider supplement was observed; completeness remains unknown."
        : "No provider-backend disconnect supplement was observed in this window.",
    ),
    limitation:
      "PushDataType 2 can evidence provider-side supplementation; reconnecting only the JavaScript WebSocket is not provider recovery evidence.",
  };
}

export function capabilityOutcome(status, reason) {
  return { status, reason };
}

export function observedEnumSemantics(counts) {
  return {
    authority: "Futu quotation definitions; vendor classification, not exchange authority",
    direction: observedMeanings(counts.direction, directionMeanings),
    tickerType: observedMeanings(counts.tickerType, tickerTypeMeanings),
    pushDataType: observedMeanings(counts.pushDataType, pushDataTypeMeanings),
    tickerTypeSign: "opaque_undocumented_int32_preserved_as_lexeme",
  };
}

function observedMeanings(counts, catalogue) {
  const keys = counts instanceof Map ? [...counts.keys()] : Object.keys(counts ?? {});
  return Object.fromEntries(
    keys
      .map(String)
      .sort((left, right) => Number(left) - Number(right))
      .map((key) => [key, catalogue[key] ?? "unknown_lexeme"]),
  );
}

function safeFailure(error, fallbackCode = "internal_probe_failure", fallbackStage = "internal") {
  return error instanceof SafeProbeFailure
    ? error
    : new SafeProbeFailure(fallbackCode, fallbackStage);
}

function failedEvidence(startedAt, probeHash, failure) {
  return {
    schemaVersion: 1,
    kind: "futu_us_ticker_blocker_probe",
    status: "failed",
    failure: {
      code: failure.code,
      stage: failure.stage,
      providerTextRetained: false,
    },
    probe: {
      sha256: probeHash,
      startedAt: startedAt.toISOString(),
      rawMarketRowsRetained: false,
      credentialMaterialRead: false,
      accountIdentifiersRetained: false,
    },
  };
}

function silenceConsole() {
  const originals = {
    debug: console.debug,
    error: console.error,
    info: console.info,
    log: console.log,
    warn: console.warn,
  };
  console.debug = () => {};
  console.error = () => {};
  console.info = () => {};
  console.log = () => {};
  console.warn = () => {};
  return () => Object.assign(console, originals);
}

async function sha256File(path) {
  const hasher = createHash("sha256");
  hasher.update(Buffer.from(await Bun.file(path).arrayBuffer()));
  return hasher.digest("hex");
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function round(value) {
  return Math.round(value * 1000) / 1000;
}

const defaultClock = {
  wallMs: () => Date.now(),
  monotonicMs: () => performance.now(),
};

if (import.meta.main) {
  const evidence = await runCli();
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
  if (evidence.status === "failed") {
    process.exitCode = 1;
  }
}
