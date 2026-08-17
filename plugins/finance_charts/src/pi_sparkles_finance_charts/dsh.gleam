import gleam/javascript/promise.{type Promise}
import pi
import pi/tool
import pi_sparkles_finance_charts/tool_surface

/// DSH owns browser presentation through its keyed SVG tool-result card. This
/// sibling registers only the headless structured chart tool and has no import
/// of Pi's terminal renderer.
pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "chart_ohlcv",
    "Render an exact OHLCV chart",
    "Produce validated OHLCV chart data for the native DSH inline browser card from one verified active-session series receipt or bounded caller-supplied bars; this view performs no analytics or interpretation",
    tool_surface.prompt_snippet(),
    tool_surface.parameters(),
    tool.Parallel,
    tool_surface.execute,
  )
  promise.resolve(Nil)
}
