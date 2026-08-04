import { existsSync, readdirSync, readFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";

export const ROOT = resolve(import.meta.dir, "..");
export const BINDING_DIR = join(ROOT, "pi_gleam");
export const PLUGINS_DIR = join(ROOT, "plugins");
export const DIST_DIR = join(ROOT, "dist");
export const WORK_DIR = join(ROOT, ".work");

export function readGleamPackage(directory) {
  const gleamToml = join(directory, "gleam.toml");
  const metadata = Bun.TOML.parse(readFileSync(gleamToml, "utf8"));
  if (typeof metadata.name !== "string" || typeof metadata.version !== "string") {
    throw new Error(`Invalid Gleam package metadata: ${gleamToml}`);
  }
  return {
    directory,
    shortName: basename(directory),
    name: metadata.name,
    version: metadata.version,
    metadata,
  };
}

export function discoverPackages(parent) {
  if (!existsSync(parent)) return [];
  return readdirSync(parent, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(parent, entry.name))
    .filter((directory) => existsSync(join(directory, "gleam.toml")))
    .map(readGleamPackage)
    .sort((a, b) => a.shortName.localeCompare(b.shortName));
}

export function binding() {
  return readGleamPackage(BINDING_DIR);
}

export function plugins(filter) {
  const found = discoverPackages(PLUGINS_DIR);
  if (!filter) return found;
  return found.filter(
    (plugin) => plugin.shortName === filter || plugin.name === filter,
  );
}

export function requirePlugins(filter) {
  const found = plugins(filter);
  if (found.length === 0) {
    throw new Error(filter ? `Plugin not found: ${filter}` : "No plugins found");
  }
  return found;
}
