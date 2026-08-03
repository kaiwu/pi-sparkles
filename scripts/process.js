export function run(command, args, options = {}) {
  const result = Bun.spawnSync([command, ...args], {
    cwd: options.cwd,
    env: options.env ?? process.env,
    stdout: options.quiet ? "pipe" : "inherit",
    stderr: options.quiet ? "pipe" : "inherit",
  });
  if (result.exitCode !== 0) {
    if (options.quiet) {
      process.stdout.write(result.stdout.toString());
      process.stderr.write(result.stderr.toString());
    }
    throw new Error(`${command} exited with code ${result.exitCode}`);
  }
  return result;
}

