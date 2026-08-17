import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Pi and DSH persist this entry on the exact active session. Calculation and
/// presentation shells can resolve it without asking the model to copy a
/// bounded OHLCV response back into another tool call.
pub const event_type = "pi_sparkles_finance_ohlcv.series_handoff.v1"

pub type Bar {
  Bar(
    date: String,
    open: String,
    high: String,
    low: String,
    close: String,
    volume: String,
    amount: String,
  )
}

pub opaque type Handoff {
  Handoff(
    track: String,
    instrument_id: String,
    mic: String,
    timezone: String,
    source_language: String,
    price_unit: String,
    volume_unit: String,
    adjustment: String,
    provider: String,
    source_reference: String,
    acquisition_receipt: String,
    retrieved_at_unix_milliseconds: Int,
    source_cutoff_unix_milliseconds: Option(Int),
    entitlement: String,
    limitations: List(String),
    bars: List(Bar),
  )
}

pub type Error {
  InvalidField(field: String)
  ReceiptMismatch
  ReceiptFailed
}

pub fn new(
  track track_value: String,
  instrument_id instrument_id_value: String,
  mic mic_value: String,
  timezone timezone_value: String,
  source_language source_language_value: String,
  price_unit price_unit_value: String,
  volume_unit volume_unit_value: String,
  adjustment adjustment_value: String,
  provider provider_value: String,
  source_reference source_reference_value: String,
  retrieved_at_unix_milliseconds retrieved_at_value: Int,
  source_cutoff_unix_milliseconds source_cutoff_value: Option(Int),
  entitlement entitlement_value: String,
  limitations limitation_values: List(String),
  bars bar_values: List(Bar),
) -> Result(Handoff, Error) {
  let value =
    Handoff(
      track: track_value,
      instrument_id: instrument_id_value,
      mic: mic_value,
      timezone: timezone_value,
      source_language: source_language_value,
      price_unit: price_unit_value,
      volume_unit: volume_unit_value,
      adjustment: adjustment_value,
      provider: provider_value,
      source_reference: source_reference_value,
      acquisition_receipt: "",
      retrieved_at_unix_milliseconds: retrieved_at_value,
      source_cutoff_unix_milliseconds: source_cutoff_value,
      entitlement: entitlement_value,
      limitations: limitation_values,
      bars: bar_values,
    )
  use _ <- result.try(validate(value, check_receipt: False))
  use digest <- result.try(
    hash.text(canonical_text(value))
    |> result.map_error(fn(_) { ReceiptFailed }),
  )
  Ok(Handoff(..value, acquisition_receipt: identity.sha256_value(digest)))
}

pub fn verify(value: Handoff) -> Result(Handoff, Error) {
  use _ <- result.try(validate(value, check_receipt: True))
  Ok(value)
}

pub fn encode(value: Handoff) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/ohlcv-series-handoff")),
    #("schemaVersion", json.int(1)),
    #("track", json.string(value.track)),
    #("instrumentId", json.string(value.instrument_id)),
    #("mic", json.string(value.mic)),
    #("timezone", json.string(value.timezone)),
    #("sourceLanguage", json.string(value.source_language)),
    #("priceUnit", json.string(value.price_unit)),
    #("volumeUnit", json.string(value.volume_unit)),
    #("adjustment", json.string(value.adjustment)),
    #("provider", json.string(value.provider)),
    #("sourceReference", json.string(value.source_reference)),
    #("acquisitionReceipt", json.string(value.acquisition_receipt)),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(value.retrieved_at_unix_milliseconds),
    ),
    #(
      "sourceCutoffUnixMilliseconds",
      case value.source_cutoff_unix_milliseconds {
        Some(cutoff) -> json.int(cutoff)
        None -> json.null()
      },
    ),
    #("entitlement", json.string(value.entitlement)),
    #("limitations", json.array(value.limitations, json.string)),
    #("bars", json.array(value.bars, encode_bar)),
  ])
}

