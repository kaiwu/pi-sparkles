import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

/// Indicator results are persisted on the active host session so a chart tool
/// can consume a short receipt instead of asking the model to copy every point
/// into another tool call.
pub const event_type = "pi_sparkles_finance_indicators.chart_handoff.v1"

pub type Point {
  Calculated(date: String, value: String)
  Unperformed(date: String, reason: String)
}

pub opaque type Handoff {
  Handoff(
    handoff_receipt: String,
    series_receipt: String,
    calculation_receipt: String,
    indicator_id: String,
    label: String,
    panel: String,
    unit: String,
    warmup_sessions: Int,
    points: List(Point),
  )
}

pub type Error {
  InvalidField(field: String)
  ReceiptMismatch
  ReceiptFailed
}

pub fn new(
  series_receipt series_receipt_value: String,
  calculation_receipt calculation_receipt_value: String,
  indicator_id indicator_id_value: String,
  label label_value: String,
  panel panel_value: String,
  unit unit_value: String,
  warmup_sessions warmup_value: Int,
  points point_values: List(Point),
) -> Result(Handoff, Error) {
  let value =
    Handoff(
      handoff_receipt: "",
      series_receipt: series_receipt_value,
      calculation_receipt: calculation_receipt_value,
      indicator_id: indicator_id_value,
      label: label_value,
      panel: panel_value,
      unit: unit_value,
      warmup_sessions: warmup_value,
      points: point_values,
    )
  use _ <- result.try(validate(value, check_receipt: False))
  use digest <- result.try(
    hash.text(canonical_text(value))
    |> result.map_error(fn(_) { ReceiptFailed }),
  )
  Ok(Handoff(..value, handoff_receipt: identity.sha256_value(digest)))
}

pub fn verify(value: Handoff) -> Result(Handoff, Error) {
  use _ <- result.try(validate(value, check_receipt: True))
  Ok(value)
}

pub fn encode(value: Handoff) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/indicator-chart-handoff")),
    #("schemaVersion", json.int(1)),
    #("handoffReceipt", json.string(value.handoff_receipt)),
    #("seriesReceipt", json.string(value.series_receipt)),
    #("calculationReceipt", json.string(value.calculation_receipt)),
    #("indicatorId", json.string(value.indicator_id)),
    #("label", json.string(value.label)),
    #("panel", json.string(value.panel)),
    #("unit", json.string(value.unit)),
    #("warmupSessions", json.int(value.warmup_sessions)),
    #("points", json.array(value.points, encode_point)),
  ])
}

pub fn decoder() -> decode.Decoder(Handoff) {
  use schema <- decode.field("schema", decode.string)
  use schema_version <- decode.field("schemaVersion", decode.int)
  use handoff_receipt <- decode.field("handoffReceipt", decode.string)
  use series_receipt <- decode.field("seriesReceipt", decode.string)
  use calculation_receipt <- decode.field("calculationReceipt", decode.string)
  use indicator_id <- decode.field("indicatorId", decode.string)
  use label <- decode.field("label", decode.string)
  use panel <- decode.field("panel", decode.string)
  use unit <- decode.field("unit", decode.string)
  use warmup_sessions <- decode.field("warmupSessions", decode.int)
  use points <- decode.field("points", decode.list(of: point_decoder()))
  let value =
    Handoff(
      handoff_receipt:,
      series_receipt:,
      calculation_receipt:,
      indicator_id:,
      label:,
      panel:,
      unit:,
      warmup_sessions:,
      points:,
    )
  case schema == "pi-sparkles/indicator-chart-handoff" && schema_version == 1 {
    True -> decode.success(value)
    False -> decode.failure(value, "supported indicator chart handoff schema")
  }
}

pub fn canonical_text(value: Handoff) -> String {
  payload_json(value) |> json.to_string
}

pub fn handoff_receipt(value: Handoff) -> String {
  value.handoff_receipt
}

pub fn series_receipt(value: Handoff) -> String {
  value.series_receipt
}

pub fn calculation_receipt(value: Handoff) -> String {
  value.calculation_receipt
}

pub fn indicator_id(value: Handoff) -> String {
  value.indicator_id
}

pub fn label(value: Handoff) -> String {
  value.label
}

pub fn panel(value: Handoff) -> String {
  value.panel
}

pub fn unit(value: Handoff) -> String {
  value.unit
}

pub fn warmup_sessions(value: Handoff) -> Int {
  value.warmup_sessions
}

