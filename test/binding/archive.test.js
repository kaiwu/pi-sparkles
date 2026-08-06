import { describe, expect, test } from "bun:test";
import { extract_zip_utf8 } from "../../finance/finance_archive/src/archive_ffi.mjs";

describe("bounded ZIP extraction boundary", () => {
  test("extracts only required UTF-8 entries with verified lengths and CRCs", async () => {
    const body = zip([
      ["xl/workbook.xml", "<workbook/>"] ,
      ["xl/worksheets/sheet1.xml", "<worksheet>港交所</worksheet>"],
      ["ignored.xml", "not returned"],
    ]).toString("base64");

    const value = await extract_zip_utf8(
      body,
      ["xl/worksheets/sheet1.xml", "xl/workbook.xml"],
      10_000,
      8,
      1_000,
      2_000,
    );

    expect(value.ok).toBeTrue();
    expect(value.entryCount).toBe(3);
    expect(value.entries.map((entry) => entry.name)).toEqual([
      "xl/worksheets/sheet1.xml",
      "xl/workbook.xml",
    ]);
    expect(value.entries[0]).toMatchObject({
      text: "<worksheet>港交所</worksheet>",
      byteLength: Buffer.byteLength("<worksheet>港交所</worksheet>"),
    });
    expect(value.entries[0].crc32).toMatch(/^[0-9a-f]{8}$/);
  });

  test("rejects unsafe, missing, corrupt, and over-budget archives", async () => {
    const unsafe = zip([["../secret", "x"]]).toString("base64");
    expect(
      await extract_zip_utf8(unsafe, ["../secret"], 10_000, 8, 100, 100),
    ).toMatchObject({ ok: false, kind: "unsafe_entry_name" });

    const ordinary = zip([["xl/workbook.xml", "workbook"]]);
    expect(
      await extract_zip_utf8(
        ordinary.toString("base64"),
        ["xl/missing.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "missing_required_entry" });
    expect(
      await extract_zip_utf8(
        ordinary.toString("base64"),
        ["xl/workbook.xml"],
        10,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "archive_too_large" });

    const corrupt = Buffer.from(ordinary);
    corrupt[30 + Buffer.byteLength("xl/workbook.xml")] ^= 0xff;
    expect(
      await extract_zip_utf8(
        corrupt.toString("base64"),
        ["xl/workbook.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "checksum_mismatch" });
  });

  test("rejects duplicate, encrypted, ZIP64, unsupported, invalid UTF-8, and length-drift entries", async () => {
    const duplicated = zip([
      ["same.xml", "first"],
      ["same.xml", "second"],
    ]).toString("base64");
    expect(
      await extract_zip_utf8(duplicated, ["same.xml"], 10_000, 8, 100, 100),
    ).toMatchObject({ ok: false, kind: "duplicate_entry" });

    const baseline = zip([["entry.xml", "safe"]]);
    const centralOffset = signatureOffset(baseline, 0x02014b50);

    const encrypted = Buffer.from(baseline);
    encrypted.writeUInt16LE(encrypted.readUInt16LE(6) | 1, 6);
    encrypted.writeUInt16LE(
      encrypted.readUInt16LE(centralOffset + 8) | 1,
      centralOffset + 8,
    );
    expect(
      await extract_zip_utf8(
        encrypted.toString("base64"),
        ["entry.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "encrypted_entry" });

    const zip64 = Buffer.from(baseline);
    zip64.writeUInt32LE(0xffffffff, centralOffset + 20);
    expect(
      await extract_zip_utf8(
        zip64.toString("base64"),
        ["entry.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "zip64" });

    const unsupported = Buffer.from(baseline);
    unsupported.writeUInt16LE(12, 8);
    unsupported.writeUInt16LE(12, centralOffset + 10);
    expect(
      await extract_zip_utf8(
        unsupported.toString("base64"),
        ["entry.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "unsupported_compression" });

    const lengthDrift = Buffer.from(baseline);
    lengthDrift.writeUInt32LE(5, centralOffset + 24);
    expect(
      await extract_zip_utf8(
        lengthDrift.toString("base64"),
        ["entry.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "entry_length_mismatch" });

    const invalidUtf8 = zip([["entry.xml", Buffer.from([0xff])]]);
    expect(
      await extract_zip_utf8(
        invalidUtf8.toString("base64"),
        ["entry.xml"],
        10_000,
        8,
        100,
        100,
      ),
    ).toMatchObject({ ok: false, kind: "invalid_utf8" });
  });
});

function zip(entries) {
  const localParts = [];
  const centralParts = [];
  let localOffset = 0;

  for (const [nameValue, text] of entries) {
    const name = Buffer.from(nameValue, "utf8");
    const body = Buffer.isBuffer(text) ? text : Buffer.from(text, "utf8");
    const checksum = crc32(body);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(0, 8);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(body.length, 22);
    local.writeUInt16LE(name.length, 26);
    localParts.push(local, name, body);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(0, 10);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(body.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(localOffset, 42);
    centralParts.push(central, name);
    localOffset += local.length + name.length + body.length;
  }

  const central = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(central.length, 12);
  eocd.writeUInt32LE(localOffset, 16);
  return Buffer.concat([...localParts, central, eocd]);
}

function signatureOffset(bytes, signature) {
  const pattern = Buffer.alloc(4);
  pattern.writeUInt32LE(signature, 0);
  const offset = bytes.indexOf(pattern);
  if (offset < 0) throw new Error("ZIP signature missing in fixture");
  return offset;
}

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    }
  }
  return (value ^ 0xffffffff) >>> 0;
}
