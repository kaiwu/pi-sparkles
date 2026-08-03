export function identity(value) {
  return value;
}

export function undefined_value() {
  return undefined;
}

export function null_value() {
  return null;
}

export function object(entries) {
  return Object.fromEntries(entries);
}

export function get(target, property) {
  return target[property];
}

export function set(target, property, value) {
  target[property] = value;
}

export function call(target, method, args) {
  return target[method](...args);
}

export function as_promise(value) {
  return value;
}

export function on(api, event, handler) {
  api.on(event, handler);
}

export function register_tool(api, definition) {
  api.registerTool(definition);
}

export function register_message_renderer(api, customType, renderer) {
  api.registerMessageRenderer(customType, renderer);
}

export function register_entry_renderer(api, customType, renderer) {
  api.registerEntryRenderer(customType, renderer);
}

export function register_markdown_transformer(api, transformer) {
  api.registerMarkdownTransformer(transformer);
}
