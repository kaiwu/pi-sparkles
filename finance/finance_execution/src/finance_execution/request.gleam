import finance_execution/calculation.{type RoundingSpec}
import finance_execution/fact.{type Fact}
import finance_execution/instruction.{type DesiredInstruction}
import finance_provenance/identity.{type Sha256}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type OperationSpec {
  OperationSpec(
    operation_id: String,
    model_or_formula_variant: String,
    ordered_parameters: List(#(String, String)),
    instruction_reference: Sha256,
    input_fact_ids: List(String),
  )
}

pub type InputReference {
  InputReference(
    fact_id: String,
    state: String,
    source_kinds: List(String),
    source_references: List(Sha256),
    source_lexemes: List(String),
    currencies: List(String),
    units: List(String),
    scopes: List(String),
    retained_alternatives: List(String),
  )
}

pub type ReferenceSet {
  ReferenceSet(
    capability_references: List(Sha256),
    rule_references: List(Sha256),
    calendar_references: List(Sha256),
    market_event_references: List(Sha256),
    lifecycle_references: List(Sha256),
    position_references: List(Sha256),
    risk_receipt_references: List(Sha256),
    cost_receipt_references: List(Sha256),
    fx_receipts: List(Sha256),
  )
}

pub type BranchPolicy {
  AllBranches
  SelectedBranch(branch_id: String, instruction_reference: Sha256)
}

pub type Budgets {
  Budgets(
    max_events: Int,
    max_depth_levels: Int,
    max_branches: Int,
    max_fills: Int,
    max_outputs: Int,
    max_bytes: Int,
    max_operations: Int,
  )
}

pub opaque type Request {
  Request(
    desired_instruction: DesiredInstruction,
    ordered_operations: List(OperationSpec),
    ordered_inputs: List(InputReference),
    references: ReferenceSet,
    session_scope: String,
    date_time_scope: String,
    simulation_policy: List(#(String, String)),
    trigger_policy: List(#(String, String)),
    fill_policy: List(#(String, String)),
    cost_policy: List(#(String, String)),
    benchmark_policy: List(#(String, String)),
    rounding_policy: RoundingSpec,
    currency_policy: String,
    branch_policy: BranchPolicy,
    requested_summary_fields: List(String),
    budgets: Budgets,
    available_operations: List(String),
  )
}

pub type RequestError {
  InvalidText(field: String)
  InvalidBudget(field: String)
  TooManyOperations(requested: Int, maximum: Int)
  DuplicateOperationId(operation_id: String)
}

pub fn operation(
  operation_id operation_id_value: String,
  model_or_formula_variant variant_value: String,
  ordered_parameters parameter_values: List(#(String, String)),
  instruction_reference instruction_value: Sha256,
  input_fact_ids input_values: List(String),
) -> Result(OperationSpec, RequestError) {
  case valid_text(operation_id_value), valid_text(variant_value) {
    False, _ -> Error(InvalidText("operation_id"))
    _, False -> Error(InvalidText("model_or_formula_variant"))
    True, True ->
      Ok(OperationSpec(
        operation_id_value,
        variant_value,
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
    list.map(sources, fact.source_lexeme),
    list.map(sources, fact.currency),
    list.map(sources, fact.unit),
    list.map(sources, fact.scope),
    sources |> list.flat_map(fact.retained_alternatives),
  )
}

pub fn request(
  desired_instruction instruction_value: DesiredInstruction,
  ordered_operations operation_values: List(OperationSpec),
  ordered_inputs input_values: List(InputReference),
  references reference_values: ReferenceSet,
  session_scope session_value: String,
  date_time_scope date_time_value: String,
  simulation_policy simulation_values: List(#(String, String)),
  trigger_policy trigger_values: List(#(String, String)),
  fill_policy fill_values: List(#(String, String)),
  cost_policy cost_values: List(#(String, String)),
  benchmark_policy benchmark_values: List(#(String, String)),
  rounding_policy rounding_value: RoundingSpec,
  currency_policy currency_value: String,
  branch_policy branch_value: BranchPolicy,
  requested_summary_fields summary_values: List(String),
  budgets budget_values: Budgets,
  available_operations available_values: List(String),
) -> Result(Request, RequestError) {
  case
    valid_text(session_value),
    valid_text(date_time_value),
    valid_text(currency_value)
  {
    False, _, _ -> Error(InvalidText("session_scope"))
    _, False, _ -> Error(InvalidText("date_time_scope"))
    _, _, False -> Error(InvalidText("currency_policy"))
    True, True, True ->
      case invalid_budget(budget_values) {
        Some(field) -> Error(InvalidBudget(field))
        None -> {
          let maximum = max_operations(budget_values)
          case list.length(operation_values) > maximum {
            True ->
              Error(TooManyOperations(list.length(operation_values), maximum))
            False ->
              case duplicate_operation_id(operation_values) {
                Some(id) -> Error(DuplicateOperationId(id))
                None ->
                  Ok(Request(
                    instruction_value,
                    operation_values,
                    input_values,
                    reference_values,
                    session_value,
                    date_time_value,
                    simulation_values,
                    trigger_values,
                    fill_values,
                    cost_values,
                    benchmark_values,
                    rounding_value,
                    currency_value,
                    branch_value,
                    summary_values,
                    budget_values,
                    available_values,
                  ))
              }
          }
        }
      }
  }
}

pub fn desired_instruction(value: Request) -> DesiredInstruction {
  value.desired_instruction
}

pub fn ordered_operations(value: Request) -> List(OperationSpec) {
  value.ordered_operations
}

pub fn ordered_inputs(value: Request) -> List(InputReference) {
  value.ordered_inputs
}

pub fn references(value: Request) -> ReferenceSet {
  value.references
}

pub fn session_scope(value: Request) -> String {
  value.session_scope
}

pub fn date_time_scope(value: Request) -> String {
  value.date_time_scope
}

pub fn simulation_policy(value: Request) -> List(#(String, String)) {
  value.simulation_policy
}

pub fn trigger_policy(value: Request) -> List(#(String, String)) {
  value.trigger_policy
}

pub fn fill_policy(value: Request) -> List(#(String, String)) {
  value.fill_policy
}

pub fn cost_policy(value: Request) -> List(#(String, String)) {
  value.cost_policy
}

pub fn benchmark_policy(value: Request) -> List(#(String, String)) {
  value.benchmark_policy
}

pub fn rounding_policy(value: Request) -> RoundingSpec {
  value.rounding_policy
}

pub fn currency_policy(value: Request) -> String {
  value.currency_policy
}

pub fn branch_policy(value: Request) -> BranchPolicy {
  value.branch_policy
}

pub fn requested_summary_fields(value: Request) -> List(String) {
  value.requested_summary_fields
}

pub fn budgets(value: Request) -> Budgets {
  value.budgets
}

pub fn available_operations(value: Request) -> List(String) {
  value.available_operations
}

pub fn operation_id(value: OperationSpec) -> String {
  value.operation_id
}

pub fn model_or_formula_variant(value: OperationSpec) -> String {
  value.model_or_formula_variant
}

pub fn ordered_parameters(value: OperationSpec) -> List(#(String, String)) {
  value.ordered_parameters
}

pub fn operation_instruction_reference(value: OperationSpec) -> Sha256 {
  value.instruction_reference
}

pub fn input_fact_ids(value: OperationSpec) -> List(String) {
  value.input_fact_ids
}

pub fn max_events(value: Budgets) -> Int {
  let Budgets(value, _, _, _, _, _, _) = value
  value
}

pub fn max_depth_levels(value: Budgets) -> Int {
  let Budgets(_, value, _, _, _, _, _) = value
  value
}

pub fn max_branches(value: Budgets) -> Int {
  let Budgets(_, _, value, _, _, _, _) = value
  value
}

pub fn max_fills(value: Budgets) -> Int {
  let Budgets(_, _, _, value, _, _, _) = value
  value
}

pub fn max_outputs(value: Budgets) -> Int {
  let Budgets(_, _, _, _, value, _, _) = value
  value
}

pub fn max_bytes(value: Budgets) -> Int {
  let Budgets(_, _, _, _, _, value, _) = value
  value
}

pub fn max_operations(value: Budgets) -> Int {
  let Budgets(_, _, _, _, _, _, value) = value
  value
}

fn invalid_budget(value: Budgets) -> Option(String) {
  let Budgets(events, depth, branches, fills, outputs, bytes, operations) =
    value
  case
    events > 0,
    depth > 0,
    branches > 0,
    fills > 0,
    outputs > 0,
    bytes > 0,
    operations > 0
  {
    False, _, _, _, _, _, _ -> Some("max_events")
    _, False, _, _, _, _, _ -> Some("max_depth_levels")
    _, _, False, _, _, _, _ -> Some("max_branches")
    _, _, _, False, _, _, _ -> Some("max_fills")
    _, _, _, _, False, _, _ -> Some("max_outputs")
    _, _, _, _, _, False, _ -> Some("max_bytes")
    _, _, _, _, _, _, False -> Some("max_operations")
    True, True, True, True, True, True, True -> None
  }
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
