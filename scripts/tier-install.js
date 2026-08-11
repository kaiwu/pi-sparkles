import { resolve } from "node:path";
import { run } from "./process.js";
import { readTierManifest } from "./tiers.js";
import {
  packageTier,
  tierPackagePlan,
  verifyTierPackage,
} from "./tier-package.js";

export function piInstallArguments(packageDirectory, scope, approve = false) {
  if (!new Set(["user", "project"]).has(scope)) {
    throw new Error(`Unknown install scope: ${scope}`);
  }
  if (approve && scope !== "project") {
    throw new Error("--approve applies only to project-local installation");
  }
  return [
    "install",
    resolve(packageDirectory),
    ...(scope === "project" ? ["--local"] : []),
    ...(approve ? ["--approve"] : []),
  ];
}

export async function installTier(
  tierId,
  {
    build = true,
    outputDirectory,
    scope = "user",
    approve = false,
    piCommand,
    cwd = process.cwd(),
  } = {},
) {
  const plan = tierPackagePlan(readTierManifest(), tierId);
  const output = outputDirectory ?? plan.outputDirectory;
  const summary = build
    ? await packageTier(tierId, { build: true, outputDirectory: output })
    : verifyTierPackage(output, plan);
  if (summary.tierId !== tierId) {
    throw new Error(`Tier package contains ${summary.tierId}, expected ${tierId}`);
  }

  const executable = piCommand ?? Bun.which("pi");
  if (!executable) throw new Error("No installed plain Pi executable found");
  const args = piInstallArguments(summary.directory, scope, approve);
  run(executable, args, { cwd });
  console.log(
    `${tierId} installed in ${scope} Pi settings from ${summary.directory}`,
  );
  return { ...summary, scope };
}

function usage() {
  return [
    "Usage: bun run tier:install -- T1 [--no-build] [--output <directory>]",
    "       [--scope user|project] [--approve] [--pi <executable>]",
    "The installer delegates settings changes to plain Pi's `pi install` command.",
  ].join("\n");
}

function parseArguments(args) {
  let tierId;
  let build = true;
  let outputDirectory;
  let scope = "user";
  let approve = false;
  let piCommand;
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--no-build") build = false;
    else if (arg === "--approve") approve = true;
    else if (arg === "--output") {
      outputDirectory = args[index + 1];
      index += 1;
      if (!outputDirectory) throw new Error("--output requires a directory");
    } else if (arg === "--scope") {
      scope = args[index + 1];
      index += 1;
      if (!scope) throw new Error("--scope requires user or project");
    } else if (arg === "--pi") {
      piCommand = args[index + 1];
      index += 1;
      if (!piCommand) throw new Error("--pi requires an executable");
    } else if (arg === "--help" || arg === "-h") {
      console.log(usage());
      process.exit(0);
    } else if (arg.startsWith("-")) throw new Error(`Unknown option: ${arg}`);
    else if (tierId) throw new Error(`Unexpected argument: ${arg}`);
    else tierId = arg;
  }
  return { tierId, build, outputDirectory, scope, approve, piCommand };
}

if (import.meta.main) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const manifest = readTierManifest();
    await installTier(options.tierId ?? manifest.active_tier, options);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    console.error(usage());
    process.exit(1);
  }
}
