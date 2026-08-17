import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None, Some}

pub type SourceInput {
  SourceInput(
    provider: String,
    source_reference: String,
    acquisition_receipt: String,
    retrieved_at_unix_milliseconds: Int,
    source_cutoff_unix_milliseconds: Option(Int),
    entitlement: String,
  )
}

pub type AdjustmentInput {
  AdjustmentInput(kind: String, label: Option(String))
}

pub type ContextInput {
  ContextInput(
    instruction_ref: String,
    track: String,
    instrument_id: String,
    mic: String,
    timezone: String,
    source_language: String,
    price_unit: String,
    volume_unit: String,
    adjustment: AdjustmentInput,
    source: SourceInput,
    limitations: List(String),
  )
}

pub type BarInput {
  BarInput(
    date: String,
    session_type: String,
    open: String,
    high: String,
    low: String,
    close: String,
    volume: String,
  )
}

pub type IndicatorPointInput {
  Calculated(date: String, value: String)
  Unperformed(date: String, reason: String)
}

pub type IndicatorInput {
  IndicatorInput(
    indicator_id: String,
    label: String,
    panel: String,
    unit: String,
    warmup_sessions: Int,
    calculation_receipt: String,
    points: List(IndicatorPointInput),
  )
}

pub type TradeInput {
  TradeInput(
    trade_id: String,
    date: String,
    side: String,
    price: String,
    quantity: String,
    status: String,
    evidence_receipt: String,
  )
}

pub type GapInput {
  GapInput(
    date: String,
    state: String,
    reason: String,
    evidence_roots: List(String),
  )
}

pub type Input {
  Input(
    context: ContextInput,
    series: List(BarInput),
    indicators: List(IndicatorInput),
    trades: List(TradeInput),
    gaps: List(GapInput),
    input_omissions: List(String),
    fallback_maximum_rows: Int,
  )
}

pub type Request {
  Direct(Input)
  SessionReceipt(
    series_receipt: String,
    maximum_bars: Int,
    indicator_receipts: List(String),
    trades: List(TradeInput),
    gaps: List(GapInput),
    input_omissions: List(String),
    fallback_maximum_rows: Int,
  )
}

pub fn chart_ohlcv() -> decoder.Decoder(Request) {
  use series_receipt <- optional_string("seriesReceipt")
  use maximum_bars <- optional_int("maximumBars")
  use indicator_receipts <- decoder.optional_field(
    "indicatorReceipts",
    [],
    decoder.list(of: decoder.string),
  )
  use context <- decoder.optional_field(
    "context",
    None,
    decoder.optional(context_decoder()),
  )
  use series <- decoder.optional_field(
    "series",
    None,
    decoder.optional(decoder.list(of: bar_decoder())),
  )
  use indicators <- decoder.optional_field(
    "indicators",
    None,
    decoder.optional(decoder.list(of: indicator_decoder())),
  )
  use trades <- decoder.field("trades", decoder.list(of: trade_decoder()))
  use gaps <- decoder.field("gaps", decoder.list(of: gap_decoder()))
  use input_omissions <- decoder.field(
    "inputOmissions",
    decoder.list(of: decoder.string),
  )
  use fallback_maximum_rows <- decoder.field("fallbackMaximumRows", decoder.int)
  case
    series_receipt,
    maximum_bars,
    indicator_receipts,
    context,
    series,
    indicators
  {
    Some(receipt), Some(maximum), receipts, None, None, None ->
      decoder.success(SessionReceipt(
        receipt,
        maximum,
        receipts,
        trades,
        gaps,
        input_omissions,
        fallback_maximum_rows,
      ))
    None, None, [], Some(context), Some(series), Some(indicators) ->
      decoder.success(
        Direct(Input(
          context,
          series,
          indicators,
          trades,
          gaps,
          input_omissions,
          fallback_maximum_rows,
        )),
      )
    _, _, _, _, _, _ ->
      decoder.failure(
        SessionReceipt(
          "",
          1,
          [],
          trades,
          gaps,
          input_omissions,
          fallback_maximum_rows,
        ),
        "exactly one of seriesReceipt plus maximumBars or context plus series plus indicators",
      )
  }
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}

