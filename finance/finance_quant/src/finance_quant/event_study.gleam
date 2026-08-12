import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time
import finance_math/exact
import finance_math/regression
import finance_math/statistics
import finance_quant/common.{type Error, type Response}
import finance_series/returns
import finance_series/series
import finance_track
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

const maximum_events = 500

const maximum_prices_per_event = 1000

type Window {
  Window(start: Int, end: Int)
}

type Definition {
  Definition(
    study_id: String,
    event_type: String,
    model: String,
    return_kind: String,
    estimation_window: Window,
    event_window: Window,
    cluster_policy: String,
    missing_policy: String,
    scale: Int,
    rounding: String,
    requested_statistics: List(String),
  )
}

type PricePoint {
  PricePoint(offset: Int, raw: String, source_receipt: String)
}

type EventInput {
  EventInput(
    event_id: String,
    listing_id: String,
    mic: String,
    event_date: String,
    cluster_id: String,
    duplicate_of: Option(String),
    delisted_during_window: Bool,
    unperformed_reason: Option(String),
    security_prices: List(PricePoint),
    benchmark_prices: List(PricePoint),
    event_receipt: String,
  )
}

type Request {
  Request(
    binding: common.BindingInput,
    definition: Definition,
    events: List(EventInput),
  )
}

type ReturnPoint {
  ReturnPoint(offset: Int, security: Decimal, benchmark: Decimal)
}

type ModelFacts {
  ModelFacts(alpha: String, beta: String, r_squared: String, observations: Int)
}

type AbnormalPoint {
  AbnormalPoint(
    offset: Int,
    security: Decimal,
    benchmark: Decimal,
    expected: Decimal,
    abnormal: Decimal,
  )
}

type EventResult {
  Performed(
    input: EventInput,
    model: ModelFacts,
    abnormal: List(AbnormalPoint),
    car: Decimal,
  )
  Unperformed(input: EventInput, reason: String)
}

pub fn calculate(
  bytes: String,
  expected_sha256: String,
) -> Result(Response, Error) {
  use _ <- result.try(common.verify_packet(
    bytes,
    expected_sha256,
    "stock_event_study_v1",
    "calculate",
  ))
  use request <- result.try(common.parse(bytes, request_decoder()))
  use binding <- result.try(common.prepare_binding(request.binding))
  use _ <- result.try(common.bounded_count(
    "events",
    request.events,
    maximum_events,
  ))
  use _ <- result.try(common.require_unique(
    "events[].eventId",
    list.map(request.events, fn(value) { value.event_id }),
  ))
  use mode <- result.try(validate_definition(request.definition))
  use events <- result.try(
    list.try_map(request.events, fn(value) {
      calculate_event(value, request.definition, mode, binding)
    }),
  )
  let performed =
    list.filter_map(events, fn(value) {
      case value {
        Performed(..) -> Ok(value)
        Unperformed(..) -> Error(Nil)
      }
    })
  let unperformed_count = list.length(events) - list.length(performed)
  let aar = aggregate_aar(performed, request.definition.scale, mode)
  use car_mean <- result.try(case performed {
    [] -> Ok(None)
    _ ->
      list.map(performed, fn(value) {
        let assert Performed(car: car, ..) = value
        car
      })
      |> exact.mean(request.definition.scale, mode)
      |> map_math
      |> result.map(Some)
  })
  use statistics <- result.try(requested_statistics(
    request.definition.requested_statistics,
    performed,
  ))
  let fields = [
    #("schema", json.string("pi-sparkles/stock-event-study-result")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string("calculate")),
    #("binding", common.binding_json(binding)),
    #("definition", definition_json(request.definition)),
    #("eventCount", json.int(list.length(events))),
    #("performedCount", json.int(list.length(performed))),
    #("unperformedCount", json.int(unperformed_count)),
    #("carMean", json.nullable(car_mean, decimal_json)),
    #("aar", json.array(aar, abnormal_average_json)),
    #("requestedStatistics", statistics),
    #("events", json.array(events, event_result_json)),
    #(
      "orderedFormulas",
      json.array(
        [
          "security_return_t = security_price_t / security_price_t-1 - 1",
          "benchmark_return_t = benchmark_price_t / benchmark_price_t-1 - 1",
          "expected_return_t = caller_selected_model(estimation_sample, benchmark_return_t)",
          "abnormal_return_t = security_return_t - expected_return_t",
          "CAR_event = sum(abnormal_return_t over event_window)",
          "AAR_t = mean(performed abnormal_return_t)",
        ],
        json.string,
      ),
    ),
    #("availableOperations", json.array(["calculate"], json.string)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
    #(
      "limitations",
      json.array(
        [
          "matching canonical hashes prove content coherence, not provider origin or causal identification",
          "models, windows, event identities, clusters, and requested statistics are caller selected",
          "no significance threshold, causal attribution, expected-impact label, recommendation, or deployment verdict is produced",
        ],
        json.string,
      ),
    ),
  ]
  Ok(common.response(
    "Event study "
      <> request.definition.study_id
      <> " | "
      <> int.to_string(list.length(performed))
      <> " performed, "
      <> int.to_string(unperformed_count)
      <> " unperformed",
    common.content_bound(fields),
  ))
}

