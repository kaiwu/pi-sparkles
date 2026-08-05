import finance_core/decimal
import finance_core/time
import finance_eastmoney/query
import finance_math/error
import finance_math/formula
import finance_math/metric as math_metric
import finance_math/metrics
import finance_track
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const cn_income_report_name = "RPT_DMSK_FN_INCOME"

pub const hk_income_context_report_name = "RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY"

pub const hk_income_report_name = "RPT_HKF10_FN_INCOME_PC"

pub type CurrencyEvidence {
  CallerDeclared
  ProviderReported
}

pub type Fact {
  Fact(
    line_code: String,
    original_label: String,
    raw_value: String,
    reported_unit: String,
  )
}

pub opaque type Statement {
  Statement(
    track: finance_track.Track,
    code: String,
    name: String,
    organization_code: String,
    statement_name: String,
    report_start: Option(String),
    report_end: String,
    notice_date: Option(String),
    reported_currency: String,
    normalized_currency: Option(String),
    currency_evidence: CurrencyEvidence,
    accounting_standard: String,
    statement_scope: String,
    report_type: String,
    audit_state: String,
    restatement_state: String,
    facts: List(Fact),
    provider_report_names: List(String),
  )
}

pub type Metric {
  Revenue
  NetIncomeAttributableToParent
}

pub type Mapping {
  Mapping(
    metric: Metric,
    accepted_line_codes: List(String),
    accepted_labels: List(String),
    unit_kind: String,
    period_kind: String,
    method: String,
  )
}

pub type Normalized {
  Normalized(mapping: Mapping, fact: Fact)
}

pub type Derived {
  Derived(
    calculation: math_metric.Metric,
    formula: formula.Formula,
    revenue: Normalized,
    net_income: Normalized,
    method: String,
  )
}

type CnRow {
  CnRow(
    code: String,
    name: String,
    organization_code: String,
    date_type_code: String,
    report_type_code: String,
    data_state: String,
    notice_date: String,
    report_date: String,
    revenue: Option(String),
    net_income: Option(String),
  )
}

type HkContextEnvelope {
  HkContextEnvelope(records: List(HkContext))
}

pub opaque type HkContext {
  HkContext(
    code: String,
    name: String,
    start_date: String,
    report_date: String,
    fiscal_year: String,
    currency: String,
    accounting_standard: String,
    report_type: String,
  )
}

type HkRow {
  HkRow(
    code: String,
    name: String,
    organization_code: String,
    report_date: String,
    date_type_code: String,
    fiscal_year: String,
    start_date: String,
    line_code: String,
    label: String,
    amount: Option(String),
  )
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  WrongTrack
  EmptyResult
  TooManyRows(maximum: Int, received: Int)
  CodeMismatch(expected: String, received: String)
  ReportDateMismatch(expected: String, received: String)
  ContextMismatch
}

pub type NormalizeError {
  MissingMetric(metric: Metric)
  AmbiguousMetric(metric: Metric, count: Int)
}

pub type DeriveError {
  NormalizationFailed(NormalizeError)
  InvalidNumericSource(metric: Metric)
  CalculationFailed(error.MetricError)
}

pub fn decode_cn_income(
  body: String,
  for plan: query.IncomeQuery,
  declared_currency declared_currency: String,
) -> Result(Statement, DecodeError) {
  case query.income_track(plan) {
    finance_track.Cn -> {
      use rows <- result.try(
        body
        |> normalize_numbers
        |> json.parse(cn_payload_decoder())
        |> result.map_error(InvalidJson),
      )
      case rows {
        [] -> Error(EmptyResult)
        [row] -> cn_statement(row, plan, declared_currency)
        values -> Error(TooManyRows(1, list.length(values)))
      }
    }
    _ -> Error(WrongTrack)
  }
}

pub fn decode_hk_context(
  body: String,
  for plan: query.IncomeQuery,
) -> Result(HkContext, DecodeError) {
  case query.income_track(plan) {
    finance_track.Hk -> {
      use envelope <- result.try(
        body
        |> normalize_numbers
        |> json.parse(hk_context_payload_decoder())
        |> result.map_error(InvalidJson),
      )
      let expected_date = date_text(query.income_report_date(plan))
      let matches =
        envelope.records
        |> list.filter(fn(value) {
          value.code == query.income_code(plan)
          && date_prefix(value.report_date) == expected_date
        })
      case matches {
        [] -> Error(EmptyResult)
        [value] -> Ok(value)
        values -> Error(TooManyRows(1, list.length(values)))
      }
    }
    _ -> Error(WrongTrack)
  }
}

