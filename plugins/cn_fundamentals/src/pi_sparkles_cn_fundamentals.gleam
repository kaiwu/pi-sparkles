import finance_core/decimal
import finance_core/time
import finance_eastmoney
import finance_eastmoney/fundamentals
import finance_eastmoney/query
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_http/response as http_response
import finance_http/transport
import finance_math/formula
import finance_math/metric as math_metric
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_fundamentals/effect/environment

pub type StatementInput {
  StatementInput(
    market: query.Market,
    code: String,
    report_date: time.Date,
    declared_currency: String,
  )
}

pub type FundamentalInput {
  FundamentalInput(statement: StatementInput, metric: fundamentals.Metric)
}

pub type MetricInput {
  MetricInput(statement: StatementInput, scale: Int)
}

type Provider {
  Ready(access: finance_eastmoney.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_financial_statement",
    "CN raw income statement slice",
    "Fetch one exact-period Eastmoney mainland income row and expose exact source number tokens, original field codes and Chinese labels, caller-declared currency, provider codes, and every unknown filing context",
    "Inspect bounded raw revenue and parent-attributable net-income fields without treating vendor data as an official filing",
    tool.parameters(statement_schema(), statement_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      use outcome <- promise.await(execute(
        provider,
        input,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(value) ->
          tool.text_result(
            statement_text(value),
            statement_json(value, environment.now_milliseconds()),
          )
          |> promise.resolve
      }
    },
  )
  tool.register(
    api,
    "cn_stock_fundamental",
    "CN normalized fundamental",
    "Resolve one exact Eastmoney mainland source field through a visible single-code mapping while preserving the original code, Chinese label, number token, period, attribution, and unknown context",
    "Get revenue or parent-attributable net income without hidden tag precedence or restatement selection",
    tool.parameters(fundamental_schema(), fundamental_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      let FundamentalInput(statement_input, metric) = input
      use outcome <- promise.await(execute(
        provider,
        statement_input,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(statement) ->
          case fundamentals.resolve(statement, metric) {
            Error(error) ->
              tool.reject(
                "CN fundamental did not resolve uniquely: "
                <> string.inspect(error),
              )
            Ok(value) ->
              tool.text_result(
                normalized_text(statement, value),
                normalized_json(
                  statement,
                  value,
                  environment.now_milliseconds(),
                ),
              )
              |> promise.resolve
          }
      }
    },
  )
  tool.register(
    api,
    "cn_stock_fundamental_metric",
    "CN reproducible net margin",
    "Calculate exact net margin from uniquely resolved revenue and parent-attributable net income in one Eastmoney mainland income row; retain both raw leaves, mappings, formula, scale, rounding, assumptions, and unknown filing context",
    "Derive one auditable same-response ratio without cross-period or cross-source joining",
    tool.parameters(metric_schema(), metric_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      let MetricInput(statement_input, scale) = input
      use outcome <- promise.await(execute(
        provider,
        statement_input,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      ))
      case outcome {
        Error(message) -> tool.reject(message)
        Ok(statement) ->
          case fundamentals.net_margin(statement, scale) {
            Error(error) ->
              tool.reject(
                "CN net margin failed closed: " <> string.inspect(error),
              )
            Ok(value) ->
              tool.text_result(
                derived_text(statement, value),
                derived_json(
                  statement,
                  value,
                  scale,
                  environment.now_milliseconds(),
                ),
              )
              |> promise.resolve
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_eastmoney.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "Eastmoney access requires AGENT_CONTACT (for example ops@example.com)",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(value) -> Ready(access, value)
        Error(_) ->
          InvalidConfiguration(
            "Eastmoney bounded runtime could not initialize safely",
          )
      }
  }
}

fn execute(
  provider: Provider,
  input: StatementInput,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(fundamentals.Statement, String)) {
  case provider {
    InvalidConfiguration(reason) -> promise.resolve(Error(reason))
    Ready(access, provider_runtime) -> {
      case
        query.income_statement(
          finance_track.Cn,
          input.market,
          input.code,
          input.report_date,
        )
      {
        Error(_) -> promise.resolve(Error("Invalid explicit CN income query"))
        Ok(plan) ->
          case provider_request.cn_income_statement(access, plan) {
            Error(_) ->
              promise.resolve(Error("Eastmoney CN income request was invalid"))
            Ok(request_value) -> {
              use outcome <- promise.await(runtime.send(
                provider_runtime,
                id,
                request_value,
                cancellation,
              ))
              case checked_body(outcome) {
                Error(message) -> promise.resolve(Error(message))
                Ok(body) ->
                  promise.resolve(
                    fundamentals.decode_cn_income(
                      body,
                      for: plan,
                      declared_currency: input.declared_currency,
                    )
                    |> result.map_error(fn(error) {
                      "Eastmoney returned an invalid or mismatched CN income row: "
                      <> string.inspect(error)
                    }),
                  )
              }
            }
          }
      }
    }
  }
}

fn checked_body(outcome) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "Eastmoney CN income request failed safely: " <> string.inspect(error),
      )
    Ok(response) -> {
      let status = http_response.status(response)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(response))
        False ->
          Error(
            "Eastmoney CN income request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn statement_schema() -> schema.Schema {
  schema.object(statement_properties())
}

fn statement_properties() -> List(schema.Property) {
  [
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required(
      "reportDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "currency",
      schema.string_enum(["CNY", "HKD", "USD"])
        |> schema.described(
          "Presentation currency independently verified from the filing; Eastmoney's mainland row does not prove it",
        ),
    ),
  ]
}

fn fundamental_schema() -> schema.Schema {
  schema.object(
    list.append(statement_properties(), [
      schema.Required(
        "metric",
        schema.string_enum(["revenue", "net_income_attributable_to_parent"]),
      ),
    ]),
  )
}

fn metric_schema() -> schema.Schema {
  schema.object(
    list.append(statement_properties(), [
      schema.Optional(
        "scale",
        schema.integer() |> schema.with_number_range(0.0, 18.0),
      ),
    ]),
  )
}

fn statement_decoder() -> decode.Decoder(StatementInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use currency <- decode.field("currency", decode.string)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case
    market_from_name(venue),
    parse_date(report_date),
    valid_currency(currency)
  {
    Ok(market), Ok(date), True ->
      decode.success(StatementInput(market, code, date, currency))
    _, _, _ ->
      decode.failure(
        StatementInput(query.CnSse, "000001", placeholder, "CNY"),
        "valid CN income statement query",
      )
  }
}

fn fundamental_decoder() -> decode.Decoder(FundamentalInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use currency <- decode.field("currency", decode.string)
  use metric <- decode.field("metric", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  let placeholder =
    FundamentalInput(
      StatementInput(query.CnSse, "000001", placeholder_date, "CNY"),
      fundamentals.Revenue,
    )
  case
    market_from_name(venue),
    parse_date(report_date),
    valid_currency(currency),
    fundamentals.metric_from_name(metric)
  {
    Ok(market), Ok(date), True, Ok(metric) ->
      decode.success(FundamentalInput(
        StatementInput(market, code, date, currency),
        metric,
      ))
    _, _, _, _ -> decode.failure(placeholder, "supported CN fundamental metric")
  }
}

fn metric_decoder() -> decode.Decoder(MetricInput) {
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use currency <- decode.field("currency", decode.string)
  use scale <- decode.optional_field("scale", 6, decode.int)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  case
    market_from_name(venue),
    parse_date(report_date),
    valid_currency(currency)
  {
    Ok(market), Ok(date), True ->
      decode.success(MetricInput(
        StatementInput(market, code, date, currency),
        scale,
      ))
    _, _, _ ->
      decode.failure(
        MetricInput(
          StatementInput(query.CnSse, "000001", placeholder_date, "CNY"),
          6,
        ),
        "valid CN net-margin query",
      )
  }
}

fn market_from_name(value: String) -> Result(query.Market, Nil) {
  case value {
    "sse" -> Ok(query.CnSse)
    "szse" -> Ok(query.CnSzse)
    "bse" -> Ok(query.CnBse)
    _ -> Error(Nil)
  }
}

fn valid_currency(value: String) -> Bool {
  value == "CNY" || value == "HKD" || value == "USD"
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
  }
}

fn result_context(scope: String) -> track_context.Context {
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: scope,
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "zh-CN",
      providers: ["eastmoney"],
      entitlement: "public_web_local_analysis",
      limitations: limitations(),
    )
  value
}

fn limitations() -> List(String) {
  [
    "vendor_origin_not_exchange_filing_evidence",
    "source_document_and_version_identity_unavailable",
    "report_start_accounting_standard_statement_scope_audit_and_restatement_unknown",
    "presentation_currency_is_caller_declared_not_provider_verified",
    "only_revenue_and_parent_attributable_net_income_are_mapped",
    "null_or_absent_values_remain_unavailable_and_are_never_zero",
    "provider_row_may_change_without_preserved_version_history",
    "service_level_licence_and_redistribution_rights_unknown",
    "no_stale_or_generated_fallback",
  ]
}

fn statement_text(value: fundamentals.Statement) -> String {
  "CN track | Eastmoney vendor income slice | "
  <> fundamentals.code(value)
  <> " "
  <> fundamentals.name(value)
  <> " | report end "
  <> fundamentals.report_end(value)
  <> " | "
  <> int.to_string(list.length(fundamentals.facts(value)))
  <> " exact raw facts"
}

fn normalized_text(
  statement: fundamentals.Statement,
  value: fundamentals.Normalized,
) -> String {
  "CN track | normalized "
  <> fundamentals.metric_name(value.mapping.metric)
  <> " | "
  <> fundamentals.code(statement)
  <> " | "
  <> value.fact.raw_value
  <> " declared "
  <> fundamentals.reported_currency(statement)
}

fn derived_text(
  statement: fundamentals.Statement,
  value: fundamentals.Derived,
) -> String {
  "CN track | exact net margin | "
  <> fundamentals.code(statement)
  <> " | "
  <> decimal.to_string(value.calculation.value)
  <> "%"
}

fn statement_json(
  value: fundamentals.Statement,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(common_fields(value, "cn_financial_statement", retrieved_at), [
      #("facts", json.array(fundamentals.facts(value), fact_json)),
    ]),
  )
}

fn normalized_json(
  statement: fundamentals.Statement,
  value: fundamentals.Normalized,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(common_fields(statement, "cn_stock_fundamental", retrieved_at), [
      #("status", json.string("unique")),
      #("metric", json.string(fundamentals.metric_name(value.mapping.metric))),
      #("value", json.string(value.fact.raw_value)),
      #("mapping", mapping_json(value.mapping)),
      #("sourceFact", fact_json(value.fact)),
    ]),
  )
}

