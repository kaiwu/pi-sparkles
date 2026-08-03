export function emit(bus, channel, data) {
  bus.emit(channel, data);
}

export function on(bus, channel, handler) {
  return bus.on(channel, handler);
}

export function unsubscribe(subscription) {
  subscription();
}