fn request_decoder() -> decode.Decoder(Request) {
  use binding <- decode.field("binding", common.binding_decoder())
  use definition <- decode.field("definition", definition_decoder())
  use events <- decode.field("events", decode.list(of: event_decoder()))
  decode.success(Request(binding, definition, events))
}

fn definition_decoder() -> decode.Decoder(Definition) {
  use study_id <- decode.field("studyId", decode.string)
  use event_type <- decode.field("eventType", decode.string)
  use model <- decode.field("model", decode.string)
  use return_kind <- decode.field("returnKind", decode.string)
  use estimation <- decode.field("estimationWindow", window_decoder())
  use event <- decode.field("eventWindow", window_decoder())
  use cluster <- decode.field("clusterPolicy", decode.string)
  use missing <- decode.field("missingPolicy", decode.string)
  use scale <- decode.field("scale", decode.int)
  use rounding <- decode.field("rounding", decode.string)
  use statistics <- decode.field(
    "requestedStatistics",
    decode.list(of: decode.string),
  )
  decode.success(Definition(
    study_id,
    event_type,
    model,
    return_kind,
    estimation,
    event,
    cluster,
    missing,
    scale,
    rounding,
    statistics,
  ))
}

fn window_decoder() -> decode.Decoder(Window) {
  use start <- decode.field("startOffset", decode.int)
  use end <- decode.field("endOffset", decode.int)
  decode.success(Window(start, end))
}

fn event_decoder() -> decode.Decoder(EventInput) {
  use event_id <- decode.field("eventId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use event_date <- decode.field("eventDate", decode.string)
  use cluster_id <- decode.field("clusterId", decode.string)
  use duplicate <- decode.optional_field(
    "duplicateOf",
    None,
    decode.optional(decode.string),
  )
  use delisted <- decode.field("delistedDuringWindow", decode.bool)
  use unperformed <- decode.optional_field(
    "unperformedReason",
    None,
    decode.optional(decode.string),
  )
  use security <- decode.field(
    "securityPrices",
    decode.list(of: price_decoder()),
  )
  use benchmark <- decode.field(
    "benchmarkPrices",
    decode.list(of: price_decoder()),
  )
  use receipt <- decode.field("eventReceipt", decode.string)
  decode.success(EventInput(
    event_id,
    listing_id,
    mic,
    event_date,
    cluster_id,
    duplicate,
    delisted,
    unperformed,
    security,
    benchmark,
    receipt,
  ))
}

fn price_decoder() -> decode.Decoder(PricePoint) {
  use offset <- decode.field("offset", decode.int)
  use raw <- decode.field("raw", decode.string)
  use receipt <- decode.field("sourceReceipt", decode.string)
  decode.success(PricePoint(offset, raw, receipt))
}

fn validate_definition(value: Definition) -> Result(RoundingMode, Error) {
  use _ <- result.try(common.non_empty("definition.studyId", value.study_id))
  use _ <- result.try(common.non_empty("definition.eventType", value.event_type))
  use _ <- result.try(
    case
      list.contains(
        ["mean_adjusted_v1", "market_adjusted_v1", "market_model_v1"],
        value.model,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.model",
          "unsupported caller-selected first-slice model",
        ))
    },
  )
  use _ <- result.try(case value.return_kind == "simple_return_v1" {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "definition.returnKind",
        "expected simple_return_v1",
      ))
  })
  use _ <- result.try(validate_window(
    "definition.estimationWindow",
    value.estimation_window,
  ))
  use _ <- result.try(validate_window(
    "definition.eventWindow",
    value.event_window,
  ))
  use _ <- result.try(
    case value.estimation_window.end < value.event_window.start {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.windows",
          "estimation window must end before event window starts",
        ))
    },
  )
  use _ <- result.try(
    case
      list.contains(
        ["include_all", "exclude_same_cluster", "caller_resolved"],
        value.cluster_policy,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.clusterPolicy",
          "unsupported explicit cluster policy",
        ))
    },
  )
  use _ <- result.try(
    case
      list.contains(
        ["unperform_event", "retain_partial_unperformed"],
        value.missing_policy,
      )
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.missingPolicy",
          "unsupported explicit missing policy",
        ))
    },
  )
  use _ <- result.try(case value.scale >= 0 && value.scale <= 18 {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField("definition.scale", "must be between 0 and 18"))
  })
  use _ <- result.try(common.require_unique(
    "definition.requestedStatistics",
    value.requested_statistics,
  ))
  use _ <- result.try(
    case
      list.all(value.requested_statistics, fn(value) {
        list.contains(["car_mean", "car_sample_stddev"], value)
      })
    {
      True -> Ok(Nil)
      False ->
        Error(common.InvalidField(
          "definition.requestedStatistics",
          "supports car_mean and car_sample_stddev only",
        ))
    },
  )
  rounding_mode(value.rounding)
}

