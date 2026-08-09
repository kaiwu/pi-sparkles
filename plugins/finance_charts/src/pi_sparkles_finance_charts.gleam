import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_finance_charts/decode
import pi_sparkles_finance_charts/domain
import pi_sparkles_finance_charts/effect/png

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "chart_ohlcv",
    "Render an exact OHLCV chart",
    "Validate bounded caller-supplied completed-daily OHLCV, already-calculated indicators, trade markers, gaps, units, adjustment, and source context; return a deterministic PNG plus exact structured and table fallbacks without analytics or interpretation",
    "Supply exact sourced inputs and explicit omissions; the PNG is only a view and structured decimal facts remain controlling",
    tool.parameters(chart_schema(), decode.chart_ohlcv()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True ->
          tool.reject("Finance-chart rendering was cancelled before work began")
        False ->
          case domain.run(input) {
            Ok(value) ->
              tool.result(
                [
                  tool.text(value.fallback),
                  tool.image(png.render(value.plan_json), "image/png"),
                ],
                value.details,
                False,
              )
              |> promise.resolve
            Error(error) -> tool.reject(domain.error_message(error))
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn chart_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", context_schema()),
    schema.Required(
      "series",
      schema.array(bar_schema()) |> schema.with_array_length(1, 240),
    ),
    schema.Required(
      "indicators",
      schema.array(indicator_schema()) |> schema.with_array_length(0, 4),
    ),
    schema.Required(
      "trades",
      schema.array(trade_schema()) |> schema.with_array_length(0, 240),
    ),
    schema.Required(
      "gaps",
      schema.array(gap_schema()) |> schema.with_array_length(0, 240),
    ),
    schema.Required(
      "inputOmissions",
      schema.array(bounded_string(1, 1000))
        |> schema.with_array_length(0, 240),
    ),
    schema.Required(
      "fallbackMaximumRows",
      schema.integer() |> schema.with_number_range(1.0, 50.0),
    ),
  ])
}

fn context_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionRef", hash_schema()),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("instrumentId", bounded_string(1, 200)),
    schema.Required(
      "mic",
      schema.string_enum(["XSHG", "XSHE", "XBSE", "XHKG", "XNYS", "XNAS"]),
    ),
    schema.Required("timezone", bounded_string(1, 100)),
    schema.Required("sourceLanguage", bounded_string(1, 35)),
    schema.Required("priceUnit", bounded_string(1, 100)),
    schema.Required("volumeUnit", bounded_string(1, 100)),
    schema.Required("adjustment", adjustment_schema()),
    schema.Required("source", source_schema()),
    schema.Required(
      "limitations",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn adjustment_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "raw",
        "split_adjusted",
        "dividend_adjusted",
        "total_return_adjusted",
        "provider_adjusted",
      ]),
    ),
    schema.Required("label", schema.nullable(bounded_string(1, 500))),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 200)),
    schema.Required("sourceReference", bounded_string(1, 4000)),
    schema.Required("acquisitionReceipt", hash_schema()),
    schema.Required("retrievedAtUnixMilliseconds", schema.integer()),
    schema.Required(
      "sourceCutoffUnixMilliseconds",
      schema.nullable(schema.integer()),
    ),
    schema.Required("entitlement", bounded_string(1, 200)),
  ])
}

fn bar_schema() -> schema.Schema {
  schema.object([
    schema.Required("date", date_schema()),
    schema.Required(
      "sessionType",
      schema.string_enum(["regular", "half_day", "unknown"]),
    ),
    schema.Required("open", decimal_schema()),
    schema.Required("high", decimal_schema()),
    schema.Required("low", decimal_schema()),
    schema.Required("close", decimal_schema()),
    schema.Required("volume", decimal_schema()),
  ])
}

fn indicator_schema() -> schema.Schema {
  schema.object([
    schema.Required("indicatorId", bounded_string(1, 100)),
    schema.Required("label", bounded_string(1, 80)),
    schema.Required(
      "panel",
      schema.string_enum(["price_overlay", "lower_panel"]),
    ),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required(
      "warmupSessions",
      schema.integer() |> schema.with_number_range(0.0, 239.0),
    ),
    schema.Required("calculationReceipt", hash_schema()),
    schema.Required(
      "points",
      schema.array(indicator_point_schema())
        |> schema.with_array_length(1, 240),
    ),
  ])
}

fn indicator_point_schema() -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("state", schema.literal_string("calculated")),
      schema.Required("date", date_schema()),
      schema.Required("value", decimal_schema()),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("unperformed")),
      schema.Required("date", date_schema()),
      schema.Required("reason", bounded_string(1, 1000)),
    ]),
  ])
}

fn trade_schema() -> schema.Schema {
  schema.object([
    schema.Required("tradeId", bounded_string(1, 100)),
    schema.Required("date", date_schema()),
    schema.Required("side", schema.string_enum(["buy", "sell"])),
    schema.Required("price", decimal_schema()),
    schema.Required("quantity", decimal_schema()),
    schema.Required(
      "status",
      schema.string_enum(["proposed", "simulated", "observed"]),
    ),
    schema.Required("evidenceReceipt", hash_schema()),
  ])
}

fn gap_schema() -> schema.Schema {
  schema.object([
    schema.Required("date", date_schema()),
    schema.Required(
      "state",
      schema.string_enum([
        "market_closure",
        "suspension",
        "provider_omission",
        "unavailable_history",
        "unknown",
      ]),
    ),
    schema.Required("reason", bounded_string(1, 1000)),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 20),
    ),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(10, 10)
}

fn decimal_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(1, 200)
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
