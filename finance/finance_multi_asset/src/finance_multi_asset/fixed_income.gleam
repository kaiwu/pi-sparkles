import finance_core/decimal
import finance_math/error as math_error
import finance_math/fixed_income as fixed_math
import finance_math/root
import finance_multi_asset/common
import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

pub type TreasuryPacket {
  TreasuryPacket(
    source: common.Source,
    observation_kind: String,
    instrument_id: Option(String),
    series_id: Option(String),
    security_type: String,
    maturity: String,
    currency: String,
    rate_kind: String,
    frequency: String,
    unit: String,
    raw_value: String,
    observation_date: String,
    publication_unix_ms: Int,
    vintage_date: String,
    on_the_run: Option(Bool),
    auction_date: Option(String),
    observation_receipt: String,
  )
}

pub fn treasury(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "rates_treasury_v1",
    "inspect",
    treasury_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_treasury(packet))
  Ok(
    common.response(
      "rates_treasury_v1",
      "inspect",
      decoded.1,
      case packet.observation_kind {
        "cmt_rate" ->
          "Exact US Treasury constant-maturity rate kept distinct from a tradable security; no benchmark, curve, forecast, or relative-value selection"
        _ ->
          "Exact tradable US Treasury identity and observation kept distinct from an interpolated CMT rate; no benchmark, curve, forecast, or relative-value selection"
      },
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("observationKind", json.string(packet.observation_kind)),
        #("instrumentId", common.option_string_json(packet.instrument_id)),
        #("seriesId", common.option_string_json(packet.series_id)),
        #("securityType", json.string(packet.security_type)),
        #("maturity", json.string(packet.maturity)),
        #("currency", json.string(packet.currency)),
        #("rateKind", json.string(packet.rate_kind)),
        #("frequency", json.string(packet.frequency)),
        #("unit", json.string(packet.unit)),
        #("rawValue", json.string(packet.raw_value)),
        #("observationDate", json.string(packet.observation_date)),
        #("publicationUnixMilliseconds", json.int(packet.publication_unix_ms)),
        #("vintageDate", json.string(packet.vintage_date)),
        #("onTheRun", case packet.on_the_run {
          Some(value) -> json.bool(value)
          None -> json.null()
        }),
        #("auctionDate", common.option_string_json(packet.auction_date)),
        #("observationReceipt", json.string(packet.observation_receipt)),
        #("tradable", json.bool(packet.observation_kind == "tradable_security")),
      ],
    ),
  )
}

fn treasury_decoder() -> decode.Decoder(TreasuryPacket) {
  use source <- decode.field("source", common.source_decoder())
  use kind <- decode.field("observationKind", decode.string)
  use instrument <- decode.optional_field(
    "instrumentId",
    None,
    decode.optional(decode.string),
  )
  use series <- decode.optional_field(
    "seriesId",
    None,
    decode.optional(decode.string),
  )
  use security_type <- decode.field("securityType", decode.string)
  use maturity <- decode.field("maturity", decode.string)
  use currency <- decode.field("currency", decode.string)
  use rate_kind <- decode.field("rateKind", decode.string)
  use frequency <- decode.field("frequency", decode.string)
  use unit <- decode.field("unit", decode.string)
  use raw <- decode.field("rawValue", decode.string)
  use date <- decode.field("observationDate", decode.string)
  use publication <- decode.field("publicationUnixMilliseconds", decode.int)
  use vintage <- decode.field("vintageDate", decode.string)
  use on_the_run <- decode.optional_field(
    "onTheRun",
    None,
    decode.optional(decode.bool),
  )
  use auction <- decode.optional_field(
    "auctionDate",
    None,
    decode.optional(decode.string),
  )
  use receipt <- decode.field("observationReceipt", decode.string)
  decode.success(TreasuryPacket(
    source,
    kind,
    instrument,
    series,
    security_type,
    maturity,
    currency,
    rate_kind,
    frequency,
    unit,
    raw,
    date,
    publication,
    vintage,
    on_the_run,
    auction,
    receipt,
  ))
}

