export function register(
  api,
  name,
  label,
  description,
  promptSnippet,
  parameters,
  executionMode,
  execute,
) {
  api.registerTool({
    name,
    label,
    description,
    ...(promptSnippet === "" ? {} : { promptSnippet }),
    parameters,
    ...(executionMode === "" ? {} : { executionMode }),
    execute,
  });
}

export function text(value) {
  return { type: "text", text: value };
}

export function image(data, mimeType) {
  return { type: "image", data, mimeType };
}

export function result(content, details, terminate) {
  return { content, details, ...(terminate ? { terminate: true } : {}) };
}

export function text_result(value, details) {
  return { content: [{ type: "text", text: value }], details };
}

export function update(sink, result) {
  if (typeof sink === "function") sink(result);
}

export function is_cancelled(signal) {
  return signal?.aborted === true;
}

export function reject(message) {
  return Promise.reject(new Error(message));
}
