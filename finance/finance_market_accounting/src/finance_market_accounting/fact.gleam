import finance_core/decimal.{type Decimal}
import finance_core/market.{type Unit}
import finance_core/time.{type Date}
import finance_listing/listing.{type Key}
import finance_market_documents/document.{type DocumentId}
import finance_provenance/identity.{type EvidenceId}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

pub type StatementScope {
  Consolidated
  ParentCompany
  OtherScope(String)
}

pub type AuditState {
  Audited
  Reviewed
  Unaudited
  UnknownAuditState
}

pub type RestatementState {
  Original
  Restated
  Corrected
  Superseded
  UnknownRestatementState
}

pub type Period {
  Instant(Date)
  Duration(start: Date, end: Date)
}

pub opaque type Scale {
  Scale(original_label: String, multiplier: Decimal)
}

pub opaque type ReportedValue {
  Numeric(raw_lexeme: String)
  Text(exact_text: String)
  Boolean(Bool)
  Missing(reason: String)
}

/// A lossless public view for codecs and renderers.
///
/// Numeric values remain their exact source token. Consumers that need a
/// decimal must call `normalized_numeric` explicitly.
pub type ReportedValueView {
  NumericValue(raw_lexeme: String)
  TextValue(exact_text: String)
  BooleanValue(Bool)
  MissingValue(reason: String)
}

pub opaque type Fact {
  Fact(
    listing: Key,
    document_id: DocumentId,
    line_code: Option(String),
    original_label: String,
    value: ReportedValue,
    reported_unit: String,
    scale: Scale,
    normalized_unit: Option(Unit),
    accounting_standard: String,
    statement_scope: StatementScope,
    period: Period,
    report_class: String,
    audit_state: AuditState,
    restatement_state: RestatementState,
    evidence_id: EvidenceId,
  )
}

pub type FactError {
  InvalidNumericLexeme
  InvalidText
  InvalidMissingReason
  InvalidScaleLabel
  NonPositiveScaleMultiplier
  InvalidLineCode
  InvalidOriginalLabel
  InvalidReportedUnit
  InvalidAccountingStandard
  InvalidStatementScope
  InvalidPeriod
  InvalidReportClass
}

pub type NormalizationError {
  NonNumericValue
  InvalidStoredNumericLexeme
}

pub fn scale(
  original_label label: String,
  multiplier multiplier_value: Decimal,
) -> Result(Scale, FactError) {
  case
    valid_single_line(label, 100),
    decimal.compare(multiplier_value, decimal.zero())
  {
    False, _ -> Error(InvalidScaleLabel)
    _, Lt -> Error(NonPositiveScaleMultiplier)
    _, Eq -> Error(NonPositiveScaleMultiplier)
    True, Gt -> Ok(Scale(label, multiplier_value))
  }
}

pub fn scale_label(value: Scale) -> String {
  value.original_label
}

pub fn scale_multiplier(value: Scale) -> Decimal {
  value.multiplier
}

pub fn numeric(raw_lexeme: String) -> Result(ReportedValue, FactError) {
  case decimal.parse(raw_lexeme) {
    Ok(_) -> Ok(Numeric(raw_lexeme))
    Error(_) -> Error(InvalidNumericLexeme)
  }
}

pub fn text(exact_text: String) -> Result(ReportedValue, FactError) {
  case exact_text != "" {
    True -> Ok(Text(exact_text))
    False -> Error(InvalidText)
  }
}

pub fn boolean(value: Bool) -> ReportedValue {
  Boolean(value)
}

pub fn missing(reason: String) -> Result(ReportedValue, FactError) {
  case valid_single_line(reason, 500) {
    True -> Ok(Missing(reason))
    False -> Error(InvalidMissingReason)
  }
}

pub fn raw_numeric(value: ReportedValue) -> Option(String) {
  case value {
    Numeric(raw) -> Some(raw)
    Text(_) | Boolean(_) | Missing(_) -> None
  }
}

pub fn exact_text(value: ReportedValue) -> Option(String) {
  case value {
    Text(text) -> Some(text)
    Numeric(_) | Boolean(_) | Missing(_) -> None
  }
}

