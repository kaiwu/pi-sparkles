export function now_milliseconds() {
  return Date.now();
}

export function sleep_milliseconds(milliseconds, cancellation) {
  return new Promise((resolve) => {
    if (cancellation.signal.aborted) {
      resolve(false);
      return;
    }

    let settled = false;
    const finish = (completed) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      cancellation.signal.removeEventListener("abort", onAbort);
      resolve(completed);
    };
    const onAbort = () => finish(false);
    const timer = setTimeout(() => finish(true), milliseconds);
    cancellation.signal.addEventListener("abort", onAbort, { once: true });
  });
}