fn validate_treasury(packet: TreasuryPacket) -> Result(Nil, common.Error) {
  use _ <- result.try(
    common.one_of("observationKind", packet.observation_kind, [
      "cmt_rate",
      "tradable_security",
    ]),
  )
  use _ <- result.try(common.non_empty("securityType", packet.security_type))
  use _ <- result.try(common.non_empty("maturity", packet.maturity))
  use _ <- result.try(common.one_of("currency", packet.currency, ["USD"]))
  use _ <- result.try(common.non_empty("rateKind", packet.rate_kind))
  use _ <- result.try(common.non_empty("frequency", packet.frequency))
  use _ <- result.try(common.non_empty("unit", packet.unit))
  use _ <- result.try(case decimal.parse(packet.raw_value) {
    Ok(_) -> Ok(Nil)
    Error(_) ->
      Error(common.InvalidField("rawValue", "must be an exact decimal lexeme"))
  })
  use _ <- result.try(common.date("observationDate", packet.observation_date))
  use _ <- result.try(common.non_negative(
    "publicationUnixMilliseconds",
    packet.publication_unix_ms,
  ))
  use _ <- result.try(common.date("vintageDate", packet.vintage_date))
  use _ <- result.try(common.receipt(
    "observationReceipt",
    packet.observation_receipt,
  ))
  case packet.observation_kind, packet.instrument_id, packet.series_id {
    "cmt_rate", None, Some(series_id) -> {
      use _ <- result.try(common.non_empty("seriesId", series_id))
      common.one_of("securityType", packet.security_type, ["CMT"])
    }
    "tradable_security", Some(instrument_id), None -> {
      use _ <- result.try(common.non_empty("instrumentId", instrument_id))
      common.one_of("securityType", packet.security_type, [
        "Bill",
        "Note",
        "Bond",
        "TIPS",
        "FRN",
        "STRIPS",
      ])
    }
    "cmt_rate", _, _ ->
      Error(common.InvalidField(
        "observationKind",
        "CMT requires seriesId and forbids tradable instrumentId",
      ))
    _, _, _ ->
      Error(common.InvalidField(
        "observationKind",
        "tradable security requires instrumentId and forbids CMT seriesId",
      ))
  }
}

pub type BondIdentity {
  BondIdentity(
    instrument_id: String,
    issuer_id: String,
    issuer_name: String,
    currency: String,
    coupon_type: String,
    coupon_frequency: Int,
    day_count: String,
    payment_convention: String,
    holiday_calendar: String,
    issue_date: String,
    maturity_date: String,
    status: String,
    terms_receipt: String,
  )
}

pub type CashFlow {
  CashFlow(
    payment_date: String,
    amount_raw: String,
    years_from_settlement: String,
    state: String,
    receipt: String,
  )
}

pub type SolverPolicy {
  SolverPolicy(
    method: String,
    lower_yield: String,
    upper_yield: String,
    tolerance: String,
    maximum_iterations: Int,
    compounding_frequency: Int,
    shock: String,
  )
}

pub type Benchmark {
  Benchmark(
    instrument_id: String,
    yield_raw: String,
    day_count: String,
    compounding_frequency: Int,
    receipt: String,
  )
}

pub type CurveKnot {
  CurveKnot(tenor_years: String, zero_rate: String, receipt: String)
}

pub type BondPacket {
  BondPacket(
    source: common.Source,
    identity: BondIdentity,
    settlement_date: String,
    face_value: common.Fact,
    coupon_rate: common.Fact,
    clean_price: common.Fact,
    accrued_interest: common.Fact,
    cash_flows: List(CashFlow),
    solver: SolverPolicy,
    benchmark: Benchmark,
    curve_id: String,
    curve_method: String,
    extrapolation: String,
    curve_knots: List(CurveKnot),
    requested_tenor: String,
  )
}

