import { randomUUID } from "node:crypto";
import { lstat, open, readFile, rename, unlink } from "node:fs/promises";

function cancelled(signal) {
  return Boolean(signal && typeof signal === "object" && signal.aborted);
}

function code(error) {
  return typeof error?.code === "string" ? error.code : "io_failure";
}

function strictUtf8(buffer) {
  try {
    return { ok: true, text: new TextDecoder("utf-8", { fatal: true }).decode(buffer) };
  } catch {
    return { ok: false };
  }
}

async function readExisting(path, maximumBytes) {
  try {
    const metadata = await lstat(path);
    if (metadata.isSymbolicLink()) return { state: "failure", code: "symbolic_link_not_supported" };
    if (!metadata.isFile()) return { state: "failure", code: "not_a_regular_file" };
    if (metadata.size > maximumBytes) return { state: "too_large", bytes: metadata.size, maximum: maximumBytes };
    const buffer = await readFile(path);
    if (buffer.byteLength > maximumBytes) return { state: "too_large", bytes: buffer.byteLength, maximum: maximumBytes };
    const decoded = strictUtf8(buffer);
    if (!decoded.ok) return { state: "invalid_utf8" };
    return { state: "loaded", text: decoded.text, bytes: buffer.byteLength };
  } catch (error) {
    if (error?.code === "ENOENT") return { state: "missing" };
    return { state: "failure", code: code(error) };
  }
}

export async function read_text(path, maximumBytes, signal) {
  if (cancelled(signal)) return { state: "cancelled" };
  const result = await readExisting(path, maximumBytes);
  if (cancelled(signal)) return { state: "cancelled" };
  return result;
}

export async function replace_if_unchanged(path, expected, replacement, maximumBytes, signal) {
  const replacementBytes = Buffer.byteLength(replacement, "utf8");
  if (replacementBytes > maximumBytes) return { state: "too_large", bytes: replacementBytes, maximum: maximumBytes };
  if (cancelled(signal)) return { state: "cancelled" };
  const lockPath = `${path}.lock`;
  let lock;
  let temporaryPath;
  try {
    try {
      lock = await open(lockPath, "wx", 0o600);
    } catch (error) {
      if (error?.code === "EEXIST") return { state: "busy" };
      return { state: "failure", code: code(error) };
    }
    const current = await readExisting(path, maximumBytes);
    if (["too_large", "failure", "invalid_utf8"].includes(current.state)) return current;
    if (cancelled(signal)) return { state: "cancelled" };
    const currentText = current.state === "missing" ? "" : current.text;
    if (currentText !== expected) return { state: "changed", bytes: Buffer.byteLength(currentText, "utf8") };
    temporaryPath = `${path}.${process.pid}.${randomUUID()}.tmp`;
    const temporary = await open(temporaryPath, "wx", 0o600);
    try {
      await temporary.writeFile(replacement, "utf8");
      await temporary.sync();
    } finally {
      await temporary.close();
    }
    if (cancelled(signal)) {
      await unlink(temporaryPath).catch(() => {});
      temporaryPath = undefined;
      return { state: "cancelled" };
    }
    await rename(temporaryPath, path);
    temporaryPath = undefined;
    return { state: "replaced", bytes: replacementBytes };
  } catch (error) {
    return { state: "failure", code: code(error) };
  } finally {
    if (temporaryPath) await unlink(temporaryPath).catch(() => {});
    if (lock) {
      await lock.close().catch(() => {});
      await unlink(lockPath).catch(() => {});
    }
  }
}
