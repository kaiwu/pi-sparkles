import finance_core/time.{type Instant}
import finance_journal/event.{type Attribution}
import finance_journal/receipt.{type Envelope}
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_items = 64

pub type AnswerSchema {
  YesNo
  YesNoUnknown
  Scale(minimum: Int, maximum: Int)
  FreeText
  Numeric(unit: String)
  DeclaredValue(vocabulary_reference: Option(Sha256))
}

pub type Item {
  Item(
    item_id: String,
    prompt_text: String,
    answer_schema: AnswerSchema,
    role: Option(String),
    evidence_slot: Bool,
  )
}

pub opaque type Definition {
  Definition(
    definition_id: String,
    version: String,
    title: String,
    persona_scope: String,
    stage_scope: String,
    track_scope: List(Track),
    items: List(Item),
    attribution: Attribution,
    created_at: Instant,
  )
}

pub type AnswerState {
  Yes
  No
  Unknown(reason: String)
  NotAsked
  Declined
  NotApplicable(reason: String)
  Text(value: String)
  NumericValue(lexeme: String, unit: String)
  Declared(value: String)
}

pub type Answer {
  Answer(
    item_id: String,
    state: AnswerState,
    evidence_reference: Option(Sha256),
  )
}

pub opaque type Response {
  Response(
    definition_id: String,
    definition_version: String,
    definition_hash: Sha256,
    scope: String,
    attribution: Attribution,
    answered_at: Instant,
    recorded_at: Instant,
    answers: List(Answer),
    source_receipts: List(Sha256),
  )
}

pub type ChecklistError {
  InvalidText(field: String)
  EmptyItems
  TooManyItems(received: Int, maximum: Int)
  DuplicateItemId(item_id: String)
  InvalidScale(minimum: Int, maximum: Int)
  UnsupportedAttribution
  DuplicateAnswer(item_id: String)
  UnknownItem(item_id: String)
  AnswerDoesNotMatchSchema(item_id: String)
}

pub fn definition(
  definition_id definition_id_value: String,
  version version_value: String,
  title title_value: String,
  persona_scope persona_value: String,
  stage_scope stage_value: String,
  track_scope track_values: List(Track),
  items item_values: List(Item),
  attribution attribution_value: Attribution,
  created_at created_at_value: Instant,
) -> Result(Definition, ChecklistError) {
  use _ <- result.try(valid_text(definition_id_value, "definition_id"))
  use _ <- result.try(valid_text(version_value, "version"))
  use _ <- result.try(valid_text(title_value, "title"))
  use _ <- result.try(valid_text(persona_value, "persona_scope"))
  use _ <- result.try(valid_text(stage_value, "stage_scope"))
  use _ <- result.try(validate_attribution(attribution_value))
  use _ <- result.try(validate_items(item_values, []))
  Ok(Definition(
    definition_id_value,
    version_value,
    title_value,
    persona_value,
    stage_value,
    list.unique(track_values),
    item_values,
    attribution_value,
    created_at_value,
  ))
}

pub fn response(
  definition definition_value: Definition,
  scope scope_value: String,
  attribution attribution_value: Attribution,
  answered_at answered_at_value: Instant,
  recorded_at recorded_at_value: Instant,
  answers answer_values: List(Answer),
  source_receipts source_values: List(Sha256),
) -> Result(Response, ChecklistError) {
  use _ <- result.try(valid_text(scope_value, "scope"))
  use _ <- result.try(validate_attribution(attribution_value))
  use _ <- result.try(
    validate_answers(answer_values, definition_value.items, []),
  )
  Ok(Response(
    definition_value.definition_id,
    definition_value.version,
    definition_receipt(definition_value)
      |> receipt.content_hash,
    scope_value,
    attribution_value,
    answered_at_value,
    recorded_at_value,
    answer_values,
    source_values,
  ))
}

pub fn definition_receipt(value: Definition) -> Envelope {
  json.object([
    #("schema", json.string("pi-sparkles/journal-checklist-definition")),
    #("schema_version", json.int(1)),
    #("definition_id", json.string(value.definition_id)),
    #("version", json.string(value.version)),
    #("title", json.string(value.title)),
    #("persona_scope", json.string(value.persona_scope)),
    #("stage_scope", json.string(value.stage_scope)),
    #(
      "track_scope",
      value.track_scope
        |> list.map(finance_track.name)
        |> json.array(json.string),
    ),
    #("items", json.array(value.items, item_json)),
    #("attribution", attribution_json(value.attribution)),
    #(
      "created_at_unix_ms",
      value.created_at |> time.unix_milliseconds |> json.int,
    ),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
  |> receipt.envelope
}