fn validate_window(field: String, value: Window) -> Result(Nil, Error) {
  case value.start <= value.end {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(field, "startOffset must not exceed endOffset"))
  }
}

fn calculate_event(
  input: EventInput,
  definition: Definition,
  mode: RoundingMode,
  binding: common.Binding,
) -> Result(EventResult, Error) {
  use _ <- result.try(common.non_empty("events[].eventId", input.event_id))
  use _ <- result.try(common.non_empty("events[].listingId", input.listing_id))
  use _ <- result.try(common.non_empty("events[].clusterId", input.cluster_id))
  use _ <- result.try(common.receipt(
    "events[].eventReceipt",
    input.event_receipt,
  ))
  use _ <- result.try(validate_mic(binding.track, input.mic))
  case input.unperformed_reason {
    Some(reason) -> {
      use _ <- result.try(common.non_empty("events[].unperformedReason", reason))
      Ok(Unperformed(input, reason))
    }
    None -> perform_event(input, definition, mode)
  }
}

fn perform_event(
  input: EventInput,
  definition: Definition,
  mode: RoundingMode,
) -> Result(EventResult, Error) {
  use _ <- result.try(common.bounded_count(
    "events[].securityPrices",
    input.security_prices,
    maximum_prices_per_event,
  ))
  use _ <- result.try(common.bounded_count(
    "events[].benchmarkPrices",
    input.benchmark_prices,
    maximum_prices_per_event,
  ))
  use _ <- result.try(validate_price_timeline(
    input.security_prices,
    "securityPrices",
  ))
  use _ <- result.try(validate_price_timeline(
    input.benchmark_prices,
    "benchmarkPrices",
  ))
  use security <- result.try(return_series(
    input.security_prices,
    definition.scale,
    mode,
  ))
  use benchmark <- result.try(return_series(
    input.benchmark_prices,
    definition.scale,
    mode,
  ))
  use paired <- result.try(pair_returns(security, benchmark))
  let estimation = in_window(paired, definition.estimation_window)
  let event = in_window(paired, definition.event_window)
  use _ <- result.try(case estimation != [] && event != [] {
    True -> Ok(Nil)
    False ->
      Error(common.CalculationFailure(
        "estimation or event return window is empty",
      ))
  })
  use model <- result.try(fit_model(
    definition.model,
    estimation,
    definition.scale,
  ))
  use abnormal <- result.try(
    list.try_map(event, fn(point) {
      abnormal_point(
        point,
        definition.model,
        model,
        estimation,
        definition.scale,
      )
    }),
  )
  let car = abnormal |> list.map(fn(value) { value.abnormal }) |> exact.sum
  Ok(Performed(input, model, abnormal, car))
}