pub fn points(value: Handoff) -> List(Point) {
  value.points
}

fn payload_json(value: Handoff) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/indicator-chart-handoff-payload")),
    #("schemaVersion", json.int(1)),
    #("seriesReceipt", json.string(value.series_receipt)),
    #("calculationReceipt", json.string(value.calculation_receipt)),
    #("indicatorId", json.string(value.indicator_id)),
    #("label", json.string(value.label)),
    #("panel", json.string(value.panel)),
    #("unit", json.string(value.unit)),
    #("warmupSessions", json.int(value.warmup_sessions)),
    #("points", json.array(value.points, encode_point)),
  ])
}

fn encode_point(value: Point) -> json.Json {
  case value {
    Calculated(date, value) ->
      json.object([
        #("state", json.string("calculated")),
        #("date", json.string(date)),
        #("value", json.string(value)),
      ])
    Unperformed(date, reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("date", json.string(date)),
        #("reason", json.string(reason)),
      ])
  }
}

fn point_decoder() -> decode.Decoder(Point) {
  use state <- decode.field("state", decode.string)
  use date <- decode.field("date", decode.string)
  case state {
    "calculated" -> {
      use value <- decode.field("value", decode.string)
      decode.success(Calculated(date, value))
    }
    "unperformed" -> {
      use reason <- decode.field("reason", decode.string)
      decode.success(Unperformed(date, reason))
    }
    _ -> decode.failure(Calculated(date, "0"), "supported point state")
  }
}

fn validate(
  value: Handoff,
  check_receipt check_receipt: Bool,
) -> Result(Nil, Error) {
  use _ <- result.try(require_hash("seriesReceipt", value.series_receipt))
  use _ <- result.try(require_hash(
    "calculationReceipt",
    value.calculation_receipt,
  ))
  use _ <- result.try(require_text("indicatorId", value.indicator_id))
  use _ <- result.try(require_text("label", value.label))
  use _ <- result.try(
    case value.panel == "price_overlay" || value.panel == "lower_panel" {
      True -> Ok(Nil)
      False -> Error(InvalidField("panel"))
    },
  )
  use _ <- result.try(require_text("unit", value.unit))
  use _ <- result.try(
    case
      value.warmup_sessions >= 0
      && value.warmup_sessions <= 1999
      && list.length(value.points) >= 1
      && list.length(value.points) <= 2000
    {
      True -> Ok(Nil)
      False -> Error(InvalidField("warmupSessions/points"))
    },
  )
  use _ <- result.try(validate_points(value.points))
  case check_receipt {
    False -> Ok(Nil)
    True -> {
      use _ <- result.try(require_hash("handoffReceipt", value.handoff_receipt))
      use digest <- result.try(
        hash.text(canonical_text(value))
        |> result.map_error(fn(_) { ReceiptFailed }),
      )
      case identity.sha256_value(digest) == value.handoff_receipt {
        True -> Ok(Nil)
        False -> Error(ReceiptMismatch)
      }
    }
  }
}

fn validate_points(values: List(Point)) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(case value {
        Calculated(date, point_value) -> {
          use _ <- result.try(require_date(date))
          require_text("points.value", point_value)
        }
        Unperformed(date, reason) -> {
          use _ <- result.try(require_date(date))
          require_text("points.reason", reason)
        }
      })
      validate_points(rest)
    }
  }
}

fn require_date(value: String) -> Result(Nil, Error) {
  case string.length(value) == 10 {
    True -> Ok(Nil)
    False -> Error(InvalidField("points.date"))
  }
}

fn require_hash(field: String, value: String) -> Result(Nil, Error) {
  case string.length(value) == 64 && all_hex(string.to_graphemes(value)) {
    True -> Ok(Nil)
    False -> Error(InvalidField(field))
  }
}

fn all_hex(values: List(String)) -> Bool {
  list.all(values, fn(value) { string.contains("0123456789abcdef", value) })
}

fn require_text(field: String, value: String) -> Result(Nil, Error) {
  case
    string.trim(value) == ""
    || string.contains(value, "\n")
    || string.contains(value, "\r")
  {
    True -> Error(InvalidField(field))
    False -> Ok(Nil)
  }
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidField(field) -> "invalid indicator chart handoff field " <> field
    ReceiptMismatch ->
      "stored indicator points did not match the handoff receipt"
    ReceiptFailed -> "indicator chart handoff receipt could not be calculated"
  }
}
