export function new_cell(value) {
  return { value };
}

export function read_cell(cell) {
  return cell.value;
}

export function write_cell(cell, value) {
  cell.value = value;
}

export function new_subscriptions() {
  return new Map();
}

export function subscribe(subscriptions, id, cancellation, callback) {
  unsubscribe(subscriptions, id);

  const signal = cancellation.signal;
  if (signal.aborted) {
    callback();
    return;
  }

  const onAbort = () => {
    subscriptions.delete(id);
    callback();
  };
  signal.addEventListener("abort", onAbort, { once: true });
  subscriptions.set(id, { signal, onAbort });
}

export function unsubscribe(subscriptions, id) {
  const subscription = subscriptions.get(id);
  if (subscription === undefined) return;

  subscription.signal.removeEventListener("abort", subscription.onAbort);
  subscriptions.delete(id);
}
