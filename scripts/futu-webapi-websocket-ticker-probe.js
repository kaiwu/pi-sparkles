import {
  parseJsonWithExactSequences,
  readShortLivedToken,
} from "./futu-webapi-ticker-probe.js";

const websocketEndpoint = "wss://webapi-quote.futunn.com/ws";
const confirmation = "I_ACCEPT_ONE_FUTU_DIRECT_TICKER_WEBSOCKET";
const captureMs = 30_000;
const maximumElapsedMs = 60_000;
const maximumMessageBytes = 1024 * 1024;
const maximumTotalBytes = 8 * 1024 * 1024;
const maximumEvents = 10_000;
const queueCapacity = 512;
const slowConsumerMs = 2_000;
const controlTimeoutMs = 8_000;
const reviewedHkSymbol = "HK.00700";

const requestIds = Object.freeze({
  auth: "t6-auth-1",
  subscribe: "t6-sub-1",
  unsubscribe: "t6-unsub-1",
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

export const directWebSocketLimits = Object.freeze({
  connections: 1,
  symbols: 1,
  dataTypes: ["ticker"],
  retries: 0,
  reconnects: 0,
  captureMs,
  maximumElapsedMs,
  maximumMessageBytes,
  maximumTotalBytes,
  maximumEvents,
  queueCapacity,
  slowConsumerMs,
});

export function validateWebSocketProbeConfig(argv, environment, now = new Date()) {
  if (argv.length === 0) return { live: false, now };
  if (
    argv.length !== 5 ||
    argv[0] !== "--live" ||
    argv[1] !== "--track" ||
    argv[2] !== "hk" ||
    argv[3] !== "--mic" ||
    argv[4] !== "XHKG"
  ) {
    throw new SafeProbeFailure("only_reviewed_hk_leg_allowed", "configuration");
  }
  if (environment.FUTU_WEBAPI_CONFIRM !== confirmation) {
    throw new SafeProbeFailure("live_confirmation_missing", "configuration");
  }
  if (
    environment.FUTU_WEBAPI_TOKEN_FILE !== undefined ||
    environment.FUTU_WEBAPI_WEBSOCKET_URL !== undefined
  ) {
    throw new SafeProbeFailure("endpoint_or_token_override_forbidden", "configuration");
  }
  for (const key of Object.keys(environment)) {
    if (/^FUTU_.*(?:TOKEN|SECRET|PASSWORD|PWD)$/i.test(key)) {
      throw new SafeProbeFailure("ambient_secret_forbidden", "configuration");
    }
  }
  const clock = hongKongClock(now);
  if (clock.weekday === "Sat" || clock.weekday === "Sun") {
    throw new SafeProbeFailure("weekend_is_not_a_probe_window", "market_window");
  }
  const morning = clock.minuteOfDay >= 9 * 60 + 30 && clock.minuteOfDay <= 11 * 60 + 58;
  const afternoon = clock.minuteOfDay >= 13 * 60 && clock.minuteOfDay <= 15 * 60 + 58;
  if (!morning && !afternoon) {
    throw new SafeProbeFailure("outside_guarded_hk_live_window", "market_window");
  }
  return { live: true, track: "hk", mic: "XHKG", now };
}

function hongKongClock(now) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Hong_Kong",
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

export function authFrame(accessToken) {
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new SafeProbeFailure("missing_access_token", "control_frame");
  }
  return {
    id: requestIds.auth,
    action: "auth",
    data: {
      auth_type: "oauth2",
      authorization: `Bearer ${accessToken}`,
    },
  };
}

export function tickerControlFrame(action) {
  if (!new Set(["subscribe", "unsubscribe"]).has(action)) {
    throw new SafeProbeFailure("invalid_ticker_control_action", "control_frame");
  }
  const frame = {
    id: action === "subscribe" ? requestIds.subscribe : requestIds.unsubscribe,
    action,
    ticker: [reviewedHkSymbol],
  };
  assertTickerOnlyControlFrame(frame);
  return frame;
}

export function assertTickerOnlyControlFrame(frame) {
  if (
    !frame ||
    !new Set(["subscribe", "unsubscribe"]).has(frame.action) ||
    Object.keys(frame).sort().join(",") !== "action,id,ticker" ||
    !Array.isArray(frame.ticker) ||
    frame.ticker.length !== 1 ||
    frame.ticker[0] !== reviewedHkSymbol
  ) {
    throw new SafeProbeFailure("non_ticker_control_forbidden", "control_frame");
  }
  return true;
}

function messageText(value) {
  if (typeof value === "string") return value;
  if (value instanceof ArrayBuffer) {
    return new TextDecoder("utf-8", { fatal: true }).decode(value);
  }
  if (ArrayBuffer.isView(value)) {
    return new TextDecoder("utf-8", { fatal: true }).decode(
      new Uint8Array(value.buffer, value.byteOffset, value.byteLength),
    );
  }
  throw new SafeProbeFailure("unsupported_websocket_message", "decode");
}

export function tickerRows(message) {
  if (
    message?.type !== "TICKER" ||
    message.symbol !== reviewedHkSymbol ||
    !Array.isArray(message.data?.ticker_list)
  ) {
    throw new SafeProbeFailure("wrong_ticker_push_shape", "decode");
  }
  return message.data.ticker_list.map((row) => {
    if (
      !row ||
      typeof row.sequence !== "string" ||
      !/^[0-9]{1,19}$/.test(row.sequence) ||
      !Number.isSafeInteger(row.time_ms) ||
      typeof row.direction !== "string" ||
      typeof row.type !== "string"
    ) {
      throw new SafeProbeFailure("malformed_ticker_push_row", "decode");
    }
    const sequence = BigInt(row.sequence);
    if (sequence > 9_223_372_036_854_775_807n) {
      throw new SafeProbeFailure("sequence_outside_int64", "decode");
    }
    return {
      sequence,
      timeMs: row.time_ms,
      direction: row.direction,
      tickerType: row.type,
    };
  });
}

export function tickerPushOrdering(subscriptionRequested, subscribed) {
  if (!subscriptionRequested) {
    throw new SafeProbeFailure("ticker_before_subscription", "stream");
  }
  return subscribed ? "after_ack" : "before_ack";
}

function newAggregate() {
  return {
    events: 0,
    sequences: [],
    eventTimes: [],
    directions: { BUY: 0, SELL: 0, NEUTRAL: 0, UNKNOWN: 0, other: 0 },
    knownTickerTypes: 0,
    unknownTickerTypes: 0,
  };
}

function acceptRow(aggregate, row) {
  aggregate.events += 1;
  aggregate.sequences.push(row.sequence);
  aggregate.eventTimes.push(row.timeMs);
  if (Object.hasOwn(aggregate.directions, row.direction)) {
    aggregate.directions[row.direction] += 1;
  } else {
    aggregate.directions.other += 1;
  }
  if (row.tickerType === "UNKNOWN") aggregate.unknownTickerTypes += 1;
  else aggregate.knownTickerTypes += 1;
}

export function summarizeWebSocketAggregate(aggregate, finishedAtMs) {
  let increases = 0;
  let decreases = 0;
  let duplicates = 0;
  let maximumAbsoluteDelta = 0n;
  for (let index = 1; index < aggregate.sequences.length; index += 1) {
    const delta = aggregate.sequences[index] - aggregate.sequences[index - 1];
    if (delta > 0n) increases += 1;
    else if (delta < 0n) decreases += 1;
    else duplicates += 1;
    const absolute = delta < 0n ? -delta : delta;
    if (absolute > maximumAbsoluteDelta) maximumAbsoluteDelta = absolute;
  }
  return {
    eventCount: aggregate.events,
    sequence: {
      exactInt64LexemesPreserved: true,
      distinctCount: new Set(aggregate.sequences.map(String)).size,
      receiveOrderIncreases: increases,
      receiveOrderDecreases: decreases,
      receiveOrderDuplicates: duplicates,
      maximumAbsoluteDelta: maximumAbsoluteDelta.toString(),
    },
    eventClock: {
      millisecondTimestampCount: aggregate.eventTimes.filter((time) => time % 1_000 !== 0).length,
      secondAlignedTimestampCount: aggregate.eventTimes.filter((time) => time % 1_000 === 0).length,
      minimumReceiptMinusEventMs: aggregate.eventTimes.length > 0
        ? Math.min(...aggregate.eventTimes.map((time) => finishedAtMs - time))
        : null,
      maximumReceiptMinusEventMs: aggregate.eventTimes.length > 0
        ? Math.max(...aggregate.eventTimes.map((time) => finishedAtMs - time))
        : null,
      interpretation: "unsynchronized_clock_offset_not_latency",
    },
    directionCounts: aggregate.directions,
    tickerTypeCounts: {
      known: aggregate.knownTickerTypes,
      unknown: aggregate.unknownTickerTypes,
    },
  };
}

async function execute(config) {
  const accessToken = await readShortLivedToken(config.now);
  const startedAtMs = Date.now();
  const aggregate = newAggregate();
  const queue = [];
  let queueHighWater = 0;
  let totalBytes = 0;
  let pushMessages = 0;
  let nonTickerPushMessages = 0;
  let subscriptionRequested = false;
  let pushObservedBeforeSubscriptionAck = false;
  let subscribed = false;
  let unsubscribeRequested = false;
  let unsubscribeConfirmed = false;
  let captureStartedAtMs = null;
  let pendingFailure = null;
  let settled = false;
  let drainTimer;
  let captureTimer;
  let controlTimer;
  let maximumTimer;
  let closeTimer;

  const websocket = new WebSocket(websocketEndpoint);
  websocket.binaryType = "arraybuffer";

  return await new Promise((resolve) => {
    const clearTimers = () => {
      clearTimeout(drainTimer);
      clearTimeout(captureTimer);
      clearTimeout(controlTimer);
      clearTimeout(maximumTimer);
      clearTimeout(closeTimer);
    };

    const resultFailure = (error) => ({
      schemaVersion: 1,
      kind: "futu_direct_transaction_ticker_websocket_probe",
      status: "failed",
      failure: {
        code: error instanceof SafeProbeFailure ? error.code : "internal_probe_failure",
        stage: error instanceof SafeProbeFailure ? error.stage : "internal",
        ...(Number.isInteger(error?.details?.providerCode)
          ? { providerCode: error.details.providerCode }
          : {}),
        providerTextRetained: false,
      },
      cleanup: {
        subscriptionRequested,
        subscribed,
        pushObservedBeforeSubscriptionAck,
        unsubscribeRequested,
        unsubscribeConfirmed,
        pushMessages,
        queueHighWater,
        reconnects: 0,
        retries: 0,
      },
    });

    const settle = (result) => {
      if (settled) return;
      settled = true;
      clearTimers();
      resolve(result);
    };

    const drain = () => {
      clearTimeout(drainTimer);
      if (
        captureStartedAtMs !== null &&
        Date.now() < captureStartedAtMs + slowConsumerMs
      ) {
        drainTimer = setTimeout(drain, captureStartedAtMs + slowConsumerMs - Date.now());
        return;
      }
      while (queue.length > 0) acceptRow(aggregate, queue.shift());
    };

    const completeAfterCleanup = () => {
      drain();
      const finishedAtMs = Date.now();
      if (pendingFailure) {
        settle(resultFailure(pendingFailure));
      } else if (aggregate.events === 0) {
        settle(resultFailure(new SafeProbeFailure("no_ticker_events", "capture")));
      } else {
        settle({
          schemaVersion: 1,
          kind: "futu_direct_transaction_ticker_websocket_probe",
          status: "observed",
          track: "hk",
          mic: "XHKG",
          provider: "Futu direct Web API",
          providerEndpoint: "quote WebSocket TICKER",
          providerAuthorizationScope: "quote:read",
          quoteSnapshotCalls: 0,
          bidOfferCalls: 0,
          orderBookCalls: 0,
          klineCalls: 0,
          tradeOrAccountCalls: 0,
          limits: directWebSocketLimits,
            lifecycle: {
              authRequests: 1,
              subscribeRequests: 1,
              pushObservedBeforeSubscriptionAck,
            unsubscribeRequests: 1,
            unsubscribeConfirmed,
            reconnects: 0,
            retries: 0,
            elapsedMs: finishedAtMs - startedAtMs,
          },
          stream: {
            pushMessages,
            nonTickerPushMessages,
            totalBytes,
            queueHighWater,
            droppedEvents: 0,
            coalescedEvents: 0,
          },
          summary: summarizeWebSocketAggregate(aggregate, finishedAtMs),
          recovery: {
            reconnectExercised: false,
            subscriptionRestoredByServer: false,
            documentedRestLatestWindowMaximum: 750,
            completeReplayAvailable: false,
            failClosedWithoutRestOverlap: true,
          },
          authority: {
            mic: "caller_reviewed_mapping_not_provider_authenticated",
            feed: "caller_oauth_entitlement_response_not_feed_completeness_proof",
            rawMarketRowsRetained: false,
            symbolRetained: false,
            pricesSizesTurnoverRetained: false,
            rawSequencesOrTimesRetained: false,
            providerTextRetained: false,
            tokenSessionOrAccountFieldsRetained: false,
          },
        });
      }
    };

    const closeAfterCleanup = () => {
      drain();
      websocket.close(1000, "probe complete");
      closeTimer = setTimeout(completeAfterCleanup, 250);
    };

    const requestUnsubscribe = () => {
      if (
        !subscriptionRequested ||
        unsubscribeRequested ||
        websocket.readyState !== WebSocket.OPEN
      ) {
        if (!subscriptionRequested) {
          websocket.close(1000, "probe stopped");
          settle(resultFailure(pendingFailure ?? new SafeProbeFailure("not_subscribed", "cleanup")));
        }
        return;
      }
      unsubscribeRequested = true;
      websocket.send(JSON.stringify(tickerControlFrame("unsubscribe")));
      clearTimeout(controlTimer);
      controlTimer = setTimeout(() => {
        pendingFailure ??= new SafeProbeFailure("unsubscribe_timeout", "cleanup");
        websocket.close(1000, "unsubscribe timeout");
        settle(resultFailure(pendingFailure));
      }, controlTimeoutMs);
    };

    const fail = (error) => {
      pendingFailure ??= error instanceof SafeProbeFailure
        ? error
        : new SafeProbeFailure("internal_probe_failure", "internal");
      clearTimeout(captureTimer);
      if (subscriptionRequested) requestUnsubscribe();
      else {
        websocket.close(1000, "probe failed");
        settle(resultFailure(pendingFailure));
      }
    };

    maximumTimer = setTimeout(
      () => fail(new SafeProbeFailure("maximum_elapsed_exceeded", "budget")),
      maximumElapsedMs,
    );

    websocket.addEventListener("open", () => {
      try {
        websocket.send(JSON.stringify(authFrame(accessToken)));
        controlTimer = setTimeout(
          () => fail(new SafeProbeFailure("auth_timeout", "authentication")),
          controlTimeoutMs,
        );
      } catch (error) {
        fail(error);
      }
    });

    websocket.addEventListener("message", (event) => {
      if (settled) return;
      try {
        const text = messageText(event.data);
        const bytes = new TextEncoder().encode(text).byteLength;
        if (bytes > maximumMessageBytes || totalBytes + bytes > maximumTotalBytes) {
          throw new SafeProbeFailure("message_budget_exceeded", "budget");
        }
        totalBytes += bytes;
        const message = parseJsonWithExactSequences(text);

        if (message.id === requestIds.auth) {
          if (
            typeof message.session_id !== "string" ||
            !Number.isSafeInteger(message.server_time)
          ) {
            throw new SafeProbeFailure(
              "websocket_auth_rejected",
              "authentication",
              { providerCode: message.code },
            );
          }
          clearTimeout(controlTimer);
          subscriptionRequested = true;
          websocket.send(JSON.stringify(tickerControlFrame("subscribe")));
          controlTimer = setTimeout(
            () => fail(new SafeProbeFailure("subscribe_timeout", "subscription")),
            controlTimeoutMs,
          );
          return;
        }

        if (message.id === requestIds.subscribe) {
          if (message.code !== 0) {
            throw new SafeProbeFailure("subscribe_rejected", "subscription", {
              providerCode: message.code,
            });
          }
          clearTimeout(controlTimer);
          subscribed = true;
          captureStartedAtMs = Date.now();
          captureTimer = setTimeout(requestUnsubscribe, captureMs);
          return;
        }

        if (message.id === requestIds.unsubscribe) {
          if (message.code !== 0) {
            throw new SafeProbeFailure("unsubscribe_rejected", "cleanup", {
              providerCode: message.code,
            });
          }
          clearTimeout(controlTimer);
          unsubscribeConfirmed = true;
          closeAfterCleanup();
          return;
        }

        if (message.type === "TICKER") {
          const ordering = tickerPushOrdering(subscriptionRequested, subscribed);
          if (ordering === "before_ack") pushObservedBeforeSubscriptionAck = true;
          pushMessages += 1;
          const rows = tickerRows(message);
          if (aggregate.events + queue.length + rows.length > maximumEvents) {
            throw new SafeProbeFailure("event_budget_exceeded", "budget");
          }
          queue.push(...rows);
          queueHighWater = Math.max(queueHighWater, queue.length);
          if (queue.length > queueCapacity) {
            throw new SafeProbeFailure("queue_capacity_exceeded", "backpressure");
          }
          drain();
          return;
        }

        if (typeof message.type === "string") nonTickerPushMessages += 1;
        else if (Number.isInteger(message.code)) {
          throw new SafeProbeFailure("websocket_channel_rejected", "channel", {
            providerCode: message.code,
          });
        }
      } catch (error) {
        fail(error);
      }
    });

    websocket.addEventListener("error", () => {
      fail(new SafeProbeFailure("websocket_transport_error", "transport"));
    });

    websocket.addEventListener("close", () => {
      if (settled) return;
      if (unsubscribeConfirmed) {
        clearTimeout(closeTimer);
        completeAfterCleanup();
      } else {
        settle(
          resultFailure(
            pendingFailure ?? new SafeProbeFailure("unexpected_disconnect", "transport"),
          ),
        );
      }
    });
  });
}

function failed(error) {
  return {
    schemaVersion: 1,
    kind: "futu_direct_transaction_ticker_websocket_probe",
    status: "failed",
    failure: {
      code: error instanceof SafeProbeFailure ? error.code : "internal_probe_failure",
      stage: error instanceof SafeProbeFailure ? error.stage : "internal",
      providerTextRetained: false,
    },
  };
}

async function run() {
  try {
    const config = validateWebSocketProbeConfig(process.argv.slice(2), process.env);
    if (!config.live) {
      return {
        schemaVersion: 1,
        kind: "futu_direct_transaction_ticker_websocket_probe",
        status: "dry_run",
        endpoint: websocketEndpoint,
        allowedTrack: "hk:XHKG",
        dataTypes: ["ticker"],
        requiredConfirmation: confirmation,
        limits: directWebSocketLimits,
        forbidden: [
          "quote",
          "bid_offer",
          "order_book",
          "kline",
          "trade_or_account_api",
          "retry",
          "reconnect",
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
