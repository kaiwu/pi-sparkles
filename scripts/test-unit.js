import { existsSync } from "node:fs";
import { join } from "node:path";
import { requireUnitPackages, unitPackages } from "./modules.js";
import {
  recommendedConcurrency,
  runParallel,
} from "./process.js";

const filter = process.argv[2];
const packages = filter ? requireUnitPackages(filter) : unitPackages();

const tasks = packages.map((pkg) => {
  if (!existsSync(join(pkg.directory, "test"))) {
    return {
      label: `testing ${pkg.shortName} (no package-local pure tests; shell is covered by artifact/Pi/tier lanes)`,
    };
  }
  return {
    command: "gleam",
    args: ["test", "--target", "javascript", "--runtime", "bun"],
    options: { cwd: pkg.directory },
    label: `testing ${pkg.shortName}`,
  };
});

await runParallel(tasks, {
  concurrency: recommendedConcurrency(process.env.PI_SPARKLES_TEST_JOBS),
});
