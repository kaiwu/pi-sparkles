import { availableParallelism } from "node:os";

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

export function recommendedConcurrency(
  configured,
  available = availableParallelism(),
) {
  if (configured === undefined || configured === "") {
    return Math.max(1, Math.min(4, available));
  }
  if (!/^[1-9][0-9]*$/.test(configured)) {
    throw new Error("PI_SPARKLES_TEST_JOBS must be an integer from 1 through 16");
  }
  const parsed = Number(configured);
  if (parsed > 16) {
    throw new Error("PI_SPARKLES_TEST_JOBS must be an integer from 1 through 16");
  }
  return parsed;
}

export async function runParallel(tasks, options = {}) {
  if (tasks.length === 0) return [];
  const concurrency = Math.min(
    tasks.length,
    options.concurrency ?? recommendedConcurrency(undefined),
  );
  if (!Number.isSafeInteger(concurrency) || concurrency < 1) {
    throw new Error("Parallel process concurrency must be a positive integer");
  }

  const results = Array(tasks.length);
  let nextIndex = 0;
  async function worker() {
    for (;;) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= tasks.length) return;
      results[index] = await runCaptured(tasks[index]);
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));

  for (let index = 0; index < tasks.length; index += 1) {
    const task = tasks[index];
    const result = results[index];
    if (task.label) console.log(task.label);
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
  }

  const failureIndex = results.findIndex((result) => result.exitCode !== 0);
  if (failureIndex !== -1) {
    const task = tasks[failureIndex];
    const result = results[failureIndex];
    throw new Error(`${task.command} exited with code ${result.exitCode}`);
  }
  return results;
}

async function runCaptured(task) {
  if (!task.command) return { exitCode: 0, stdout: "", stderr: "" };
  try {
    const child = Bun.spawn([task.command, ...(task.args ?? [])], {
      cwd: task.options?.cwd,
      env: task.options?.env ?? process.env,
      stdout: "pipe",
      stderr: "pipe",
    });
    const stdout = new Response(child.stdout).text();
    const stderr = new Response(child.stderr).text();
    const [exitCode, capturedStdout, capturedStderr] = await Promise.all([
      child.exited,
      stdout,
      stderr,
    ]);
    return { exitCode, stdout: capturedStdout, stderr: capturedStderr };
  } catch (error) {
    return {
      exitCode: -1,
      stdout: "",
      stderr: `${error instanceof Error ? error.message : String(error)}\n`,
    };
  }
}
