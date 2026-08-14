import { writeFile } from "node:fs/promises";

const registrationEndpoint = "https://webapi.futunn.com/oauth2/register";
const authorizationEndpoint = "https://webapi.futunn.com/oauth2/authorize/confirm";
const tokenEndpoint = "https://webapi.futunn.com/oauth2/token";
const callbackHost = "127.0.0.1";
const callbackPort = 60355;
const callbackUrl = `http://localhost:${callbackPort}/callback`;
const tokenFile = "/tmp/pi-sparkles-futu-webapi-quote-token.json";
const confirmation = "I_ACCEPT_ONE_FUTU_QUOTE_ONLY_OAUTH_FLOW";
const allowedScope = "quote:read";

export function validateOauthProbeConfig(argv, environment) {
  if (!argv.includes("--live") || argv.some((argument) => argument !== "--live")) {
    throw new Error("explicit_live_argument_required");
  }
  if (environment.FUTU_WEBAPI_CONFIRM !== confirmation) {
    throw new Error("oauth_confirmation_missing");
  }
  if (environment.FUTU_WEBAPI_TOKEN_FILE !== undefined) {
    throw new Error("token_path_override_forbidden");
  }
  for (const key of Object.keys(environment)) {
    if (/^FUTU_.*(?:TOKEN|SECRET|PASSWORD|PWD)$/i.test(key)) {
      throw new Error("ambient_secret_forbidden");
    }
  }
}

export function registrationRequest() {
  return {
    redirect_uris: [callbackUrl],
    token_endpoint_auth_method: "none",
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    client_name: "pi-sparkles T6 development quote probe",
  };
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

export async function pkceFromBytes(verifierBytes, stateBytes) {
  if (verifierBytes.byteLength < 32 || stateBytes.byteLength < 24) {
    throw new Error("insufficient_pkce_entropy");
  }
  const verifier = base64Url(verifierBytes);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );
  return {
    verifier,
    challenge: base64Url(new Uint8Array(digest)),
    state: base64Url(stateBytes),
  };
}

export function authorizationUrl(clientId, challenge, state) {
  if (![clientId, challenge, state].every((value) => typeof value === "string" && value)) {
    throw new Error("invalid_authorization_material");
  }
  const url = new URL(authorizationEndpoint);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("redirect_uri", callbackUrl);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("state", state);
  return url.toString();
}

export function validateQuoteOnlyToken(response) {
  const scopes = new Set(String(response?.scope ?? "").split(/\s+/).filter(Boolean));
  if (
    typeof response?.access_token !== "string" ||
    response.access_token.length === 0 ||
    response?.token_type !== "Bearer" ||
    !Number.isInteger(response?.expires_in) ||
    response.expires_in <= 0 ||
    scopes.size !== 1 ||
    !scopes.has(allowedScope)
  ) {
    const error = new Error("quote_only_scope_not_granted");
    error.scopeClassification = classifyGrantedScopes(scopes);
    throw error;
  }
  return {
    accessToken: response.access_token,
    expiresIn: response.expires_in,
    scope: allowedScope,
  };
}

export function classifyGrantedScopes(value) {
  const scopes = value instanceof Set
    ? value
    : new Set(String(value?.scope ?? "").split(/\s+/).filter(Boolean));
  const known = new Set([
    "quote:read",
    "quote:write",
    "trade:read",
    "trade:write",
  ]);
  return {
    scopeCount: scopes.size,
    quoteRead: scopes.has("quote:read"),
    quoteWrite: scopes.has("quote:write"),
    tradeRead: scopes.has("trade:read"),
    tradeWrite: scopes.has("trade:write"),
    accountScope: [...scopes].some((scope) => scope.startsWith("accid:")),
    unknownScope: [...scopes].some(
      (scope) => !known.has(scope) && !scope.startsWith("accid:"),
    ),
  };
}

export function safeCompletion(token) {
  return {
    schemaVersion: 1,
    kind: "futu_webapi_quote_oauth_probe",
    status: "authorized",
    provider: "Futu direct Web API",
    scope: token.scope,
    expiresInSeconds: token.expiresIn,
    tokenFile,
    tokenFileMode: "0600",
    refreshTokenRetained: false,
    clientRegistrationCredentialRetained: false,
    accountFieldsRetained: false,
    tradeScopeAccepted: false,
  };
}

