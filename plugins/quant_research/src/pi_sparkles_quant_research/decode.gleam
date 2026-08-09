import finance_replay/fact.{type Fact}
import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type AuthorInput {
  AuthorInput(kind: String, import_source: Option(String))
}

pub type HypothesisInput {
  HypothesisInput(
    hypothesis_id: String,
    version: String,
    content_hash: String,
    author: AuthorInput,
    author_id: Option(String),
    declared_time_unix_ms: Int,
    text: String,
    structured_expression: Option(String),
    target_value: Option(String),
    population_ref: Option(String),
    feature_refs: List(String),
    strategy_ref: Option(String),
    source_cutoff_unix_ms: Option(Int),
    supporting_refs: List(String),
    privacy: String,
    export_classification: String,
  )
}

pub type ParameterInput {
  ParameterInput(
    name: String,
    exact_value: String,
    author: AuthorInput,
    source_receipt: Fact(String),
  )
}

pub type TrialDefinitionInput {
  TrialDefinitionInput(
    trial_id: String,
    parent_trial_id: Option(String),
    batch_id: Option(String),
    run_definition_hash: String,
    parameter_values: List(ParameterInput),
    trial_rationale: Fact(String),
    partition_ref: String,
    model_refs: List(String),
    seed: Fact(String),
    metric_refs: List(String),
    budget_refs: List(String),
    author: AuthorInput,
    declared_time_unix_ms: Int,
    privacy: String,
  )
}

pub type StatusInput {
  StatusInput(
    state: String,
    reason: Option(String),
    at_unix_ms: Option(Int),
    by: Option(String),
    existing_trial_id: Option(String),
  )
}

pub type LedgerEventInput {
  LedgerEventInput(
    ledger_event_id: String,
    trial: TrialDefinitionInput,
    status: StatusInput,
    start_time_unix_ms: Int,
    end_time: Fact(Int),
    output_receipt_hashes: List(String),
    error_facts: List(String),
    effect_receipt_hash: String,
    idempotency_key: String,
  )
}

pub type ExpectedCounts {
  ExpectedCounts(
    total: Int,
    completed: Int,
    failed: Int,
    cancelled: Int,
    truncated: Int,
    duplicate: Int,
    unperformed: Int,
  )
}

pub type InspectInput {
  InspectInput(
    hypothesis: HypothesisInput,
    population_id: String,
    completeness_policy: String,
    expected_counts: ExpectedCounts,
    events: List(LedgerEventInput),
    include_hypothesis_text: Bool,
    include_trial_payloads: Bool,
    offset: Int,
    limit: Int,
  )
}

pub type MetricMetadataInput {
  MetricMetadataInput(
    request_id: String,
    formula: String,
    formula_version: String,
    unit: String,
    scale: Int,
    rounding: String,
    missing_conflict_policy: String,
    sample_population: String,
    ordering: String,
    benchmark: Fact(String),
    source_receipts: List(String),
  )
}

pub type DecimalInput {
  DecimalInput(name: String, exact_lexeme: String, source_receipt: String)
}

pub type TradePnlInput {
  TradePnlInput(
    trade_id: String,
    net_pnl_lexeme: String,
    source_receipt: String,
  )
}

pub type EquityPointInput {
  EquityPointInput(label: String, value: DecimalInput)
}

pub type TradeInput {
  TradeInput(
    trade_id: String,
    instruction_receipt: String,
    lifecycle_receipts: List(String),
    exact_payload: String,
  )
}

pub type MetricRequestInput {
  NetReturn(denominator: Fact(DecimalInput), ending_value: Fact(DecimalInput))
  WinLossCounts(trades: List(TradePnlInput), zero_policy: String)
  DrawdownSeries(points: List(EquityPointInput), peak_convention: String)
  TradeList(trades: List(TradeInput))
}

pub type MetricInput {
  MetricInput(metadata: MetricMetadataInput, request: MetricRequestInput)
}

pub type DefinitionInput {
  DefinitionInput(canonical_json: String, content_hash: String)
}

