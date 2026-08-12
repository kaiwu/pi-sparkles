import finance_math/error as math_error
import finance_math/root
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/result

pub type Identity {
  Identity(
    option_id: String,
    underlying_listing_id: String,
    underlying_mic: String,
    underlying_track: String,
    option_venue: String,
    root_symbol: String,
    call_put: String,
    style: String,
    strike_raw: String,
    expiration_date: String,
    multiplier: Int,
    settlement: String,
    deliverable_kind: String,
    currency: String,
    contract_version: String,
    identity_receipt: String,
    adjustment_lineage: List(String),
  )
}

pub type Quote {
  Quote(
    bid_raw: String,
    bid_size: Int,
    ask_raw: String,
    ask_size: Int,
    observed_price_raw: String,
    observed_price_kind: String,
    quote_unix_ms: Int,
    receipt_unix_ms: Int,
    entitlement: String,
    state: String,
    receipt: String,
  )
}

pub type Leg {
  Leg(
    option_id: String,
    call_put: String,
    strike_raw: String,
    multiplier: Int,
    direction: String,
    quantity: Int,
    entry_premium_raw: String,
    receipt: String,
  )
}

pub type Pricing {
  Pricing(
    model: String,
    spot_raw: String,
    time_years_raw: String,
    volatility_raw: String,
    rate_raw: String,
    dividend_yield_raw: String,
    steps: Int,
    sigma_lower_raw: String,
    sigma_upper_raw: String,
    tolerance_raw: String,
    maximum_iterations: Int,
    spot_bump_raw: String,
    volatility_bump_raw: String,
    rate_bump_raw: String,
    time_bump_raw: String,
    input_receipts: List(String),
  )
}

pub type Packet {
  Packet(
    source: common.Source,
    identity: Identity,
    quote: Quote,
    legs: List(Leg),
    underlying_grid: List(String),
    pricing: Pricing,
  )
}

type ModelInputs {
  ModelInputs(
    spot: Float,
    strike: Float,
    time_years: Float,
    volatility: Float,
    rate: Float,
    dividend_yield: Float,
    steps: Int,
  )
}

type Greeks {
  Greeks(delta: Float, gamma: Float, theta: Float, vega: Float, rho: Float)
}

pub fn analyze(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "options_v1",
    "analyze",
    packet_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate(packet))
  let inputs = model_inputs(packet)
  let model_price = case inputs {
    Ok(values) -> price(packet.pricing.model, packet.identity, values)
    Error(error) -> Error(error)
  }
  let implied_volatility = implied_volatility(packet, inputs)
  let greeks = calculate_greeks(packet, inputs)
  let quote_midpoint = case
    float.parse(packet.quote.bid_raw),
    float.parse(packet.quote.ask_raw)
  {
    Ok(bid), Ok(ask) -> Ok({ bid +. ask } /. 2.0)
    _, _ -> Error(common.InvalidField("quote", "bid and ask must be numeric"))
  }
  let crossed = case
    float.parse(packet.quote.bid_raw),
    float.parse(packet.quote.ask_raw)
  {
    Ok(bid), Ok(ask) -> bid >. ask
    _, _ -> False
  }
  Ok(
    common.response(
      "options_v1",
      "analyze",
      decoded.1,
      "Exact US listed-option identity, adjusted deliverable, quote, caller-selected payoff/model/IV/Greek calculations; no value, probability, liquidity, hedge, exercise, or strategy judgment",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.string("us")),
        #("identity", identity_json(packet.identity)),
        #("quote", quote_json(packet.quote, quote_midpoint, crossed)),
        #(
          "payoffGrid",
          json.array(packet.underlying_grid, fn(raw) {
            payoff_point_json(raw, packet.legs)
          }),
        ),
        #("pricing", model_result_json(packet, model_price)),
        #(
          "impliedVolatility",
          float_result_json(
            "bounded_bisection_observed_price_equals_model_price",
            implied_volatility,
            "annual_volatility_fraction",
          ),
        ),
        #("greeks", greeks_json(packet, greeks)),
        #(
          "inputReceipts",
          json.array(packet.pricing.input_receipts, json.string),
        ),
        #(
          "limitations",
          json.array(
            [
              "implied_volatility_is_model_dependent",
              "adjusted_deliverable_is_not_assumed_to_be_100_standard_shares",
              "no_probability_of_profit_or_exercise_prediction",
            ],
            json.string,
          ),
        ),
      ],
    ),
  )
}

