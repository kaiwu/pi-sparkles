import { constants } from "node:fs";
import { open } from "node:fs/promises";

const READ_FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;
const READ_CHUNK_BYTES = 64 * 1024;

function cancelled(signal) {
  return Boolean(signal && typeof signal === "object" && signal.aborted);
}

function errorCode(error) {
  return typeof error?.code === "string" ? error.code : "io_failure";
}

function decodeUtf8(buffer) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } catch {
    return undefined;
  }
}

async function openRegular(path) {
  let handle;
  try {
    handle = await open(path, READ_FLAGS);
    const metadata = await handle.stat();
    if (!metadata.isFile()) {
      await handle.close();
      return { result: { state: "failure", code: "not_a_regular_file" } };
    }
    return { handle, metadata };
  } catch (error) {
    await handle?.close().catch(() => {});
    if (error?.code === "ENOENT") return { result: { state: "missing" } };
    if (error?.code === "ELOOP") {
      return {
        result: { state: "failure", code: "symbolic_link_not_supported" },
      };
    }
    return { result: { state: "failure", code: errorCode(error) } };
  }
}

async function readBounded(handle, maximumBytes, signal) {
  const chunks = [];
  let total = 0;
  while (total <= maximumBytes) {
    if (cancelled(signal)) return { cancelled: true };
    const remaining = maximumBytes + 1 - total;
    const buffer = Buffer.allocUnsafe(Math.min(READ_CHUNK_BYTES, remaining));
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, total);
    if (bytesRead === 0) break;
    chunks.push(buffer.subarray(0, bytesRead));
    total += bytesRead;
  }
  return { cancelled: false, buffer: Buffer.concat(chunks, total) };
}

export async function read_text(path, maximumBytes, signal) {
  if (cancelled(signal)) return { state: "cancelled" };
  if (
    typeof path !== "string" ||
    path.length === 0 ||
    path.length > 4096 ||
    path.includes("\0") ||
    !Number.isSafeInteger(maximumBytes) ||
    maximumBytes < 1 ||
    maximumBytes > 5_000_000
  ) {
    return { state: "failure", code: "invalid_read_request" };
  }

  const opened = await openRegular(path);
  if (opened.result) return opened.result;
  const { handle, metadata } = opened;
  try {
    if (cancelled(signal)) return { state: "cancelled" };
    if (metadata.size > maximumBytes) {
      return {
        state: "truncated",
        bytes: maximumBytes,
        total: metadata.size,
      };
    }

    const read = await readBounded(handle, maximumBytes, signal);
    if (read.cancelled) return { state: "cancelled" };
    const { buffer } = read;
    if (buffer.byteLength > maximumBytes) {
      const latest = await handle.stat();
      return {
        state: "truncated",
        bytes: maximumBytes,
        total: Math.max(metadata.size, latest.size, buffer.byteLength),
      };
    }
    const text = decodeUtf8(buffer);
    return text === undefined
      ? { state: "invalid_utf8" }
      : { state: "loaded", text, bytes: buffer.byteLength };
  } catch (error) {
    return { state: "failure", code: errorCode(error) };
  } finally {
    await handle.close().catch(() => {});
  }
}
