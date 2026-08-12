import { randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { open, rename, unlink } from "node:fs/promises";

const READ_FLAGS = constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK;
const READ_CHUNK_BYTES = 64 * 1024;

function cancelled(signal) {
  return Boolean(signal && typeof signal === "object" && signal.aborted);
}

function errorCode(error) {
  return typeof error?.code === "string" ? error.code : "io_failure";
}

function validRequest(path, maximumBytes) {
  return (
    typeof path === "string" &&
    path.length > 0 &&
    path.length <= 4096 &&
    !path.includes("\0") &&
    Number.isSafeInteger(maximumBytes) &&
    maximumBytes >= 1 &&
    maximumBytes <= 10_000_000
  );
}

function strictUtf8(buffer) {
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

async function readExisting(path, maximumBytes, signal) {
  const opened = await openRegular(path);
  if (opened.result) return opened.result;
  const { handle, metadata } = opened;
  try {
    if (cancelled(signal)) return { state: "cancelled" };
    if (metadata.size > maximumBytes) {
      return { state: "too_large", bytes: metadata.size, maximum: maximumBytes };
    }
    const read = await readBounded(handle, maximumBytes, signal);
    if (read.cancelled) return { state: "cancelled" };
    const { buffer } = read;
    if (buffer.byteLength > maximumBytes) {
      const latest = await handle.stat();
      return {
        state: "too_large",
        bytes: Math.max(metadata.size, latest.size, buffer.byteLength),
        maximum: maximumBytes,
      };
    }
    const text = strictUtf8(buffer);
    return text === undefined
      ? { state: "invalid_utf8" }
      : { state: "loaded", text, bytes: buffer.byteLength };
  } catch (error) {
    return { state: "failure", code: errorCode(error) };
  } finally {
    await handle.close().catch(() => {});
  }
}

export async function read_text(path, maximumBytes, signal) {
  if (!validRequest(path, maximumBytes)) {
    return { state: "failure", code: "invalid_read_request" };
  }
  if (cancelled(signal)) return { state: "cancelled" };
  const result = await readExisting(path, maximumBytes, signal);
  return cancelled(signal) ? { state: "cancelled" } : result;
}

export async function replace_if_unchanged(
  path,
  expected,
  replacement,
  maximumBytes,
  signal,
) {
  if (
    !validRequest(path, maximumBytes) ||
    typeof expected !== "string" ||
    typeof replacement !== "string"
  ) {
    return { state: "failure", code: "invalid_replace_request" };
  }
  const replacementBytes = Buffer.byteLength(replacement, "utf8");
  if (replacementBytes > maximumBytes) {
    return { state: "too_large", bytes: replacementBytes, maximum: maximumBytes };
  }
  if (cancelled(signal)) return { state: "cancelled" };

  const lockPath = `${path}.lock`;
  let lock;
  let temporaryPath;
  try {
    try {
      lock = await open(lockPath, "wx", 0o600);
    } catch (error) {
      return error?.code === "EEXIST"
        ? { state: "busy" }
        : { state: "failure", code: errorCode(error) };
    }
    const current = await readExisting(path, maximumBytes, signal);
    if (
      ["too_large", "failure", "invalid_utf8", "cancelled"].includes(
        current.state,
      )
    ) {
      return current;
    }
    if (cancelled(signal)) return { state: "cancelled" };
    const currentText = current.state === "missing" ? "" : current.text;
    if (currentText !== expected) {
      return { state: "changed", bytes: Buffer.byteLength(currentText, "utf8") };
    }

    temporaryPath = `${path}.${process.pid}.${randomUUID()}.tmp`;
    const temporary = await open(temporaryPath, "wx", 0o600);
    try {
      await temporary.writeFile(replacement, "utf8");
      await temporary.sync();
    } finally {
      await temporary.close();
    }
    if (cancelled(signal)) return { state: "cancelled" };
    await rename(temporaryPath, path);
    temporaryPath = undefined;
    return { state: "replaced", bytes: replacementBytes };
  } catch (error) {
    return { state: "failure", code: errorCode(error) };
  } finally {
    if (temporaryPath) await unlink(temporaryPath).catch(() => {});
    if (lock) {
      await lock.close().catch(() => {});
      await unlink(lockPath).catch(() => {});
    }
  }
}