fn packet_decoder() -> decode.Decoder(Packet) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", identity_decoder())
  use quote <- decode.field("quote", quote_decoder())
  use legs <- decode.field("legs", decode.list(of: leg_decoder()))
  use grid <- decode.field("underlyingGrid", decode.list(of: decode.string))
  use pricing <- decode.field("pricing", pricing_decoder())
  decode.success(Packet(source, identity, quote, legs, grid, pricing))
}

fn identity_decoder() -> decode.Decoder(Identity) {
  use id <- decode.field("optionId", decode.string)
  use listing <- decode.field("underlyingListingId", decode.string)
  use mic <- decode.field("underlyingMic", decode.string)
  use track <- decode.field("underlyingTrack", decode.string)
  use venue <- decode.field("optionVenue", decode.string)
  use root <- decode.field("rootSymbol", decode.string)
  use call_put <- decode.field("callPut", decode.string)
  use style <- decode.field("style", decode.string)
  use strike <- decode.field("strike", decode.string)
  use expiration <- decode.field("expirationDate", decode.string)
  use multiplier <- decode.field("multiplier", decode.int)
  use settlement <- decode.field("settlement", decode.string)
  use deliverable <- decode.field("deliverableKind", decode.string)
  use currency <- decode.field("currency", decode.string)
  use version <- decode.field("contractVersion", decode.string)
  use receipt <- decode.field("identityReceipt", decode.string)
  use adjustments <- decode.field(
    "adjustmentLineage",
    decode.list(of: decode.string),
  )
  decode.success(Identity(
    id,
    listing,
    mic,
    track,
    venue,
    root,
    call_put,
    style,
    strike,
    expiration,
    multiplier,
    settlement,
    deliverable,
    currency,
    version,
    receipt,
    adjustments,
  ))
}

fn quote_decoder() -> decode.Decoder(Quote) {
  use bid <- decode.field("bid", decode.string)
  use bid_size <- decode.field("bidSize", decode.int)
  use ask <- decode.field("ask", decode.string)
  use ask_size <- decode.field("askSize", decode.int)
  use observed <- decode.field("observedPrice", decode.string)
  use observed_kind <- decode.field("observedPriceKind", decode.string)
  use quote_time <- decode.field("quoteUnixMilliseconds", decode.int)
  use receipt_time <- decode.field("receiptUnixMilliseconds", decode.int)
  use entitlement <- decode.field("entitlement", decode.string)
  use state <- decode.field("state", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Quote(
    bid,
    bid_size,
    ask,
    ask_size,
    observed,
    observed_kind,
    quote_time,
    receipt_time,
    entitlement,
    state,
    receipt,
  ))
}

fn leg_decoder() -> decode.Decoder(Leg) {
  use id <- decode.field("optionId", decode.string)
  use call_put <- decode.field("callPut", decode.string)
  use strike <- decode.field("strike", decode.string)
  use multiplier <- decode.field("multiplier", decode.int)
  use direction <- decode.field("direction", decode.string)
  use quantity <- decode.field("quantity", decode.int)
  use premium <- decode.field("entryPremium", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Leg(
    id,
    call_put,
    strike,
    multiplier,
    direction,
    quantity,
    premium,
    receipt,
  ))
}

fn pricing_decoder() -> decode.Decoder(Pricing) {
  use model <- decode.field("model", decode.string)
  use spot <- decode.field("spot", decode.string)
  use time <- decode.field("timeYears", decode.string)
  use volatility <- decode.field("volatility", decode.string)
  use rate <- decode.field("riskFreeRate", decode.string)
  use dividend <- decode.field("dividendYield", decode.string)
  use steps <- decode.field("steps", decode.int)
  use lower <- decode.field("sigmaLower", decode.string)
  use upper <- decode.field("sigmaUpper", decode.string)
  use tolerance <- decode.field("tolerance", decode.string)
  use maximum <- decode.field("maximumIterations", decode.int)
  use spot_bump <- decode.field("spotBump", decode.string)
  use volatility_bump <- decode.field("volatilityBump", decode.string)
  use rate_bump <- decode.field("rateBump", decode.string)
  use time_bump <- decode.field("timeBump", decode.string)
  use receipts <- decode.field("inputReceipts", decode.list(of: decode.string))
  decode.success(Pricing(
    model,
    spot,
    time,
    volatility,
    rate,
    dividend,
    steps,
    lower,
    upper,
    tolerance,
    maximum,
    spot_bump,
    volatility_bump,
    rate_bump,
    time_bump,
    receipts,
  ))
}

