import { randomUUID } from "node:crypto";
import { lstat, open, readFile, rename, unlink } from "node:fs/promises";

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

async function readExisting(path, maximumBytes) {
  try {
    const metadata = await lstat(path);
    if (metadata.isSymbolicLink()) {
      return { state: "failure", code: "symbolic_link_not_supported" };
    }
    if (!metadata.isFile()) {
      return { state: "failure", code: "not_a_regular_file" };
    }
    if (metadata.size > maximumBytes) {
      return { state: "too_large", bytes: metadata.size, maximum: maximumBytes };
    }
    const buffer = await readFile(path);
    if (buffer.byteLength > maximumBytes) {
      return { state: "too_large", bytes: buffer.byteLength, maximum: maximumBytes };
    }
    const text = strictUtf8(buffer);
    return text === undefined
      ? { state: "invalid_utf8" }
      : { state: "loaded", text, bytes: buffer.byteLength };
  } catch (error) {
    return error?.code === "ENOENT"
      ? { state: "missing" }
      : { state: "failure", code: errorCode(error) };
  }
}

export async function read_text(path, maximumBytes, signal) {
  if (!validRequest(path, maximumBytes)) {
    return { state: "failure", code: "invalid_read_request" };
  }
  if (cancelled(signal)) return { state: "cancelled" };
  const result = await readExisting(path, maximumBytes);
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
    const current = await readExisting(path, maximumBytes);
    if (["too_large", "failure", "invalid_utf8"].includes(current.state)) {
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
