import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/definition.{type RunDefinition}
import finance_replay/wire
import gleam/json
import gleam/list

pub type OutputField {
  OutputField(name: String, exact_value: String, source_receipt: Sha256)
}

pub type Difference {
  Difference(field: String, left: String, right: String)
}

pub opaque type Comparison {
  Comparison(
    left_definition_hash: Sha256,
    right_definition_hash: Sha256,
    input_differences: List(Difference),
    output_differences: List(Difference),
    left_output_receipts: List(Sha256),
    right_output_receipts: List(Sha256),
    digest: Sha256,
  )
}

/// Compare two caller-selected definitions and caller-selected output fields.
/// The result is alignment information, not a causal or quality judgment.
pub fn runs(
  left: RunDefinition,
  right: RunDefinition,
  left_outputs: List(OutputField),
  right_outputs: List(OutputField),
) -> Comparison {
  let input_differences = definition_differences(left, right)
  let output_differences = field_differences(left_outputs, right_outputs)
  let left_receipts =
    left_outputs |> list.map(fn(value) { value.source_receipt })
  let right_receipts =
    right_outputs |> list.map(fn(value) { value.source_receipt })
  let payload =
    payload(
      definition.digest(left),
      definition.digest(right),
      input_differences,
      output_differences,
      left_receipts,
      right_receipts,
    )
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Comparison(
    definition.digest(left),
    definition.digest(right),
    input_differences,
    output_differences,
    left_receipts,
    right_receipts,
    digest,
  )
}

fn definition_differences(
  left: RunDefinition,
  right: RunDefinition,
) -> List(Difference) {
  []
  |> add_difference(
    "version",
    definition.version(left),
    definition.version(right),
  )
  |> add_difference(
    "feature_receipts",
    sha_list(definition.feature_receipts(left)),
    sha_list(definition.feature_receipts(right)),
  )
  |> add_difference(
    "strategy_receipt",
    sha(definition.strategy_receipt(left)),
    sha(definition.strategy_receipt(right)),
  )
  |> add_difference(
    "risk_receipts",
    sha_list(definition.risk_receipts(left)),
    sha_list(definition.risk_receipts(right)),
  )
  |> add_difference(
    "execution_receipt",
    sha(definition.execution_receipt(left)),
    sha(definition.execution_receipt(right)),
  )
  |> add_difference(
    "universe_manifest",
    sha(definition.universe_manifest(left)),
    sha(definition.universe_manifest(right)),
  )
  |> add_difference(
    "dataset_manifest",
    sha(definition.dataset_manifest(left)),
    sha(definition.dataset_manifest(right)),
  )
  |> add_difference(
    "partition_receipt",
    sha(definition.partition_receipt(left)),
    sha(definition.partition_receipt(right)),
  )
  |> add_difference(
    "execution_branch_policy",
    definition.execution_branch_policy(left),
    definition.execution_branch_policy(right),
  )
  |> add_difference(
    "canonical_definition",
    definition.encode(left),
    definition.encode(right),
  )
  |> list.reverse
}

fn field_differences(
  left: List(OutputField),
  right: List(OutputField),
) -> List(Difference) {
  field_differences_loop(left, right, [])
}

fn field_differences_loop(
  left: List(OutputField),
  right: List(OutputField),
  reversed: List(Difference),
) -> List(Difference) {
  case left {
    [] ->
      right
      |> list.fold(reversed, fn(acc, value) {
        [Difference(value.name, "not_supplied", value.exact_value), ..acc]
      })
      |> list.reverse
    [left_value, ..rest] ->
      case find_output(right, left_value.name) {
        Error(_) ->
          field_differences_loop(rest, right, [
            Difference(left_value.name, left_value.exact_value, "not_supplied"),
            ..reversed
          ])
        Ok(right_value) -> {
          let next = case left_value.exact_value == right_value.exact_value {
            True -> reversed
            False -> [
              Difference(
                left_value.name,
                left_value.exact_value,
                right_value.exact_value,
              ),
              ..reversed
            ]
          }
          field_differences_loop(
            rest,
            remove_output(right, left_value.name),
            next,
          )
        }
      }
  }
}

fn find_output(
  values: List(OutputField),
  name: String,
) -> Result(OutputField, Nil) {
  case values {
    [] -> Error(Nil)
    [value, ..rest] ->
      case value.name == name {
        True -> Ok(value)
        False -> find_output(rest, name)
      }
  }
}

fn remove_output(values: List(OutputField), name: String) -> List(OutputField) {
  values |> list.filter(fn(value) { value.name != name })
}

fn add_difference(
  values: List(Difference),
  field: String,
  left: String,
  right: String,
) -> List(Difference) {
  case left == right {
    True -> values
    False -> [Difference(field, left, right), ..values]
  }
}

fn sha(value: Sha256) -> String {
  identity.sha256_value(value)
}

fn sha_list(values: List(Sha256)) -> String {
  values
  |> list.map(sha)
  |> list.intersperse(",")
  |> list.fold("", fn(acc, value) { acc <> value })
}

pub fn as_json(value: Comparison) -> json.Json {
  json.object([
    #(
      "payload",
      payload(
        value.left_definition_hash,
        value.right_definition_hash,
        value.input_differences,
        value.output_differences,
        value.left_output_receipts,
        value.right_output_receipts,
      ),
    ),
    #("canonical_content_hash", wire.sha_json(value.digest)),
  ])
}

fn payload(
  left_hash: Sha256,
  right_hash: Sha256,
  input_differences: List(Difference),
  output_differences: List(Difference),
  left_outputs: List(Sha256),
  right_outputs: List(Sha256),
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_run_comparison")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("left_definition_hash", wire.sha_json(left_hash)),
    #("right_definition_hash", wire.sha_json(right_hash)),
    #("input_differences", json.array(input_differences, difference_json)),
    #("output_differences", json.array(output_differences, difference_json)),
    #("left_output_receipts", json.array(left_outputs, wire.sha_json)),
    #("right_output_receipts", json.array(right_outputs, wire.sha_json)),
    #("interpretation", json.string("llm_owned")),
  ])
}

fn difference_json(value: Difference) -> json.Json {
  json.object([
    #("field", json.string(value.field)),
    #("left", json.string(value.left)),
    #("right", json.string(value.right)),
  ])
}

pub fn input_differences(value: Comparison) -> List(Difference) {
  value.input_differences
}

pub fn output_differences(value: Comparison) -> List(Difference) {
  value.output_differences
}

pub fn content_hash(value: Comparison) -> Sha256 {
  value.digest
}