fn validate(packet: Packet) -> Result(Nil, common.Error) {
  let identity = packet.identity
  use _ <- result.try(common.non_empty("identity.optionId", identity.option_id))
  use _ <- result.try(common.non_empty(
    "identity.underlyingListingId",
    identity.underlying_listing_id,
  ))
  use _ <- result.try(
    common.one_of("identity.underlyingMic", identity.underlying_mic, [
      "XNYS",
      "XNAS",
    ]),
  )
  use _ <- result.try(
    common.one_of("identity.underlyingTrack", identity.underlying_track, ["us"]),
  )
  use _ <- result.try(common.non_empty(
    "identity.optionVenue",
    identity.option_venue,
  ))
  use _ <- result.try(common.non_empty(
    "identity.rootSymbol",
    identity.root_symbol,
  ))
  use _ <- result.try(
    common.one_of("identity.callPut", identity.call_put, ["call", "put"]),
  )
  use _ <- result.try(
    common.one_of("identity.style", identity.style, ["american", "european"]),
  )
  use _ <- result.try(positive_float("identity.strike", identity.strike_raw))
  use _ <- result.try(common.date(
    "identity.expirationDate",
    identity.expiration_date,
  ))
  use _ <- result.try(common.positive(
    "identity.multiplier",
    identity.multiplier,
  ))
  use _ <- result.try(
    common.one_of("identity.settlement", identity.settlement, [
      "physical",
      "cash",
    ]),
  )
  use _ <- result.try(
    common.one_of("identity.deliverableKind", identity.deliverable_kind, [
      "standard",
      "non_standard",
    ]),
  )
  use _ <- result.try(
    common.one_of("identity.currency", identity.currency, ["USD"]),
  )
  use _ <- result.try(common.non_empty(
    "identity.contractVersion",
    identity.contract_version,
  ))
  use _ <- result.try(common.receipt(
    "identity.identityReceipt",
    identity.identity_receipt,
  ))
  use _ <- result.try(common.validate_receipts(
    "identity.adjustmentLineage",
    identity.adjustment_lineage,
  ))
  use _ <- result.try(validate_quote(packet.quote))
  use _ <- result.try(case packet.legs, packet.underlying_grid {
    [], _ -> Error(common.InvalidField("legs", "must not be empty"))
    _, [] -> Error(common.InvalidField("underlyingGrid", "must not be empty"))
    legs, grid ->
      case list.length(legs) <= 20, list.length(grid) <= 500 {
        True, True -> Ok(Nil)
        False, _ -> Error(common.BudgetExceeded("legs", list.length(legs), 20))
        _, False ->
          Error(common.BudgetExceeded("underlyingGrid", list.length(grid), 500))
      }
  })
  use _ <- result.try(
    packet.legs
    |> list.try_map(validate_leg)
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(
    packet.underlying_grid
    |> list.try_map(fn(value) { positive_float("underlyingGrid", value) })
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(
    common.one_of("pricing.model", packet.pricing.model, [
      "black_scholes_v1",
      "binomial_tree_v1",
    ]),
  )
  use _ <- result.try(case packet.identity.style, packet.pricing.model {
    "american", "black_scholes_v1" ->
      Error(common.InvalidField(
        "pricing.model",
        "Black-Scholes cannot price an American-style contract",
      ))
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(common.positive("pricing.steps", packet.pricing.steps))
  use _ <- result.try(case packet.pricing.steps <= 500 {
    True -> Ok(Nil)
    False ->
      Error(common.BudgetExceeded("pricing.steps", packet.pricing.steps, 500))
  })
  use _ <- result.try(common.positive(
    "pricing.maximumIterations",
    packet.pricing.maximum_iterations,
  ))
  use _ <- result.try(common.validate_receipts(
    "pricing.inputReceipts",
    packet.pricing.input_receipts,
  ))
  use _ <- result.try(model_inputs(packet) |> result.map(fn(_) { Nil }))
  use _ <- result.try(positive_float(
    "pricing.sigmaLower",
    packet.pricing.sigma_lower_raw,
  ))
  use _ <- result.try(positive_float(
    "pricing.sigmaUpper",
    packet.pricing.sigma_upper_raw,
  ))
  use _ <- result.try(positive_float(
    "pricing.tolerance",
    packet.pricing.tolerance_raw,
  ))
  use _ <- result.try(positive_float(
    "pricing.spotBump",
    packet.pricing.spot_bump_raw,
  ))
  use _ <- result.try(positive_float(
    "pricing.volatilityBump",
    packet.pricing.volatility_bump_raw,
  ))
  use _ <- result.try(positive_float(
    "pricing.rateBump",
    packet.pricing.rate_bump_raw,
  ))
  positive_float("pricing.timeBump", packet.pricing.time_bump_raw)
}

fn validate_quote(quote: Quote) -> Result(Nil, common.Error) {
  use _ <- result.try(non_negative_float("quote.bid", quote.bid_raw))
  use _ <- result.try(non_negative_float("quote.ask", quote.ask_raw))
  use _ <- result.try(non_negative_float(
    "quote.observedPrice",
    quote.observed_price_raw,
  ))
  use _ <- result.try(common.non_negative("quote.bidSize", quote.bid_size))
  use _ <- result.try(common.non_negative("quote.askSize", quote.ask_size))
  use _ <- result.try(
    common.one_of("quote.observedPriceKind", quote.observed_price_kind, [
      "bid",
      "ask",
      "mid",
      "last",
    ]),
  )
  use _ <- result.try(common.non_negative(
    "quote.quoteUnixMilliseconds",
    quote.quote_unix_ms,
  ))
  use _ <- result.try(common.non_negative(
    "quote.receiptUnixMilliseconds",
    quote.receipt_unix_ms,
  ))
  use _ <- result.try(common.non_empty("quote.entitlement", quote.entitlement))
  use _ <- result.try(
    common.one_of("quote.state", quote.state, ["known", "stale", "conflicting"]),
  )
  common.receipt("quote.receipt", quote.receipt)
}

fn validate_leg(leg: Leg) -> Result(Nil, common.Error) {
  use _ <- result.try(common.non_empty("leg.optionId", leg.option_id))
  use _ <- result.try(
    common.one_of("leg.callPut", leg.call_put, ["call", "put"]),
  )
  use _ <- result.try(positive_float("leg.strike", leg.strike_raw))
  use _ <- result.try(common.positive("leg.multiplier", leg.multiplier))
  use _ <- result.try(
    common.one_of("leg.direction", leg.direction, ["long", "short"]),
  )
  use _ <- result.try(common.positive("leg.quantity", leg.quantity))
  use _ <- result.try(non_negative_float(
    "leg.entryPremium",
    leg.entry_premium_raw,
  ))
  common.receipt("leg.receipt", leg.receipt)
}

fn model_inputs(packet: Packet) -> Result(ModelInputs, common.Error) {
  case
    float.parse(packet.pricing.spot_raw),
    float.parse(packet.identity.strike_raw),
    float.parse(packet.pricing.time_years_raw),
    float.parse(packet.pricing.volatility_raw),
    float.parse(packet.pricing.rate_raw),
    float.parse(packet.pricing.dividend_yield_raw)
  {
    Ok(spot), Ok(strike), Ok(time), Ok(volatility), Ok(rate), Ok(dividend)
      if spot >. 0.0 && strike >. 0.0 && time >. 0.0 && volatility >. 0.0
    ->
      Ok(ModelInputs(
        spot,
        strike,
        time,
        volatility,
        rate,
        dividend,
        packet.pricing.steps,
      ))
    _, _, _, _, _, _ ->
      Error(common.InvalidField(
        "pricing",
        "spot, strike, time and volatility must be positive finite numbers; rates must be finite",
      ))
  }
}

fn price(
  model: String,
  identity: Identity,
  inputs: ModelInputs,
) -> Result(Float, common.Error) {
  case model {
    "black_scholes_v1" -> black_scholes(identity.call_put, inputs)
    "binomial_tree_v1" -> binomial(identity.call_put, identity.style, inputs)
    _ -> Error(common.CalculationUnperformed("unsupported pricing model"))
  }
}

fn black_scholes(
  call_put: String,
  inputs: ModelInputs,
) -> Result(Float, common.Error) {
  use log_ratio <- result.try(
    float.logarithm(inputs.spot /. inputs.strike)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("Black-Scholes logarithm domain error")
    }),
  )
  use root_time <- result.try(
    float.square_root(inputs.time_years)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("Black-Scholes time domain error")
    }),
  )
  let d1 =
    {
      log_ratio
      +. {
        inputs.rate
        -. inputs.dividend_yield
        +. 0.5
        *. inputs.volatility
        *. inputs.volatility
      }
      *. inputs.time_years
    }
    /. { inputs.volatility *. root_time }
  let d2 = d1 -. inputs.volatility *. root_time
  let spot_present =
    inputs.spot
    *. float.exponential(0.0 -. inputs.dividend_yield *. inputs.time_years)
  let strike_present =
    inputs.strike *. float.exponential(0.0 -. inputs.rate *. inputs.time_years)
  case call_put {
    "call" ->
      Ok(spot_present *. normal_cdf(d1) -. strike_present *. normal_cdf(d2))
    "put" ->
      Ok(
        strike_present
        *. normal_cdf(0.0 -. d2)
        -. spot_present
        *. normal_cdf(0.0 -. d1),
      )
    _ -> Error(common.CalculationUnperformed("unsupported call/put type"))
  }
}