pub fn decoder() -> decode.Decoder(Handoff) {
  use schema <- decode.field("schema", decode.string)
  use schema_version <- decode.field("schemaVersion", decode.int)
  use track <- decode.field("track", decode.string)
  use instrument_id <- decode.field("instrumentId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  use source_language <- decode.field("sourceLanguage", decode.string)
  use price_unit <- decode.field("priceUnit", decode.string)
  use volume_unit <- decode.field("volumeUnit", decode.string)
  use adjustment <- decode.field("adjustment", decode.string)
  use provider <- decode.field("provider", decode.string)
  use source_reference <- decode.field("sourceReference", decode.string)
  use acquisition_receipt <- decode.field("acquisitionReceipt", decode.string)
  use retrieved_at <- decode.field("retrievedAtUnixMilliseconds", decode.int)
  use source_cutoff <- decode.field(
    "sourceCutoffUnixMilliseconds",
    decode.optional(decode.int),
  )
  use entitlement <- decode.field("entitlement", decode.string)
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  use bars <- decode.field("bars", decode.list(of: bar_decoder()))
  let value =
    Handoff(
      track:,
      instrument_id:,
      mic:,
      timezone:,
      source_language:,
      price_unit:,
      volume_unit:,
      adjustment:,
      provider:,
      source_reference:,
      acquisition_receipt:,
      retrieved_at_unix_milliseconds: retrieved_at,
      source_cutoff_unix_milliseconds: source_cutoff,
      entitlement:,
      limitations:,
      bars:,
    )
  case schema == "pi-sparkles/ohlcv-series-handoff" && schema_version == 1 {
    True -> decode.success(value)
    False -> decode.failure(value, "supported OHLCV series handoff schema")
  }
}

pub fn canonical_text(value: Handoff) -> String {
  value.source_reference
  <> "\nretrievedAtUnixMilliseconds="
  <> int.to_string(value.retrieved_at_unix_milliseconds)
  <> "\ndate,open,high,low,close,volume,amount\n"
  <> csv_rows(value)
}

pub fn csv_rows(value: Handoff) -> String {
  value.bars
  |> list.map(fn(bar) {
    [
      bar.date,
      bar.open,
      bar.high,
      bar.low,
      bar.close,
      bar.volume,
      bar.amount,
    ]
    |> string.join(",")
  })
  |> string.join("\n")
}

pub fn receipt(value: Handoff) -> String {
  value.acquisition_receipt
}

pub fn track(value: Handoff) -> String {
  value.track
}

pub fn instrument_id(value: Handoff) -> String {
  value.instrument_id
}

pub fn mic(value: Handoff) -> String {
  value.mic
}

pub fn timezone(value: Handoff) -> String {
  value.timezone
}

pub fn source_language(value: Handoff) -> String {
  value.source_language
}

pub fn price_unit(value: Handoff) -> String {
  value.price_unit
}

pub fn volume_unit(value: Handoff) -> String {
  value.volume_unit
}

pub fn adjustment(value: Handoff) -> String {
  value.adjustment
}

pub fn provider(value: Handoff) -> String {
  value.provider
}

pub fn source_reference(value: Handoff) -> String {
  value.source_reference
}

pub fn retrieved_at_unix_milliseconds(value: Handoff) -> Int {
  value.retrieved_at_unix_milliseconds
}

pub fn source_cutoff_unix_milliseconds(value: Handoff) -> Option(Int) {
  value.source_cutoff_unix_milliseconds
}

pub fn entitlement(value: Handoff) -> String {
  value.entitlement
}

pub fn limitations(value: Handoff) -> List(String) {
  value.limitations
}

pub fn bars(value: Handoff) -> List(Bar) {
  value.bars
}

fn encode_bar(value: Bar) -> json.Json {
  json.object([
    #("date", json.string(value.date)),
    #("open", json.string(value.open)),
    #("high", json.string(value.high)),
    #("low", json.string(value.low)),
    #("close", json.string(value.close)),
    #("volume", json.string(value.volume)),
    #("amount", json.string(value.amount)),
  ])
}

fn bar_decoder() -> decode.Decoder(Bar) {
  use date <- decode.field("date", decode.string)
  use open <- decode.field("open", decode.string)
  use high <- decode.field("high", decode.string)
  use low <- decode.field("low", decode.string)
  use close <- decode.field("close", decode.string)
  use volume <- decode.field("volume", decode.string)
  use amount <- decode.field("amount", decode.string)
  decode.success(Bar(date:, open:, high:, low:, close:, volume:, amount:))
}

fn validate(
  value: Handoff,
  check_receipt check_receipt: Bool,
) -> Result(Nil, Error) {
  use _ <- result.try(case value.track, value.mic, value.timezone {
    "cn", "XSHG", "Asia/Shanghai"
    | "cn", "XSHE", "Asia/Shanghai"
    | "cn", "XBSE", "Asia/Shanghai"
    | "hk", "XHKG", "Asia/Hong_Kong"
    | "us", "XNYS", "America/New_York"
    | "us", "XNAS", "America/New_York"
    -> Ok(Nil)
    _, _, _ -> Error(InvalidField("track/mic/timezone"))
  })
  use _ <- result.try(require_text("instrumentId", value.instrument_id))
  use _ <- result.try(require_text("sourceLanguage", value.source_language))
  use _ <- result.try(require_text("priceUnit", value.price_unit))
  use _ <- result.try(require_text("volumeUnit", value.volume_unit))
  use _ <- result.try(require_text("adjustment", value.adjustment))
  use _ <- result.try(require_text("provider", value.provider))
  use _ <- result.try(require_text("sourceReference", value.source_reference))
  use _ <- result.try(require_text("entitlement", value.entitlement))
  use _ <- result.try(
    case list.length(value.bars) >= 1 && list.length(value.bars) <= 1000 {
      True -> Ok(Nil)
      False -> Error(InvalidField("bars"))
    },
  )
  use _ <- result.try(validate_bars(value.bars))
  case check_receipt {
    False -> Ok(Nil)
    True -> {
      use digest <- result.try(
        hash.text(canonical_text(value))
        |> result.map_error(fn(_) { ReceiptFailed }),
      )
      case identity.sha256_value(digest) == value.acquisition_receipt {
        True -> Ok(Nil)
        False -> Error(ReceiptMismatch)
      }
    }
  }
}

fn validate_bars(values: List(Bar)) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [bar, ..rest] -> {
      use _ <- result.try(case string.length(bar.date) == 10 {
        True -> Ok(Nil)
        False -> Error(InvalidField("bars.date"))
      })
      use _ <- result.try(
        validate_lexemes([
          bar.date,
          bar.open,
          bar.high,
          bar.low,
          bar.close,
          bar.volume,
          bar.amount,
        ]),
      )
      validate_bars(rest)
    }
  }
}

fn validate_lexemes(values: List(String)) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        value != ""
        && !string.contains(value, ",")
        && !string.contains(value, "\n")
        && !string.contains(value, "\r")
      {
        True -> validate_lexemes(rest)
        False -> Error(InvalidField("bars.lexeme"))
      }
  }
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
    InvalidField(field) -> "invalid exact handoff field " <> field
    ReceiptMismatch -> "stored OHLCV rows did not match the requested receipt"
    ReceiptFailed -> "OHLCV handoff receipt could not be calculated"
  }
}
