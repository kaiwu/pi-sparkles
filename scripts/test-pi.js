import { existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { build } from "./build.js";
import { DIST_DIR, ROOT, requirePlugins } from "./modules.js";
import { run } from "./process.js";

const filter = process.argv[2];
const selected = requirePlugins(filter);
await build(filter);

const piSource = resolve(
  process.env.PI_SOURCE_DIR ?? join(ROOT, "..", "..", "github", "pi-mono"),
);
const piTest = join(piSource, "pi-test.sh");
const sourceTsx = join(piSource, "node_modules", ".bin", "tsx");
const useSourceRuntime = existsSync(piTest) && existsSync(sourceTsx);
const piCommand = useSourceRuntime ? piTest : Bun.which("pi");
if (!piCommand) throw new Error("No runnable Pi installation found");

if (!useSourceRuntime) {
  console.log(
    `Pi source checkout is not hydrated; using installed Pi at ${piCommand}`,
  );
}

for (const plugin of selected) {
  console.log(
    `loading ${plugin.shortName} with ${useSourceRuntime ? `Pi from ${piSource}` : "installed Pi"}`,
  );
  run(
    piCommand,
    [
      ...(useSourceRuntime ? ["--no-env"] : []),
      "--no-extensions",
      "--extension",
      join(DIST_DIR, plugin.shortName),
      "--list-models",
    ],
    { cwd: ROOT, quiet: true },
  );
}