fn derived_json(
  statement: fundamentals.Statement,
  value: fundamentals.Derived,
  scale: Int,
  retrieved_at: Int,
) -> json.Json {
  json.object(
    list.append(
      common_fields(statement, "cn_stock_fundamental_metric", retrieved_at),
      [
        #("status", json.string("calculated")),
        #("metric", json.string(value.calculation.name)),
        #("value", json.string(decimal.to_string(value.calculation.value))),
        #("unit", json.string("percentage_points")),
        #("scale", json.int(scale)),
        #("rounding", json.string("half_even")),
        #("method", json.string(value.method)),
        #("formula", formula_json(value.formula)),
        #("inputNames", json.array(value.calculation.input_names, json.string)),
        #(
          "assumptions",
          json.array(value.calculation.assumptions, assumption_json),
        ),
        #(
          "sources",
          json.array([value.net_income, value.revenue], normalized_source_json),
        ),
      ],
    ),
  )
}

fn common_fields(
  value: fundamentals.Statement,
  scope: String,
  retrieved_at: Int,
) -> List(#(String, json.Json)) {
  list.append(track_json.result_fields(result_context(scope)), [
    #("provider", json.string("eastmoney")),
    #("route", json.string("direct")),
    #(
      "providerReportNames",
      json.array(fundamentals.provider_report_names(value), json.string),
    ),
    #("code", json.string(fundamentals.code(value))),
    #("name", json.string(fundamentals.name(value))),
    #("organizationCode", json.string(fundamentals.organization_code(value))),
    #("statement", json.string(fundamentals.statement_name(value))),
    #("reportStart", option_json(fundamentals.report_start(value))),
    #("reportEnd", json.string(fundamentals.report_end(value))),
    #("noticeDate", option_json(fundamentals.notice_date(value))),
    #("reportedCurrency", json.string(fundamentals.reported_currency(value))),
    #(
      "normalizedCurrency",
      option_json(fundamentals.normalized_currency(value)),
    ),
    #(
      "currencyEvidence",
      json.string(
        fundamentals.currency_evidence_name(fundamentals.currency_evidence(
          value,
        )),
      ),
    ),
    #(
      "accountingStandard",
      json.string(fundamentals.accounting_standard(value)),
    ),
    #("statementScope", json.string(fundamentals.statement_scope(value))),
    #("reportType", json.string(fundamentals.report_type(value))),
    #("auditState", json.string(fundamentals.audit_state(value))),
    #("restatementState", json.string(fundamentals.restatement_state(value))),
    #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
    #("entitlement", json.string("public_web_local_analysis")),
    #("redistribution", json.string("unknown")),
    #("limitations", json.array(limitations(), json.string)),
  ])
}

