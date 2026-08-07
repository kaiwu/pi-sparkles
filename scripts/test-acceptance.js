import { ROOT } from "./modules.js";
import { run } from "./process.js";
import { buildAcceptanceFixture } from "./build-acceptance-fixture.js";

const lane = process.argv[2] ?? "swing";

if (lane !== "swing") {
  throw new Error(`Unknown acceptance lane: ${lane}`);
}

// This lane executes a fully declared fixture. It does not select a scenario,
// policy, branch, quantity, conclusion, or next operation.
buildAcceptanceFixture();
run("bun", ["scripts/test-unit.js", "swing_workbench"], { cwd: ROOT });
run("bun", ["scripts/build.js", "cn_ohlcv"], { cwd: ROOT });
run("bun", ["scripts/build.js", "hk_ohlcv"], { cwd: ROOT });
run("bun", ["scripts/build.js", "us_ohlcv"], { cwd: ROOT });
run("bun", ["scripts/build.js", "stock_screener"], { cwd: ROOT });
run("bun", ["scripts/build.js", "swing_workbench"], { cwd: ROOT });
run("bun", ["scripts/build.js", "trade_journal"], { cwd: ROOT });
run("bun", ["test", "test/acceptance/swing_workflow.test.js"], {
  cwd: ROOT,
});
