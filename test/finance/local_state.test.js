import { afterEach, describe, expect, test } from "bun:test";
import { mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const built = resolve(
  import.meta.dir,
  "../../finance/finance_local_state/build/dev/javascript/finance_local_state/finance_local_state_ffi.mjs",
);
let directory;

afterEach(async () => {
  if (directory) await rm(directory, { recursive: true, force: true });
  directory = undefined;
});

describe("local durable state capability", () => {
  test("atomically replaces only unchanged regular UTF-8 state", async () => {
    directory = await mkdtemp(join(tmpdir(), "pi-sparkles-state-"));
    const file = join(directory, "journal.jsonl");
    const { read_text, replace_if_unchanged } = await import(`${built}?t=${Date.now()}`);
    const signal = new AbortController().signal;

    expect(await read_text(file, 1024, signal)).toEqual({ state: "missing" });
    expect(await replace_if_unchanged(file, "", "one\n", 1024, signal)).toEqual({
      state: "replaced",
      bytes: 4,
    });
    expect(await replace_if_unchanged(file, "", "two\n", 1024, signal)).toEqual({
      state: "changed",
      bytes: 4,
    });
    expect(await readFile(file, "utf8")).toBe("one\n");
  });

  test("rejects symlinks, budgets, and cancellation", async () => {
    directory = await mkdtemp(join(tmpdir(), "pi-sparkles-state-"));
    const target = join(directory, "target");
    const link = join(directory, "link");
    await writeFile(target, "abcdef", "utf8");
    await symlink(target, link);
    const { read_text } = await import(`${built}?t=${Date.now()}`);
    expect(await read_text(link, 1024, new AbortController().signal)).toMatchObject({
      state: "failure",
      code: "symbolic_link_not_supported",
    });
    expect(await read_text(target, 2, new AbortController().signal)).toMatchObject({
      state: "too_large",
      bytes: 6,
    });
    const controller = new AbortController();
    controller.abort();
    expect(await read_text(target, 1024, controller.signal)).toEqual({
      state: "cancelled",
    });
  });
});