pub fn response_receipt(value: Response) -> Envelope {
  json.object([
    #("schema", json.string("pi-sparkles/journal-checklist-response")),
    #("schema_version", json.int(1)),
    #("definition_id", json.string(value.definition_id)),
    #("definition_version", json.string(value.definition_version)),
    #(
      "definition_content_hash",
      value.definition_hash |> identity.sha256_value |> json.string,
    ),
    #("scope", json.string(value.scope)),
    #("attribution", attribution_json(value.attribution)),
    #(
      "answered_at_unix_ms",
      value.answered_at |> time.unix_milliseconds |> json.int,
    ),
    #(
      "recorded_at_unix_ms",
      value.recorded_at |> time.unix_milliseconds |> json.int,
    ),
    #("answers", json.array(value.answers, answer_json)),
    #("source_receipts", hashes_json(value.source_receipts)),
    #("answer_counts", answer_counts_json(value.answers)),
    #("decision_owner", json.string("llm")),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
  |> receipt.envelope
}

fn validate_items(
  values: List(Item),
  seen: List(String),
) -> Result(Nil, ChecklistError) {
  case values, list.length(values) > maximum_items {
    [], _ -> Error(EmptyItems)
    _, True -> Error(TooManyItems(list.length(values), maximum_items))
    _, False -> validate_item_loop(values, seen)
  }
}

fn validate_item_loop(
  values: List(Item),
  seen: List(String),
) -> Result(Nil, ChecklistError) {
  case values {
    [] -> Ok(Nil)
    [Item(id, prompt, schema, role, _), ..rest] -> {
      use _ <- result.try(valid_text(id, "item_id"))
      use _ <- result.try(valid_text(prompt, "prompt_text"))
      use _ <- result.try(validate_optional(role, "role"))
      use _ <- result.try(validate_schema(schema))
      case list.contains(seen, id) {
        True -> Error(DuplicateItemId(id))
        False -> validate_item_loop(rest, [id, ..seen])
      }
    }
  }
}

fn validate_answers(
  values: List(Answer),
  items: List(Item),
  seen: List(String),
) -> Result(Nil, ChecklistError) {
  case values {
    [] -> Ok(Nil)
    [Answer(id, state, _), ..rest] ->
      case list.contains(seen, id), find_item(items, id) {
        True, _ -> Error(DuplicateAnswer(id))
        False, None -> Error(UnknownItem(id))
        False, Some(item) ->
          case answer_matches(item, state) {
            False -> Error(AnswerDoesNotMatchSchema(id))
            True -> validate_answers(rest, items, [id, ..seen])
          }
      }
  }
}

fn answer_matches(item: Item, state: AnswerState) -> Bool {
  let Item(_, _, schema, _, _) = item
  case state {
    Unknown(_) | NotAsked | Declined | NotApplicable(_) -> True
    Yes | No ->
      case schema {
        YesNo | YesNoUnknown -> True
        _ -> False
      }
    Text(_) -> schema == FreeText
    NumericValue(_, unit) ->
      case schema {
        Numeric(expected) -> unit == expected
        Scale(_, _) -> True
        _ -> False
      }
    Declared(_) ->
      case schema {
        DeclaredValue(_) -> True
        _ -> False
      }
  }
}

fn validate_schema(value: AnswerSchema) -> Result(Nil, ChecklistError) {
  case value {
    Scale(minimum, maximum) if minimum >= maximum ->
      Error(InvalidScale(minimum, maximum))
    Numeric(unit) -> valid_text(unit, "numeric_unit")
    _ -> Ok(Nil)
  }
}

fn validate_attribution(value: Attribution) -> Result(Nil, ChecklistError) {
  case value {
    event.UserDeclared(_) | event.LlmDeclared(_, _) -> Ok(Nil)
    _ -> Error(UnsupportedAttribution)
  }
}

