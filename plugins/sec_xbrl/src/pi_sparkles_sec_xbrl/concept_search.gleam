import finance_sec/xbrl.{type Concept}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

pub opaque type Plan {
  Plan(query: String, taxonomy: Option(String), limit: Int)
}

pub type PlanError {
  InvalidQuery
  InvalidTaxonomy
  InvalidLimit
}

pub type MatchReason {
  ExactTag
  TagPrefix
  ExactLabel
  LabelContains
  DescriptionContains
}

pub type Match {
  Match(concept: Concept, reason: MatchReason)
}

type Ranked {
  Ranked(score: Int, concept: Concept)
}

pub fn plan(
  query: String,
  taxonomy: Option(String),
  limit: Int,
) -> Result(Plan, PlanError) {
  let normalized_query = query |> string.trim |> string.uppercase
  case
    normalized_query == "" || string.length(normalized_query) > 200,
    normalize_taxonomy(taxonomy),
    limit < 1 || limit > 50
  {
    True, _, _ -> Error(InvalidQuery)
    _, Error(_), _ -> Error(InvalidTaxonomy)
    _, _, True -> Error(InvalidLimit)
    False, Ok(taxonomy), False -> Ok(Plan(normalized_query, taxonomy, limit))
  }
}

pub fn find(concepts: List(Concept), plan: Plan) -> List(Match) {
  let Plan(query, taxonomy, limit) = plan
  concepts
  |> list.filter(fn(concept) {
    case taxonomy {
      None -> True
      Some(expected) -> string.lowercase(xbrl.taxonomy(concept.id)) == expected
    }
  })
  |> list.filter_map(fn(concept) {
    case rank(concept, query) {
      Error(_) -> Error(Nil)
      Ok(score) -> Ok(Ranked(score, concept))
    }
  })
  |> list.sort(by: compare_ranked)
  |> list.take(limit)
  |> list.map(fn(ranked) {
    let Ranked(score, concept) = ranked
    Match(concept, reason(score))
  })
}

pub fn reason_name(value: MatchReason) -> String {
  case value {
    ExactTag -> "exact_tag"
    TagPrefix -> "tag_prefix"
    ExactLabel -> "exact_label"
    LabelContains -> "label_contains"
    DescriptionContains -> "description_contains"
  }
}

fn rank(concept: Concept, query: String) -> Result(Int, Nil) {
  let tag = concept.id |> xbrl.tag |> string.uppercase
  let label = string.uppercase(concept.label)
  let description = string.uppercase(concept.description)
  case
    tag == query,
    string.starts_with(tag, query),
    label == query,
    string.contains(label, query),
    string.contains(description, query)
  {
    True, _, _, _, _ -> Ok(0)
    _, True, _, _, _ -> Ok(1)
    _, _, True, _, _ -> Ok(2)
    _, _, _, True, _ -> Ok(3)
    _, _, _, _, True -> Ok(4)
    False, False, False, False, False -> Error(Nil)
  }
}

fn reason(score: Int) -> MatchReason {
  case score {
    0 -> ExactTag
    1 -> TagPrefix
    2 -> ExactLabel
    3 -> LabelContains
    _ -> DescriptionContains
  }
}

fn compare_ranked(left: Ranked, right: Ranked) -> order.Order {
  let Ranked(left_score, left_concept) = left
  let Ranked(right_score, right_concept) = right
  case int.compare(left_score, right_score) {
    order.Eq -> compare_concept(left_concept, right_concept)
    other -> other
  }
}

fn compare_concept(left: Concept, right: Concept) -> order.Order {
  case string.compare(xbrl.taxonomy(left.id), xbrl.taxonomy(right.id)) {
    order.Eq -> string.compare(xbrl.tag(left.id), xbrl.tag(right.id))
    other -> other
  }
}

fn normalize_taxonomy(value: Option(String)) -> Result(Option(String), Nil) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      let normalized = value |> string.trim |> string.lowercase
      case normalized == "" || string.length(normalized) > 50 {
        True -> Error(Nil)
        False -> Ok(Some(normalized))
      }
    }
  }
}