pub fn analyze(
  bytes: String,
  expected_sha256: String,
) -> Result(common.Response, common.Error) {
  use decoded <- result.try(common.decode_packet(
    bytes,
    expected_sha256,
    "fixed_income_v1",
    "analyze",
    bond_decoder(),
  ))
  let packet = decoded.0
  use _ <- result.try(common.validate_source(packet.source))
  use _ <- result.try(validate_bond(packet))
  let dirty_price = case
    common.fact_decimal("cleanPrice", packet.clean_price),
    common.fact_decimal("accruedInterest", packet.accrued_interest)
  {
    Ok(clean), Ok(accrued) -> Ok(decimal.add(clean, accrued))
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let current_yield = case
    common.fact_decimal("couponRate", packet.coupon_rate),
    common.fact_decimal("faceValue", packet.face_value),
    common.fact_decimal("cleanPrice", packet.clean_price)
  {
    Ok(rate), Ok(face), Ok(price) ->
      common.percentage(decimal.multiply(rate, face), price, 6)
    Error(error), _, _ -> Error(error)
    _, Error(error), _ -> Error(error)
    _, _, Error(error) -> Error(error)
  }
  let flows = cash_flows_for_math(packet.cash_flows)
  let solver = solver_values(packet.solver)
  let dirty_float = case dirty_price {
    Ok(value) -> decimal_to_float(value)
    Error(error) -> Error(error)
  }
  let ytm = case flows, solver, dirty_float {
    Ok(flows), Ok(policy), Ok(price) ->
      root.bisection(
        fn(yield) {
          use present <- result.try(fixed_math.present_value(
            flows,
            yield,
            fixed_math.Periodic(packet.solver.compounding_frequency),
          ))
          Ok(present -. price)
        },
        lower: policy.lower,
        upper: policy.upper,
        tolerance: policy.tolerance,
        maximum_iterations: packet.solver.maximum_iterations,
      )
      |> result.map_error(math_to_common)
    Error(error), _, _ -> Error(error)
    _, Error(error), _ -> Error(error)
    _, _, Error(error) -> Error(error)
  }
  let sensitivity = case flows, ytm {
    Ok(flows), Ok(yield) ->
      fixed_math.sensitivity(
        flows,
        yield,
        fixed_math.Periodic(packet.solver.compounding_frequency),
      )
      |> result.map_error(math_to_common)
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
  let spread = case
    ytm,
    float.parse(packet.benchmark.yield_raw),
    packet.identity.day_count == packet.benchmark.day_count,
    packet.solver.compounding_frequency
    == packet.benchmark.compounding_frequency
  {
    Ok(yield), Ok(benchmark), True, True -> Ok(yield -. benchmark)
    _, _, False, _ ->
      Error(common.CalculationUnperformed("incompatible day-count conventions"))
    _, _, _, False ->
      Error(common.CalculationUnperformed(
        "incompatible compounding conventions",
      ))
    Error(error), _, _, _ -> Error(error)
    _, Error(_), _, _ ->
      Error(common.InvalidField(
        "benchmark.yield",
        "must be a finite decimal lexeme",
      ))
  }
  let interpolated =
    interpolate_curve(packet.curve_knots, packet.requested_tenor)
  Ok(
    common.response(
      "fixed_income_v1",
      "analyze",
      decoded.1,
      "Exact bond cash-flow, bounded-yield, sensitivity, spread and caller-selected curve calculations; no curve, convention, credit model, fair value, or trade selection",
      [
        #("source", common.source_json(packet.source)),
        #("track", json.null()),
        #("identity", bond_identity_json(packet.identity)),
        #("settlementDate", json.string(packet.settlement_date)),
        #("cashFlows", json.array(packet.cash_flows, cash_flow_json)),
        #(
          "dirtyPrice",
          common.calculation_json(
            "clean_price + accrued_interest",
            dirty_price,
            packet.identity.currency,
            [
              #("cleanPrice", common.fact_json(packet.clean_price)),
              #("accruedInterest", common.fact_json(packet.accrued_interest)),
            ],
          ),
        ),
        #(
          "currentYieldPercent",
          common.calculation_json(
            "coupon_rate * face_value / clean_price * 100",
            current_yield,
            "percent",
            [
              #("couponRate", common.fact_json(packet.coupon_rate)),
              #("faceValue", common.fact_json(packet.face_value)),
              #("cleanPrice", common.fact_json(packet.clean_price)),
            ],
          ),
        ),
        #(
          "yieldToMaturity",
          float_result_json(
            "bounded_bisection_price_equals_discounted_cash_flows",
            ytm,
            "annual_yield_fraction",
          ),
        ),
        #("sensitivity", sensitivity_json(sensitivity)),
        #(
          "gSpread",
          float_result_json(
            "bond_ytm - caller_selected_benchmark_yield",
            spread,
            "annual_yield_fraction",
          ),
        ),
        #(
          "benchmark",
          json.object([
            #("instrumentId", json.string(packet.benchmark.instrument_id)),
            #("yield", json.string(packet.benchmark.yield_raw)),
            #("dayCount", json.string(packet.benchmark.day_count)),
            #(
              "compoundingFrequency",
              json.int(packet.benchmark.compounding_frequency),
            ),
            #("receipt", json.string(packet.benchmark.receipt)),
          ]),
        ),
        #(
          "curve",
          json.object([
            #("curveId", json.string(packet.curve_id)),
            #("method", json.string(packet.curve_method)),
            #("extrapolation", json.string(packet.extrapolation)),
            #("knots", json.array(packet.curve_knots, curve_knot_json)),
            #("requestedTenor", json.string(packet.requested_tenor)),
            #(
              "interpolatedZeroRate",
              float_result_json(
                "linear_zero_v1",
                interpolated,
                "annual_yield_fraction",
              ),
            ),
          ]),
        ),
        #(
          "solver",
          json.object([
            #("method", json.string(packet.solver.method)),
            #("lowerYield", json.string(packet.solver.lower_yield)),
            #("upperYield", json.string(packet.solver.upper_yield)),
            #("tolerance", json.string(packet.solver.tolerance)),
            #("maximumIterations", json.int(packet.solver.maximum_iterations)),
            #(
              "compoundingFrequency",
              json.int(packet.solver.compounding_frequency),
            ),
            #("shock", json.string(packet.solver.shock)),
          ]),
        ),
      ],
    ),
  )
}

