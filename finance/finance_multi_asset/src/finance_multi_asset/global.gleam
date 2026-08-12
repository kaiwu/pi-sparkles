import finance_core/decimal.{type Decimal}
import finance_math/error
import finance_math/statistics
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type Point {
  Point(
    local_date: String,
    session_state: String,
    value: common.Fact,
    observation_receipt: String,
  )
}

pub type Leg {
  Leg(
    leg_id: String,
    track: String,
    instrument_kind: String,
    instrument_id: String,
    display_name: String,
    mic: String,
    currency: String,
    timezone: String,
    calendar_receipt: String,
    source_receipt: String,
    points: List(Point),
  )
}

pub type Packet {
  Packet(
    alignment_policy: String,
    return_method: String,
    legs: List(Leg),
    handoff_receipts: List(String),
  )
}

pub fn compare(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "global_markets_v1",
    "compare",
    decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(validate(packet))
  let matched_dates = intersection_dates(packet.legs)
  let legs_with_points =
    packet.legs
    |> list.map(fn(leg) {
      let matched = matched_points(leg.points, matched_dates)
      #(leg, matched)
    })
  Ok(
    common.response(
      "global_markets_v1",
      "compare",
      decoded.1,
      "Explicit CN/HK/US comparison legs with exact instrument kind, native currencies, source/calendar receipts and open-session date intersection; no synthetic global track, index/ETF equivalence, silent FX or stale carry",
      [
        #("track", json.null()),
        #("alignmentPolicy", json.string(packet.alignment_policy)),
        #("returnMethod", json.string(packet.return_method)),
        #("currencyPolicy", json.string("native_no_fx_conversion")),
        #("matchedDates", json.array(matched_dates, json.string)),
        #(
          "legs",
          json.array(legs_with_points, fn(item) { leg_json(item.0, item.1) }),
        ),
        #("correlations", correlations_json(legs_with_points)),
        #("handoffReceipts", json.array(packet.handoff_receipts, json.string)),
        #(
          "interpretation",
          json.string("not_provided_decision_owner_is_llm_or_user"),
        ),
      ],
    ),
  )
}

fn decoder() -> decode.Decoder(Packet) {
  use alignment <- decode.field("alignmentPolicy", decode.string)
  use method <- decode.field("returnMethod", decode.string)
  use legs <- decode.field("legs", decode.list(of: leg_decoder()))
  use receipts <- decode.field(
    "handoffReceipts",
    decode.list(of: decode.string),
  )
  decode.success(Packet(alignment, method, legs, receipts))
}