fn context_decoder() -> decoder.Decoder(ContextInput) {
  use instruction_ref <- decoder.field("instructionRef", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use instrument_id <- decoder.field("instrumentId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use timezone <- decoder.field("timezone", decoder.string)
  use source_language <- decoder.field("sourceLanguage", decoder.string)
  use price_unit <- decoder.field("priceUnit", decoder.string)
  use volume_unit <- decoder.field("volumeUnit", decoder.string)
  use adjustment <- decoder.field("adjustment", adjustment_decoder())
  use source <- decoder.field("source", source_decoder())
  use limitations <- decoder.field(
    "limitations",
    decoder.list(of: decoder.string),
  )
  decoder.success(ContextInput(
    instruction_ref,
    track,
    instrument_id,
    mic,
    timezone,
    source_language,
    price_unit,
    volume_unit,
    adjustment,
    source,
    limitations,
  ))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use provider <- decoder.field("provider", decoder.string)
  use source_reference <- decoder.field("sourceReference", decoder.string)
  use acquisition_receipt <- decoder.field("acquisitionReceipt", decoder.string)
  use retrieved_at <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use source_cutoff <- decoder.field(
    "sourceCutoffUnixMilliseconds",
    decoder.optional(decoder.int),
  )
  use entitlement <- decoder.field("entitlement", decoder.string)
  decoder.success(SourceInput(
    provider,
    source_reference,
    acquisition_receipt,
    retrieved_at,
    source_cutoff,
    entitlement,
  ))
}

fn adjustment_decoder() -> decoder.Decoder(AdjustmentInput) {
  use kind <- decoder.field("kind", decoder.string)
  use label <- decoder.field("label", decoder.optional(decoder.string))
  decoder.success(AdjustmentInput(kind, label))
}

fn bar_decoder() -> decoder.Decoder(BarInput) {
  use date <- decoder.field("date", decoder.string)
  use session_type <- decoder.field("sessionType", decoder.string)
  use open <- decoder.field("open", decoder.string)
  use high <- decoder.field("high", decoder.string)
  use low <- decoder.field("low", decoder.string)
  use close <- decoder.field("close", decoder.string)
  use volume <- decoder.field("volume", decoder.string)
  decoder.success(BarInput(date, session_type, open, high, low, close, volume))
}

fn indicator_decoder() -> decoder.Decoder(IndicatorInput) {
  use indicator_id <- decoder.field("indicatorId", decoder.string)
  use label <- decoder.field("label", decoder.string)
  use panel <- decoder.field("panel", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use warmup_sessions <- decoder.field("warmupSessions", decoder.int)
  use calculation_receipt <- decoder.field("calculationReceipt", decoder.string)
  use points <- decoder.field(
    "points",
    decoder.list(of: indicator_point_decoder()),
  )
  decoder.success(IndicatorInput(
    indicator_id,
    label,
    panel,
    unit,
    warmup_sessions,
    calculation_receipt,
    points,
  ))
}

fn indicator_point_decoder() -> decoder.Decoder(IndicatorPointInput) {
  use state <- decoder.field("state", decoder.string)
  case state {
    "calculated" -> {
      use date <- decoder.field("date", decoder.string)
      use value <- decoder.field("value", decoder.string)
      decoder.success(Calculated(date, value))
    }
    "unperformed" -> {
      use date <- decoder.field("date", decoder.string)
      use reason <- decoder.field("reason", decoder.string)
      decoder.success(Unperformed(date, reason))
    }
    _ -> decoder.failure(Unperformed("", ""), "calculated or unperformed")
  }
}

fn trade_decoder() -> decoder.Decoder(TradeInput) {
  use trade_id <- decoder.field("tradeId", decoder.string)
  use date <- decoder.field("date", decoder.string)
  use side <- decoder.field("side", decoder.string)
  use price <- decoder.field("price", decoder.string)
  use quantity <- decoder.field("quantity", decoder.string)
  use status <- decoder.field("status", decoder.string)
  use evidence_receipt <- decoder.field("evidenceReceipt", decoder.string)
  decoder.success(TradeInput(
    trade_id,
    date,
    side,
    price,
    quantity,
    status,
    evidence_receipt,
  ))
}

fn gap_decoder() -> decoder.Decoder(GapInput) {
  use date <- decoder.field("date", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use reason <- decoder.field("reason", decoder.string)
  use evidence_roots <- decoder.field(
    "evidenceRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(GapInput(date, state, reason, evidence_roots))
}
