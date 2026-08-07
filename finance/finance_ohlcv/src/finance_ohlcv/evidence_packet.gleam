import finance_core/adjustment.{type Adjustment}
import finance_core/currency.{type Currency}
import finance_core/time.{type Date}
import finance_ohlcv/acquisition_attempt.{type Attempt}
import finance_ohlcv/fact.{type Fact}
import finance_ohlcv/quantity.{type QuantityFacts}
import finance_ohlcv/reported_row.{type RowFacts}
import finance_ohlcv/rights.{type RightsFacts}
import finance_ohlcv/timing.{type TimingFacts}
import finance_track.{type Track}

pub type VenueState {
  Open
  Closed
}

pub type SecurityStatus {
  Trading
  Suspended
  NonTrading
}

pub type QualityFact {
  Reported
  Estimated
  Revised
  Corrected
  Restated
  CallerDeclared
}

pub type AvailableOperation {
  DrillField
  DrillProvenance
  DrillGaps
  DrillTiming
  DrillRights
  DrillAdjustmentFactors
  CompareTiming
  RequestCalculation
  RequestMoreBars
  OtherOperation(name: String)
}

pub opaque type EvidenceRoot {
  EvidenceRoot(name: String, reference: String)
}

pub opaque type IdentityFacts {
  IdentityFacts(
    track: Track,
    instrument_id: Fact(String),
    symbol: Fact(String),
    mic: Fact(String),
    currency: Fact(Currency),
    evidence_root: Fact(String),
  )
}

pub opaque type SessionFacts {
  SessionFacts(
    session_date: Date,
    venue_state: Fact(VenueState),
    listing_effective: Fact(Bool),
    security_status: Fact(SecurityStatus),
    descriptive_classification: Fact(String),
    classification_rule: Fact(String),
  )
}

/// A full information packet. No field is an aggregate correctness or action
/// verdict, and no unavailable slot discards the other slots.
pub opaque type Packet {
  Packet(
    identity: IdentityFacts,
    session: SessionFacts,
    provider_row: Fact(RowFacts),
    acquisition: Fact(Attempt),
    timing: TimingFacts,
    adjustment: Fact(Adjustment),
    quantity: QuantityFacts,
    rights: RightsFacts,
    quality: Fact(QualityFact),
    evidence_roots: List(EvidenceRoot),
    available_operations: List(AvailableOperation),
  )
}

pub fn evidence_root(
  name name_value: String,
  reference reference_value: String,
) -> EvidenceRoot {
  EvidenceRoot(name_value, reference_value)
}

pub fn identity(
  track track_value: Track,
  instrument_id instrument_value: Fact(String),
  symbol symbol_value: Fact(String),
  mic mic_value: Fact(String),
  currency currency_value: Fact(Currency),
  evidence_root root_value: Fact(String),
) -> IdentityFacts {
  IdentityFacts(
    track_value,
    instrument_value,
    symbol_value,
    mic_value,
    currency_value,
    root_value,
  )
}

pub fn session(
  session_date date_value: Date,
  venue_state venue_value: Fact(VenueState),
  listing_effective listing_value: Fact(Bool),
  security_status status_value: Fact(SecurityStatus),
  descriptive_classification classification_value: Fact(String),
  classification_rule rule_value: Fact(String),
) -> SessionFacts {
  SessionFacts(
    date_value,
    venue_value,
    listing_value,
    status_value,
    classification_value,
    rule_value,
  )
}

pub fn new(
  identity identity_value: IdentityFacts,
  session session_value: SessionFacts,
  provider_row row_value: Fact(RowFacts),
  acquisition acquisition_value: Fact(Attempt),
  timing timing_value: TimingFacts,
  adjustment adjustment_value: Fact(Adjustment),
  quantity quantity_value: QuantityFacts,
  rights rights_value: RightsFacts,
  quality quality_value: Fact(QualityFact),
  evidence_roots root_values: List(EvidenceRoot),
  available_operations operation_values: List(AvailableOperation),
) -> Packet {
  Packet(
    identity_value,
    session_value,
    row_value,
    acquisition_value,
    timing_value,
    adjustment_value,
    quantity_value,
    rights_value,
    quality_value,
    root_values,
    operation_values,
  )
}

pub fn track(value: IdentityFacts) -> Track {
  value.track
}

pub fn instrument_id(value: IdentityFacts) -> Fact(String) {
  value.instrument_id
}

pub fn identity_symbol(value: IdentityFacts) -> Fact(String) {
  value.symbol
}

pub fn mic(value: IdentityFacts) -> Fact(String) {
  value.mic
}

pub fn currency(value: IdentityFacts) -> Fact(Currency) {
  value.currency
}

pub fn identity_evidence_root(value: IdentityFacts) -> Fact(String) {
  value.evidence_root
}

pub fn session_date(value: SessionFacts) -> Date {
  value.session_date
}

pub fn venue_state(value: SessionFacts) -> Fact(VenueState) {
  value.venue_state
}

pub fn listing_effective(value: SessionFacts) -> Fact(Bool) {
  value.listing_effective
}

pub fn security_status(value: SessionFacts) -> Fact(SecurityStatus) {
  value.security_status
}

pub fn descriptive_classification(value: SessionFacts) -> Fact(String) {
  value.descriptive_classification
}

pub fn classification_rule(value: SessionFacts) -> Fact(String) {
  value.classification_rule
}

pub fn packet_identity(value: Packet) -> IdentityFacts {
  value.identity
}

pub fn packet_session(value: Packet) -> SessionFacts {
  value.session
}

pub fn provider_row(value: Packet) -> Fact(RowFacts) {
  value.provider_row
}

pub fn acquisition(value: Packet) -> Fact(Attempt) {
  value.acquisition
}

pub fn timing(value: Packet) -> TimingFacts {
  value.timing
}

pub fn adjustment(value: Packet) -> Fact(Adjustment) {
  value.adjustment
}

pub fn quantity(value: Packet) -> QuantityFacts {
  value.quantity
}

pub fn rights(value: Packet) -> RightsFacts {
  value.rights
}

pub fn quality(value: Packet) -> Fact(QualityFact) {
  value.quality
}

pub fn evidence_roots(value: Packet) -> List(EvidenceRoot) {
  value.evidence_roots
}

pub fn available_operations(value: Packet) -> List(AvailableOperation) {
  value.available_operations
}

pub fn evidence_root_name(value: EvidenceRoot) -> String {
  value.name
}

pub fn evidence_root_reference(value: EvidenceRoot) -> String {
  value.reference
}
