import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time.{type Date, type Instant, type Timezone}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_track.{type Track}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type UnitFact {
  KnownUnit(label: String)
  UnknownUnit(reason: String)
}

pub type InputBasis {
  Raw
  SplitAdjusted(factor_roots: List(EvidenceId))
  DividendAdjusted(factor_roots: List(EvidenceId))
  TotalReturn(factor_roots: List(EvidenceId))
  ProviderDefined(label: String, factor_roots: List(EvidenceId))
  LlmProjection(
    name: String,
    instruction_ref: Sha256,
    evidence_roots: List(EvidenceId),
  )
}

pub type WindowVariant {
  SlotWindowV1
}

pub type GapPolicy {
  StopAtGapV1
  RestartSeedAfterGapV1
}

pub type ParseablePolicy {
  IncludeParseableWithChecks
  ExcludeParseableWithChecks
}

pub type RoundingPolicy {
  PerStep
  FinalOnly
}

pub type RoundingSpec {
  RoundingSpec(
    output_scale: Int,
    rounding_mode: RoundingMode,
    rounding_policy: RoundingPolicy,
    intermediate_scale: Int,
  )
}

pub type RsiZeroZeroConvention {
  ZeroZeroUnperformedV1
  ZeroZeroValueV1(value: Decimal)
}

pub type CalculationSpec {
  SmaV1(period: Int, window: WindowVariant)
  WilderRsiV1(
    period: Int,
    window: WindowVariant,
    gap_policy: GapPolicy,
    zero_zero: RsiZeroZeroConvention,
  )
  WilderAtrV1(period: Int, window: WindowVariant, gap_policy: GapPolicy)
}

pub type SummaryField {
  LatestValue
  PriorValue(offset: Int)
  AbsoluteChange
  PercentChange
}

pub opaque type SourceLeg {
  SourceLeg(
    provider: String,
    source_reference: String,
    acquisition_receipt: Sha256,
    retrieval_time: Instant,
  )
}

pub opaque type Context {
  Context(
    track: Track,
    instrument_id: String,
    mic: String,
    timezone: Timezone,
    date_start: Date,
    date_end: Date,
    source_leg: SourceLeg,
    source_cutoff: Option(Instant),
    input_field: String,
    input_unit: UnitFact,
    adjustment_basis: InputBasis,
    retained_alternatives: List(String),
    gap_facts: List(String),
    evidence_roots: List(EvidenceId),
  )
}

pub opaque type Request {
  Request(
    instruction_ref: Sha256,
    context: Context,
    calculation: CalculationSpec,
    parseable_policy: ParseablePolicy,
    rounding: RoundingSpec,
    summary_fields: List(SummaryField),
  )
}

pub type RequestError {
  InvalidText(field: String)
  InvalidDateRange
  InvalidPeriod
  InvalidScale
  UnsupportedRoundingPolicy
  InvalidSummaryOffset
}

pub fn source_leg(
  provider provider_value: String,
  source_reference reference_value: String,
  acquisition_receipt receipt_value: Sha256,
  retrieval_time retrieval_value: Instant,
) -> Result(SourceLeg, RequestError) {
  case valid_text(provider_value), valid_text(reference_value) {
    False, _ -> Error(InvalidText("provider"))
    _, False -> Error(InvalidText("source_reference"))
    True, True ->
      Ok(SourceLeg(
        provider_value,
        reference_value,
        receipt_value,
        retrieval_value,
      ))
  }
}

pub fn context(
  track track_value: Track,
  instrument_id instrument_value: String,
  mic mic_value: String,
  timezone timezone_value: Timezone,
  date_start start_value: Date,
  date_end end_value: Date,
  source_leg source_value: SourceLeg,
  source_cutoff cutoff_value: Option(Instant),
  input_field field_value: String,
  input_unit unit_value: UnitFact,
  adjustment_basis basis_value: InputBasis,
  retained_alternatives alternative_values: List(String),
  gap_facts gap_values: List(String),
  evidence_roots root_values: List(EvidenceId),
) -> Result(Context, RequestError) {
  use _ <- result.try(validate_context_text(
    instrument_value,
    mic_value,
    field_value,
    unit_value,
    basis_value,
  ))
  case date_key(start_value) <= date_key(end_value) {
    False -> Error(InvalidDateRange)
    True ->
      Ok(Context(
        track_value,
        instrument_value,
        mic_value,
        timezone_value,
        start_value,
        end_value,
        source_value,
        cutoff_value,
        field_value,
        unit_value,
        basis_value,
        alternative_values,
        gap_values,
        root_values,
      ))
  }
}