pub fn decode_hk_income(
  body: String,
  for plan: query.IncomeQuery,
  context context: HkContext,
) -> Result(Statement, DecodeError) {
  case query.income_track(plan) {
    finance_track.Hk -> {
      use rows <- result.try(
        body
        |> normalize_numbers
        |> json.parse(hk_rows_payload_decoder())
        |> result.map_error(InvalidJson),
      )
      case rows {
        [] -> Error(EmptyResult)
        [first, ..] ->
          case list.length(rows) > 200 {
            True -> Error(TooManyRows(200, list.length(rows)))
            False -> hk_statement(first, rows, plan, context)
          }
      }
    }
    _ -> Error(WrongTrack)
  }
}

pub fn metric_from_name(value: String) -> Result(Metric, Nil) {
  case value {
    "revenue" -> Ok(Revenue)
    "net_income_attributable_to_parent" -> Ok(NetIncomeAttributableToParent)
    _ -> Error(Nil)
  }
}

pub fn metric_name(value: Metric) -> String {
  case value {
    Revenue -> "revenue"
    NetIncomeAttributableToParent -> "net_income_attributable_to_parent"
  }
}

pub fn mapping(track: finance_track.Track, metric: Metric) -> Mapping {
  case track, metric {
    finance_track.Cn, Revenue ->
      Mapping(
        metric,
        ["TOTAL_OPERATE_INCOME"],
        ["营业总收入"],
        "presentation_currency",
        "duration_start_unknown",
        "exact Eastmoney mainland income-row field; no alternative-code precedence",
      )
    finance_track.Cn, NetIncomeAttributableToParent ->
      Mapping(
        metric,
        ["PARENT_NETPROFIT"],
        ["归属于母公司股东的净利润"],
        "presentation_currency",
        "provider_report_period_duration",
        "exact Eastmoney mainland parent-attributable field; attribution is not collapsed into generic profit",
      )
    finance_track.Hk, Revenue ->
      Mapping(
        metric,
        ["004001001"],
        ["营业额"],
        "presentation_currency",
        "exact_duration",
        "exact Eastmoney HK standardized income line; no alternative-code precedence",
      )
    finance_track.Hk, NetIncomeAttributableToParent ->
      Mapping(
        metric,
        ["004025002"],
        ["股东应占溢利"],
        "presentation_currency",
        "exact_duration",
        "exact Eastmoney HK standardized parent-attributable line; attribution is retained",
      )
    finance_track.Us, Revenue
    | finance_track.Us, NetIncomeAttributableToParent
    ->
      Mapping(
        metric,
        ["unsupported_us_track"],
        ["unsupported US track"],
        "unsupported",
        "unsupported",
        "Eastmoney CN/HK mapping is intentionally unavailable on the US track",
      )
  }
}

pub fn resolve(
  statement: Statement,
  metric metric: Metric,
) -> Result(Normalized, NormalizeError) {
  let definition = mapping(statement.track, metric)
  let matches =
    statement.facts
    |> list.filter(fn(value) {
      list.contains(definition.accepted_line_codes, value.line_code)
    })
  case matches {
    [] -> Error(MissingMetric(metric))
    [value] -> Ok(Normalized(definition, value))
    values -> Error(AmbiguousMetric(metric, list.length(values)))
  }
}