fn find_item(values: List(Item), id: String) -> Option(Item) {
  case
    list.find(values, fn(value) {
      let Item(item_id, _, _, _, _) = value
      item_id == id
    })
  {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn item_json(value: Item) -> json.Json {
  let Item(id, prompt, schema, role, evidence_slot) = value
  json.object([
    #("item_id", json.string(id)),
    #("prompt_text", json.string(prompt)),
    #("answer_schema", answer_schema_json(schema)),
    #("role", json.nullable(role, json.string)),
    #("evidence_slot", json.bool(evidence_slot)),
  ])
}

fn answer_schema_json(value: AnswerSchema) -> json.Json {
  case value {
    YesNo -> tagged("yes_no")
    YesNoUnknown -> tagged("yes_no_unknown")
    Scale(minimum, maximum) ->
      json.object([
        #("kind", json.string("scale")),
        #("minimum", json.int(minimum)),
        #("maximum", json.int(maximum)),
      ])
    FreeText -> tagged("free_text")
    Numeric(unit) ->
      json.object([
        #("kind", json.string("numeric")),
        #("unit", json.string(unit)),
      ])
    DeclaredValue(reference) ->
      json.object([
        #("kind", json.string("declared_value")),
        #(
          "vocabulary_reference",
          json.nullable(reference, fn(value) {
            value |> identity.sha256_value |> json.string
          }),
        ),
      ])
  }
}

fn answer_json(value: Answer) -> json.Json {
  let Answer(id, state, evidence_reference) = value
  json.object([
    #("item_id", json.string(id)),
    #("state", answer_state_json(state)),
    #(
      "evidence_reference",
      json.nullable(evidence_reference, fn(value) {
        value |> identity.sha256_value |> json.string
      }),
    ),
  ])
}

fn answer_state_json(value: AnswerState) -> json.Json {
  case value {
    Yes -> tagged("yes")
    No -> tagged("no")
    Unknown(reason) -> reason_json("unknown", reason)
    NotAsked -> tagged("not_asked")
    Declined -> tagged("declined")
    NotApplicable(reason) -> reason_json("not_applicable", reason)
    Text(value) ->
      json.object([
        #("kind", json.string("text")),
        #("value", json.string(value)),
      ])
    NumericValue(lexeme, unit) ->
      json.object([
        #("kind", json.string("numeric")),
        #("lexeme", json.string(lexeme)),
        #("unit", json.string(unit)),
      ])
    Declared(value) ->
      json.object([
        #("kind", json.string("declared")),
        #("value", json.string(value)),
      ])
  }
}

fn answer_counts_json(values: List(Answer)) -> json.Json {
  json.object([
    #("answered", values |> list.filter(is_answered) |> list.length |> json.int),
    #(
      "unknown",
      values
        |> list.filter(fn(value) {
          let Answer(_, state, _) = value
          case state {
            Unknown(_) -> True
            _ -> False
          }
        })
        |> list.length
        |> json.int,
    ),
    #(
      "not_asked",
      count_state(values, fn(value) { value == NotAsked }) |> json.int,
    ),
    #(
      "declined",
      count_state(values, fn(value) { value == Declined }) |> json.int,
    ),
    #(
      "not_applicable",
      values
        |> list.filter(fn(value) {
          let Answer(_, state, _) = value
          case state {
            NotApplicable(_) -> True
            _ -> False
          }
        })
        |> list.length
        |> json.int,
    ),
  ])
}

fn is_answered(value: Answer) -> Bool {
  let Answer(_, state, _) = value
  case state {
    Yes | No | Text(_) | NumericValue(_, _) | Declared(_) -> True
    _ -> False
  }
}

fn count_state(
  values: List(Answer),
  predicate: fn(AnswerState) -> Bool,
) -> Int {
  values
  |> list.filter(fn(value) {
    let Answer(_, state, _) = value
    predicate(state)
  })
  |> list.length
}

fn attribution_json(value: Attribution) -> json.Json {
  json.object([#("kind", value |> event.attribution_name |> json.string)])
}

fn hashes_json(values: List(Sha256)) -> json.Json {
  values
  |> list.map(identity.sha256_value)
  |> json.array(json.string)
}

fn tagged(kind: String) -> json.Json {
  json.object([#("kind", json.string(kind))])
}

fn reason_json(kind: String, reason: String) -> json.Json {
  json.object([
    #("kind", json.string(kind)),
    #("reason", json.string(reason)),
  ])
}

fn validate_optional(
  value: Option(String),
  field: String,
) -> Result(Nil, ChecklistError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> valid_text(value, field)
  }
}

fn valid_text(value: String, field: String) -> Result(Nil, ChecklistError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

pub fn definition_id(value: Definition) -> String {
  value.definition_id
}

pub fn definition_version(value: Definition) -> String {
  value.version
}

pub fn items(value: Definition) -> List(Item) {
  value.items
}

pub fn answers(value: Response) -> List(Answer) {
  value.answers
}

pub fn response_definition_hash(value: Response) -> Sha256 {
  value.definition_hash
}