type SolverValues {
  SolverValues(lower: Float, upper: Float, tolerance: Float, shock: Float)
}

fn bond_decoder() -> decode.Decoder(BondPacket) {
  use source <- decode.field("source", common.source_decoder())
  use identity <- decode.field("identity", bond_identity_decoder())
  use settlement <- decode.field("settlementDate", decode.string)
  use face <- decode.field("faceValue", common.fact_decoder())
  use coupon <- decode.field("couponRate", common.fact_decoder())
  use clean <- decode.field("cleanPrice", common.fact_decoder())
  use accrued <- decode.field("accruedInterest", common.fact_decoder())
  use flows <- decode.field("cashFlows", decode.list(of: cash_flow_decoder()))
  use solver <- decode.field("solver", solver_decoder())
  use benchmark <- decode.field("benchmark", benchmark_decoder())
  use curve_id <- decode.field("curveId", decode.string)
  use curve_method <- decode.field("curveMethod", decode.string)
  use extrapolation <- decode.field("extrapolation", decode.string)
  use knots <- decode.field("curveKnots", decode.list(of: curve_knot_decoder()))
  use requested <- decode.field("requestedTenorYears", decode.string)
  decode.success(BondPacket(
    source,
    identity,
    settlement,
    face,
    coupon,
    clean,
    accrued,
    flows,
    solver,
    benchmark,
    curve_id,
    curve_method,
    extrapolation,
    knots,
    requested,
  ))
}

fn bond_identity_decoder() -> decode.Decoder(BondIdentity) {
  use id <- decode.field("instrumentId", decode.string)
  use issuer_id <- decode.field("issuerId", decode.string)
  use issuer_name <- decode.field("issuerName", decode.string)
  use currency <- decode.field("currency", decode.string)
  use coupon_type <- decode.field("couponType", decode.string)
  use frequency <- decode.field("couponFrequency", decode.int)
  use day_count <- decode.field("dayCountConvention", decode.string)
  use payment <- decode.field("paymentConvention", decode.string)
  use calendar <- decode.field("holidayCalendar", decode.string)
  use issue <- decode.field("issueDate", decode.string)
  use maturity <- decode.field("maturityDate", decode.string)
  use status <- decode.field("status", decode.string)
  use receipt <- decode.field("termsReceipt", decode.string)
  decode.success(BondIdentity(
    id,
    issuer_id,
    issuer_name,
    currency,
    coupon_type,
    frequency,
    day_count,
    payment,
    calendar,
    issue,
    maturity,
    status,
    receipt,
  ))
}

