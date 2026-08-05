import { expect, test } from "bun:test";
import * as time from "../../finance/finance_http/build/dev/javascript/finance_core/finance_core/time.mjs";
import * as binaryClient from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/binary_client.mjs";
import * as binaryResponse from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/binary_response.mjs";
import * as client from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/client.mjs";
import * as request from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/request.mjs";
import * as response from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/response.mjs";
import * as retry from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/retry.mjs";
import * as transport from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/transport.mjs";
import { sleep_milliseconds } from "../../finance/finance_http/src/finance_http/client_ffi.mjs";
import { Error, Ok, toList } from "../../finance/finance_http/build/dev/javascript/finance_http/gleam.mjs";
import { Option$None$const } from "../../finance/finance_http/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

function unwrap(result) {
  if (result instanceof Ok) return result[0];
  throw new Error(`Expected Ok, received ${result.constructor.name}`);
}

function duration(milliseconds) {
  return unwrap(time.duration(milliseconds));
}

function instant(milliseconds) {
  return unwrap(time.instant(milliseconds));
}

function retryPolicy({ attempts = 3, baseDelay = 0 } = {}) {
  return unwrap(
    retry.policy(
      attempts,
      duration(5_000),
      duration(baseDelay),
      duration(baseDelay),
    ),
  );
}

function getRequest() {
  return unwrap(
    request.new$(
      request.Method$Get$const,
      "https://data.example.test",
      "/quotes",
      Option$None$const,
    ),
  );
}

function postRequest() {
  return unwrap(
    request.new$(
      request.Method$Post$const,
      "https://data.example.test",
      "/orders",
      Option$None$const,
    ),
  );
}

function httpResponse(status, body, headers = []) {
  return unwrap(
    response.new$(status, toList(headers), body, Buffer.byteLength(body), duration(1)),
  );
}

function binaryPdfResponse(status, headers = []) {
  return unwrap(
    binaryResponse.new$(
      status,
      toList(headers),
      "JVBERi0=",
      5,
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "255044462d",
      duration(1),
    ),
  );
}

test("policy client retries an idempotent transient status through injected effects", async () => {
  let calls = 0;
  const sleeps = [];
  const sender = async () => {
    calls += 1;
    if (calls === 1) {
      return new Ok(
        httpResponse(503, "private outage body", [
          response.Header$Header("Retry-After", "0"),
        ]),
      );
    }
    return new Ok(httpResponse(200, "quote"));
  };
  const sleeper = async (delay) => {
    sleeps.push(time.duration_milliseconds(delay));
    return true;
  };
  const policyClient = client.new$(
    retryPolicy(),
    sender,
    sleeper,
    () => instant(1_700_000_000_000),
  );

  const result = await client.send(
    policyClient,
    getRequest(),
    transport.new_cancellation(),
  );

  expect(result).toBeInstanceOf(Ok);
  expect(response.status(result[0])).toBe(200);
  expect(response.body(result[0])).toBe("quote");
  expect(calls).toBe(2);
  expect(sleeps).toEqual([0]);
});

test("binary policy client reuses retry laws without decoding the body as text", async () => {
  let calls = 0;
  const sender = async () => {
    calls += 1;
    if (calls === 1) {
      return new Ok(
        binaryPdfResponse(503, [response.Header$Header("Retry-After", "0")]),
      );
    }
    return new Ok(binaryPdfResponse(200));
  };
  const policyClient = binaryClient.new$(
    retryPolicy(),
    sender,
    async () => true,
    () => instant(1_700_000_000_000),
  );

  const result = await binaryClient.send(
    policyClient,
    getRequest(),
    transport.new_cancellation(),
  );

  expect(result).toBeInstanceOf(Ok);
  expect(binaryResponse.status(result[0])).toBe(200);
  expect(binaryResponse.body_base64(result[0])).toBe("JVBERi0=");
  expect(calls).toBe(2);
});

test("policy client does not retry an unkeyed non-idempotent request", async () => {
  let calls = 0;
  const sender = async () => {
    calls += 1;
    return new Ok(httpResponse(503, "provider secret body"));
  };
  const policyClient = client.new$(
    retryPolicy(),
    sender,
    async () => true,
    () => instant(1_700_000_000_000),
  );

  const result = await client.send(
    policyClient,
    postRequest(),
    transport.new_cancellation(),
  );

  expect(result).toBeInstanceOf(Error);
  expect(result[0]).toBeInstanceOf(client.RetryStopped);
  expect(result[0].reason).toBe(retry.StopReason$NonIdempotentRequest$const);
  expect(result[0].attempts).toBe(1);
  expect(calls).toBe(1);
  expect(JSON.stringify(result[0])).not.toContain("provider secret body");
});

test("policy client makes retry sleep cancellation terminal", async () => {
  const cancellation = transport.new_cancellation();
  const policyClient = client.new$(
    retryPolicy({ baseDelay: 100 }),
    async () => new Error(transport.TransportError$Timeout$const),
    async () => {
      transport.cancel(cancellation);
      return false;
    },
    () => instant(1_700_000_000_000),
  );

  const result = await client.send(policyClient, getRequest(), cancellation);

  expect(result).toBeInstanceOf(Error);
  expect(result[0]).toBe(client.ClientError$Cancelled$const);
});

test("policy client status acceptance is immutable and provider-configurable", async () => {
  const base = client.new$(
    retryPolicy(),
    async () => new Ok(httpResponse(304, "")),
    async () => true,
    () => instant(1_700_000_000_000),
  );
  const acceptsNotModified = client.with_status_acceptor(
    base,
    (status) => status === 304,
  );

  const accepted = await client.send(
    acceptsNotModified,
    getRequest(),
    transport.new_cancellation(),
  );
  const rejected = await client.send(
    base,
    getRequest(),
    transport.new_cancellation(),
  );

  expect(accepted).toBeInstanceOf(Ok);
  expect(rejected).toBeInstanceOf(Error);
});

test("default retry sleep is abort-aware", async () => {
  const cancellation = transport.new_cancellation();
  const sleeping = sleep_milliseconds(10_000, cancellation);
  transport.cancel(cancellation);

  expect(await sleeping).toBe(false);
});
