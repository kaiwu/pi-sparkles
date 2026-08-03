import { bindings, plugins } from "./modules.js";
import { run } from "./process.js";

const packages = [...bindings(), ...plugins()];
if (packages.length === 0) throw new Error("No Gleam packages found");

for (const pkg of packages) {
  console.log(`checking ${pkg.shortName}`);
  run("gleam", ["format", "--check", "src", "test"], { cwd: pkg.directory });
  run(
    "gleam",
    ["build", "--target", "javascript", "--warnings-as-errors"],
    { cwd: pkg.directory },
  );
}

