const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_SIGNATURE = 0x02014b50;
const LOCAL_SIGNATURE = 0x04034b50;
const textDecoder = new TextDecoder("utf-8", { fatal: true });
const CRC32_TABLE = Uint32Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) {
    value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return value >>> 0;
});

export async function extract_zip_utf8(
  bodyBase64,
  requiredNames,
  maximumArchiveBytes,
  maximumEntries,
  maximumEntryBytes,
  maximumTotalUncompressedBytes,
  cancellation,
) {
  try {
    if (isCancelled(cancellation)) return failure("cancelled");
    if (typeof bodyBase64 !== "string") return failure("invalid_base64");
    const bytes = Buffer.from(bodyBase64, "base64");
    if (bytes.toString("base64") !== bodyBase64) {
      return failure("invalid_base64");
    }
    if (bytes.length > maximumArchiveBytes) {
      return failure("archive_too_large", null, maximumArchiveBytes, bytes.length);
    }

    const eocdOffset = findEocd(bytes);
    if (eocdOffset < 0) return failure("invalid_archive");
    const disk = u16(bytes, eocdOffset + 4);
    const centralDisk = u16(bytes, eocdOffset + 6);
    const diskEntries = u16(bytes, eocdOffset + 8);
    const entryCount = u16(bytes, eocdOffset + 10);
    const centralSize = u32(bytes, eocdOffset + 12);
    const centralOffset = u32(bytes, eocdOffset + 16);
    if (disk !== 0 || centralDisk !== 0 || diskEntries !== entryCount) {
      return failure("multi_disk");
    }
    if (
      entryCount === 0xffff ||
      centralSize === 0xffffffff ||
      centralOffset === 0xffffffff
    ) {
      return failure("zip64");
    }
    if (entryCount > maximumEntries) {
      return failure("too_many_entries", null, maximumEntries, entryCount);
    }
    if (centralOffset + centralSize !== eocdOffset) {
      return failure("invalid_archive");
    }

    const records = new Map();
    let cursor = centralOffset;
    let totalUncompressedBytes = 0;
    for (let index = 0; index < entryCount; index += 1) {
      if (isCancelled(cancellation)) return failure("cancelled");
      if (cursor + 46 > eocdOffset || u32(bytes, cursor) !== CENTRAL_SIGNATURE) {
        return failure("invalid_archive");
      }
      const flags = u16(bytes, cursor + 8);
      const method = u16(bytes, cursor + 10);
      const crc = u32(bytes, cursor + 16);
      const compressedSize = u32(bytes, cursor + 20);
      const uncompressedSize = u32(bytes, cursor + 24);
      const nameLength = u16(bytes, cursor + 28);
      const extraLength = u16(bytes, cursor + 30);
      const commentLength = u16(bytes, cursor + 32);
      const diskStart = u16(bytes, cursor + 34);
      const localOffset = u32(bytes, cursor + 42);
      const end = cursor + 46 + nameLength + extraLength + commentLength;
      if (end > eocdOffset || diskStart !== 0) return failure("invalid_archive");
      if (
        compressedSize === 0xffffffff ||
        uncompressedSize === 0xffffffff ||
        localOffset === 0xffffffff
      ) {
        return failure("zip64");
      }
      const name = decodeName(bytes.subarray(cursor + 46, cursor + 46 + nameLength));
      if (name === null || !safeName(name)) {
        return failure("unsafe_entry_name", name ?? "");
      }
      if (records.has(name)) return failure("duplicate_entry", name);
      if ((flags & 0x2041) !== 0) return failure("encrypted_entry", name);
      if (method !== 0 && method !== 8) {
        return failure("unsupported_compression", name);
      }
      if (uncompressedSize > maximumEntryBytes) {
        return failure("entry_too_large", name, maximumEntryBytes, uncompressedSize);
      }
      totalUncompressedBytes += uncompressedSize;
      if (totalUncompressedBytes > maximumTotalUncompressedBytes) {
        return failure(
          "total_uncompressed_too_large",
          null,
          maximumTotalUncompressedBytes,
          totalUncompressedBytes,
        );
      }
      records.set(name, {
        name,
        flags,
        method,
        crc,
        compressedSize,
        uncompressedSize,
        localOffset,
      });
      cursor = end;
    }
    if (cursor !== eocdOffset) return failure("invalid_archive");

    const entries = [];
    for (const name of requiredNames) {
      if (isCancelled(cancellation)) return failure("cancelled");
      const record = records.get(name);
      if (!record) return failure("missing_required_entry", name);
      const extracted = await extractRecord(
        bytes,
        record,
        centralOffset,
        maximumEntryBytes,
        cancellation,
      );
      if (!extracted.ok) return extracted;
      entries.push({
        name,
        text: extracted.text,
        byteLength: record.uncompressedSize,
        crc32: hex32(record.crc),
      });
    }
    return {
      ok: true,
      archiveByteLength: bytes.length,
      entryCount,
      totalUncompressedBytes,
      entries,
    };
  } catch {
    return failure("invalid_archive");
  }
}