pub fn request(
  instruction_ref instruction_value: Sha256,
  context context_value: Context,
  calculation calculation_value: CalculationSpec,
  parseable_policy parseable_value: ParseablePolicy,
  rounding rounding_value: RoundingSpec,
  summary_fields summary_values: List(SummaryField),
) -> Result(Request, RequestError) {
  use _ <- result.try(validate_calculation(calculation_value))
  use _ <- result.try(validate_rounding(rounding_value))
  use _ <- result.try(validate_summary_fields(summary_values))
  Ok(Request(
    instruction_value,
    context_value,
    calculation_value,
    parseable_value,
    rounding_value,
    summary_values,
  ))
}

pub fn instruction_ref(value: Request) -> Sha256 {
  value.instruction_ref
}

pub fn request_context(value: Request) -> Context {
  value.context
}

pub fn calculation(value: Request) -> CalculationSpec {
  value.calculation
}

pub fn parseable_policy(value: Request) -> ParseablePolicy {
  value.parseable_policy
}

pub fn rounding(value: Request) -> RoundingSpec {
  value.rounding
}

pub fn summary_fields(value: Request) -> List(SummaryField) {
  value.summary_fields
}

pub fn context_track(value: Context) -> Track {
  value.track
}

pub fn instrument_id(value: Context) -> String {
  value.instrument_id
}

pub fn mic(value: Context) -> String {
  value.mic
}

pub fn timezone(value: Context) -> Timezone {
  value.timezone
}

pub fn date_start(value: Context) -> Date {
  value.date_start
}

pub fn date_end(value: Context) -> Date {
  value.date_end
}

pub fn context_source_leg(value: Context) -> SourceLeg {
  value.source_leg
}

pub fn source_cutoff(value: Context) -> Option(Instant) {
  value.source_cutoff
}

pub fn input_field(value: Context) -> String {
  value.input_field
}

pub fn input_unit(value: Context) -> UnitFact {
  value.input_unit
}

pub fn adjustment_basis(value: Context) -> InputBasis {
  value.adjustment_basis
}

pub fn retained_alternatives(value: Context) -> List(String) {
  value.retained_alternatives
}

pub fn gap_facts(value: Context) -> List(String) {
  value.gap_facts
}

pub fn evidence_roots(value: Context) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn source_provider(value: SourceLeg) -> String {
  value.provider
}

pub fn source_reference(value: SourceLeg) -> String {
  value.source_reference
}

pub fn acquisition_receipt(value: SourceLeg) -> Sha256 {
  value.acquisition_receipt
}

pub fn retrieval_time(value: SourceLeg) -> Instant {
  value.retrieval_time
}

pub fn calculation_id(value: CalculationSpec) -> String {
  case value {
    SmaV1(_, _) -> "sma_v1"
    WilderRsiV1(_, _, _, _) -> "rsi_wilder_v1"
    WilderAtrV1(_, _, _) -> "atr_wilder_v1"
  }
}

pub fn formula_variant(value: CalculationSpec) -> String {
  calculation_id(value)
}

pub fn period(value: CalculationSpec) -> Int {
  case value {
    SmaV1(period, _)
    | WilderRsiV1(period, _, _, _)
    | WilderAtrV1(period, _, _) -> period
  }
}

pub fn window_variant(value: CalculationSpec) -> WindowVariant {
  case value {
    SmaV1(_, window)
    | WilderRsiV1(_, window, _, _)
    | WilderAtrV1(_, window, _) -> window
  }
}

pub fn gap_policy(value: CalculationSpec) -> Option(GapPolicy) {
  case value {
    SmaV1(_, _) -> None
    WilderRsiV1(_, _, policy, _) | WilderAtrV1(_, _, policy) -> Some(policy)
  }
}

