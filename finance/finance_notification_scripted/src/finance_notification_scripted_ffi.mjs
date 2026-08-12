import { createHash } from "node:crypto";

function cancelled(signal) {
  return Boolean(signal && typeof signal === "object" && signal.aborted);
}

export async function deliver(
  channel,
  destinationRef,
  attempt,
  scriptedOutcome,
  signal,
) {
  if (cancelled(signal)) return { status: "cancelled" };
  if (
    channel !== "scripted_local" ||
    typeof destinationRef !== "string" ||
    destinationRef.length < 1 ||
    destinationRef.length > 500 ||
    !Number.isSafeInteger(attempt) ||
    attempt < 1 ||
    attempt > 10 ||
    !["delivered", "rate_limited", "failed"].includes(scriptedOutcome)
  ) {
    return { status: "invalid" };
  }
  const receipt = createHash("sha256")
    .update(JSON.stringify({ channel, destinationRef, attempt, scriptedOutcome }))
    .digest("hex");
  return cancelled(signal)
    ? { status: "cancelled" }
    : { status: scriptedOutcome, receipt };
}
