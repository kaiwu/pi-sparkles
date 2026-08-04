import { unitPackages } from "./modules.js";
import { run } from "./process.js";

for (const pkg of unitPackages()) {
  console.log(`checking ${pkg.shortName}`);
  run("gleam", ["format", "--check", "src", "test"], { cwd: pkg.directory });
  run(
    "gleam",
    ["build", "--target", "javascript", "--warnings-as-errors"],
    { cwd: pkg.directory },
  );
}
