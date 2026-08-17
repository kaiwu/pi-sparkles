import gleam/dynamic.{type Dynamic}

@external(javascript, "./terminal_ffi.mjs", "render_result")
pub fn render_result(
  result: Dynamic,
  expanded: Bool,
  theme: Dynamic,
  last_component: Dynamic,
) -> Dynamic