async function parseJsonResponse(response, code) {
  if (!response.ok) throw new Error(code);
  try {
    return await response.json();
  } catch {
    throw new Error(code);
  }
}

async function registerClient() {
  const response = await fetch(registrationEndpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(registrationRequest()),
    signal: AbortSignal.timeout(15_000),
  });
  const body = await parseJsonResponse(response, "client_registration_failed");
  if (typeof body.client_id !== "string" || body.client_id.length === 0) {
    throw new Error("client_registration_failed");
  }
  return body.client_id;
}

function waitForAuthorization(expectedState) {
  let settle;
  const callback = new Promise((resolve, reject) => {
    settle = { resolve, reject };
  });
  let completed = false;
  const server = Bun.serve({
    hostname: callbackHost,
    port: callbackPort,
    async fetch(request) {
      const url = new URL(request.url);
      if (url.pathname !== "/callback") return new Response("Not found", { status: 404 });
      if (completed) return new Response("Authorization already received.");
      completed = true;
      const state = url.searchParams.get("state");
      const code = url.searchParams.get("code");
      const error = url.searchParams.get("error");
      if (error || state !== expectedState || !code) {
        settle.reject(new Error(error ? "authorization_denied" : "invalid_oauth_callback"));
        return new Response("Futu quote authorization was not accepted.", { status: 400 });
      }
      settle.resolve(code);
      return new Response(
        "Futu quote-only authorization received. You may close this page.",
        { headers: { "content-type": "text/plain; charset=utf-8" } },
      );
    },
  });
  return {
    async code() {
      let timeout;
      try {
        return await Promise.race([
          callback,
          new Promise((_, reject) => {
            timeout = setTimeout(
              () => reject(new Error("authorization_timeout")),
              300_000,
            );
          }),
        ]);
      } finally {
        clearTimeout(timeout);
        server.stop(true);
      }
    },
  };
}

async function exchangeCode(clientId, code, verifier) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    client_id: clientId,
    redirect_uri: callbackUrl,
    code_verifier: verifier,
  });
  const response = await fetch(tokenEndpoint, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
    signal: AbortSignal.timeout(15_000),
  });
  return validateQuoteOnlyToken(
    await parseJsonResponse(response, "token_exchange_failed"),
  );
}

async function persistShortLivedToken(token) {
  const record = {
    access_token: token.accessToken,
    scope: token.scope,
    expires_at_ms: Date.now() + token.expiresIn * 1_000,
  };
  try {
    await writeFile(tokenFile, `${JSON.stringify(record)}\n`, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
  } catch (error) {
    if (error?.code === "EEXIST") throw new Error("token_file_already_exists");
    throw error;
  }
}

async function run() {
  validateOauthProbeConfig(process.argv.slice(2), process.env);
  const verifierBytes = crypto.getRandomValues(new Uint8Array(32));
  const stateBytes = crypto.getRandomValues(new Uint8Array(24));
  const pkce = await pkceFromBytes(verifierBytes, stateBytes);
  const clientId = await registerClient();
  const callback = waitForAuthorization(pkce.state);
  process.stdout.write(`${authorizationUrl(clientId, pkce.challenge, pkce.state)}\n`);
  const code = await callback.code();
  const token = await exchangeCode(clientId, code, pkce.verifier);
  await persistShortLivedToken(token);
  return safeCompletion(token);
}

function failed(error) {
  const allowed = new Set([
    "explicit_live_argument_required",
    "oauth_confirmation_missing",
    "token_path_override_forbidden",
    "ambient_secret_forbidden",
    "client_registration_failed",
    "authorization_denied",
    "invalid_oauth_callback",
    "authorization_timeout",
    "token_exchange_failed",
    "quote_only_scope_not_granted",
    "token_file_already_exists",
  ]);
  const candidate = error instanceof Error ? error.message : "oauth_probe_failed";
  return {
    schemaVersion: 1,
    kind: "futu_webapi_quote_oauth_probe",
    status: "failed",
    failure: {
      code: allowed.has(candidate) ? candidate : "oauth_probe_failed",
      ...(candidate === "quote_only_scope_not_granted" &&
      error?.scopeClassification
        ? { scopeClassification: error.scopeClassification }
        : {}),
    },
  };
}

if (import.meta.main) {
  let result;
  try {
    result = await run();
  } catch (error) {
    result = failed(error);
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.status === "failed") process.exitCode = 1;
}