pub type OutputInput {
  OutputInput(name: String, exact_value: String, source_receipt: String)
}

pub type CompareInput {
  CompareInput(
    comparison_policy: String,
    left_definition: DefinitionInput,
    right_definition: DefinitionInput,
    left_outputs: List(OutputInput),
    right_outputs: List(OutputInput),
  )
}

pub fn inspect_trial_ledger() -> decoder.Decoder(InspectInput) {
  use hypothesis <- decoder.field("hypothesis", hypothesis_decoder())
  use population_id <- decoder.field("populationId", decoder.string)
  use completeness_policy <- decoder.field("completenessPolicy", decoder.string)
  use expected_counts <- decoder.field("expectedCounts", counts_decoder())
  use events <- decoder.field(
    "events",
    decoder.list(of: ledger_event_decoder()),
  )
  use include_hypothesis_text <- decoder.field(
    "includeHypothesisText",
    decoder.bool,
  )
  use include_trial_payloads <- decoder.field(
    "includeTrialPayloads",
    decoder.bool,
  )
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(InspectInput(
    hypothesis,
    population_id,
    completeness_policy,
    expected_counts,
    events,
    include_hypothesis_text,
    include_trial_payloads,
    offset,
    limit,
  ))
}

pub fn request_metric() -> decoder.Decoder(MetricInput) {
  use metadata <- decoder.field("metadata", metadata_decoder())
  use request <- decoder.field("request", metric_request_decoder())
  decoder.success(MetricInput(metadata, request))
}

pub fn compare_runs() -> decoder.Decoder(CompareInput) {
  use policy <- decoder.field("comparisonPolicy", decoder.string)
  use left <- decoder.field("leftDefinition", definition_decoder())
  use right <- decoder.field("rightDefinition", definition_decoder())
  use left_outputs <- decoder.field(
    "leftOutputs",
    decoder.list(of: output_decoder()),
  )
  use right_outputs <- decoder.field(
    "rightOutputs",
    decoder.list(of: output_decoder()),
  )
  decoder.success(CompareInput(policy, left, right, left_outputs, right_outputs))
}

fn hypothesis_decoder() -> decoder.Decoder(HypothesisInput) {
  use hypothesis_id <- decoder.field("hypothesisId", decoder.string)
  use version <- decoder.field("version", decoder.string)
  use content_hash <- decoder.field("contentHash", decoder.string)
  use author <- decoder.field("author", author_decoder())
  use author_id <- optional_string("authorId")
  use declared_time <- decoder.field(
    "declaredTimeUnixMilliseconds",
    decoder.int,
  )
  use text <- decoder.field("text", decoder.string)
  use structured_expression <- optional_string("structuredExpression")
  use target_value <- optional_string("targetValue")
  use population_ref <- optional_string("populationRef")
  use feature_refs <- decoder.field(
    "featureRefs",
    decoder.list(of: decoder.string),
  )
  use strategy_ref <- optional_string("strategyRef")
  use source_cutoff <- optional_int("sourceCutoffUnixMilliseconds")
  use supporting_refs <- decoder.field(
    "supportingRefs",
    decoder.list(of: decoder.string),
  )
  use privacy <- decoder.field("privacy", decoder.string)
  use export_classification <- decoder.field(
    "exportClassification",
    decoder.string,
  )
  decoder.success(HypothesisInput(
    hypothesis_id,
    version,
    content_hash,
    author,
    author_id,
    declared_time,
    text,
    structured_expression,
    target_value,
    population_ref,
    feature_refs,
    strategy_ref,
    source_cutoff,
    supporting_refs,
    privacy,
    export_classification,
  ))
}

