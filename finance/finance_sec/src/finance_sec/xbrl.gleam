import finance_sec.{type Cik}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam/string

pub opaque type ConceptId {
  ConceptId(taxonomy: String, tag: String)
}

pub type ConceptIdError {
  InvalidTaxonomy
  InvalidTag
}

pub type FactValue {
  Numeric(raw: String)
  Text(value: String)
  Boolean(value: Bool)
}

pub type Fact {
  Fact(
    start: Option(String),
    end: String,
    value: FactValue,
    accession: String,
    fiscal_year: Option(String),
    fiscal_period: Option(String),
    form: String,
    filed: String,
    frame: Option(String),
  )
}

pub type UnitFacts {
  UnitFacts(unit: String, facts: List(Fact))
}

pub type Concept {
  Concept(
    id: ConceptId,
    label: String,
    description: String,
    units: List(UnitFacts),
  )
}

pub type CompanyFacts {
  CompanyFacts(cik: Cik, entity_name: String, concepts: List(Concept))
}

pub type CompanyConcept {
  CompanyConcept(cik: Cik, entity_name: String, concept: Concept)
}

type RawConcept {
  RawConcept(
    label: String,
    description: String,
    units: Dict(String, List(Fact)),
  )
}

pub fn concept_id(
  taxonomy: String,
  tag: String,
) -> Result(ConceptId, ConceptIdError) {
  case valid_path_segment(taxonomy, 50), valid_path_segment(tag, 200) {
    False, _ -> Error(InvalidTaxonomy)
    _, False -> Error(InvalidTag)
    True, True -> Ok(ConceptId(taxonomy, tag))
  }
}

pub fn taxonomy(value: ConceptId) -> String {
  let ConceptId(taxonomy, _) = value
  taxonomy
}

pub fn tag(value: ConceptId) -> String {
  let ConceptId(_, tag) = value
  tag
}

pub fn decode_company_facts(
  body: String,
) -> Result(CompanyFacts, json.DecodeError) {
  body
  |> normalize_numbers
  |> json.parse(company_facts_decoder())
}

pub fn decode_company_concept(
  body: String,
) -> Result(CompanyConcept, json.DecodeError) {
  body
  |> normalize_numbers
  |> json.parse(company_concept_decoder())
}

fn company_facts_decoder() -> decode.Decoder(CompanyFacts) {
  use cik_value <- decode.field("cik", scalar_string_decoder())
  use entity_name <- decode.field("entityName", decode.string)
  use taxonomies <- decode.field(
    "facts",
    decode.dict(
      decode.string,
      decode.dict(decode.string, raw_concept_decoder()),
    ),
  )
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  case finance_sec.cik(cik_value) {
    Error(_) ->
      decode.failure(
        CompanyFacts(placeholder_cik, entity_name, []),
        "valid SEC company-facts CIK",
      )
    Ok(cik) ->
      decode.success(CompanyFacts(cik, entity_name, flatten(taxonomies)))
  }
}

fn company_concept_decoder() -> decode.Decoder(CompanyConcept) {
  use cik_value <- decode.field("cik", scalar_string_decoder())
  use entity_name <- decode.field("entityName", decode.string)
  use taxonomy_value <- decode.field("taxonomy", decode.string)
  use tag_value <- decode.field("tag", decode.string)
  use label <- decode.field("label", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use units <- decode.field(
    "units",
    decode.dict(decode.string, decode.list(of: fact_decoder())),
  )
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_id) = concept_id("us-gaap", "Assets")
  case finance_sec.cik(cik_value), concept_id(taxonomy_value, tag_value) {
    Ok(cik), Ok(id) ->
      decode.success(CompanyConcept(
        cik,
        entity_name,
        Concept(id, label, description, unit_list(units)),
      ))
    _, _ ->
      decode.failure(
        CompanyConcept(
          placeholder_cik,
          entity_name,
          Concept(placeholder_id, label, description, []),
        ),
        "valid SEC company-concept identity",
      )
  }
}

fn raw_concept_decoder() -> decode.Decoder(RawConcept) {
  use label <- decode.field("label", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use units <- decode.field(
    "units",
    decode.dict(decode.string, decode.list(of: fact_decoder())),
  )
  decode.success(RawConcept(label, description, units))
}

fn fact_decoder() -> decode.Decoder(Fact) {
  use start <- optional_string_field("start")
  use end <- decode.field("end", decode.string)
  use value <- decode.field("val", fact_value_decoder())
  use accession <- decode.field("accn", decode.string)
  use fiscal_year <- optional_scalar_string_field("fy")
  use fiscal_period <- optional_string_field("fp")
  use form <- decode.field("form", decode.string)
  use filed <- decode.field("filed", decode.string)
  use frame <- optional_string_field("frame")
  decode.success(Fact(
    start,
    end,
    value,
    accession,
    fiscal_year,
    fiscal_period,
    form,
    filed,
    frame,
  ))
}

fn fact_value_decoder() -> decode.Decoder(FactValue) {
  decode.at(["__finance_sec_number__"], decode.string)
  |> decode.map(Numeric)
  |> decode.one_of(or: [
    decode.string |> decode.map(Text),
    decode.bool |> decode.map(Boolean),
  ])
}

fn scalar_string_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_sec_number__"], decode.string)
  |> decode.one_of(or: [decode.string])
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_scalar_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(
    name,
    None,
    decode.optional(scalar_string_decoder()),
    next,
  )
}

fn flatten(
  taxonomies: Dict(String, Dict(String, RawConcept)),
) -> List(Concept) {
  taxonomies
  |> dict.to_list
  |> list.sort(by: compare_named_taxonomy)
  |> list.flat_map(fn(entry) {
    let #(taxonomy_value, concepts) = entry
    concepts
    |> dict.to_list
    |> list.sort(by: compare_named_concept)
    |> list.map(fn(concept_entry) {
      let #(tag_value, RawConcept(label, description, units)) = concept_entry
      let assert Ok(id) = concept_id(taxonomy_value, tag_value)
      Concept(id, label, description, unit_list(units))
    })
  })
}

fn unit_list(units: Dict(String, List(Fact))) -> List(UnitFacts) {
  units
  |> dict.to_list
  |> list.sort(by: compare_named_facts)
  |> list.map(fn(entry) {
    let #(unit, facts) = entry
    UnitFacts(unit, facts)
  })
}

fn compare_named_taxonomy(
  left: #(String, Dict(String, RawConcept)),
  right: #(String, Dict(String, RawConcept)),
) -> order.Order {
  string.compare(left.0, right.0)
}

fn compare_named_concept(
  left: #(String, RawConcept),
  right: #(String, RawConcept),
) -> order.Order {
  string.compare(left.0, right.0)
}

fn compare_named_facts(
  left: #(String, List(Fact)),
  right: #(String, List(Fact)),
) -> order.Order {
  string.compare(left.0, right.0)
}

fn valid_path_segment(value: String, maximum: Int) -> Bool {
  value != ""
  && string.length(value) <= maximum
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-",
        character,
      )
    })
  }
}

@external(javascript, "./xbrl_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
