import { createHash } from "node:crypto";

export function new_cancellation() {
  const controller = new AbortController();
  return {
    signal: controller.signal,
    cancel: () => controller.abort(),
  };
}

export function from_abort_signal(signal) {
  if (
    signal !== null &&
    typeof signal === "object" &&
    typeof signal.aborted === "boolean" &&
    typeof signal.addEventListener === "function" &&
    typeof signal.removeEventListener === "function"
  ) {
    return { signal, cancel: null };
  }
  return new_cancellation();
}

export function cancel(cancellation) {
  cancellation.cancel?.();
}

export function is_cancelled(cancellation) {
  return cancellation.signal.aborted;
}

export async function send_request(payload, cancellation) {
  return send(payload, cancellation, "text");
}

export async function send_binary_request(payload, cancellation) {
  return send(payload, cancellation, "binary");
}

async function send(payload, cancellation, responseKind) {
  const request = JSON.parse(payload);
  const controller = new AbortController();
  let abortKind = null;

  if (cancellation.signal.aborted) {
    return { ok: false, kind: "cancelled" };
  }

  const forwardCancellation = () => {
    abortKind ??= "cancelled";
    controller.abort();
  };
  cancellation.signal.addEventListener("abort", forwardCancellation, { once: true });
  const timer = setTimeout(() => {
    abortKind ??= "timeout";
    controller.abort();
  }, request.timeoutMs);
  const started = performance.now();

  try {
    const url = new URL(request.path, `${request.origin}/`);
    for (const parameter of request.query) {
      url.searchParams.append(parameter.name, parameter.value);
    }

    const headers = new Headers();
    for (const header of request.headers) {
      headers.append(header.name, header.value);
    }
    if (request.idempotencyKey !== null && !headers.has("idempotency-key")) {
      headers.set("idempotency-key", request.idempotencyKey);
    }
    if (request.body !== null && !headers.has("content-type")) {
      headers.set("content-type", request.body.contentType);
    }

    const response = await fetch(url, {
      method: request.method,
      headers,
      body: request.body === null ? undefined : request.body.value,
      signal: controller.signal,
      redirect: "error",
    });

    const declaredLength = response.headers.get("content-length");
    if (
      declaredLength !== null &&
      Number.isSafeInteger(Number(declaredLength)) &&
      Number(declaredLength) > request.maximumResponseBytes
    ) {
      await response.body?.cancel();
      return {
        ok: false,
        kind: "response_too_large",
        limit: request.maximumResponseBytes,
      };
    }

    const read = responseKind === "binary"
      ? await readBoundedBinaryBody(response.body, request.maximumResponseBytes)
      : await readBoundedBody(response.body, request.maximumResponseBytes);
    if (!read.ok) {
      return read;
    }

    return {
      ok: true,
      status: response.status,
      headers: Array.from(response.headers.entries(), ([name, value]) => ({ name, value })),
      ...read,
      elapsedMs: Math.max(0, Math.round(performance.now() - started)),
    };
  } catch (_) {
    if (abortKind === "timeout") {
      return { ok: false, kind: "timeout" };
    }
    if (abortKind === "cancelled" || cancellation.signal.aborted) {
      return { ok: false, kind: "cancelled" };
    }
    return { ok: false, kind: "network" };
  } finally {
    clearTimeout(timer);
    cancellation.signal.removeEventListener("abort", forwardCancellation);
  }
}

async function readBoundedBinaryBody(stream, limit) {
  const hash = createHash("sha256");
  if (stream === null) {
    return {
      ok: true,
      bodyBase64: "",
      byteLength: 0,
      contentSha256: hash.digest("hex"),
      prefixHex: "",
    };
  }

  const reader = stream.getReader();
  const chunks = [];
  let byteLength = 0;
  let prefix = new Uint8Array(0);

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      byteLength += value.byteLength;
      if (byteLength > limit) {
        await reader.cancel();
        return { ok: false, kind: "response_too_large", limit };
      }
      if (prefix.byteLength < 16) {
        const needed = 16 - prefix.byteLength;
        const addition = value.subarray(0, needed);
        const combined = new Uint8Array(prefix.byteLength + addition.byteLength);
        combined.set(prefix);
        combined.set(addition, prefix.byteLength);
        prefix = combined;
      }
      hash.update(value);
      chunks.push(value);
    }

    const bytes = Buffer.concat(
      chunks.map((chunk) => Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength)),
      byteLength,
    );
    return {
      ok: true,
      bodyBase64: bytes.toString("base64"),
      byteLength,
      contentSha256: hash.digest("hex"),
      prefixHex: Buffer.from(prefix).toString("hex"),
    };
  } finally {
    reader.releaseLock();
  }
}

async function readBoundedBody(stream, limit) {
  if (stream === null) {
    return { ok: true, body: "", byteLength: 0 };
  }

  const reader = stream.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const parts = [];
  let byteLength = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      byteLength += value.byteLength;
      if (byteLength > limit) {
        await reader.cancel();
        return { ok: false, kind: "response_too_large", limit };
      }
      parts.push(decoder.decode(value, { stream: true }));
    }
    parts.push(decoder.decode());
    return { ok: true, body: parts.join(""), byteLength };
  } finally {
    reader.releaseLock();
  }
}