pub fn reported_value_view(value: ReportedValue) -> ReportedValueView {
  case value {
    Numeric(raw) -> NumericValue(raw)
    Text(text) -> TextValue(text)
    Boolean(value) -> BooleanValue(value)
    Missing(reason) -> MissingValue(reason)
  }
}

pub fn new(
  listing listing_key: Key,
  document_id document: DocumentId,
  line_code line_code_value: Option(String),
  original_label original_label_value: String,
  value reported_value: ReportedValue,
  reported_unit reported_unit_value: String,
  scale reported_scale: Scale,
  normalized_unit normalized_unit_value: Option(Unit),
  accounting_standard standard: String,
  statement_scope scope: StatementScope,
  period reporting_period: Period,
  report_class report_class_value: String,
  audit_state audit: AuditState,
  restatement_state restatement: RestatementState,
  evidence_id evidence: EvidenceId,
) -> Result(Fact, FactError) {
  case
    valid_optional_code(line_code_value),
    valid_single_line(original_label_value, 1000),
    valid_single_line(reported_unit_value, 100),
    valid_single_line(standard, 200),
    valid_scope(scope),
    valid_period(reporting_period),
    valid_token(report_class_value)
  {
    False, _, _, _, _, _, _ -> Error(InvalidLineCode)
    _, False, _, _, _, _, _ -> Error(InvalidOriginalLabel)
    _, _, False, _, _, _, _ -> Error(InvalidReportedUnit)
    _, _, _, False, _, _, _ -> Error(InvalidAccountingStandard)
    _, _, _, _, False, _, _ -> Error(InvalidStatementScope)
    _, _, _, _, _, False, _ -> Error(InvalidPeriod)
    _, _, _, _, _, _, False -> Error(InvalidReportClass)
    True, True, True, True, True, True, True ->
      Ok(Fact(
        listing: listing_key,
        document_id: document,
        line_code: line_code_value,
        original_label: original_label_value,
        value: reported_value,
        reported_unit: reported_unit_value,
        scale: reported_scale,
        normalized_unit: normalized_unit_value,
        accounting_standard: standard,
        statement_scope: scope,
        period: reporting_period,
        report_class: report_class_value,
        audit_state: audit,
        restatement_state: restatement,
        evidence_id: evidence,
      ))
  }
}

pub fn normalized_numeric(value: Fact) -> Result(Decimal, NormalizationError) {
  case value.value {
    Numeric(raw) ->
      case decimal.parse(raw) {
        Ok(parsed) -> Ok(decimal.multiply(parsed, value.scale.multiplier))
        Error(_) -> Error(InvalidStoredNumericLexeme)
      }
    Text(_) | Boolean(_) | Missing(_) -> Error(NonNumericValue)
  }
}

pub fn listing(value: Fact) -> Key {
  value.listing
}

pub fn document_id(value: Fact) -> DocumentId {
  value.document_id
}

pub fn line_code(value: Fact) -> Option(String) {
  value.line_code
}

pub fn original_label(value: Fact) -> String {
  value.original_label
}

pub fn value(value: Fact) -> ReportedValue {
  value.value
}

pub fn reported_unit(value: Fact) -> String {
  value.reported_unit
}

pub fn reported_scale(value: Fact) -> Scale {
  value.scale
}

pub fn normalized_unit(value: Fact) -> Option(Unit) {
  value.normalized_unit
}

pub fn accounting_standard(value: Fact) -> String {
  value.accounting_standard
}

pub fn statement_scope(value: Fact) -> StatementScope {
  value.statement_scope
}

pub fn period(value: Fact) -> Period {
  value.period
}

pub fn report_class(value: Fact) -> String {
  value.report_class
}

pub fn audit_state(value: Fact) -> AuditState {
  value.audit_state
}

pub fn restatement_state(value: Fact) -> RestatementState {
  value.restatement_state
}

pub fn evidence_id(value: Fact) -> EvidenceId {
  value.evidence_id
}

fn valid_optional_code(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(code) -> valid_single_line(code, 200)
  }
}

fn valid_scope(value: StatementScope) -> Bool {
  case value {
    Consolidated | ParentCompany -> True
    OtherScope(name) -> valid_single_line(name, 200)
  }
}

fn valid_period(value: Period) -> Bool {
  case value {
    Instant(_) -> True
    Duration(start, end) -> date_number(start) <= date_number(end)
  }
}

fn valid_token(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_single_line(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