fn ledger_event_decoder() -> decoder.Decoder(LedgerEventInput) {
  use ledger_event_id <- decoder.field("ledgerEventId", decoder.string)
  use trial <- decoder.field("trial", trial_definition_decoder())
  use status <- decoder.field("status", status_decoder())
  use start_time <- decoder.field("startTimeUnixMilliseconds", decoder.int)
  use end_time <- decoder.field("endTime", fact.decoder(decoder.int))
  use outputs <- decoder.field(
    "outputReceiptHashes",
    decoder.list(of: decoder.string),
  )
  use errors <- decoder.field("errorFacts", decoder.list(of: decoder.string))
  use effect <- decoder.field("effectReceiptHash", decoder.string)
  use key <- decoder.field("idempotencyKey", decoder.string)
  decoder.success(LedgerEventInput(
    ledger_event_id,
    trial,
    status,
    start_time,
    end_time,
    outputs,
    errors,
    effect,
    key,
  ))
}

fn trial_definition_decoder() -> decoder.Decoder(TrialDefinitionInput) {
  use trial_id <- decoder.field("trialId", decoder.string)
  use parent_trial_id <- optional_string("parentTrialId")
  use batch_id <- optional_string("batchId")
  use run_definition_hash <- decoder.field("runDefinitionHash", decoder.string)
  use parameters <- decoder.field(
    "parameterValues",
    decoder.list(of: parameter_decoder()),
  )
  use rationale <- decoder.field("trialRationale", fact.decoder(decoder.string))
  use partition_ref <- decoder.field("partitionRef", decoder.string)
  use model_refs <- decoder.field("modelRefs", decoder.list(of: decoder.string))
  use seed <- decoder.field("seed", fact.decoder(decoder.string))
  use metric_refs <- decoder.field(
    "metricRefs",
    decoder.list(of: decoder.string),
  )
  use budget_refs <- decoder.field(
    "budgetRefs",
    decoder.list(of: decoder.string),
  )
  use author <- decoder.field("author", author_decoder())
  use declared_time <- decoder.field(
    "declaredTimeUnixMilliseconds",
    decoder.int,
  )
  use privacy <- decoder.field("privacy", decoder.string)
  decoder.success(TrialDefinitionInput(
    trial_id,
    parent_trial_id,
    batch_id,
    run_definition_hash,
    parameters,
    rationale,
    partition_ref,
    model_refs,
    seed,
    metric_refs,
    budget_refs,
    author,
    declared_time,
    privacy,
  ))
}

fn parameter_decoder() -> decoder.Decoder(ParameterInput) {
  use name <- decoder.field("name", decoder.string)
  use exact_value <- decoder.field("exactValue", decoder.string)
  use author <- decoder.field("author", author_decoder())
  use source <- decoder.field("sourceReceipt", fact.decoder(decoder.string))
  decoder.success(ParameterInput(name, exact_value, author, source))
}

fn author_decoder() -> decoder.Decoder(AuthorInput) {
  use kind <- decoder.field("kind", decoder.string)
  use import_source <- optional_string("importSource")
  decoder.success(AuthorInput(kind, import_source))
}

fn status_decoder() -> decoder.Decoder(StatusInput) {
  use state <- decoder.field("state", decoder.string)
  use reason <- optional_string("reason")
  use at <- optional_int("atUnixMilliseconds")
  use by <- optional_string("by")
  use existing <- optional_string("existingTrialId")
  decoder.success(StatusInput(state, reason, at, by, existing))
}

fn counts_decoder() -> decoder.Decoder(ExpectedCounts) {
  use total <- decoder.field("total", decoder.int)
  use completed <- decoder.field("completed", decoder.int)
  use failed <- decoder.field("failed", decoder.int)
  use cancelled <- decoder.field("cancelled", decoder.int)
  use truncated <- decoder.field("truncated", decoder.int)
  use duplicate <- decoder.field("duplicate", decoder.int)
  use unperformed <- decoder.field("unperformed", decoder.int)
  decoder.success(ExpectedCounts(
    total,
    completed,
    failed,
    cancelled,
    truncated,
    duplicate,
    unperformed,
  ))
}