fn normal_cdf(value: Float) -> Float {
  let absolute = float.absolute_value(value)
  let t = 1.0 /. { 1.0 +. 0.2316419 *. absolute }
  let polynomial =
    0.31938153
    *. t
    +. -0.356563782
    *. t
    *. t
    +. 1.781477937
    *. t
    *. t
    *. t
    +. -1.821255978
    *. t
    *. t
    *. t
    *. t
    +. 1.330274429
    *. t
    *. t
    *. t
    *. t
    *. t
  let density =
    0.3989422804014327 *. float.exponential(-0.5 *. absolute *. absolute)
  let positive = 1.0 -. density *. polynomial
  case value >=. 0.0 {
    True -> positive
    False -> 1.0 -. positive
  }
}

fn binomial(
  call_put: String,
  style: String,
  inputs: ModelInputs,
) -> Result(Float, common.Error) {
  let step_count = inputs.steps
  let dt = inputs.time_years /. int.to_float(step_count)
  use root_dt <- result.try(
    float.square_root(dt)
    |> result.map_error(fn(_) {
      common.CalculationUnperformed("binomial time domain error")
    }),
  )
  let up = float.exponential(inputs.volatility *. root_dt)
  let down = 1.0 /. up
  let growth = float.exponential({ inputs.rate -. inputs.dividend_yield } *. dt)
  let probability = { growth -. down } /. { up -. down }
  use _ <- result.try(case probability >=. 0.0 && probability <=. 1.0 {
    True -> Ok(Nil)
    False ->
      Error(common.CalculationUnperformed(
        "binomial risk-neutral probability is outside [0,1]",
      ))
  })
  let discount = float.exponential(0.0 -. inputs.rate *. dt)
  use terminal <- result.try(
    int.range(from: 0, to: step_count + 1, with: [], run: fn(values, value) {
      [value, ..values]
    })
    |> list.reverse
    |> list.try_map(fn(up_count) {
      use up_power <- result.try(
        float.power(up, of: int.to_float(up_count))
        |> result.map_error(fn(_) {
          common.CalculationUnperformed("binomial up power failed")
        }),
      )
      use down_power <- result.try(
        float.power(down, of: int.to_float(step_count - up_count))
        |> result.map_error(fn(_) {
          common.CalculationUnperformed("binomial down power failed")
        }),
      )
      Ok(intrinsic(
        call_put,
        inputs.spot *. up_power *. down_power,
        inputs.strike,
      ))
    }),
  )
  backward_tree(
    terminal,
    step_count - 1,
    call_put,
    style,
    inputs,
    up,
    down,
    probability,
    discount,
  )
}