fn cash_flow_decoder() -> decode.Decoder(CashFlow) {
  use date <- decode.field("paymentDate", decode.string)
  use amount <- decode.field("amount", decode.string)
  use years <- decode.field("yearsFromSettlement", decode.string)
  use state <- decode.field("state", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(CashFlow(date, amount, years, state, receipt))
}

fn solver_decoder() -> decode.Decoder(SolverPolicy) {
  use method <- decode.field("method", decode.string)
  use lower <- decode.field("lowerYield", decode.string)
  use upper <- decode.field("upperYield", decode.string)
  use tolerance <- decode.field("tolerance", decode.string)
  use maximum <- decode.field("maximumIterations", decode.int)
  use frequency <- decode.field("compoundingFrequency", decode.int)
  use shock <- decode.field("shock", decode.string)
  decode.success(SolverPolicy(
    method,
    lower,
    upper,
    tolerance,
    maximum,
    frequency,
    shock,
  ))
}

fn benchmark_decoder() -> decode.Decoder(Benchmark) {
  use id <- decode.field("instrumentId", decode.string)
  use yield <- decode.field("yield", decode.string)
  use day_count <- decode.field("dayCountConvention", decode.string)
  use frequency <- decode.field("compoundingFrequency", decode.int)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Benchmark(id, yield, day_count, frequency, receipt))
}

