import { expect, test } from "bun:test";
import * as time from "../../finance/finance_http/build/dev/javascript/finance_core/finance_core/time.mjs";
import * as client from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/client.mjs";
import * as pool from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/pool.mjs";
import * as request from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/request.mjs";
import * as response from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/response.mjs";
import * as retry from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/retry.mjs";
import * as scheduler from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/scheduler.mjs";
import * as transport from "../../finance/finance_http/build/dev/javascript/finance_http/finance_http/transport.mjs";
import { Error, Ok, toList } from "../../finance/finance_http/build/dev/javascript/finance_http/gleam.mjs";
import { Option$None$const } from "../../finance/finance_http/build/dev/javascript/gleam_stdlib/gleam/option.mjs";

function unwrap(result) {
  if (result instanceof Ok) return result[0];
  throw new globalThis.Error(`Expected Ok, received ${result.constructor.name}`);
}

function duration(milliseconds) {
  return unwrap(time.duration(milliseconds));
}

function instant(milliseconds) {
  return unwrap(time.instant(milliseconds));
}

function policyClient(sender) {
  const policy = unwrap(
    retry.policy(1, duration(5_000), duration(0), duration(0)),
  );
  return client.new$(
    policy,
    sender,
    async () => true,
    () => instant(1_700_000_000_000),
  );
}

function getRequest(origin, path) {
  return unwrap(
    request.new$(
      request.Method$Get$const,
      origin,
      path,
      Option$None$const,
    ),
  );
}

function httpResponse(body) {
  return unwrap(
    response.new$(200, toList([]), body, Buffer.byteLength(body), duration(1)),
  );
}

function controlledSender() {
  const started = [];
  const pending = new Map();
  const sender = (requestValue, cancellation) => {
    const path = request.path(requestValue);
    started.push(path);
    return new Promise((resolve) => {
      pending.set(path, resolve);
      cancellation.signal.addEventListener(
        "abort",
        () => resolve(new Error(transport.TransportError$Cancelled$const)),
        { once: true },
      );
    });
  };
  return { sender, started, pending };
}

test("pool enforces both limits and skips an ineligible queue head", async () => {
  const controlled = controlledSender();
  const requests = {
    a1: getRequest("https://a.example.test", "/a1"),
    c1: getRequest("https://c.example.test", "/c1"),
    a2: getRequest("https://a.example.test", "/a2"),
    b1: getRequest("https://b.example.test", "/b1"),
  };
  const requestPool = unwrap(pool.new$(policyClient(controlled.sender), 2, 1, 4));

  const a1 = pool.send(
    requestPool,
    "a1",
    requests.a1,
    transport.new_cancellation(),
  );
  const c1 = pool.send(
    requestPool,
    "c1",
    requests.c1,
    transport.new_cancellation(),
  );
  const a2 = pool.send(
    requestPool,
    "a2",
    requests.a2,
    transport.new_cancellation(),
  );
  const b1 = pool.send(
    requestPool,
    "b1",
    requests.b1,
    transport.new_cancellation(),
  );

  expect(controlled.started).toEqual(["/a1", "/c1"]);
  expect(pool.in_flight(requestPool)).toBe(2);
  expect(pool.waiting_count(requestPool)).toBe(2);

  controlled.pending.get("/c1")(new Ok(httpResponse("c1")));
  expect(await c1).toBeInstanceOf(Ok);
  expect(controlled.started).toEqual(["/a1", "/c1", "/b1"]);
  expect(pool.waiting_count(requestPool)).toBe(1);

  controlled.pending.get("/a1")(new Ok(httpResponse("a1")));
  expect(await a1).toBeInstanceOf(Ok);
  expect(controlled.started).toEqual(["/a1", "/c1", "/b1", "/a2"]);

  controlled.pending.get("/b1")(new Ok(httpResponse("b1")));
  controlled.pending.get("/a2")(new Ok(httpResponse("a2")));
  expect(await b1).toBeInstanceOf(Ok);
  expect(await a2).toBeInstanceOf(Ok);
  expect(pool.in_flight(requestPool)).toBe(0);
});