pub fn net_margin(
  statement: Statement,
  scale scale: Int,
) -> Result(Derived, DeriveError) {
  use revenue <- result.try(
    resolve(statement, Revenue) |> result.map_error(NormalizationFailed),
  )
  use net_income <- result.try(
    resolve(statement, NetIncomeAttributableToParent)
    |> result.map_error(NormalizationFailed),
  )
  use revenue_value <- result.try(
    decimal.parse(revenue.fact.raw_value)
    |> result.map_error(fn(_) { InvalidNumericSource(Revenue) }),
  )
  use net_income_value <- result.try(
    decimal.parse(net_income.fact.raw_value)
    |> result.map_error(fn(_) {
      InvalidNumericSource(NetIncomeAttributableToParent)
    }),
  )
  let expression =
    metrics.percentage(
      formula.Reference("net_income_attributable_to_parent"),
      formula.Reference("revenue"),
      scale,
      decimal.HalfEven,
    )
  use definition <- result.try(
    math_metric.define(
      name: "net_margin",
      unit: math_metric.PercentagePoints,
      formula: expression,
      assumptions: [
        math_metric.Assumption(
          "coherence",
          "both exact source leaves come from one provider income-statement response and one report context",
        ),
        math_metric.Assumption("numerator", "parent-attributable net income"),
        math_metric.Assumption("rounding", "half_even"),
        math_metric.Assumption("scale", int.to_string(scale)),
      ],
    )
    |> result.map_error(CalculationFailed),
  )
  use calculation <- result.try(
    math_metric.calculate(definition, [
      formula.Input(
        "net_income_attributable_to_parent",
        formula.Available(net_income_value),
      ),
      formula.Input("revenue", formula.Available(revenue_value)),
    ])
    |> result.map_error(CalculationFailed),
  )
  Ok(Derived(
    calculation,
    expression,
    revenue,
    net_income,
    "100 * parent-attributable net income / revenue; exact decimal arithmetic, caller-selected scale, half-even rounding",
  ))
}

pub fn track(value: Statement) -> finance_track.Track {
  value.track
}

pub fn code(value: Statement) -> String {
  value.code
}

pub fn name(value: Statement) -> String {
  value.name
}

pub fn organization_code(value: Statement) -> String {
  value.organization_code
}

pub fn statement_name(value: Statement) -> String {
  value.statement_name
}

pub fn report_start(value: Statement) -> Option(String) {
  value.report_start
}

pub fn report_end(value: Statement) -> String {
  value.report_end
}

pub fn notice_date(value: Statement) -> Option(String) {
  value.notice_date
}

pub fn reported_currency(value: Statement) -> String {
  value.reported_currency
}

pub fn normalized_currency(value: Statement) -> Option(String) {
  value.normalized_currency
}

pub fn currency_evidence(value: Statement) -> CurrencyEvidence {
  value.currency_evidence
}

pub fn accounting_standard(value: Statement) -> String {
  value.accounting_standard
}

pub fn statement_scope(value: Statement) -> String {
  value.statement_scope
}

pub fn report_type(value: Statement) -> String {
  value.report_type
}

pub fn audit_state(value: Statement) -> String {
  value.audit_state
}

pub fn restatement_state(value: Statement) -> String {
  value.restatement_state
}

pub fn facts(value: Statement) -> List(Fact) {
  value.facts
}

pub fn provider_report_names(value: Statement) -> List(String) {
  value.provider_report_names
}

pub fn currency_evidence_name(value: CurrencyEvidence) -> String {
  case value {
    CallerDeclared -> "caller_declared_not_provider_verified"
    ProviderReported -> "provider_reported"
  }
}

fn cn_statement(
  row: CnRow,
  plan: query.IncomeQuery,
  declared_currency: String,
) -> Result(Statement, DecodeError) {
  let expected_code = query.income_code(plan)
  let expected_date = date_text(query.income_report_date(plan))
  case
    row.code == expected_code,
    date_prefix(row.report_date) == expected_date
  {
    False, _ -> Error(CodeMismatch(expected_code, row.code))
    _, False -> Error(ReportDateMismatch(expected_date, row.report_date))
    True, True ->
      Ok(
        Statement(
          track: finance_track.Cn,
          code: row.code,
          name: row.name,
          organization_code: row.organization_code,
          statement_name: "income",
          report_start: None,
          report_end: expected_date,
          notice_date: Some(row.notice_date),
          reported_currency: declared_currency,
          normalized_currency: Some(declared_currency),
          currency_evidence: CallerDeclared,
          accounting_standard: "unknown",
          statement_scope: "provider_row_scope_unknown; net-income attribution is parent",
          report_type: "date_type_code="
            <> row.date_type_code
            <> ";report_type_code="
            <> row.report_type_code
            <> ";data_state="
            <> row.data_state,
          audit_state: "unknown",
          restatement_state: "unknown",
          facts: optional_facts([
            optional_fact(
              "TOTAL_OPERATE_INCOME",
              "营业总收入",
              row.revenue,
              declared_currency,
            ),
            optional_fact(
              "PARENT_NETPROFIT",
              "归属于母公司股东的净利润",
              row.net_income,
              declared_currency,
            ),
          ]),
          provider_report_names: [cn_income_report_name],
        ),
      )
  }
}