fn backward_tree(
  values: List(Float),
  step: Int,
  call_put: String,
  style: String,
  inputs: ModelInputs,
  up: Float,
  down: Float,
  probability: Float,
  discount: Float,
) -> Result(Float, common.Error) {
  case step < 0, values {
    True, [value] -> Ok(value)
    True, _ ->
      Error(common.CalculationUnperformed("invalid binomial terminal tree"))
    False, _ -> {
      use next <- result.try(
        backward_level(
          values,
          step,
          0,
          call_put,
          style,
          inputs,
          up,
          down,
          probability,
          discount,
          [],
        ),
      )
      backward_tree(
        next,
        step - 1,
        call_put,
        style,
        inputs,
        up,
        down,
        probability,
        discount,
      )
    }
  }
}

fn backward_level(
  values: List(Float),
  step: Int,
  up_count: Int,
  call_put: String,
  style: String,
  inputs: ModelInputs,
  up: Float,
  down: Float,
  probability: Float,
  discount: Float,
  accumulated: List(Float),
) -> Result(List(Float), common.Error) {
  case values {
    [lower, upper, ..rest] -> {
      let continuation =
        discount *. { { 1.0 -. probability } *. lower +. probability *. upper }
      use up_power <- result.try(
        float.power(up, of: int.to_float(up_count))
        |> result.map_error(fn(_) {
          common.CalculationUnperformed("binomial node power failed")
        }),
      )
      use down_power <- result.try(
        float.power(down, of: int.to_float(step - up_count))
        |> result.map_error(fn(_) {
          common.CalculationUnperformed("binomial node power failed")
        }),
      )
      let exercise =
        intrinsic(
          call_put,
          inputs.spot *. up_power *. down_power,
          inputs.strike,
        )
      let value = case style == "american" && exercise >. continuation {
        True -> exercise
        False -> continuation
      }
      backward_level(
        [upper, ..rest],
        step,
        up_count + 1,
        call_put,
        style,
        inputs,
        up,
        down,
        probability,
        discount,
        [value, ..accumulated],
      )
    }
    [_] -> Ok(list.reverse(accumulated))
    [] -> Error(common.CalculationUnperformed("invalid binomial level"))
  }
}

