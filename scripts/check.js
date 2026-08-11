import { existsSync } from "node:fs";
import { join } from "node:path";
import { unitPackages } from "./modules.js";
import { run } from "./process.js";
import {
  ACCEPTANCE_FIXTURE_DIR,
  buildAcceptanceFixture,
} from "./build-acceptance-fixture.js";

for (const pkg of unitPackages()) {
  console.log(`checking ${pkg.shortName}`);
  const formatPaths = ["src"];
  if (existsSync(join(pkg.directory, "test"))) formatPaths.push("test");
  run("gleam", ["format", "--check", ...formatPaths], {
    cwd: pkg.directory,
  });
  run(
    "gleam",
    ["build", "--target", "javascript", "--warnings-as-errors"],
    { cwd: pkg.directory },
  );
}

console.log("checking acceptance_fixture");
run("gleam", ["format", "--check", "src"], {
  cwd: ACCEPTANCE_FIXTURE_DIR,
});
buildAcceptanceFixture();
