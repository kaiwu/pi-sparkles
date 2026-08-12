import finance_core/decimal
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

pub type Packet {
  Packet(
    source: common.Source,
    effective_date: String,
    publication_at_unix_ms: Int,
    target_calendar_receipt: String,
    pivot_currency: String,
    base_currency: String,
    quote_currency: String,
    amount: common.Fact,
    base_per_pivot: common.Fact,
    quote_per_pivot: common.Fact,
  )
}

pub fn calculate(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "fx_ecb_v1",
    "calculate",
    decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(validate(packet))
  let amount = common.fact_decimal("amount", packet.amount)
  let base = common.fact_decimal("basePerPivot", packet.base_per_pivot)
  let quote = common.fact_decimal("quotePerPivot", packet.quote_per_pivot)
  let cross_rate = case base, quote {
    Ok(base), Ok(quote) -> common.ratio(quote, base, 12)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let inverse_rate = case cross_rate {
    Ok(rate) -> {
      let assert Ok(one) = decimal.parse("1")
      common.ratio(one, rate, 12)
    }
    Error(error) -> Error(error)
  }
  let converted = case amount, cross_rate {
    Ok(amount), Ok(rate) -> Ok(decimal.multiply(amount, rate))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  Ok(
    common.response(
      "fx_ecb_v1",
      "calculate",
      decoded.1,
      "Same-date ECB euro-reference cross conversion with exact source, publication, TARGET-calendar and receipt context; reference rates are not executable quotes",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("effectiveDate", json.string(packet.effective_date)),
        #(
          "publicationAtUnixMilliseconds",
          json.int(packet.publication_at_unix_ms),
        ),
        #("targetCalendarReceipt", json.string(packet.target_calendar_receipt)),
        #("pivotCurrency", json.string(packet.pivot_currency)),
        #("baseCurrency", json.string(packet.base_currency)),
        #("quoteCurrency", json.string(packet.quote_currency)),
        #("amount", common.fact_json(packet.amount)),
        #("basePerPivot", common.fact_json(packet.base_per_pivot)),
        #("quotePerPivot", common.fact_json(packet.quote_per_pivot)),
        #(
          "crossRate",
          common.calculation_json(
            "quote_per_EUR / base_per_EUR",
            cross_rate,
            packet.quote_currency <> "_per_" <> packet.base_currency,
            [
              #("basePerPivot", common.fact_json(packet.base_per_pivot)),
              #("quotePerPivot", common.fact_json(packet.quote_per_pivot)),
            ],
          ),
        ),
        #(
          "inverseRate",
          common.calculation_json(
            "1 / cross_rate",
            inverse_rate,
            packet.base_currency <> "_per_" <> packet.quote_currency,
            [],
          ),
        ),
        #(
          "convertedAmount",
          common.calculation_json(
            "amount * cross_rate",
            converted,
            packet.quote_currency,
            [#("amount", common.fact_json(packet.amount))],
          ),
        ),
        #("rateKind", json.string("ecb_reference_not_executable_quote")),
        #("staleCarry", json.bool(False)),
      ],
    ),
  )
}

fn decoder() -> decode.Decoder(Packet) {
  use source <- decode.field("source", common.source_decoder())
  use effective <- decode.field("effectiveDate", decode.string)
  use published <- decode.field("publicationAtUnixMilliseconds", decode.int)
  use calendar <- decode.field("targetCalendarReceipt", decode.string)
  use pivot <- decode.field("pivotCurrency", decode.string)
  use base_currency <- decode.field("baseCurrency", decode.string)
  use quote_currency <- decode.field("quoteCurrency", decode.string)
  use amount <- decode.field("amount", common.fact_decoder())
  use base <- decode.field("basePerPivot", common.fact_decoder())
  use quote <- decode.field("quotePerPivot", common.fact_decoder())
  decode.success(Packet(
    source,
    effective,
    published,
    calendar,
    pivot,
    base_currency,
    quote_currency,
    amount,
    base,
    quote,
  ))
}

fn validate(packet: Packet) -> Result(Nil, common.Error) {
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(common.date("effectiveDate", packet.effective_date))
  use _ <- result.try(common.non_negative(
    "publicationAtUnixMilliseconds",
    packet.publication_at_unix_ms,
  ))
  use _ <- result.try(common.receipt(
    "targetCalendarReceipt",
    packet.target_calendar_receipt,
  ))
  use _ <- result.try(case packet.pivot_currency == "EUR" {
    True -> Ok(Nil)
    False -> Error(common.InvalidField("pivotCurrency", "must be EUR"))
  })
  use _ <- result.try(validate_currency("baseCurrency", packet.base_currency))
  use _ <- result.try(validate_currency("quoteCurrency", packet.quote_currency))
  use _ <- result.try(case packet.base_currency != packet.quote_currency {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "quoteCurrency",
        "must differ from baseCurrency",
      ))
  })
  use _ <- result.try(common.validate_fact("amount", packet.amount))
  use _ <- result.try(common.validate_fact(
    "basePerPivot",
    packet.base_per_pivot,
  ))
  use _ <- result.try(common.validate_fact(
    "quotePerPivot",
    packet.quote_per_pivot,
  ))
  use _ <- result.try(
    case
      packet.base_per_pivot.unit == packet.base_currency <> "_per_EUR",
      packet.quote_per_pivot.unit == packet.quote_currency <> "_per_EUR",
      packet.amount.unit == packet.base_currency,
      packet.base_per_pivot.observed_at_unix_ms
      == packet.quote_per_pivot.observed_at_unix_ms
    {
      True, True, True, True -> Ok(Nil)
      False, _, _, _ ->
        Error(common.InvalidField(
          "basePerPivot.unit",
          "must match base currency per EUR",
        ))
      _, False, _, _ ->
        Error(common.InvalidField(
          "quotePerPivot.unit",
          "must match quote currency per EUR",
        ))
      _, _, False, _ ->
        Error(common.InvalidField("amount.unit", "must match base currency"))
      _, _, _, False ->
        Error(common.InvalidField(
          "basePerPivot.observedAtUnixMilliseconds",
          "both ECB legs must share one publication observation",
        ))
    },
  )
  common.validate_receipts(
    "rateReceipts",
    list.append(packet.base_per_pivot.receipts, packet.quote_per_pivot.receipts),
  )
}

fn validate_currency(
  field: String,
  value: String,
) -> Result(Nil, common.Error) {
  case list.contains(["EUR", "USD", "CNY", "HKD", "GBP", "JPY", "CHF"], value) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        field,
        "must be an explicitly supported ECB reference currency",
      ))
  }
}
