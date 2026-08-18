import gleam/javascript/promise.{type Promise}
import pi
import pi/tool
import pi_sparkles_finance_charts/effect/terminal
import pi_sparkles_finance_charts_tool_surface as tool_surface

/// Pi owns the Unicode terminal renderer. The DSH bundle imports the sibling
/// headless extension and never loads this TUI component.
pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register_rendered(
    api,
    "chart_ohlcv",
    "Render an exact OHLCV chart",
    "Render a responsive inline Pi terminal OHLCV chart from one verified active-session series receipt or bounded caller-supplied bars, plus optional receipt-bound indicators and explicit annotations; this view performs no analytics or interpretation",
    tool_surface.prompt_snippet(),
    tool_surface.parameters(),
    tool.Parallel,
    terminal.render_result,
    tool_surface.execute,
  )
  promise.resolve(Nil)
}
