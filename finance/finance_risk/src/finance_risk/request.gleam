import finance_core/time.{type Instant}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_risk/bound.{type ProjectionPolicy}
import finance_risk/calculation.{type RoundingSpec}
import finance_risk/fact.{type Fact}
import finance_track.{type Track}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Context {
  Context(
    account_scope: String,
    portfolio_scope: String,
    track: Track,
    listing_id: String,
    as_of_time: Instant,
    currency: String,
    evidence_roots: List(EvidenceId),
  )
}

pub opaque type OperationSpec {
  OperationSpec(
    operation_id: String,
    formula_variant: String,
    ordered_parameters: List(#(String, String)),
    instruction_ref: Sha256,
    input_fact_ids: List(String),
  )
}

pub type InputReference {
  InputReference(
    fact_id: String,
    state: String,
    source_kinds: List(String),
    source_references: List(Sha256),
    effective_times: List(Instant),
    retrieval_times: List(Instant),
    source_lexemes: List(String),
    currencies: List(String),
    units: List(String),
    scopes: List(String),
    retained_alternatives: List(String),
  )
}

pub type CurrencyPolicy {
  NativeCurrency
}

pub type BranchPolicy {
  AllBranches
  SelectedBranch(branch_id: String, instruction_ref: Sha256)
}

pub type ExecutionBudgets {
  ExecutionBudgets(maximum_outputs: Int, maximum_operations: Int)
}

pub opaque type Request {
  Request(
    instruction_ref: Sha256,
    context: Context,
    operations: List(OperationSpec),
    ordered_inputs: List(InputReference),
    selected_budget_ids: List(String),
    selected_scenario_ids: List(String),
    selected_cost_component_ids: List(String),
    projection_policy: ProjectionPolicy,
    rounding: RoundingSpec,
    currency_policy: CurrencyPolicy,
    branch_policy: BranchPolicy,
    aggregation_policies: List(String),
    requested_summary_fields: List(String),
    budgets: ExecutionBudgets,
    available_operations: List(String),
  )
}

pub type RequestError {
  InvalidText(field: String)
  InvalidBudget
  TooManyOperations(requested: Int, maximum: Int)
  DuplicateOperationId(operation_id: String)
}

pub fn context(
  account_scope account_scope_value: String,
  portfolio_scope portfolio_scope_value: String,
  track track_value: Track,
  listing_id listing_id_value: String,
  as_of_time as_of_value: Instant,
  currency currency_value: String,
  evidence_roots root_values: List(EvidenceId),
) -> Result(Context, RequestError) {
  case
    valid_text(account_scope_value),
    valid_text(portfolio_scope_value),
    valid_text(listing_id_value),
    valid_text(currency_value)
  {
    False, _, _, _ -> Error(InvalidText("account_scope"))
    _, False, _, _ -> Error(InvalidText("portfolio_scope"))
    _, _, False, _ -> Error(InvalidText("listing_id"))
    _, _, _, False -> Error(InvalidText("currency"))
    True, True, True, True ->
      Ok(Context(
        account_scope_value,
        portfolio_scope_value,
        track_value,
        listing_id_value,
        as_of_value,
        currency_value,
        root_values,
      ))
  }
}

pub fn operation(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  ordered_parameters parameter_values: List(#(String, String)),
  instruction_ref instruction_value: Sha256,
  input_fact_ids input_values: List(String),
) -> Result(OperationSpec, RequestError) {
  case valid_text(operation_id_value), valid_text(formula_value) {
    False, _ -> Error(InvalidText("operation_id"))
    _, False -> Error(InvalidText("formula_variant"))
    True, True ->
      Ok(OperationSpec(
        operation_id_value,
        formula_value,
        parameter_values,
        instruction_value,
        input_values,
      ))
  }
}

pub fn input_reference(fact_id: String, value: Fact(value)) -> InputReference {
  let sources = fact.fact_sources(value)
  InputReference(
    fact_id,
    fact.state_name(value),
    list.map(sources, fn(source) {
      source |> fact.source_kind |> fact.source_kind_name
    }),
    list.map(sources, fact.source_reference),
    list.map(sources, fact.effective_at),
    list.map(sources, fact.retrieved_at),
    list.map(sources, fact.source_lexeme),
    list.map(sources, fact.currency),
    list.map(sources, fact.unit),
    list.map(sources, fact.scope),
    sources |> list.flat_map(fact.retained_alternatives),
  )
}

pub fn request(
  instruction_ref instruction_value: Sha256,
  context context_value: Context,
  operations operation_values: List(OperationSpec),
  ordered_inputs input_values: List(InputReference),
  selected_budget_ids budget_ids: List(String),
  selected_scenario_ids scenario_ids: List(String),
  selected_cost_component_ids cost_ids: List(String),
  projection_policy projection_value: ProjectionPolicy,
  rounding rounding_value: RoundingSpec,
  currency_policy currency_value: CurrencyPolicy,
  branch_policy branch_value: BranchPolicy,
  aggregation_policies aggregation_values: List(String),
  requested_summary_fields summary_values: List(String),
  budgets budget_values: ExecutionBudgets,
  available_operations available_values: List(String),
) -> Result(Request, RequestError) {
  let ExecutionBudgets(maximum_outputs, maximum_operations) = budget_values
  let operation_count = list.length(operation_values)
  case maximum_outputs <= 0 || maximum_operations <= 0 {
    True -> Error(InvalidBudget)
    False ->
      case operation_count > maximum_operations {
        True -> Error(TooManyOperations(operation_count, maximum_operations))
        False ->
          case duplicate_operation_id(operation_values) {
            Some(id) -> Error(DuplicateOperationId(id))
            None ->
              Ok(Request(
                instruction_value,
                context_value,
                operation_values,
                input_values,
                budget_ids,
                scenario_ids,
                cost_ids,
                projection_value,
                rounding_value,
                currency_value,
                branch_value,
                aggregation_values,
                summary_values,
                budget_values,
                available_values,
              ))
          }
      }
  }
}

pub fn instruction_ref(value: Request) -> Sha256 {
  value.instruction_ref
}

pub fn request_context(value: Request) -> Context {
  value.context
}

pub fn operations(value: Request) -> List(OperationSpec) {
  value.operations
}

pub fn ordered_inputs(value: Request) -> List(InputReference) {
  value.ordered_inputs
}

pub fn selected_budget_ids(value: Request) -> List(String) {
  value.selected_budget_ids
}

pub fn selected_scenario_ids(value: Request) -> List(String) {
  value.selected_scenario_ids
}

pub fn selected_cost_component_ids(value: Request) -> List(String) {
  value.selected_cost_component_ids
}

pub fn projection_policy(value: Request) -> ProjectionPolicy {
  value.projection_policy
}

pub fn request_rounding(value: Request) -> RoundingSpec {
  value.rounding
}

pub fn currency_policy(value: Request) -> CurrencyPolicy {
  value.currency_policy
}

pub fn branch_policy(value: Request) -> BranchPolicy {
  value.branch_policy
}

pub fn aggregation_policies(value: Request) -> List(String) {
  value.aggregation_policies
}

pub fn requested_summary_fields(value: Request) -> List(String) {
  value.requested_summary_fields
}

pub fn execution_budgets(value: Request) -> ExecutionBudgets {
  value.budgets
}

pub fn available_operations(value: Request) -> List(String) {
  value.available_operations
}

pub fn account_scope(value: Context) -> String {
  value.account_scope
}

pub fn portfolio_scope(value: Context) -> String {
  value.portfolio_scope
}

pub fn context_track(value: Context) -> Track {
  value.track
}

pub fn listing_id(value: Context) -> String {
  value.listing_id
}

pub fn as_of_time(value: Context) -> Instant {
  value.as_of_time
}

pub fn context_currency(value: Context) -> String {
  value.currency
}

pub fn evidence_roots(value: Context) -> List(EvidenceId) {
  value.evidence_roots
}

pub fn operation_id(value: OperationSpec) -> String {
  value.operation_id
}

pub fn formula_variant(value: OperationSpec) -> String {
  value.formula_variant
}

pub fn ordered_parameters(value: OperationSpec) -> List(#(String, String)) {
  value.ordered_parameters
}

pub fn operation_instruction_ref(value: OperationSpec) -> Sha256 {
  value.instruction_ref
}

pub fn input_fact_ids(value: OperationSpec) -> List(String) {
  value.input_fact_ids
}

pub fn maximum_outputs(value: ExecutionBudgets) -> Int {
  let ExecutionBudgets(value, _) = value
  value
}

pub fn maximum_operations(value: ExecutionBudgets) -> Int {
  let ExecutionBudgets(_, value) = value
  value
}

fn duplicate_operation_id(values: List(OperationSpec)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case
        list.any(rest, fn(value) { value.operation_id == first.operation_id })
      {
        True -> Some(first.operation_id)
        False -> duplicate_operation_id(rest)
      }
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