fn fact_json(value: fundamentals.Fact) -> json.Json {
  json.object([
    #("lineCode", json.string(value.line_code)),
    #("originalLabel", json.string(value.original_label)),
    #("rawValue", json.string(value.raw_value)),
    #("reportedUnit", json.string(value.reported_unit)),
  ])
}

fn mapping_json(value: fundamentals.Mapping) -> json.Json {
  json.object([
    #("metric", json.string(fundamentals.metric_name(value.metric))),
    #("acceptedLineCodes", json.array(value.accepted_line_codes, json.string)),
    #("acceptedLabels", json.array(value.accepted_labels, json.string)),
    #("unitKind", json.string(value.unit_kind)),
    #("periodKind", json.string(value.period_kind)),
    #("method", json.string(value.method)),
  ])
}

fn normalized_source_json(value: fundamentals.Normalized) -> json.Json {
  json.object([
    #("name", json.string(fundamentals.metric_name(value.mapping.metric))),
    #("mapping", mapping_json(value.mapping)),
    #("fact", fact_json(value.fact)),
  ])
}

fn assumption_json(value: math_metric.Assumption) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
  ])
}

fn formula_json(value: formula.Formula) -> json.Json {
  case value {
    formula.Literal(value) ->
      json.object([
        #("operation", json.string("literal")),
        #("value", json.string(decimal.to_string(value))),
      ])
    formula.Reference(name) ->
      json.object([
        #("operation", json.string("reference")),
        #("name", json.string(name)),
      ])
    formula.Add(left, right) -> binary_formula_json("add", left, right)
    formula.Subtract(left, right) ->
      binary_formula_json("subtract", left, right)
    formula.Multiply(left, right) ->
      binary_formula_json("multiply", left, right)
    formula.Divide(numerator, denominator, scale, rounding) ->
      json.object([
        #("operation", json.string("divide")),
        #("numerator", formula_json(numerator)),
        #("denominator", formula_json(denominator)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Negate(value) -> unary_formula_json("negate", value)
    formula.Absolute(value) -> unary_formula_json("absolute", value)
    formula.Power(value, exponent) ->
      json.object([
        #("operation", json.string("power")),
        #("value", formula_json(value)),
        #("exponent", json.int(exponent)),
      ])
    formula.Quantize(value, scale, rounding) ->
      json.object([
        #("operation", json.string("quantize")),
        #("value", formula_json(value)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Sum(values) -> aggregate_formula_json("sum", values)
    formula.Mean(values, scale, rounding) ->
      json.object([
        #("operation", json.string("mean")),
        #("values", json.array(values, formula_json)),
        #("scale", json.int(scale)),
        #("rounding", json.string(rounding_name(rounding))),
      ])
    formula.Minimum(values) -> aggregate_formula_json("minimum", values)
    formula.Maximum(values) -> aggregate_formula_json("maximum", values)
  }
}

fn binary_formula_json(operation, left, right) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("left", formula_json(left)),
    #("right", formula_json(right)),
  ])
}

fn unary_formula_json(operation, value) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("value", formula_json(value)),
  ])
}

fn aggregate_formula_json(operation, values) -> json.Json {
  json.object([
    #("operation", json.string(operation)),
    #("values", json.array(values, formula_json)),
  ])
}

fn rounding_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}
