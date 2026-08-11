import { existsSync } from "node:fs";
import { join } from "node:path";
import { requireUnitPackages, unitPackages } from "./modules.js";
import { run } from "./process.js";

const filter = process.argv[2];
const packages = filter ? requireUnitPackages(filter) : unitPackages();

for (const pkg of packages) {
  if (!existsSync(join(pkg.directory, "test"))) {
    console.log(
      `testing ${pkg.shortName} (no package-local pure tests; shell is covered by artifact/Pi/tier lanes)`,
    );
    continue;
  }
  console.log(`testing ${pkg.shortName}`);
  run("gleam", ["test", "--target", "javascript", "--runtime", "bun"], {
    cwd: pkg.directory,
  });
}