pub fn zero_zero_convention(
  value: CalculationSpec,
) -> Option(RsiZeroZeroConvention) {
  case value {
    WilderRsiV1(_, _, _, convention) -> Some(convention)
    SmaV1(_, _) | WilderAtrV1(_, _, _) -> None
  }
}

pub fn output_scale(value: RoundingSpec) -> Int {
  value.output_scale
}

pub fn rounding_mode(value: RoundingSpec) -> RoundingMode {
  value.rounding_mode
}

pub fn rounding_policy(value: RoundingSpec) -> RoundingPolicy {
  value.rounding_policy
}

pub fn intermediate_scale(value: RoundingSpec) -> Int {
  value.intermediate_scale
}

pub fn window_variant_name(value: WindowVariant) -> String {
  case value {
    SlotWindowV1 -> "slot_window_v1"
  }
}

pub fn gap_policy_name(value: GapPolicy) -> String {
  case value {
    StopAtGapV1 -> "stop_at_gap_v1"
    RestartSeedAfterGapV1 -> "restart_seed_after_gap_v1"
  }
}

pub fn parseable_policy_name(value: ParseablePolicy) -> String {
  case value {
    IncludeParseableWithChecks -> "include_parseable_with_checks"
    ExcludeParseableWithChecks -> "exclude_parseable_with_checks"
  }
}

pub fn rounding_policy_name(value: RoundingPolicy) -> String {
  case value {
    PerStep -> "per_step"
    FinalOnly -> "final_only"
  }
}

pub fn unit_name(value: UnitFact) -> String {
  case value {
    KnownUnit(label) -> label
    UnknownUnit(_) -> "unknown"
  }
}

pub fn date_key(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}

fn validate_context_text(
  instrument: String,
  mic: String,
  field: String,
  unit: UnitFact,
  basis: InputBasis,
) -> Result(Nil, RequestError) {
  case valid_text(instrument), valid_text(mic), valid_text(field) {
    False, _, _ -> Error(InvalidText("instrument_id"))
    _, False, _ -> Error(InvalidText("mic"))
    _, _, False -> Error(InvalidText("input_field"))
    True, True, True -> {
      use _ <- result.try(validate_unit(unit))
      validate_basis(basis)
    }
  }
}

fn validate_unit(value: UnitFact) -> Result(Nil, RequestError) {
  case value {
    KnownUnit(label) ->
      case valid_text(label) {
        True -> Ok(Nil)
        False -> Error(InvalidText("input_unit"))
      }
    UnknownUnit(reason) ->
      case valid_text(reason) {
        True -> Ok(Nil)
        False -> Error(InvalidText("input_unit_reason"))
      }
  }
}

fn validate_basis(value: InputBasis) -> Result(Nil, RequestError) {
  case value {
    ProviderDefined(label, _) ->
      case valid_text(label) {
        True -> Ok(Nil)
        False -> Error(InvalidText("provider_basis"))
      }
    LlmProjection(name, _, _) ->
      case valid_text(name) {
        True -> Ok(Nil)
        False -> Error(InvalidText("projection_name"))
      }
    Raw | SplitAdjusted(_) | DividendAdjusted(_) | TotalReturn(_) -> Ok(Nil)
  }
}

fn validate_calculation(value: CalculationSpec) -> Result(Nil, RequestError) {
  case period(value) > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidPeriod)
  }
}

fn validate_rounding(value: RoundingSpec) -> Result(Nil, RequestError) {
  case value.rounding_policy {
    FinalOnly -> Error(UnsupportedRoundingPolicy)
    PerStep ->
      case
        value.output_scale >= 0
        && value.intermediate_scale >= value.output_scale
      {
        True -> Ok(Nil)
        False -> Error(InvalidScale)
      }
  }
}

fn validate_summary_fields(
  values: List(SummaryField),
) -> Result(Nil, RequestError) {
  case
    list.any(values, fn(value) {
      case value {
        PriorValue(offset) -> offset <= 0
        LatestValue | AbsoluteChange | PercentChange -> False
      }
    })
  {
    True -> Error(InvalidSummaryOffset)
    False -> Ok(Nil)
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
