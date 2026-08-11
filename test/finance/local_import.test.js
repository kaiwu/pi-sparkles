import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { read_text } from "../../finance/finance_local_import/src/finance_local_import_ffi.mjs";

let directory;

beforeAll(async () => {
  directory = await mkdtemp(join(tmpdir(), "finance-local-import-"));
});

afterAll(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
});

describe("shared bounded local research import", () => {
  test("loads strict UTF-8 and reports the exact byte count", async () => {
    const path = join(directory, "utf8.json");
    await writeFile(path, "贵州茅台", "utf8");
    expect(await read_text(path, 100, new AbortController().signal)).toEqual({
      state: "loaded",
      text: "贵州茅台",
      bytes: 12,
    });
  });

  test("reports truncation without returning partial text", async () => {
    const path = join(directory, "large.txt");
    await writeFile(path, "1234567890", "utf8");
    expect(await read_text(path, 4, new AbortController().signal)).toEqual({
      state: "truncated",
      bytes: 4,
      total: 10,
    });
  });

  test("fails closed on invalid UTF-8, symlinks, directories, and cancellation", async () => {
    const invalid = join(directory, "invalid.bin");
    await writeFile(invalid, Uint8Array.from([0xc3, 0x28]));
    expect(await read_text(invalid, 100, null)).toEqual({
      state: "invalid_utf8",
    });

    const target = join(directory, "target.txt");
    const link = join(directory, "link.txt");
    await writeFile(target, "target", "utf8");
    await symlink(target, link);
    expect(await read_text(link, 100, null)).toEqual({
      state: "failure",
      code: "symbolic_link_not_supported",
    });

    const child = join(directory, "directory");
    await mkdir(child);
    expect(await read_text(child, 100, null)).toEqual({
      state: "failure",
      code: "not_a_regular_file",
    });

    const controller = new AbortController();
    controller.abort();
    expect(await read_text(target, 100, controller.signal)).toEqual({
      state: "cancelled",
    });
  });
});
