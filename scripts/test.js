import { run } from "./process.js";
import { ROOT } from "./modules.js";
import { buildAcceptanceFixture } from "./build-acceptance-fixture.js";

run("bun", ["scripts/check.js"], { cwd: ROOT });
run("bun", ["scripts/test-unit.js"], { cwd: ROOT });
run("bun", ["test", "test/architecture", "test/finance"], { cwd: ROOT });
run("bun", ["scripts/build.js"], { cwd: ROOT });
buildAcceptanceFixture();
run("bun", ["test", "test/binding", "test/artifacts"], {
  cwd: ROOT,
});
// Acceptance invokes bundled provider tools under a scripted global transport.
// Keep it in a separate Bun process from binding tests, which install their own
// temporary transports.
run("bun", ["test", "test/acceptance"], {
  cwd: ROOT,
});
run("bun", ["scripts/test-pi.js"], { cwd: ROOT });
