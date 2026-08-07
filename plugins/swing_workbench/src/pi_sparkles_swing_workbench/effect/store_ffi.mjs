export function new_store(value) {
  return { value };
}

export function read_store(store) {
  return store.value;
}

export function write_store(store, value) {
  store.value = value;
}
