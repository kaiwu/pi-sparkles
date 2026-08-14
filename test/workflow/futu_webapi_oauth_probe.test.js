import { describe, expect, test } from "bun:test";

import {
  authorizationUrl,
  classifyGrantedScopes,
  pkceFromBytes,
  registrationRequest,
  safeCompletion,
  validateOauthProbeConfig,
  validateQuoteOnlyToken,
} from "../../scripts/futu-webapi-oauth-probe.js";

describe("Futu direct Web API OAuth blocker probe", () => {
  test("is inert without exact live confirmation and forbids ambient secrets", () => {
    const environment = {
      FUTU_WEBAPI_CONFIRM: "I_ACCEPT_ONE_FUTU_QUOTE_ONLY_OAUTH_FLOW",
    };
    expect(() => validateOauthProbeConfig(["--live"], environment)).not.toThrow();
    expect(() => validateOauthProbeConfig([], environment)).toThrow(
      "explicit_live_argument_required",
    );
    expect(() =>
      validateOauthProbeConfig(["--live"], {
        ...environment,
        FUTU_ACCESS_TOKEN: "must-not-be-ambient",
      }),
    ).toThrow("ambient_secret_forbidden");
  });

  test("registers a public authorization-code client on localhost only", () => {
    expect(registrationRequest()).toEqual({
      redirect_uris: ["http://localhost:60355/callback"],
      token_endpoint_auth_method: "none",
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      client_name: "pi-sparkles T6 development quote probe",
    });
  });

  test("generates S256 PKCE without inventing an authorization scope parameter", async () => {
    const pkce = await pkceFromBytes(
      new Uint8Array(32).fill(7),
      new Uint8Array(24).fill(9),
    );
    const url = new URL(authorizationUrl("client", pkce.challenge, pkce.state));
    expect(url.origin).toBe("https://webapi.futunn.com");
    expect(url.pathname).toBe("/oauth2/authorize/confirm");
    expect(url.searchParams.has("scope")).toBeFalse();
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    expect(url.searchParams.get("redirect_uri")).toBe(
      "http://localhost:60355/callback",
    );
  });

  test("rejects every token that is not exactly quote read", () => {
    const accepted = validateQuoteOnlyToken({
      access_token: "ephemeral-secret",
      token_type: "Bearer",
      expires_in: 7200,
      scope: "quote:read",
      refresh_token: "never-retained",
    });
    expect(accepted).toEqual({
      accessToken: "ephemeral-secret",
      expiresIn: 7200,
      scope: "quote:read",
    });
    expect(() =>
      validateQuoteOnlyToken({
        access_token: "secret",
        token_type: "Bearer",
        expires_in: 7200,
        scope: "quote:read trade:read",
      }),
    ).toThrow("quote_only_scope_not_granted");
  });

  test("classifies rejected scopes without exposing account identifiers", () => {
    const classification = classifyGrantedScopes({
      scope: "quote:read trade:read accid:123456 future:scope",
    });
    expect(classification).toEqual({
      scopeCount: 4,
      quoteRead: true,
      quoteWrite: false,
      tradeRead: true,
      tradeWrite: false,
      accountScope: true,
      unknownScope: true,
    });
    expect(JSON.stringify(classification)).not.toContain("123456");
  });

  test("safe evidence contains no token or registration credential", () => {
    const result = safeCompletion({
      accessToken: "ephemeral-secret",
      expiresIn: 7200,
      scope: "quote:read",
    });
    const serialized = JSON.stringify(result);
    expect(serialized).not.toContain("ephemeral-secret");
    expect(result.tradeScopeAccepted).toBeFalse();
    expect(result.refreshTokenRetained).toBeFalse();
  });
});