fn hk_statement(
  first: HkRow,
  rows: List(HkRow),
  plan: query.IncomeQuery,
  context: HkContext,
) -> Result(Statement, DecodeError) {
  let expected_code = query.income_code(plan)
  let expected_date = date_text(query.income_report_date(plan))
  let coherent =
    rows
    |> list.all(fn(value) {
      value.code == expected_code
      && value.name == first.name
      && value.organization_code == first.organization_code
      && date_prefix(value.report_date) == expected_date
      && value.date_type_code == first.date_type_code
      && value.fiscal_year == first.fiscal_year
      && value.start_date == first.start_date
    })
  case
    first.code == expected_code,
    date_prefix(first.report_date) == expected_date,
    context.code == expected_code
    && context.name == first.name
    && context.start_date == first.start_date
    && date_prefix(context.report_date) == expected_date
    && context.fiscal_year == first.fiscal_year,
    coherent
  {
    False, _, _, _ -> Error(CodeMismatch(expected_code, first.code))
    _, False, _, _ ->
      Error(ReportDateMismatch(expected_date, first.report_date))
    _, _, False, _ | _, _, _, False -> Error(ContextMismatch)
    True, True, True, True ->
      Ok(
        Statement(
          track: finance_track.Hk,
          code: first.code,
          name: first.name,
          organization_code: first.organization_code,
          statement_name: "income",
          report_start: Some(date_prefix(first.start_date)),
          report_end: expected_date,
          notice_date: None,
          reported_currency: context.currency,
          normalized_currency: normalize_reported_currency(context.currency),
          currency_evidence: ProviderReported,
          accounting_standard: context.accounting_standard,
          statement_scope: "provider_standardized_line_scope_unknown; net-income attribution is owners/shareholders",
          report_type: context.report_type
            <> ";date_type_code="
            <> first.date_type_code,
          audit_state: "unknown",
          restatement_state: "unknown",
          facts: rows
            |> list.filter_map(fn(value) {
              case value.amount {
                Some(amount) ->
                  Ok(Fact(
                    value.line_code,
                    value.label,
                    amount,
                    hk_reported_unit(value.line_code, context.currency),
                  ))
                None -> Error(Nil)
              }
            }),
          provider_report_names: [
            hk_income_context_report_name,
            hk_income_report_name,
          ],
        ),
      )
  }
}

fn cn_payload_decoder() -> decode.Decoder(List(CnRow)) {
  use success <- decode.field("success", decode.bool)
  use rows <- decode.field("result", cn_result_decoder())
  case success {
    True -> decode.success(rows)
    False ->
      decode.failure(rows, "successful Eastmoney mainland income response")
  }
}

fn cn_result_decoder() -> decode.Decoder(List(CnRow)) {
  use rows <- decode.field("data", decode.list(of: cn_row_decoder()))
  decode.success(rows)
}

fn cn_row_decoder() -> decode.Decoder(CnRow) {
  use code <- decode.field("SECURITY_CODE", decode.string)
  use name <- decode.field("SECURITY_NAME_ABBR", decode.string)
  use organization_code <- decode.field("ORG_CODE", decode.string)
  use date_type_code <- decode.field("DATE_TYPE_CODE", decode.string)
  use report_type_code <- decode.field("REPORT_TYPE_CODE", decode.string)
  use data_state <- decode.field("DATA_STATE", decode.string)
  use notice_date <- decode.field("NOTICE_DATE", decode.string)
  use report_date <- decode.field("REPORT_DATE", decode.string)
  use revenue <- optional_number_field("TOTAL_OPERATE_INCOME")
  use net_income <- optional_number_field("PARENT_NETPROFIT")
  decode.success(CnRow(
    code,
    name,
    organization_code,
    date_type_code,
    report_type_code,
    data_state,
    notice_date,
    report_date,
    revenue,
    net_income,
  ))
}