fn leg_decoder() -> decode.Decoder(Leg) {
  use id <- decode.field("legId", decode.string)
  use track <- decode.field("track", decode.string)
  use kind <- decode.field("instrumentKind", decode.string)
  use instrument <- decode.field("instrumentId", decode.string)
  use name <- decode.field("displayName", decode.string)
  use mic <- decode.field("mic", decode.string)
  use currency <- decode.field("currency", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  use calendar <- decode.field("calendarReceipt", decode.string)
  use source <- decode.field("sourceReceipt", decode.string)
  use points <- decode.field("points", decode.list(of: point_decoder()))
  decode.success(Leg(
    id,
    track,
    kind,
    instrument,
    name,
    mic,
    currency,
    timezone,
    calendar,
    source,
    points,
  ))
}

fn point_decoder() -> decode.Decoder(Point) {
  use date <- decode.field("localDate", decode.string)
  use state <- decode.field("sessionState", decode.string)
  use value <- decode.field("value", common.fact_decoder())
  use receipt <- decode.field("observationReceipt", decode.string)
  decode.success(Point(date, state, value, receipt))
}

fn validate(packet: Packet) -> Result(Nil, common.Error) {
  use _ <- result.try(case packet.alignment_policy {
    "intersection_of_open_local_session_dates" -> Ok(Nil)
    _ ->
      Error(common.InvalidField(
        "alignmentPolicy",
        "must be intersection_of_open_local_session_dates",
      ))
  })
  use _ <- result.try(case packet.return_method {
    "simple_return_in_native_currency" -> Ok(Nil)
    _ ->
      Error(common.InvalidField(
        "returnMethod",
        "must be simple_return_in_native_currency",
      ))
  })
  use _ <- result.try(case list.length(packet.legs) {
    count if count >= 2 && count <= 9 -> Ok(Nil)
    count -> Error(common.BudgetExceeded("legs", count, 9))
  })
  use _ <- result.try(case packet.handoff_receipts {
    [] -> Error(common.InvalidField("handoffReceipts", "must not be empty"))
    receipts -> common.validate_receipts("handoffReceipts", receipts)
  })
  use _ <- result.try(validate_distinct_leg_ids(packet.legs))
  packet.legs
  |> list.index_map(fn(leg, index) {
    validate_leg(leg, "legs[" <> int.to_string(index) <> "]")
  })
  |> list.try_map(fn(value) { value })
  |> result.map(fn(_) { Nil })
}

fn validate_distinct_leg_ids(legs: List(Leg)) -> Result(Nil, common.Error) {
  let ids = list.map(legs, fn(leg) { leg.leg_id })
  case ids |> list.unique |> list.length == list.length(ids) {
    True -> Ok(Nil)
    False -> Error(common.InvalidField("legs.legId", "must be unique"))
  }
}

fn validate_leg(leg: Leg, field: String) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty(field <> ".legId", leg.leg_id))
  use _ <- result.try(
    common.one_of(field <> ".track", leg.track, [
      "cn",
      "hk",
      "us",
    ]),
  )
  use _ <- result.try(
    common.one_of(field <> ".instrumentKind", leg.instrument_kind, [
      "index",
      "etf",
      "equity",
      "adr",
    ]),
  )
  use _ <- result.try(common.non_empty(
    field <> ".instrumentId",
    leg.instrument_id,
  ))
  use _ <- result.try(common.non_empty(
    field <> ".displayName",
    leg.display_name,
  ))
  use _ <- result.try(validate_mic(leg.track, leg.mic, field <> ".mic"))
  use _ <- result.try(common.non_empty(field <> ".currency", leg.currency))
  use _ <- result.try(common.non_empty(field <> ".timezone", leg.timezone))
  use _ <- result.try(common.receipt(
    field <> ".calendarReceipt",
    leg.calendar_receipt,
  ))
  use _ <- result.try(common.receipt(
    field <> ".sourceReceipt",
    leg.source_receipt,
  ))
  use _ <- result.try(case list.length(leg.points) {
    count if count >= 3 && count <= 500 -> Ok(Nil)
    count -> Error(common.BudgetExceeded(field <> ".points", count, 500))
  })
  leg.points
  |> list.index_map(fn(point, index) {
    validate_point(
      point,
      leg.currency,
      field <> ".points[" <> int.to_string(index) <> "]",
    )
  })
  |> list.try_map(fn(value) { value })
  |> result.map(fn(_) { Nil })
}

fn validate_mic(
  track: String,
  mic: String,
  field: String,
) -> Result(Nil, common.Error) {
  let allowed = case track {
    "cn" -> ["XSHG", "XSHE", "XBSE"]
    "hk" -> ["XHKG"]
    "us" -> ["XNYS", "XNAS"]
    _ -> []
  }
  common.one_of(field, mic, allowed)
}

fn validate_point(
  point: Point,
  currency: String,
  field: String,
) -> Result(Nil, common.Error) {
  use _ <- result.try(common.date(field <> ".localDate", point.local_date))
  use _ <- result.try(
    common.one_of(field <> ".sessionState", point.session_state, [
      "open_complete",
      "closed",
      "holiday",
      "unknown",
    ]),
  )
  use _ <- result.try(common.validate_fact(field <> ".value", point.value))
  use _ <- result.try(case point.value.unit == currency {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        field <> ".value.unit",
        "must retain leg native currency",
      ))
  })
  use value <- result.try(common.fact_decimal(field <> ".value", point.value))
  use _ <- result.try(case decimal.compare(value, decimal.zero()) {
    order.Gt -> Ok(Nil)
    _ -> Error(common.InvalidField(field <> ".value.raw", "must be positive"))
  })
  common.receipt(field <> ".observationReceipt", point.observation_receipt)
}

fn intersection_dates(legs: List(Leg)) -> List(String) {
  case legs {
    [] -> []
    [first, ..rest] ->
      first.points
      |> list.filter(fn(point) { point.session_state == "open_complete" })
      |> list.map(fn(point) { point.local_date })
      |> list.filter(fn(date) {
        list.all(rest, fn(leg) {
          list.any(leg.points, fn(point) {
            point.local_date == date && point.session_state == "open_complete"
          })
        })
      })
      |> list.sort(string.compare)
  }
}

fn matched_points(points: List(Point), dates: List(String)) -> List(Point) {
  dates
  |> list.filter_map(fn(date) {
    list.find(points, fn(point) {
      point.local_date == date && point.session_state == "open_complete"
    })
  })
}

