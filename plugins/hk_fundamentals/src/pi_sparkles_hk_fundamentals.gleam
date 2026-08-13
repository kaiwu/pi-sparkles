import finance_core/decimal
import finance_core/time
import finance_eastmoney
import finance_eastmoney/fundamentals
import finance_eastmoney/query
import finance_eastmoney/request as provider_request
import finance_eastmoney/runtime
import finance_hk_identity/identity
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
import pi_sparkles_hk_fundamentals/effect/environment

pub type StatementInput {
  StatementInput(code: String, report_date: time.Date)
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
    "hk_financial_statement",
    "HK raw income statement slice",
    "Fetch and strictly join one Eastmoney HK report-context record to exact-period income line items; expose exact source number tokens, original standardized codes and Chinese labels, provider-reported currency/standard/type, and every unknown filing context",
    "Inspect a bounded vendor income statement without treating it as HKEX filing evidence",
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
    "hk_stock_fundamental",
    "HK normalized fundamental",
    "Resolve one exact Eastmoney HK standardized line through a visible single-code mapping while preserving its original code, Chinese label, number token, exact duration, attribution, currency, standard, type, and unknown context",
    "Get revenue or shareholder-attributable net income without hidden code precedence or restatement selection",
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
                "HK fundamental did not resolve uniquely: "
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
    "hk_stock_fundamental_metric",
    "HK reproducible net margin",
    "Calculate exact net margin from uniquely resolved revenue and shareholder-attributable net income in one strictly joined Eastmoney HK report context; retain both raw leaves, mappings, formula, scale, rounding, assumptions, period, currency, and standard",
    "Derive one auditable same-context ratio without cross-period or cross-source joining",
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
                "HK net margin failed closed: " <> string.inspect(error),
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
    Ready(access, provider_runtime) ->
      case
        query.income_statement(
          finance_track.Hk,
          query.Hk,
          input.code,
          input.report_date,
        )
      {
        Error(_) -> promise.resolve(Error("Invalid exact HK income query"))
        Ok(plan) ->
          fetch_context(provider_runtime, access, plan, id, cancellation)
      }
  }
}

fn fetch_context(
  provider_runtime,
  access,
  plan,
  id,
  cancellation,
) -> Promise(Result(fundamentals.Statement, String)) {
  case provider_request.hk_income_context(access, plan) {
    Error(_) ->
      promise.resolve(Error("Eastmoney HK report-context request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id <> "-context",
        request_value,
        cancellation,
      ))
      case checked_body(outcome, "report context") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case fundamentals.decode_hk_context(body, for: plan) {
            Error(error) ->
              promise.resolve(Error(
                "Eastmoney returned an invalid or mismatched HK report context: "
                <> string.inspect(error),
              ))
            Ok(context) ->
              fetch_income(
                provider_runtime,
                access,
                plan,
                context,
                id,
                cancellation,
              )
          }
      }
    }
  }
}

fn fetch_income(
  provider_runtime,
  access,
  plan,
  context,
  id,
  cancellation,
) -> Promise(Result(fundamentals.Statement, String)) {
  case provider_request.hk_income_statement(access, plan) {
    Error(_) ->
      promise.resolve(Error("Eastmoney HK income request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id <> "-income",
        request_value,
        cancellation,
      ))
      case checked_body(outcome, "income statement") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          promise.resolve(
            fundamentals.decode_hk_income(body, for: plan, context: context)
            |> result.map_error(fn(error) {
              "Eastmoney returned invalid or incoherent HK income lines: "
              <> string.inspect(error)
            }),
          )
      }
    }
  }
}

fn checked_body(outcome, resource: String) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "Eastmoney HK "
        <> resource
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(response) -> {
      let status = http_response.status(response)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(response))
        False ->
          Error(
            "Eastmoney HK "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn statement_properties() -> List(schema.Property) {
  [
    schema.Required("code", schema.string() |> schema.with_string_length(5, 5)),
    schema.Required(
      "reportDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
  ]
}

fn statement_schema() -> schema.Schema {
  schema.object(statement_properties())
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
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  let assert Ok(placeholder) = time.date(2026, 1, 1)
  case parse_date(report_date) {
    Ok(date) -> decode.success(StatementInput(code, date))
    Error(_) ->
      decode.failure(
        StatementInput("00001", placeholder),
        "valid HK income statement query",
      )
  }
}

fn fundamental_decoder() -> decode.Decoder(FundamentalInput) {
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use metric <- decode.field("metric", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  let placeholder =
    FundamentalInput(
      StatementInput("00001", placeholder_date),
      fundamentals.Revenue,
    )
  case parse_date(report_date), fundamentals.metric_from_name(metric) {
    Ok(date), Ok(metric) ->
      decode.success(FundamentalInput(StatementInput(code, date), metric))
    _, _ -> decode.failure(placeholder, "supported HK fundamental metric")
  }
}

fn metric_decoder() -> decode.Decoder(MetricInput) {
  use code <- decode.field("code", decode.string)
  use report_date <- decode.field("reportDate", decode.string)
  use scale <- decode.optional_field("scale", 6, decode.int)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  case parse_date(report_date) {
    Ok(date) -> decode.success(MetricInput(StatementInput(code, date), scale))
    Error(_) ->
      decode.failure(
        MetricInput(StatementInput("00001", placeholder_date), 6),
        "valid HK net-margin query",
      )
  }
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
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: scope,
      venue_mic: Some(identity.venue_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "zh-HK",
      providers: ["eastmoney"],
      entitlement: "public_web_local_analysis",
      limitations: limitations(),
    )
  value
}

fn limitations() -> List(String) {
  [
    "vendor_origin_not_hkex_filing_evidence",
    "source_document_notice_date_and_version_identity_unavailable",
    "full_statement_scope_audit_and_restatement_unknown",
    "only_revenue_and_shareholder_attributable_net_income_are_mapped",
    "only_numeric_amount_rows_are_exposed_null_amounts_remain_unavailable_and_are_never_zero",
    "provider_context_and_line_contracts_are_strictly_joined_but_may_change",
    "provider_row_may_change_without_preserved_version_history",
    "service_level_licence_and_redistribution_rights_unknown",
    "no_stale_or_generated_fallback",
  ]
}

fn statement_text(value: fundamentals.Statement) -> String {
  "HK track | Eastmoney vendor income slice | "
  <> fundamentals.code(value)
  <> " "
  <> fundamentals.name(value)
  <> " | "
  <> option_text(fundamentals.report_start(value))
  <> " to "
  <> fundamentals.report_end(value)
  <> " | "
  <> int.to_string(list.length(fundamentals.facts(value)))
  <> " exact raw facts"
}

fn normalized_text(
  statement: fundamentals.Statement,
  value: fundamentals.Normalized,
) -> String {
  "HK track | normalized "
  <> fundamentals.metric_name(value.mapping.metric)
  <> " | "
  <> fundamentals.code(statement)
  <> " | "
  <> value.fact.raw_value
  <> " reported "
  <> fundamentals.reported_currency(statement)
}

fn derived_text(
  statement: fundamentals.Statement,
  value: fundamentals.Derived,
) -> String {
  "HK track | exact net margin | "
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
    list.append(common_fields(value, "hk_financial_statement", retrieved_at), [
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
    list.append(common_fields(statement, "hk_stock_fundamental", retrieved_at), [
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
      common_fields(statement, "hk_stock_fundamental_metric", retrieved_at),
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
    #("route", json.string("direct_joined_context_and_lines")),
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

fn option_text(value: Option(String)) -> String {
  case value {
    Some(value) -> value
    None -> "unknown start"
  }
}
