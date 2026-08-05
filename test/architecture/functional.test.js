import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, join, relative } from "node:path";
import {
  FINANCE_DIR,
  PLUGINS_DIR,
  ROOT,
  discoverPackages,
} from "../../scripts/modules.js";

function filesBelow(directory, extension) {
  if (!existsSync(directory)) return [];
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory()
      ? filesBelow(path, extension)
      : entry.name.endsWith(extension)
        ? [path]
        : [];
  });
}

function source(path) {
  return readFileSync(path, "utf8");
}

function display(path) {
  return relative(ROOT, path);
}

const piImport = /^import pi(?:\s|\/|\.|$)/m;
const promiseImport = /^import gleam\/javascript\/promise(?:\s|\.|$)/m;

describe("functional architecture", () => {
  test("finance libraries never depend on the Pi host", () => {
    for (const pkg of discoverPackages(FINANCE_DIR)) {
      for (const path of filesBelow(join(pkg.directory, "src"), ".gleam")) {
        expect(piImport.test(source(path)), display(path)).toBeFalse();
      }
    }
  });

  test("plugin domain modules do not perform Pi or Promise effects", () => {
    for (const pkg of discoverPackages(PLUGINS_DIR)) {
      const domainDirectory = join(pkg.directory, "src", pkg.name);
      for (const path of filesBelow(domainDirectory, ".gleam")) {
        const gleam = source(path);
        expect(piImport.test(gleam), display(path)).toBeFalse();
        expect(promiseImport.test(gleam), display(path)).toBeFalse();
      }
    }
  });

  test("plugin FFI is restricted to explicitly named effect modules", () => {
    for (const pkg of discoverPackages(PLUGINS_DIR)) {
      const domainDirectory = join(pkg.directory, "src", pkg.name);
      for (const path of filesBelow(domainDirectory, ".gleam")) {
        if (!source(path).includes("@external")) continue;
        const allowed =
          basename(path) === "store.gleam" || path.includes("/effect/");
        expect(allowed, `${display(path)} must move FFI under effect/`).toBeTrue();
      }
    }
  });

  test("pure finance foundations contain no Promise or FFI boundary", () => {
    for (const name of [
      "finance_core",
      "finance_track",
      "finance_evidence",
      "finance_listing",
      "finance_calendar",
      "finance_market_calendar",
      "finance_cn_identity",
      "finance_cn_calendar",
      "finance_hk_identity",
      "finance_hk_calendar",
      "finance_math",
      "finance_series",
      "finance_table",
    ]) {
      const directory = join(FINANCE_DIR, name, "src");
      for (const path of filesBelow(directory, ".gleam")) {
        const gleam = source(path);
        expect(promiseImport.test(gleam), display(path)).toBeFalse();
        expect(gleam.includes("@external"), display(path)).toBeFalse();
      }
      expect(filesBelow(directory, ".mjs"), name).toEqual([]);
    }
  });

  test("cn and hk plugins cannot import SEC market-domain packages", () => {
    const forbidden = /^import finance_sec(?:\s|\/|\.|$)/m;
    for (const pkg of discoverPackages(PLUGINS_DIR)) {
      if (!/pi_sparkles_(cn|hk)_/.test(pkg.name)) continue;
      for (const path of filesBelow(join(pkg.directory, "src"), ".gleam")) {
        expect(forbidden.test(source(path)), display(path)).toBeFalse();
      }
    }
  });
});