fn returns(points: List(Point)) -> Result(List(Decimal), common.Error) {
  case points {
    [] -> Error(common.CalculationUnperformed("no matched observations"))
    [_] ->
      Error(common.CalculationUnperformed(
        "at least two matched observations are required",
      ))
    [first, ..rest] -> returns_loop(first, rest, [])
  }
}

fn returns_loop(
  previous: Point,
  remaining: List(Point),
  accumulated: List(Decimal),
) -> Result(List(Decimal), common.Error) {
  case remaining {
    [] -> Ok(list.reverse(accumulated))
    [current, ..rest] -> {
      use previous_value <- result.try(common.fact_decimal(
        "return.previous",
        previous.value,
      ))
      use current_value <- result.try(common.fact_decimal(
        "return.current",
        current.value,
      ))
      use value <- result.try(common.ratio(
        decimal.subtract(current_value, previous_value),
        previous_value,
        12,
      ))
      returns_loop(current, rest, [value, ..accumulated])
    }
  }
}

fn rebased(points: List(Point)) -> Result(List(Decimal), common.Error) {
  case points {
    [] -> Error(common.CalculationUnperformed("no matched observations"))
    [first, ..] -> {
      use base <- result.try(common.fact_decimal("rebase.base", first.value))
      points
      |> list.try_map(fn(point) {
        use value <- result.try(common.fact_decimal("rebase.value", point.value))
        common.percentage(value, base, 8)
      })
    }
  }
}

fn leg_json(leg: Leg, matched: List(Point)) -> json.Json {
  json.object([
    #("legId", json.string(leg.leg_id)),
    #("track", json.string(leg.track)),
    #("instrumentKind", json.string(leg.instrument_kind)),
    #("instrumentId", json.string(leg.instrument_id)),
    #("displayName", json.string(leg.display_name)),
    #("mic", json.string(leg.mic)),
    #("currency", json.string(leg.currency)),
    #("timezone", json.string(leg.timezone)),
    #("calendarReceipt", json.string(leg.calendar_receipt)),
    #("sourceReceipt", json.string(leg.source_receipt)),
    #("allPoints", json.array(leg.points, point_json)),
    #("matchedPoints", json.array(matched, point_json)),
    #(
      "unmatchedPoints",
      json.array(unmatched_points(leg.points, matched), point_json),
    ),
    #("simpleReturns", decimal_list_json(returns(matched))),
    #("rebased100", decimal_list_json(rebased(matched))),
  ])
}

fn unmatched_points(all: List(Point), matched: List(Point)) -> List(Point) {
  list.filter(all, fn(point) {
    !list.any(matched, fn(item) { item.local_date == point.local_date })
  })
}

fn point_json(point: Point) -> json.Json {
  json.object([
    #("localDate", json.string(point.local_date)),
    #("sessionState", json.string(point.session_state)),
    #("value", common.fact_json(point.value)),
    #("observationReceipt", json.string(point.observation_receipt)),
  ])
}

fn decimal_list_json(values: Result(List(Decimal), common.Error)) -> json.Json {
  case values {
    Ok(values) ->
      json.object([
        #("state", json.string("calculated")),
        #("values", json.array(values, common.decimal_json)),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(common.error_message(error))),
      ])
  }
}

fn correlations_json(legs: List(#(Leg, List(Point)))) -> json.Json {
  json.array(pairings(legs), fn(pair) {
    let left_returns = returns(pair.0.1)
    let right_returns = returns(pair.1.1)
    let value = case left_returns, right_returns {
      Ok(left), Ok(right) ->
        statistics.correlation(
          list.filter_map(left, decimal_float),
          list.filter_map(right, decimal_float),
          statistics.Population,
        )
      _, _ -> Error(error.EmptyInput)
    }
    json.object([
      #("leftLegId", json.string(pair.0.0.leg_id)),
      #("rightLegId", json.string(pair.1.0.leg_id)),
      #("estimator", json.string("population")),
      #("value", case value {
        Ok(value) -> json.string(float.to_string(value))
        Error(_) -> json.null()
      }),
    ])
  })
}

fn decimal_float(value: Decimal) -> Result(Float, Nil) {
  common.decimal_float(value)
  |> result.map_error(fn(_) { Nil })
}

fn pairings(
  values: List(#(Leg, List(Point))),
) -> List(#(#(Leg, List(Point)), #(Leg, List(Point)))) {
  case values {
    [] -> []
    [first, ..rest] ->
      list.append(list.map(rest, fn(other) { #(first, other) }), pairings(rest))
  }
}
