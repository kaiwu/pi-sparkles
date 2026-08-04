import { binding, requirePlugins } from "./modules.js";
import { run } from "./process.js";

const filter = process.argv[2];
const packages = filter
  ? requirePlugins(filter)
  : [binding(), ...requirePlugins()];

for (const pkg of packages) {
  console.log(`testing ${pkg.shortName}`);
  run("gleam", ["test", "--target", "javascript", "--runtime", "bun"], {
    cwd: pkg.directory,
  });
}