fn intrinsic(call_put: String, spot: Float, strike: Float) -> Float {
  let raw = case call_put {
    "call" -> spot -. strike
    _ -> strike -. spot
  }
  case raw >. 0.0 {
    True -> raw
    False -> 0.0
  }
}

fn implied_volatility(
  packet: Packet,
  inputs: Result(ModelInputs, common.Error),
) -> Result(Float, common.Error) {
  use inputs <- result.try(inputs)
  use observed <- result.try(
    float.parse(packet.quote.observed_price_raw)
    |> result.map_error(fn(_) {
      common.InvalidField("quote.observedPrice", "must be numeric")
    }),
  )
  use lower <- result.try(
    float.parse(packet.pricing.sigma_lower_raw)
    |> result.map_error(fn(_) {
      common.InvalidField("pricing.sigmaLower", "must be numeric")
    }),
  )
  use upper <- result.try(
    float.parse(packet.pricing.sigma_upper_raw)
    |> result.map_error(fn(_) {
      common.InvalidField("pricing.sigmaUpper", "must be numeric")
    }),
  )
  use tolerance <- result.try(
    float.parse(packet.pricing.tolerance_raw)
    |> result.map_error(fn(_) {
      common.InvalidField("pricing.tolerance", "must be numeric")
    }),
  )
  use _ <- result.try(
    case
      observed +. tolerance
      >=. intrinsic(packet.identity.call_put, inputs.spot, inputs.strike)
    {
      True -> Ok(Nil)
      False ->
        Error(common.CalculationUnperformed("observed price is below intrinsic"))
    },
  )
  root.bisection(
    fn(volatility) {
      price(
        packet.pricing.model,
        packet.identity,
        ModelInputs(..inputs, volatility:),
      )
      |> result.map(fn(value) { value -. observed })
      |> result.map_error(fn(_) { math_error.DomainError })
    },
    lower: lower,
    upper: upper,
    tolerance: tolerance,
    maximum_iterations: packet.pricing.maximum_iterations,
  )
  |> result.map_error(fn(error) {
    common.CalculationUnperformed(case error {
      math_error.RootNotBracketed -> "implied-volatility root is not bracketed"
      math_error.DidNotConverge(_) ->
        "implied-volatility solver did not converge"
      _ -> "implied-volatility solver rejected supplied inputs"
    })
  })
}

