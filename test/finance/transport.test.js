import { afterEach, expect, test } from "bun:test";
import {
  cancel,
  from_abort_signal,
  new_cancellation,
  send_request,
} from "../../finance/finance_http/src/finance_http/transport_ffi.mjs";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

function payload(overrides = {}) {
  return JSON.stringify({
    method: "POST",
    origin: "https://data.example.test",
    path: "/quotes",
    headers: [{ name: "x-api-key", value: "secret" }],
    query: [{ name: "symbol", value: "BRK B" }],
    body: { contentType: "application/json", value: "{\"limit\":1}" },
    idempotencyKey: "request-1",
    timeoutMs: 100,
    maximumResponseBytes: 1024,
    ...overrides,
  });
}

test("fetch interpreter preserves the request contract and returns bounded bytes", async () => {
  let observed;
  globalThis.fetch = async (url, options) => {
    observed = { url: url.toString(), options };
    return new Response("ok", {
      status: 201,
      headers: { "x-provider": "example" },
    });
  };

  const result = await send_request(payload(), new_cancellation());

  expect(result).toMatchObject({
    ok: true,
    status: 201,
    body: "ok",
    byteLength: 2,
  });
  expect(result.elapsedMs).toBeGreaterThanOrEqual(0);
  expect(observed.url).toBe("https://data.example.test/quotes?symbol=BRK+B");
  expect(observed.options.method).toBe("POST");
  expect(observed.options.redirect).toBe("error");
  expect(observed.options.headers.get("x-api-key")).toBe("secret");
  expect(observed.options.headers.get("idempotency-key")).toBe("request-1");
  expect(observed.options.headers.get("content-type")).toBe("application/json");
  expect(observed.options.body).toBe("{\"limit\":1}");
});

test("fetch interpreter cancels streaming once the byte limit is crossed", async () => {
  globalThis.fetch = async () => new Response("12345");

  const result = await send_request(
    payload({ method: "GET", body: null, maximumResponseBytes: 4 }),
    new_cancellation(),
  );

  expect(result).toEqual({
    ok: false,
    kind: "response_too_large",
    limit: 4,
  });
});

test("fetch interpreter distinguishes cancellation from timeout", async () => {
  const cancelled = new_cancellation();
  cancel(cancelled);
  globalThis.fetch = async () => {
    throw new Error("fetch should not start");
  };
  expect(await send_request(payload(), cancelled)).toEqual({
    ok: false,
    kind: "cancelled",
  });

  globalThis.fetch = (_url, { signal }) =>
    new Promise((_resolve, reject) => {
      signal.addEventListener("abort", () => reject(new Error("aborted")), {
        once: true,
      });
    });
  expect(
    await send_request(payload({ timeoutMs: 1 }), new_cancellation()),
  ).toEqual({ ok: false, kind: "timeout" });
});

test("fetch interpreter reuses a host-owned signal without taking ownership", async () => {
  const hostController = new AbortController();
  const adapted = from_abort_signal(hostController.signal);
  cancel(adapted);
  expect(hostController.signal.aborted).toBe(false);

  hostController.abort();
  expect(await send_request(payload(), adapted)).toEqual({
    ok: false,
    kind: "cancelled",
  });

  const absentHostSignal = from_abort_signal(undefined);
  expect(absentHostSignal.signal.aborted).toBe(false);
});

test("network exception details do not cross the FFI boundary", async () => {
  globalThis.fetch = async () => {
    throw new Error("provider failed with api_key=secret");
  };

  expect(await send_request(payload(), new_cancellation())).toEqual({
    ok: false,
    kind: "network",
  });
});
