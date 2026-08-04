import { run } from "./process.js";
import { ROOT } from "./modules.js";

run("bun", ["scripts/check.js"], { cwd: ROOT });
run("bun", ["scripts/test-unit.js"], { cwd: ROOT });
run("bun", ["test", "test/architecture"], { cwd: ROOT });
run("bun", ["scripts/build.js"], { cwd: ROOT });
run("bun", ["test", "test/binding", "test/artifacts"], { cwd: ROOT });
run("bun", ["scripts/test-pi.js"], { cwd: ROOT });