fn calculate_greeks(
  packet: Packet,
  inputs: Result(ModelInputs, common.Error),
) -> Result(Greeks, common.Error) {
  use inputs <- result.try(inputs)
  use spot_bump <- result.try(parse_bump(packet.pricing.spot_bump_raw))
  use volatility_bump <- result.try(parse_bump(
    packet.pricing.volatility_bump_raw,
  ))
  use rate_bump <- result.try(parse_bump(packet.pricing.rate_bump_raw))
  use time_bump <- result.try(parse_bump(packet.pricing.time_bump_raw))
  use base <- result.try(price(packet.pricing.model, packet.identity, inputs))
  use spot_up <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, spot: inputs.spot +. spot_bump),
  ))
  use spot_down <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, spot: inputs.spot -. spot_bump),
  ))
  use volatility_up <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, volatility: inputs.volatility +. volatility_bump),
  ))
  use volatility_down <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, volatility: inputs.volatility -. volatility_bump),
  ))
  use rate_up <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, rate: inputs.rate +. rate_bump),
  ))
  use rate_down <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, rate: inputs.rate -. rate_bump),
  ))
  use time_lower <- result.try(case inputs.time_years -. time_bump >. 0.0 {
    True -> Ok(inputs.time_years -. time_bump)
    False ->
      Error(common.CalculationUnperformed("time bump reaches expiration"))
  })
  use time_up <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, time_years: inputs.time_years +. time_bump),
  ))
  use time_down <- result.try(price(
    packet.pricing.model,
    packet.identity,
    ModelInputs(..inputs, time_years: time_lower),
  ))
  Ok(Greeks(
    { spot_up -. spot_down } /. { 2.0 *. spot_bump },
    { spot_up -. 2.0 *. base +. spot_down } /. { spot_bump *. spot_bump },
    { time_down -. time_up } /. { 2.0 *. time_bump } /. 365.0,
    { volatility_up -. volatility_down } /. { 2.0 *. volatility_bump } *. 0.01,
    { rate_up -. rate_down } /. { 2.0 *. rate_bump } *. 0.01,
  ))
}

fn parse_bump(value: String) -> Result(Float, common.Error) {
  case float.parse(value) {
    Ok(parsed) if parsed >. 0.0 -> Ok(parsed)
    _ -> Error(common.InvalidField("pricing bump", "must be positive"))
  }
}

fn payoff_point_json(raw: String, legs: List(Leg)) -> json.Json {
  let result = case float.parse(raw) {
    Ok(spot) ->
      legs
      |> list.try_map(fn(leg) { leg_pnl(leg, spot) })
      |> result.map(float.sum)
    Error(_) -> Error(common.InvalidField("underlyingGrid", "must be numeric"))
  }
  json.object([
    #("underlyingPrice", json.string(raw)),
    #(
      "totalPnl",
      float_result_json(
        "sum(direction * quantity * multiplier * (intrinsic - entry_premium))",
        result,
        "USD",
      ),
    ),
  ])
}

fn leg_pnl(leg: Leg, spot: Float) -> Result(Float, common.Error) {
  case float.parse(leg.strike_raw), float.parse(leg.entry_premium_raw) {
    Ok(strike), Ok(premium) -> {
      let payout = intrinsic(leg.call_put, spot, strike)
      let gross =
        { payout -. premium }
        *. int.to_float(leg.multiplier)
        *. int.to_float(leg.quantity)
      Ok(case leg.direction {
        "long" -> gross
        _ -> 0.0 -. gross
      })
    }
    _, _ -> Error(common.InvalidField("leg", "invalid strike or premium"))
  }
}

fn positive_float(field: String, raw: String) -> Result(Nil, common.Error) {
  case float.parse(raw) {
    Ok(value) if value >. 0.0 -> Ok(Nil)
    _ -> Error(common.InvalidField(field, "must be a positive finite number"))
  }
}

fn non_negative_float(field: String, raw: String) -> Result(Nil, common.Error) {
  case float.parse(raw) {
    Ok(value) if value >=. 0.0 -> Ok(Nil)
    _ ->
      Error(common.InvalidField(field, "must be a non-negative finite number"))
  }
}

