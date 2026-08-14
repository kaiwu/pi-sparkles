const sdkVersion = "10.10.7008";
const websocketHost = "127.0.0.1";
const websocketPort = 33333;
const getUserInfoCommand = 1005;
const quoteRightsOnlyFlag = 4;
const liveConfirmation = "I_ACCEPT_ONE_FUTU_TRACK_RIGHTS_QUERY";
const quoteRightMeanings = Object.freeze({
  0: "unknown",
  1: "bmp_subscription_unavailable",
  2: "level_1",
  3: "level_2",
  4: "sf_advanced",
  5: "no_permission",
  6: "level_3",
});

export function validateTrackRightsConfig(argv, environment) {
  if (!argv.includes("--live") || argv.some((argument) => argument !== "--live")) {
    throw new Error("explicit_live_argument_required");
  }
  if (environment.FUTU_RIGHTS_CONFIRM !== liveConfirmation) {
    throw new Error("rights_confirmation_missing");
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
}

export function allowlistedTrackRightsEvidence(response) {
  const body = response?.s2c;
  const fields = ["shQotRight", "szQotRight", "hkQotRight", "usQotRight"];
  for (const field of fields) {
    const value = body?.[field];
    if (!Number.isInteger(value) || quoteRightMeanings[value] === undefined) {
      throw new Error("malformed_track_quote_rights");
    }
  }
  const right = (field, track, mic) => ({
    track,
    mic,
    field,
    value: body[field],
    meaning: quoteRightMeanings[body[field]],
    authority: "OpenD GetUserInfo QotRight enum",
    feedCompositionAuthenticated: false,
  });
  return {
    schemaVersion: 1,
    kind: "futu_track_quote_rights_probe",
    status: "passed",
    provider: "Futu OpenD",
    openDVersion: sdkVersion,
    javascriptSdkVersion: sdkVersion,
    endpoint: `${websocketHost}:${websocketPort}`,
    protocol: {
      id: getUserInfoCommand,
      requestedFieldFlag: quoteRightsOnlyFlag,
      requestedSurface: "quote_rights_only",
    },
    quoteRights: [
      right("shQotRight", "cn", "XSHG"),
      right("szQotRight", "cn", "XSHE"),
      right("hkQotRight", "hk", "XHKG"),
      right("usQotRight", "us", "futu_generic_us_market"),
    ],
    safety: {
      requestCount: 1,
      subscriptionCalls: 0,
      tradeCalls: 0,
      historyCalls: 0,
      retries: 0,
      reconnectPolicy: "disabled",
      identityFieldsRead: false,
      accountFieldsRead: false,
      deprecatedAggregateCnRightRead: false,
      providerTextRetained: false,
    },
  };
}

async function run() {
  try {
    validateTrackRightsConfig(process.argv.slice(2), process.env);
  } catch (error) {
    return failed(error);
  }

  const restoreConsole = silenceConsole();
  let client = null;
  try {
    const sdk = await import("futu-api");
    client = new sdk.default();
    const login = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("login_timeout")), 25_000);
      client.onlogin = (success) => {
        clearTimeout(timer);
        success === true ? resolve() : reject(new Error("login_rejected"));
      };
    });
    client.start(websocketHost, websocketPort, false);
    if (!client.websock || typeof client.websock.reconnect !== "function") {
      throw new Error("sdk_reconnect_guard_unavailable");
    }
    client.websock.reconnect = () => client.websock?.killReconnectTimer?.();
    await login;
    if (!client.websock.isReadyConnect()) {
      throw new Error("quote_connection_not_ready");
    }
    const response = await client._sendCmd(
      getUserInfoCommand,
      { c2s: { flag: quoteRightsOnlyFlag } },
      "GetUserInfo",
    );
    return allowlistedTrackRightsEvidence(response);
  } catch (error) {
    return failed(error);
  } finally {
    if (client?.websock) {
      client.stop();
      client.websock.close();
    }
    restoreConsole();
  }
}

function failed(error) {
  const allowedCodes = new Set([
    "explicit_live_argument_required",
    "rights_confirmation_missing",
    "non_localhost_endpoint_forbidden",
    "unexpected_websocket_port",
    "malformed_track_quote_rights",
    "login_timeout",
    "login_rejected",
    "sdk_reconnect_guard_unavailable",
    "quote_connection_not_ready",
  ]);
  const candidate = error instanceof Error ? error.message : "provider_request_rejected";
  return {
    schemaVersion: 1,
    kind: "futu_track_quote_rights_probe",
    status: "failed",
    failure: {
      code: allowedCodes.has(candidate) ? candidate : "provider_request_rejected",
      providerTextRetained: false,
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

if (import.meta.main) {
  const evidence = await run();
  process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
  if (evidence.status === "failed") process.exitCode = 1;
}