fn hk_context_payload_decoder() -> decode.Decoder(HkContextEnvelope) {
  use success <- decode.field("success", decode.bool)
  use values <- decode.field("result", hk_context_result_decoder())
  let records = values |> list.flatten
  case success, list.length(values) <= 1, list.length(records) <= 200 {
    True, True, True -> decode.success(HkContextEnvelope(records))
    _, _, _ ->
      decode.failure(
        HkContextEnvelope([]),
        "bounded successful Eastmoney HK report context response",
      )
  }
}

fn hk_context_result_decoder() -> decode.Decoder(List(List(HkContext))) {
  use values <- decode.field(
    "data",
    decode.list(of: hk_context_envelope_decoder()),
  )
  decode.success(values)
}

fn hk_context_envelope_decoder() -> decode.Decoder(List(HkContext)) {
  use values <- decode.field(
    "REPORT_LIST",
    decode.list(of: hk_context_decoder()),
  )
  decode.success(values)
}

fn hk_context_decoder() -> decode.Decoder(HkContext) {
  use code <- decode.field("SECURITY_CODE", decode.string)
  use name <- decode.field("SECURITY_NAME_ABBR", decode.string)
  use start_date <- decode.field("START_DATE", decode.string)
  use report_date <- decode.field("REPORT_DATE", decode.string)
  use fiscal_year <- decode.field("FISCAL_YEAR", decode.string)
  use currency <- decode.field("CURRENCY", decode.string)
  use accounting_standard <- decode.field("ACCOUNT_STANDARD", decode.string)
  use report_type <- decode.field("REPORT_TYPE", decode.string)
  decode.success(HkContext(
    code,
    name,
    start_date,
    report_date,
    fiscal_year,
    currency,
    accounting_standard,
    report_type,
  ))
}

fn hk_rows_payload_decoder() -> decode.Decoder(List(HkRow)) {
  use success <- decode.field("success", decode.bool)
  use rows <- decode.field("result", hk_rows_result_decoder())
  case success {
    True -> decode.success(rows)
    False -> decode.failure(rows, "successful Eastmoney HK income response")
  }
}

fn hk_rows_result_decoder() -> decode.Decoder(List(HkRow)) {
  use rows <- decode.field("data", decode.list(of: hk_row_decoder()))
  decode.success(rows)
}

fn hk_row_decoder() -> decode.Decoder(HkRow) {
  use code <- decode.field("SECURITY_CODE", decode.string)
  use name <- decode.field("SECURITY_NAME_ABBR", decode.string)
  use organization_code <- decode.field("ORG_CODE", decode.string)
  use report_date <- decode.field("REPORT_DATE", decode.string)
  use date_type_code <- decode.field("DATE_TYPE_CODE", decode.string)
  use fiscal_year <- decode.field("FISCAL_YEAR", decode.string)
  use start_date <- decode.field("START_DATE", decode.string)
  use line_code <- decode.field("STD_ITEM_CODE", decode.string)
  use label <- decode.field("STD_ITEM_NAME", decode.string)
  use amount <- optional_number_field("AMOUNT")
  decode.success(HkRow(
    code,
    name,
    organization_code,
    report_date,
    date_type_code,
    fiscal_year,
    start_date,
    line_code,
    label,
    amount,
  ))
}

fn optional_number_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(number_decoder()), next)
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_eastmoney_number__"], decode.string)
}

fn optional_fact(
  code: String,
  label: String,
  value: Option(String),
  unit: String,
) -> Option(Fact) {
  case value {
    Some(raw) -> Some(Fact(code, label, raw, unit))
    None -> None
  }
}

fn optional_facts(values: List(Option(Fact))) -> List(Fact) {
  values
  |> list.filter_map(fn(value) {
    case value {
      Some(value) -> Ok(value)
      None -> Error(Nil)
    }
  })
}

fn normalize_reported_currency(value: String) -> Option(String) {
  case value {
    "人民币" | "CNY" -> Some("CNY")
    "港币" | "港元" | "HKD" -> Some("HKD")
    "美元" | "USD" -> Some("USD")
    _ -> None
  }
}

fn hk_reported_unit(line_code: String, currency: String) -> String {
  case line_code {
    "004001001" | "004025002" -> currency
    _ -> "unknown_not_supplied_by_endpoint"
  }
}

fn date_prefix(value: String) -> String {
  string.slice(value, at_index: 0, length: 10)
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

@external(javascript, "./fundamentals_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
