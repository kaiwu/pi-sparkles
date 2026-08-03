import { rmSync } from "node:fs";
import { join } from "node:path";
import { DIST_DIR, WORK_DIR, bindings, plugins } from "./modules.js";

rmSync(DIST_DIR, { recursive: true, force: true });
rmSync(WORK_DIR, { recursive: true, force: true });
for (const pkg of [...bindings(), ...plugins()]) {
  rmSync(join(pkg.directory, "build"), { recursive: true, force: true });
  rmSync(join(pkg.directory, "manifest.toml"), { force: true });
}