test("pool reports bounded-queue overflow without starting the request", async () => {
  const controlled = controlledSender();
  const requestPool = unwrap(pool.new$(policyClient(controlled.sender), 1, 1, 1));

  const active = pool.send(
    requestPool,
    "active",
    getRequest("https://a.example.test", "/active"),
    transport.new_cancellation(),
  );
  const waiting = pool.send(
    requestPool,
    "waiting",
    getRequest("https://b.example.test", "/waiting"),
    transport.new_cancellation(),
  );
  const overflow = await pool.send(
    requestPool,
    "overflow",
    getRequest("https://c.example.test", "/overflow"),
    transport.new_cancellation(),
  );

  expect(overflow).toBeInstanceOf(Error);
  expect(overflow[0]).toBeInstanceOf(pool.AdmissionFailed);
  expect(overflow[0].error).toBe(scheduler.SchedulerError$QueueFull$const);
  expect(controlled.started).toEqual(["/active"]);

  controlled.pending.get("/active")(new Ok(httpResponse("active")));
  expect(await active).toBeInstanceOf(Ok);
  controlled.pending.get("/waiting")(new Ok(httpResponse("waiting")));
  expect(await waiting).toBeInstanceOf(Ok);
});

test("pool removes waiting cancellation and retains an active slot until abort settles", async () => {
  const controlled = controlledSender();
  const requestPool = unwrap(pool.new$(policyClient(controlled.sender), 1, 1, 3));
  const activeCancellation = transport.new_cancellation();
  const waitingCancellation = transport.new_cancellation();

  const active = pool.send(
    requestPool,
    "active",
    getRequest("https://a.example.test", "/active"),
    activeCancellation,
  );
  const cancelledWaiting = pool.send(
    requestPool,
    "cancelled-waiting",
    getRequest("https://b.example.test", "/cancelled-waiting"),
    waitingCancellation,
  );

  transport.cancel(waitingCancellation);
  const waitingResult = await cancelledWaiting;
  expect(waitingResult).toBeInstanceOf(Error);
  expect(waitingResult[0]).toBeInstanceOf(pool.RequestFailed);
  expect(waitingResult[0].error).toBe(client.ClientError$Cancelled$const);
  expect(pool.waiting_count(requestPool)).toBe(0);

  const next = pool.send(
    requestPool,
    "next",
    getRequest("https://b.example.test", "/next"),
    transport.new_cancellation(),
  );
  transport.cancel(activeCancellation);
  expect(pool.in_flight(requestPool)).toBe(1);
  expect(controlled.started).toEqual(["/active"]);

  const activeResult = await active;
  expect(activeResult).toBeInstanceOf(Error);
  expect(activeResult[0]).toBeInstanceOf(pool.RequestFailed);
  expect(activeResult[0].error).toBe(client.ClientError$Cancelled$const);
  expect(controlled.started).toEqual(["/active", "/next"]);

  controlled.pending.get("/next")(new Ok(httpResponse("next")));
  expect(await next).toBeInstanceOf(Ok);
});

test("pool contains a rejected injected client and releases its slot", async () => {
  const started = [];
  const sender = async (requestValue) => {
    const path = request.path(requestValue);
    started.push(path);
    if (path === "/broken") throw new globalThis.Error("secret provider failure");
    return new Ok(httpResponse("recovered"));
  };
  const requestPool = unwrap(pool.new$(policyClient(sender), 1, 1, 2));

  const broken = pool.send(
    requestPool,
    "broken",
    getRequest("https://a.example.test", "/broken"),
    transport.new_cancellation(),
  );
  const recovered = pool.send(
    requestPool,
    "recovered",
    getRequest("https://b.example.test", "/recovered"),
    transport.new_cancellation(),
  );

  const brokenResult = await broken;
  expect(brokenResult).toBeInstanceOf(Error);
  expect(brokenResult[0]).toBe(pool.PoolError$UnexpectedClientFailure$const);
  expect(JSON.stringify(brokenResult)).not.toContain("secret provider failure");
  expect(await recovered).toBeInstanceOf(Ok);
  expect(started).toEqual(["/broken", "/recovered"]);
  expect(pool.in_flight(requestPool)).toBe(0);
});
