import { describe, expect, test } from "bun:test";
import { recommendedConcurrency } from "../../scripts/process.js";

describe("bounded test process concurrency", () => {
  test("uses a conservative default and accepts an explicit bounded override", () => {
    expect(recommendedConcurrency(undefined, 1)).toBe(1);
    expect(recommendedConcurrency(undefined, 32)).toBe(4);
    expect(recommendedConcurrency("8", 1)).toBe(8);
  });

  test("rejects invalid or excessive concurrency", () => {
    for (const value of ["0", "-1", "1.5", "many", "17"]) {
      expect(() => recommendedConcurrency(value, 8)).toThrow(
        "PI_SPARKLES_TEST_JOBS must be an integer from 1 through 16",
      );
    }
  });
});