async function extractRecord(
  bytes,
  record,
  centralOffset,
  maximumEntryBytes,
  cancellation,
) {
  if (isCancelled(cancellation)) return failure("cancelled");
  const offset = record.localOffset;
  if (offset + 30 > centralOffset || u32(bytes, offset) !== LOCAL_SIGNATURE) {
    return failure("malformed_entry", record.name);
  }
  const localFlags = u16(bytes, offset + 6);
  const localMethod = u16(bytes, offset + 8);
  const nameLength = u16(bytes, offset + 26);
  const extraLength = u16(bytes, offset + 28);
  const dataStart = offset + 30 + nameLength + extraLength;
  const dataEnd = dataStart + record.compressedSize;
  if (dataEnd > centralOffset || localFlags !== record.flags || localMethod !== record.method) {
    return failure("malformed_entry", record.name);
  }
  const localName = decodeName(bytes.subarray(offset + 30, offset + 30 + nameLength));
  if (localName !== record.name) return failure("malformed_entry", record.name);
  const compressed = bytes.subarray(dataStart, dataEnd);
  let output;
  try {
    output = record.method === 0
      ? Uint8Array.from(compressed)
      : await inflateBounded(
        compressed,
        maximumEntryBytes,
        record.uncompressedSize,
        cancellation,
      );
  } catch (error) {
    return error instanceof CancelledExtraction
      ? failure("cancelled", record.name)
      : failure("decompression_failed", record.name);
  }
  if (output.length !== record.uncompressedSize) {
    return failure("entry_length_mismatch", record.name);
  }
  if (crc32(output) !== record.crc) return failure("checksum_mismatch", record.name);
  try {
    return { ok: true, text: textDecoder.decode(output) };
  } catch {
    return failure("invalid_utf8", record.name);
  }
}

async function inflateBounded(compressed, limit, expected, cancellation) {
  const stream = new Blob([compressed])
    .stream()
    .pipeThrough(new DecompressionStream("deflate-raw"));
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    if (isCancelled(cancellation)) {
      await reader.cancel();
      throw new CancelledExtraction();
    }
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > limit || total > expected) {
      await reader.cancel();
      throw new Error("decompressed limit exceeded");
    }
    chunks.push(value);
  }
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

class CancelledExtraction extends Error {}

function isCancelled(cancellation) {
  return Boolean(cancellation?.signal?.aborted);
}

function findEocd(bytes) {
  const minimum = Math.max(0, bytes.length - 22 - 0xffff);
  for (let offset = bytes.length - 22; offset >= minimum; offset -= 1) {
    if (u32(bytes, offset) !== EOCD_SIGNATURE) continue;
    const commentLength = u16(bytes, offset + 20);
    if (offset + 22 + commentLength === bytes.length) return offset;
  }
  return -1;
}

function decodeName(bytes) {
  try {
    const value = textDecoder.decode(bytes);
    return [...value].every((character) => character.codePointAt(0) < 128)
      ? value
      : null;
  } catch {
    return null;
  }
}

function safeName(value) {
  if (
    value.length === 0 ||
    value.length > 240 ||
    value.startsWith("/") ||
    value.includes("\\") ||
    value.includes("\0") ||
    value.includes(":")
  ) return false;
  return value.split("/").every(
    (segment) => segment !== "" && segment !== "." && segment !== "..",
  );
}

function u16(bytes, offset) {
  if (offset < 0 || offset + 2 > bytes.length) throw new Error("bounds");
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function u32(bytes, offset) {
  if (offset < 0 || offset + 4 > bytes.length) throw new Error("bounds");
  return (
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)
  ) >>> 0;
}

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value = (value >>> 8) ^ CRC32_TABLE[(value ^ byte) & 0xff];
  }
  return (value ^ 0xffffffff) >>> 0;
}

function hex32(value) {
  return value.toString(16).padStart(8, "0");
}

function failure(kind, name = null, limit = null, received = null) {
  const value = { ok: false, kind };
  if (name !== null) value.name = name;
  if (limit !== null) value.limit = limit;
  if (received !== null) value.received = received;
  return value;
}
