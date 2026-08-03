import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/hello/index.js");

describe("hello artifact", () => {
  test("exports a Pi extension factory", async () => {
    const module = await import(`${artifact}?test=${Date.now()}`);
    expect(typeof module.default).toBe("function");
  });
});