fn identity_json(identity: Identity) -> json.Json {
  json.object([
    #("optionId", json.string(identity.option_id)),
    #("underlyingListingId", json.string(identity.underlying_listing_id)),
    #("underlyingMic", json.string(identity.underlying_mic)),
    #("underlyingTrack", json.string(identity.underlying_track)),
    #("optionVenue", json.string(identity.option_venue)),
    #("rootSymbol", json.string(identity.root_symbol)),
    #("callPut", json.string(identity.call_put)),
    #("style", json.string(identity.style)),
    #("strike", json.string(identity.strike_raw)),
    #("expirationDate", json.string(identity.expiration_date)),
    #("multiplier", json.int(identity.multiplier)),
    #("settlement", json.string(identity.settlement)),
    #("deliverableKind", json.string(identity.deliverable_kind)),
    #("currency", json.string(identity.currency)),
    #("contractVersion", json.string(identity.contract_version)),
    #("identityReceipt", json.string(identity.identity_receipt)),
    #("adjustmentLineage", json.array(identity.adjustment_lineage, json.string)),
  ])
}

fn quote_json(
  quote: Quote,
  midpoint: Result(Float, common.Error),
  crossed: Bool,
) -> json.Json {
  json.object([
    #("bid", json.string(quote.bid_raw)),
    #("bidSize", json.int(quote.bid_size)),
    #("ask", json.string(quote.ask_raw)),
    #("askSize", json.int(quote.ask_size)),
    #("observedPrice", json.string(quote.observed_price_raw)),
    #("observedPriceKind", json.string(quote.observed_price_kind)),
    #("midpoint", float_result_json("(bid + ask) / 2", midpoint, "USD")),
    #("crossed", json.bool(crossed)),
    #("quoteUnixMilliseconds", json.int(quote.quote_unix_ms)),
    #("receiptUnixMilliseconds", json.int(quote.receipt_unix_ms)),
    #("entitlement", json.string(quote.entitlement)),
    #("state", json.string(quote.state)),
    #("receipt", json.string(quote.receipt)),
  ])
}

fn model_result_json(
  packet: Packet,
  price: Result(Float, common.Error),
) -> json.Json {
  json.object([
    #("model", json.string(packet.pricing.model)),
    #("style", json.string(packet.identity.style)),
    #("spot", json.string(packet.pricing.spot_raw)),
    #("strike", json.string(packet.identity.strike_raw)),
    #("timeYears", json.string(packet.pricing.time_years_raw)),
    #("volatility", json.string(packet.pricing.volatility_raw)),
    #("riskFreeRate", json.string(packet.pricing.rate_raw)),
    #("dividendYield", json.string(packet.pricing.dividend_yield_raw)),
    #("steps", json.int(packet.pricing.steps)),
    #(
      "price",
      float_result_json(
        "caller_selected_pricing_model_v1",
        price,
        "USD_per_share",
      ),
    ),
  ])
}

fn greeks_json(
  packet: Packet,
  value: Result(Greeks, common.Error),
) -> json.Json {
  case value {
    Ok(greeks) ->
      json.object([
        #("state", json.string("calculated")),
        #("method", json.string("central_finite_difference_v1")),
        #("model", json.string(packet.pricing.model)),
        #("delta", json.string(float.to_string(greeks.delta))),
        #("gamma", json.string(float.to_string(greeks.gamma))),
        #("thetaPerDay", json.string(float.to_string(greeks.theta))),
        #("vegaPerOnePercent", json.string(float.to_string(greeks.vega))),
        #("rhoPerOnePercent", json.string(float.to_string(greeks.rho))),
        #(
          "bumpConvention",
          json.object([
            #("spot", json.string(packet.pricing.spot_bump_raw)),
            #("volatility", json.string(packet.pricing.volatility_bump_raw)),
            #("rate", json.string(packet.pricing.rate_bump_raw)),
            #("timeYears", json.string(packet.pricing.time_bump_raw)),
          ]),
        ),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(common.error_message(error))),
      ])
  }
}

fn float_result_json(
  formula: String,
  value: Result(Float, common.Error),
  unit: String,
) -> json.Json {
  case value {
    Ok(number) ->
      json.object([
        #("state", json.string("calculated")),
        #("formula", json.string(formula)),
        #("value", json.string(float.to_string(number))),
        #("unit", json.string(unit)),
        #("approximation", json.string("IEEE-754 finite model calculation")),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("formula", json.string(formula)),
        #("reason", json.string(common.error_message(error))),
        #("unit", json.string(unit)),
      ])
  }
}
