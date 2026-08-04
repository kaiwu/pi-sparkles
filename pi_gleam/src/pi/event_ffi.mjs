export function observe(api, event, handler) {
  api.on(event, handler);
}

export function respond(api, event, handler) {
  api.on(event, handler);
}

export function undefined_value() {
  return undefined;
}

export function reject(message) {
  return Promise.reject(new Error(message));
}

export function project_trust_result(trusted, remember) {
  return { trusted, remember };
}

export function resource_paths(skillPaths, promptPaths, themePaths) {
  return { skillPaths, promptPaths, themePaths };
}

export function cancel() {
  return { cancel: true };
}

export function block_tool(reason) {
  return { block: true, reason };
}

export function continue_input() {
  return { action: "continue" };
}

export function transform_input(text) {
  return { action: "transform", text };
}

export function handled_input() {
  return { action: "handled" };
}

export function system_prompt(value) {
  return { systemPrompt: value };
}

export function replace_payload(value) {
  return value;
}

export function replace_messages(messages) {
  return { messages };
}

export function event_signal(raw) {
  return raw.signal;
}