fn validate_price_timeline(
  values: List(PricePoint),
  field: String,
) -> Result(Nil, Error) {
  use _ <- result.try(case list.length(values) >= 2 {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "events[]." <> field,
        "requires at least two ordered price points",
      ))
  })
  use _ <- result.try(common.require_unique(
    "events[]." <> field <> "[].offset",
    list.map(values, fn(value) { int.to_string(value.offset) }),
  ))
  use _ <- result.try(
    list.try_each(values, fn(value) {
      use _ <- result.try(common.receipt(
        "events[]." <> field <> "[].sourceReceipt",
        value.source_receipt,
      ))
      decimal.parse(value.raw)
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(_) {
        common.InvalidField(
          "events[]." <> field <> "[].raw",
          "expected exact decimal price",
        )
      })
    }),
  )
  case strictly_increasing(values) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "events[]." <> field,
        "offsets must be strictly increasing",
      ))
  }
}

fn strictly_increasing(values: List(PricePoint)) -> Bool {
  case values {
    [] | [_] -> True
    [left, right, ..rest] ->
      left.offset < right.offset && strictly_increasing([right, ..rest])
  }
}

fn return_series(
  values: List(PricePoint),
  scale: Int,
  mode: RoundingMode,
) -> Result(List(#(Int, Decimal)), Error) {
  use points <- result.try(
    list.try_map(values, fn(value) {
      use at <- result.try(
        time.instant(value.offset)
        |> result.map_error(fn(_) {
          common.InvalidField(
            "events[].prices[].offset",
            "outside supported instant range",
          )
        }),
      )
      use raw <- result.try(
        decimal.parse(value.raw)
        |> result.map_error(fn(_) {
          common.InvalidField("events[].prices[].raw", "expected decimal")
        }),
      )
      Ok(#(at, raw))
    }),
  )
  use prices <- result.try(
    series.from_present(points)
    |> result.map_error(fn(error) {
      common.CalculationFailure(
        "invalid price series: " <> string.inspect(error),
      )
    }),
  )
  use calculated <- result.try(
    returns.simple(prices, scale: scale, rounding: mode)
    |> result.map_error(fn(error) {
      common.CalculationFailure(
        "return series failed: " <> string.inspect(error),
      )
    }),
  )
  Ok(
    calculated
    |> series.present_values
    |> list.map(fn(pair) { #(time.unix_milliseconds(pair.0), pair.1) }),
  )
}

fn pair_returns(
  security: List(#(Int, Decimal)),
  benchmark: List(#(Int, Decimal)),
) -> Result(List(ReturnPoint), Error) {
  case security, benchmark {
    [], [] -> Ok([])
    [left, ..left_rest], [right, ..right_rest] if left.0 == right.0 -> {
      use rest <- result.try(pair_returns(left_rest, right_rest))
      Ok([ReturnPoint(left.0, left.1, right.1), ..rest])
    }
    _, _ ->
      Error(common.CalculationFailure(
        "security and benchmark return timelines must match exactly",
      ))
  }
}

fn in_window(values: List(ReturnPoint), window: Window) -> List(ReturnPoint) {
  list.filter(values, fn(value) {
    value.offset >= window.start && value.offset <= window.end
  })
}

fn fit_model(
  model: String,
  estimation: List(ReturnPoint),
  scale: Int,
) -> Result(ModelFacts, Error) {
  case model {
    "market_model_v1" -> {
      let dependent =
        list.map(estimation, fn(value) { decimal_float(value.security) })
      let predictors =
        list.map(estimation, fn(value) { [decimal_float(value.benchmark)] })
      use fitted <- result.try(
        regression.ordinary_least_squares(
          dependent,
          predictors,
          include_intercept: True,
          singular_tolerance: 0.000000000001,
        )
        |> result.map_error(fn(error) {
          common.CalculationFailure(
            "market model OLS failed: " <> string.inspect(error),
          )
        }),
      )
      let regression.Model(
        intercept,
        coefficients,
        _,
        _,
        r_squared,
        _,
        observations,
      ) = fitted
      let assert [beta] = coefficients
      Ok(ModelFacts(
        float_text(intercept, scale),
        float_text(beta, scale),
        float_text(r_squared, scale),
        observations,
      ))
    }
    "mean_adjusted_v1" -> {
      use mean <- result.try(
        exact.mean(
          list.map(estimation, fn(value) { value.security }),
          scale,
          decimal.HalfEven,
        )
        |> map_math,
      )
      Ok(ModelFacts(
        decimal.to_string(mean),
        "0",
        "not_applicable",
        list.length(estimation),
      ))
    }
    _ -> Ok(ModelFacts("0", "1", "not_applicable", list.length(estimation)))
  }
}

fn abnormal_point(
  point: ReturnPoint,
  model_name: String,
  model: ModelFacts,
  estimation: List(ReturnPoint),
  scale: Int,
) -> Result(AbnormalPoint, Error) {
  use expected <- result.try(case model_name {
    "market_adjusted_v1" -> Ok(point.benchmark)
    "mean_adjusted_v1" ->
      exact.mean(
        list.map(estimation, fn(value) { value.security }),
        scale,
        decimal.HalfEven,
      )
      |> map_math
    _ -> {
      let assert Ok(alpha) = float.parse(model.alpha)
      let assert Ok(beta) = float.parse(model.beta)
      float_decimal(alpha +. beta *. decimal_float(point.benchmark), scale)
    }
  })
  Ok(AbnormalPoint(
    point.offset,
    point.security,
    point.benchmark,
    expected,
    decimal.subtract(point.security, expected),
  ))
}

fn aggregate_aar(
  events: List(EventResult),
  scale: Int,
  mode: RoundingMode,
) -> List(#(Int, Decimal, Int)) {
  let offsets =
    events
    |> list.flat_map(fn(value) {
      let assert Performed(abnormal: abnormal, ..) = value
      list.map(abnormal, fn(point) { point.offset })
    })
    |> unique_ints([])
  list.filter_map(offsets, fn(offset) {
    let values =
      events
      |> list.flat_map(fn(value) {
        let assert Performed(abnormal: abnormal, ..) = value
        abnormal
        |> list.filter(fn(point) { point.offset == offset })
        |> list.map(fn(point) { point.abnormal })
      })
    case exact.mean(values, scale, mode) {
      Ok(mean) -> Ok(#(offset, mean, list.length(values)))
      Error(_) -> Error(Nil)
    }
  })
}

fn requested_statistics(
  requested: List(String),
  events: List(EventResult),
) -> Result(json.Json, Error) {
  let cars =
    list.map(events, fn(value) {
      let assert Performed(car: car, ..) = value
      decimal_float(car)
    })
  use entries <- result.try(
    list.try_map(requested, fn(name) {
      case name {
        "car_mean" ->
          statistics.mean(cars)
          |> map_math
          |> result.map(fn(value) {
            #(name, json.string(float.to_string(value)))
          })
        "car_sample_stddev" ->
          statistics.standard_deviation(cars, statistics.Sample)
          |> map_math
          |> result.map(fn(value) {
            #(name, json.string(float.to_string(value)))
          })
        _ ->
          Error(common.InvalidField(
            "requestedStatistics",
            "unsupported statistic",
          ))
      }
    }),
  )
  Ok(json.object(entries))
}

fn validate_mic(track: finance_track.Track, mic: String) -> Result(Nil, Error) {
  let valid = case track {
    finance_track.Cn -> ["XSHG", "XSHE", "XBSE"]
    finance_track.Hk -> ["XHKG"]
    finance_track.Us -> ["XNYS", "XNAS"]
  }
  case list.contains(valid, mic) {
    True -> Ok(Nil)
    False ->
      Error(common.InvalidField(
        "events[].mic",
        "does not belong to the declared track",
      ))
  }
}

fn rounding_mode(value: String) -> Result(RoundingMode, Error) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(common.InvalidField(
        "definition.rounding",
        "unsupported rounding mode",
      ))
  }
}

fn decimal_float(value: Decimal) -> Float {
  let text = decimal.to_string(value)
  let normalized = case string.contains(text, ".") {
    True -> text
    False -> text <> ".0"
  }
  let assert Ok(parsed) = float.parse(normalized)
  parsed
}

fn float_decimal(value: Float, scale: Int) -> Result(Decimal, Error) {
  let text = float_text(value, scale)
  decimal.parse(text)
  |> result.map_error(fn(_) {
    common.CalculationFailure("non-finite model output")
  })
}

fn float_text(value: Float, scale: Int) -> String {
  let factor = scale_factor(scale, 1.0)
  value *. factor
  |> float.round
  |> int.to_float
  |> fn(value) { value /. factor }
  |> float.to_string
}

fn scale_factor(scale: Int, accumulated: Float) -> Float {
  case scale {
    0 -> accumulated
    _ -> scale_factor(scale - 1, accumulated *. 10.0)
  }
}

fn map_math(value: Result(value, error)) -> Result(value, Error) {
  value
  |> result.map_error(fn(error) {
    common.CalculationFailure(string.inspect(error))
  })
}

fn unique_ints(values: List(Int), seen: List(Int)) -> List(Int) {
  case values {
    [] -> list.reverse(seen)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> unique_ints(rest, seen)
        False -> unique_ints(rest, [value, ..seen])
      }
  }
}

fn definition_json(value: Definition) -> json.Json {
  json.object([
    #("studyId", json.string(value.study_id)),
    #("eventType", json.string(value.event_type)),
    #("model", json.string(value.model)),
    #("returnKind", json.string(value.return_kind)),
    #("estimationWindow", window_json(value.estimation_window)),
    #("eventWindow", window_json(value.event_window)),
    #("clusterPolicy", json.string(value.cluster_policy)),
    #("missingPolicy", json.string(value.missing_policy)),
    #("scale", json.int(value.scale)),
    #("rounding", json.string(value.rounding)),
    #(
      "requestedStatistics",
      json.array(value.requested_statistics, json.string),
    ),
  ])
}

fn window_json(value: Window) -> json.Json {
  json.object([
    #("startOffset", json.int(value.start)),
    #("endOffset", json.int(value.end)),
  ])
}

fn event_result_json(value: EventResult) -> json.Json {
  case value {
    Unperformed(input, reason) ->
      event_common_json(input, [
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
    Performed(input, model, abnormal, car) ->
      event_common_json(input, [
        #("state", json.string("performed")),
        #("model", model_json(model)),
        #("car", decimal_json(car)),
        #("dailyAbnormalReturns", json.array(abnormal, abnormal_json)),
      ])
  }
}

fn event_common_json(
  input: EventInput,
  extra: List(#(String, json.Json)),
) -> json.Json {
  json.object(list.append(
    [
      #("eventId", json.string(input.event_id)),
      #("listingId", json.string(input.listing_id)),
      #("mic", json.string(input.mic)),
      #("eventDate", json.string(input.event_date)),
      #("clusterId", json.string(input.cluster_id)),
      #("duplicateOf", json.nullable(input.duplicate_of, json.string)),
      #("delistedDuringWindow", json.bool(input.delisted_during_window)),
      #("eventReceipt", json.string(input.event_receipt)),
      #(
        "sourceReceipts",
        json.array(
          list.append(
            list.map(input.security_prices, fn(value) { value.source_receipt }),
            list.map(input.benchmark_prices, fn(value) { value.source_receipt }),
          ),
          json.string,
        ),
      ),
    ],
    extra,
  ))
}

fn model_json(value: ModelFacts) -> json.Json {
  json.object([
    #("alpha", json.string(value.alpha)),
    #("beta", json.string(value.beta)),
    #("rSquared", json.string(value.r_squared)),
    #("estimationObservations", json.int(value.observations)),
  ])
}

fn abnormal_json(value: AbnormalPoint) -> json.Json {
  json.object([
    #("offset", json.int(value.offset)),
    #("securityReturn", decimal_json(value.security)),
    #("benchmarkReturn", decimal_json(value.benchmark)),
    #("expectedReturn", decimal_json(value.expected)),
    #("abnormalReturn", decimal_json(value.abnormal)),
  ])
}

fn abnormal_average_json(value: #(Int, Decimal, Int)) -> json.Json {
  json.object([
    #("offset", json.int(value.0)),
    #("aar", decimal_json(value.1)),
    #("eventCount", json.int(value.2)),
  ])
}

fn decimal_json(value: Decimal) -> json.Json {
  json.string(decimal.to_string(value))
}
