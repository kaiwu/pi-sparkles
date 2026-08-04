import { rmSync } from "node:fs";
import { join } from "node:path";
import { binding, DIST_DIR, WORK_DIR, plugins } from "./modules.js";

rmSync(DIST_DIR, { recursive: true, force: true });
rmSync(WORK_DIR, { recursive: true, force: true });
for (const pkg of [binding(), ...plugins()]) {
  rmSync(join(pkg.directory, "build"), { recursive: true, force: true });
  rmSync(join(pkg.directory, "manifest.toml"), { force: true });
}
