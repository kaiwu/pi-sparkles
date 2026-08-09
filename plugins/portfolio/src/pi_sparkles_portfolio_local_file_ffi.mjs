import { lstat, open, readFile } from "node:fs/promises";

function cancelled(signal) {
  return Boolean(signal && typeof signal === "object" && signal.aborted);
}

function code(error) {
  return typeof error?.code === "string" ? error.code : "io_failure";
}

function decodeUtf8(buffer) {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } catch {
    return undefined;
  }
}

function decodePrefix(buffer) {
  for (let drop = 0; drop <= 3 && drop <= buffer.byteLength; drop += 1) {
    const retained = buffer.subarray(0, buffer.byteLength - drop);
    const text = decodeUtf8(retained);
    if (text !== undefined) return { text, bytes: retained.byteLength };
  }
  return undefined;
}

export async function read_text(path, maximumBytes, signal) {
  if (cancelled(signal)) return { state: "cancelled" };
  if (
    typeof path !== "string" ||
    path.length === 0 ||
    path.includes("\0") ||
    !Number.isSafeInteger(maximumBytes) ||
    maximumBytes < 1 ||
    maximumBytes > 10_000_000
  ) {
    return { state: "failure", code: "invalid_read_request" };
  }

  try {
    const metadata = await lstat(path);
    if (metadata.isSymbolicLink()) {
      return { state: "failure", code: "symbolic_link_not_supported" };
    }
    if (!metadata.isFile()) {
      return { state: "failure", code: "not_a_regular_file" };
    }
    if (cancelled(signal)) return { state: "cancelled" };

    if (metadata.size <= maximumBytes) {
      const buffer = await readFile(path);
      if (cancelled(signal)) return { state: "cancelled" };
      if (buffer.byteLength > maximumBytes) {
        const prefix = decodePrefix(buffer.subarray(0, maximumBytes));
        return prefix
          ? {
              state: "truncated",
              text: prefix.text,
              bytes: prefix.bytes,
              total: buffer.byteLength,
            }
          : { state: "invalid_utf8" };
      }
      const text = decodeUtf8(buffer);
      return text === undefined
        ? { state: "invalid_utf8" }
        : { state: "loaded", text, bytes: buffer.byteLength };
    }

    const handle = await open(path, "r");
    try {
      const buffer = Buffer.alloc(maximumBytes);
      const { bytesRead } = await handle.read(buffer, 0, maximumBytes, 0);
      if (cancelled(signal)) return { state: "cancelled" };
      const prefix = decodePrefix(buffer.subarray(0, bytesRead));
      return prefix
        ? {
            state: "truncated",
            text: prefix.text,
            bytes: prefix.bytes,
            total: metadata.size,
          }
        : { state: "invalid_utf8" };
    } finally {
      await handle.close();
    }
  } catch (error) {
    if (error?.code === "ENOENT") return { state: "missing" };
    return { state: "failure", code: code(error) };
  }
}