fn curve_knot_decoder() -> decode.Decoder(CurveKnot) {
  use tenor <- decode.field("tenorYears", decode.string)
  use rate <- decode.field("zeroRate", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(CurveKnot(tenor, rate, receipt))
}

fn validate_bond(packet: BondPacket) -> Result(Nil, common.Error) {
  let identity = packet.identity
  use _ <- result.try(common.non_empty(
    "identity.instrumentId",
    identity.instrument_id,
  ))
  use _ <- result.try(common.non_empty("identity.issuerId", identity.issuer_id))
  use _ <- result.try(common.non_empty(
    "identity.issuerName",
    identity.issuer_name,
  ))
  use _ <- result.try(common.non_empty("identity.currency", identity.currency))
  use _ <- result.try(common.non_empty(
    "identity.couponType",
    identity.coupon_type,
  ))
  use _ <- result.try(common.positive(
    "identity.couponFrequency",
    identity.coupon_frequency,
  ))
  use _ <- result.try(common.non_empty(
    "identity.dayCountConvention",
    identity.day_count,
  ))
  use _ <- result.try(common.non_empty(
    "identity.paymentConvention",
    identity.payment_convention,
  ))
  use _ <- result.try(common.non_empty(
    "identity.holidayCalendar",
    identity.holiday_calendar,
  ))
  use _ <- result.try(common.date("identity.issueDate", identity.issue_date))
  use _ <- result.try(common.date(
    "identity.maturityDate",
    identity.maturity_date,
  ))
  use _ <- result.try(common.receipt(
    "identity.termsReceipt",
    identity.terms_receipt,
  ))
  use _ <- result.try(common.date("settlementDate", packet.settlement_date))
  use _ <- result.try(common.validate_fact("faceValue", packet.face_value))
  use _ <- result.try(common.validate_fact("couponRate", packet.coupon_rate))
  use _ <- result.try(common.validate_fact("cleanPrice", packet.clean_price))
  use _ <- result.try(common.validate_fact(
    "accruedInterest",
    packet.accrued_interest,
  ))
  use _ <- result.try(case packet.cash_flows {
    [] -> Error(common.InvalidField("cashFlows", "must not be empty"))
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    packet.cash_flows
    |> list.try_map(validate_cash_flow)
    |> result.map(fn(_) { Nil }),
  )
  use _ <- result.try(case solver_values(packet.solver) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  })
  use _ <- result.try(common.non_empty(
    "benchmark.instrumentId",
    packet.benchmark.instrument_id,
  ))
  use _ <- result.try(common.receipt(
    "benchmark.receipt",
    packet.benchmark.receipt,
  ))
  use _ <- result.try(common.non_empty("curveId", packet.curve_id))
  use _ <- result.try(
    common.one_of("curveMethod", packet.curve_method, ["linear_zero_v1"]),
  )
  use _ <- result.try(
    common.one_of("extrapolation", packet.extrapolation, ["none"]),
  )
  use _ <- result.try(case packet.curve_knots {
    [_, _, ..] -> Ok(Nil)
    _ -> Error(common.InvalidField("curveKnots", "requires at least two knots"))
  })
  packet.curve_knots
  |> list.try_map(fn(knot) {
    use _ <- result.try(case float.parse(knot.tenor_years) {
      Ok(value) if value >. 0.0 -> Ok(Nil)
      _ ->
        Error(common.InvalidField("curveKnot.tenorYears", "must be positive"))
    })
    use _ <- result.try(case float.parse(knot.zero_rate) {
      Ok(_) -> Ok(Nil)
      _ -> Error(common.InvalidField("curveKnot.zeroRate", "must be numeric"))
    })
    common.receipt("curveKnot.receipt", knot.receipt)
  })
  |> result.map(fn(_) { Nil })
}

fn validate_cash_flow(flow: CashFlow) -> Result(Nil, common.Error) {
  use _ <- result.try(common.date("cashFlow.paymentDate", flow.payment_date))
  use _ <- result.try(
    common.one_of("cashFlow.state", flow.state, ["known", "unknown"]),
  )
  use _ <- result.try(case flow.state, float.parse(flow.amount_raw) {
    "known", Ok(_) -> Ok(Nil)
    "known", Error(_) ->
      Error(common.InvalidField("cashFlow.amount", "must be numeric when known"))
    "unknown", _ -> Ok(Nil)
    _, _ -> Error(common.InvalidField("cashFlow.state", "unsupported state"))
  })
  use _ <- result.try(case float.parse(flow.years_from_settlement) {
    Ok(value) if value >=. 0.0 -> Ok(Nil)
    _ ->
      Error(common.InvalidField(
        "cashFlow.yearsFromSettlement",
        "must be non-negative",
      ))
  })
  common.receipt("cashFlow.receipt", flow.receipt)
}

fn solver_values(policy: SolverPolicy) -> Result(SolverValues, common.Error) {
  case
    float.parse(policy.lower_yield),
    float.parse(policy.upper_yield),
    float.parse(policy.tolerance),
    float.parse(policy.shock)
  {
    Ok(lower), Ok(upper), Ok(tolerance), Ok(shock)
      if lower <. upper
      && tolerance >. 0.0
      && shock >. 0.0
      && policy.maximum_iterations > 0
      && policy.maximum_iterations <= 1000
      && policy.compounding_frequency > 0
      && policy.method == "bisection_v1"
    -> Ok(SolverValues(lower, upper, tolerance, shock))
    _, _, _, _ ->
      Error(common.InvalidField(
        "solver",
        "requires bounded bisection_v1, ordered yields, positive tolerance/shock/frequency, and at most 1000 iterations",
      ))
  }
}

fn cash_flows_for_math(
  flows: List(CashFlow),
) -> Result(List(fixed_math.CashFlow), common.Error) {
  flows
  |> list.try_map(fn(flow) {
    case
      flow.state,
      float.parse(flow.amount_raw),
      float.parse(flow.years_from_settlement)
    {
      "known", Ok(amount), Ok(years) -> Ok(fixed_math.CashFlow(amount, years))
      "unknown", _, _ ->
        Error(common.CalculationUnperformed("unknown future cash flow"))
      _, _, _ ->
        Error(common.InvalidField("cashFlows", "invalid numeric cash flow"))
    }
  })
}

fn decimal_to_float(value: decimal.Decimal) -> Result(Float, common.Error) {
  common.decimal_float(value)
}

fn math_to_common(error: math_error.MetricError) -> common.Error {
  common.CalculationUnperformed(case error {
    math_error.RootNotBracketed -> "yield root is not bracketed"
    math_error.DidNotConverge(_) -> "yield solver did not converge"
    math_error.EmptyInput -> "no cash flows"
    math_error.DivisionByZero -> "division by zero"
    _ -> "fixed-income model rejected supplied inputs"
  })
}

fn interpolate_curve(
  knots: List(CurveKnot),
  requested_tenor: String,
) -> Result(Float, common.Error) {
  use requested <- result.try(
    float.parse(requested_tenor)
    |> result.map_error(fn(_) {
      common.InvalidField("requestedTenorYears", "must be numeric")
    }),
  )
  interpolate_pairs(knots, requested)
}

fn interpolate_pairs(
  knots: List(CurveKnot),
  requested: Float,
) -> Result(Float, common.Error) {
  case knots {
    [left, right, ..rest] ->
      case
        float.parse(left.tenor_years),
        float.parse(left.zero_rate),
        float.parse(right.tenor_years),
        float.parse(right.zero_rate)
      {
        Ok(left_tenor), Ok(left_rate), Ok(right_tenor), Ok(right_rate) ->
          case requested >=. left_tenor && requested <=. right_tenor {
            True ->
              Ok(
                left_rate
                +. { right_rate -. left_rate }
                *. { requested -. left_tenor }
                /. { right_tenor -. left_tenor },
              )
            False -> interpolate_pairs([right, ..rest], requested)
          }
        _, _, _, _ -> Error(common.InvalidField("curveKnots", "invalid knot"))
      }
    _ ->
      Error(common.CalculationUnperformed(
        "requested tenor is outside the caller curve and extrapolation is none",
      ))
  }
}

fn bond_identity_json(identity: BondIdentity) -> json.Json {
  json.object([
    #("instrumentId", json.string(identity.instrument_id)),
    #("issuerId", json.string(identity.issuer_id)),
    #("issuerName", json.string(identity.issuer_name)),
    #("currency", json.string(identity.currency)),
    #("couponType", json.string(identity.coupon_type)),
    #("couponFrequency", json.int(identity.coupon_frequency)),
    #("dayCountConvention", json.string(identity.day_count)),
    #("paymentConvention", json.string(identity.payment_convention)),
    #("holidayCalendar", json.string(identity.holiday_calendar)),
    #("issueDate", json.string(identity.issue_date)),
    #("maturityDate", json.string(identity.maturity_date)),
    #("status", json.string(identity.status)),
    #("termsReceipt", json.string(identity.terms_receipt)),
  ])
}

fn cash_flow_json(flow: CashFlow) -> json.Json {
  json.object([
    #("paymentDate", json.string(flow.payment_date)),
    #("amount", json.string(flow.amount_raw)),
    #("yearsFromSettlement", json.string(flow.years_from_settlement)),
    #("state", json.string(flow.state)),
    #("receipt", json.string(flow.receipt)),
  ])
}

fn curve_knot_json(knot: CurveKnot) -> json.Json {
  json.object([
    #("tenorYears", json.string(knot.tenor_years)),
    #("zeroRate", json.string(knot.zero_rate)),
    #("receipt", json.string(knot.receipt)),
  ])
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
        #("approximation", json.string("IEEE-754 finite calculation")),
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

fn sensitivity_json(
  value: Result(fixed_math.Sensitivity, common.Error),
) -> json.Json {
  case value {
    Ok(sensitivity) ->
      json.object([
        #("state", json.string("calculated")),
        #(
          "presentValue",
          json.string(float.to_string(sensitivity.present_value)),
        ),
        #(
          "macaulayDuration",
          json.string(float.to_string(sensitivity.macaulay_duration)),
        ),
        #(
          "modifiedDuration",
          json.string(float.to_string(sensitivity.modified_duration)),
        ),
        #("convexity", json.string(float.to_string(sensitivity.convexity))),
        #("dv01", json.string(float.to_string(sensitivity.dv01))),
        #("approximation", json.string("caller-selected yield and compounding")),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(common.error_message(error))),
      ])
  }
}
