import { join } from "node:path";
import { ROOT } from "./modules.js";
import { run } from "./process.js";

export const ACCEPTANCE_FIXTURE_DIR = join(ROOT, "test", "acceptance_fixture");
export const ACCEPTANCE_FIXTURE_MODULE = join(
  ACCEPTANCE_FIXTURE_DIR,
  "build",
  "dev",
  "javascript",
  "pi_sparkles_acceptance_fixture",
  "swing_acceptance_receipts.mjs",
);

export function buildAcceptanceFixture() {
  run(
    "gleam",
    ["build", "--target", "javascript", "--warnings-as-errors"],
    { cwd: ACCEPTANCE_FIXTURE_DIR },
  );
}

if (import.meta.main) buildAcceptanceFixture();