fn metadata_decoder() -> decoder.Decoder(MetricMetadataInput) {
  use request_id <- decoder.field("requestId", decoder.string)
  use formula <- decoder.field("formula", decoder.string)
  use version <- decoder.field("formulaVersion", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use scale <- decoder.field("scale", decoder.int)
  use rounding <- decoder.field("rounding", decoder.string)
  use missing <- decoder.field("missingConflictPolicy", decoder.string)
  use population <- decoder.field("samplePopulation", decoder.string)
  use ordering <- decoder.field("ordering", decoder.string)
  use benchmark <- decoder.field("benchmark", fact.decoder(decoder.string))
  use source_receipts <- decoder.field(
    "sourceReceipts",
    decoder.list(of: decoder.string),
  )
  decoder.success(MetricMetadataInput(
    request_id,
    formula,
    version,
    unit,
    scale,
    rounding,
    missing,
    population,
    ordering,
    benchmark,
    source_receipts,
  ))
}

fn metric_request_decoder() -> decoder.Decoder(MetricRequestInput) {
  use kind <- decoder.field("kind", decoder.string)
  case kind {
    "net_return" -> {
      use denominator <- decoder.field(
        "denominator",
        fact.decoder(decimal_input_decoder()),
      )
      use ending_value <- decoder.field(
        "endingValue",
        fact.decoder(decimal_input_decoder()),
      )
      decoder.success(NetReturn(denominator, ending_value))
    }
    "win_loss_counts" -> {
      use trades <- decoder.field(
        "trades",
        decoder.list(of: trade_pnl_decoder()),
      )
      use zero_policy <- decoder.field("zeroPolicy", decoder.string)
      decoder.success(WinLossCounts(trades, zero_policy))
    }
    "drawdown_series" -> {
      use points <- decoder.field(
        "points",
        decoder.list(of: equity_point_decoder()),
      )
      use peak_convention <- decoder.field("peakConvention", decoder.string)
      decoder.success(DrawdownSeries(points, peak_convention))
    }
    "trade_list" -> {
      use trades <- decoder.field("trades", decoder.list(of: trade_decoder()))
      decoder.success(TradeList(trades))
    }
    _ ->
      decoder.failure(
        TradeList([]),
        "known finance_replay requested metric kind",
      )
  }
}

fn decimal_input_decoder() -> decoder.Decoder(DecimalInput) {
  use name <- decoder.field("name", decoder.string)
  use exact_lexeme <- decoder.field("exactLexeme", decoder.string)
  use source_receipt <- decoder.field("sourceReceipt", decoder.string)
  decoder.success(DecimalInput(name, exact_lexeme, source_receipt))
}

fn trade_pnl_decoder() -> decoder.Decoder(TradePnlInput) {
  use trade_id <- decoder.field("tradeId", decoder.string)
  use lexeme <- decoder.field("netPnlLexeme", decoder.string)
  use source <- decoder.field("sourceReceipt", decoder.string)
  decoder.success(TradePnlInput(trade_id, lexeme, source))
}

fn equity_point_decoder() -> decoder.Decoder(EquityPointInput) {
  use label <- decoder.field("label", decoder.string)
  use value <- decoder.field("value", decimal_input_decoder())
  decoder.success(EquityPointInput(label, value))
}

fn trade_decoder() -> decoder.Decoder(TradeInput) {
  use trade_id <- decoder.field("tradeId", decoder.string)
  use instruction <- decoder.field("instructionReceipt", decoder.string)
  use lifecycle <- decoder.field(
    "lifecycleReceipts",
    decoder.list(of: decoder.string),
  )
  use payload <- decoder.field("exactPayload", decoder.string)
  decoder.success(TradeInput(trade_id, instruction, lifecycle, payload))
}

fn definition_decoder() -> decoder.Decoder(DefinitionInput) {
  use canonical_json <- decoder.field("canonicalJson", decoder.string)
  use content_hash <- decoder.field("contentHash", decoder.string)
  decoder.success(DefinitionInput(canonical_json, content_hash))
}

fn output_decoder() -> decoder.Decoder(OutputInput) {
  use name <- decoder.field("name", decoder.string)
  use exact_value <- decoder.field("exactValue", decoder.string)
  use source_receipt <- decoder.field("sourceReceipt", decoder.string)
  decoder.success(OutputInput(name, exact_value, source_receipt))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}
