import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_sec
import finance_sec/request
import finance_sec/runtime
import finance_sec/xbrl.{
  type CompanyConcept, type CompanyFacts, type Concept, type FactValue,
}
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_sec_xbrl/concept_search
import pi_sparkles_sec_xbrl/effect/environment
import pi_sparkles_sec_xbrl/fact_selection

pub type ConceptSearchInput {
  ConceptSearchInput(cik: finance_sec.Cik, plan: concept_search.Plan)
}

pub type FactsInput {
  FactsInput(
    cik: finance_sec.Cik,
    concept: xbrl.ConceptId,
    plan: fact_selection.Plan,
  )
}

type Provider {
  Ready(access: finance_sec.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  tool.register(
    api,
    "sec_xbrl_concepts",
    "SEC XBRL concepts",
    "Search standard SEC company-facts concepts without guessing a taxonomy tag; custom and dimensional facts are outside this API",
    "Discover an exact taxonomy and concept tag before requesting raw facts",
    tool.parameters(concept_search_schema(), concept_search_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_company_facts(
            provider_runtime,
            access,
            input.cik,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(company) -> {
              let matches = concept_search.find(company.concepts, input.plan)
              tool.text_result(
                render_concepts(company, matches),
                concepts_json(company, matches),
              )
              |> promise.resolve
            }
          }
        }
      }
    },
  )

  tool.register(
    api,
    "sec_xbrl_facts",
    "SEC XBRL facts",
    "Retrieve exact raw SEC XBRL facts for one validated taxonomy/tag, preserving units, periods, filings, amendments, frames, and duplicates",
    "Inspect primary reported values before building a normalized metric",
    tool.parameters(facts_schema(), facts_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_company_concept(
            provider_runtime,
            access,
            input.cik,
            input.concept,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(company) -> {
              let selection = fact_selection.select(company.concept, input.plan)
              tool.text_result(
                render_facts(company, selection),
                facts_json(company, selection),
              )
              |> promise.resolve
            }
          }
        }
      }
    },
  )

  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_sec.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "SEC access requires SEC_USER_AGENT_CONTACT (for example ops@example.com); SEC_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case runtime.new(access) {
        Error(_) ->
          InvalidConfiguration("SEC XBRL runtime could not initialize safely")
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch_company_facts(
  provider_runtime: runtime.Runtime,
  access: finance_sec.Access,
  cik: finance_sec.Cik,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(CompanyFacts, String)) {
  case request.company_facts(access, cik) {
    Error(_) -> promise.resolve(Error("SEC company-facts request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_body(outcome, "company facts") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case xbrl.decode_company_facts(body) {
            Error(_) ->
              promise.resolve(Error("SEC returned invalid company-facts data"))
            Ok(company) -> promise.resolve(Ok(company))
          }
      }
    }
  }
}

fn fetch_company_concept(
  provider_runtime: runtime.Runtime,
  access: finance_sec.Access,
  cik: finance_sec.Cik,
  concept: xbrl.ConceptId,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(CompanyConcept, String)) {
  case request.company_concept(access, cik, concept) {
    Error(_) ->
      promise.resolve(Error("SEC company-concept request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_body(outcome, "company concept") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case xbrl.decode_company_concept(body) {
            Error(_) ->
              promise.resolve(Error("SEC returned invalid company-concept data"))
            Ok(company) -> promise.resolve(Ok(company))
          }
      }
    }
  }
}

fn checked_body(
  outcome: Result(http_response.Response, pool.PoolError),
  resource: String,
) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "SEC "
        <> resource
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(value))
        False ->
          Error(
            "SEC "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn concept_search_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cik",
      schema.string()
        |> schema.with_string_length(1, 10)
        |> schema.described("SEC CIK, with or without leading zeroes"),
    ),
    schema.Required(
      "query",
      schema.string()
        |> schema.with_string_length(1, 200)
        |> schema.described("Concept tag, label, or description text"),
    ),
    schema.Optional(
      "taxonomy",
      schema.string()
        |> schema.with_string_length(1, 50)
        |> schema.described(
          "Optional taxonomy filter such as us-gaap or ifrs-full",
        ),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 50.0)
        |> schema.described("Maximum concept candidates; defaults to 20"),
    ),
  ])
}

fn facts_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cik",
      schema.string()
        |> schema.with_string_length(1, 10)
        |> schema.described("SEC CIK, with or without leading zeroes"),
    ),
    schema.Required(
      "taxonomy",
      schema.string()
        |> schema.with_string_length(1, 50)
        |> schema.described("Exact standard taxonomy, for example us-gaap"),
    ),
    schema.Required(
      "tag",
      schema.string()
        |> schema.with_string_length(1, 200)
        |> schema.described("Exact XBRL concept tag"),
    ),
    schema.Optional(
      "unit",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described("Exact SEC unit key such as USD or shares"),
    ),
    schema.Optional(
      "form",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Exact form such as 10-K, 10-K/A, or 10-Q"),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 100.0)
        |> schema.described(
          "Maximum facts in latest-filed order; defaults to 20",
        ),
    ),
  ])
}

fn concept_search_decoder() -> decode.Decoder(ConceptSearchInput) {
  use cik_value <- decode.field("cik", decode.string)
  use query <- decode.field("query", decode.string)
  use taxonomy <- optional_string_field("taxonomy")
  use limit <- decode.optional_field("limit", 20, decode.int)
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_plan) = concept_search.plan("Assets", None, 20)
  case finance_sec.cik(cik_value), concept_search.plan(query, taxonomy, limit) {
    Ok(cik), Ok(plan) -> decode.success(ConceptSearchInput(cik, plan))
    _, _ ->
      decode.failure(
        ConceptSearchInput(placeholder_cik, placeholder_plan),
        "valid SEC XBRL concept search",
      )
  }
}

fn facts_decoder() -> decode.Decoder(FactsInput) {
  use cik_value <- decode.field("cik", decode.string)
  use taxonomy <- decode.field("taxonomy", decode.string)
  use tag <- decode.field("tag", decode.string)
  use unit <- optional_string_field("unit")
  use form <- optional_string_field("form")
  use limit <- decode.optional_field("limit", 20, decode.int)
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_id) = xbrl.concept_id("us-gaap", "Assets")
  let assert Ok(placeholder_plan) = fact_selection.plan(None, None, 20)
  case
    finance_sec.cik(cik_value),
    xbrl.concept_id(taxonomy, tag),
    fact_selection.plan(unit, form, limit)
  {
    Ok(cik), Ok(concept), Ok(plan) ->
      decode.success(FactsInput(cik, concept, plan))
    _, _, _ ->
      decode.failure(
        FactsInput(placeholder_cik, placeholder_id, placeholder_plan),
        "valid SEC XBRL fact selection",
      )
  }
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn render_concepts(
  company: CompanyFacts,
  matches: List(concept_search.Match),
) -> String {
  "US track | SEC EDGAR XBRL\n"
  <> case matches {
    [] ->
      company.entity_name <> ": no standard entity-wide XBRL concepts matched"
    matches ->
      company.entity_name
      <> " SEC XBRL concept candidates ("
      <> int.to_string(list.length(matches))
      <> "):\n"
      <> {
        matches
        |> list.map(fn(value) {
          "- "
          <> xbrl.taxonomy(value.concept.id)
          <> ":"
          <> xbrl.tag(value.concept.id)
          <> " | "
          <> value.concept.label
          <> " | units "
          <> unit_names(value.concept)
          <> " | "
          <> concept_search.reason_name(value.reason)
        })
        |> string.join("\n")
      }
  }
}

fn render_facts(
  company: CompanyConcept,
  selection: fact_selection.Selection,
) -> String {
  let concept = company.concept
  "US track | SEC EDGAR XBRL\n"
  <> case selection.facts {
    [] ->
      company.entity_name
      <> " "
      <> xbrl.taxonomy(concept.id)
      <> ":"
      <> xbrl.tag(concept.id)
      <> ": no facts matched the requested unit/form"
    facts ->
      company.entity_name
      <> " "
      <> xbrl.taxonomy(concept.id)
      <> ":"
      <> xbrl.tag(concept.id)
      <> " raw facts ("
      <> int.to_string(list.length(facts))
      <> " of "
      <> int.to_string(selection.total)
      <> "):\n"
      <> {
        facts
        |> list.map(fn(selected) {
          "- "
          <> fact_value_text(selected.fact.value)
          <> " "
          <> selected.unit
          <> " | period "
          <> period_text(selected.fact.start, selected.fact.end)
          <> " | "
          <> selected.fact.form
          <> " filed "
          <> selected.fact.filed
          <> " | accession "
          <> selected.fact.accession
        })
        |> string.join("\n")
      }
  }
}

fn concepts_json(
  company: CompanyFacts,
  matches: List(concept_search.Match),
) -> json.Json {
  json.object(
    list.append(
      provider_fields(
        "https://data.sec.gov/api/xbrl/companyfacts/CIK"
        <> finance_sec.cik_value(company.cik)
        <> ".json",
      ),
      [
        #("cik", json.string(finance_sec.cik_value(company.cik))),
        #("company", json.string(company.entity_name)),
        #("candidates", json.array(matches, concept_match_json)),
      ],
    ),
  )
}

fn facts_json(
  company: CompanyConcept,
  selection: fact_selection.Selection,
) -> json.Json {
  let concept = company.concept
  json.object(
    list.append(
      provider_fields(
        "https://data.sec.gov/api/xbrl/companyconcept/CIK"
        <> finance_sec.cik_value(company.cik)
        <> "/"
        <> xbrl.taxonomy(concept.id)
        <> "/"
        <> xbrl.tag(concept.id)
        <> ".json",
      ),
      [
        #("cik", json.string(finance_sec.cik_value(company.cik))),
        #("company", json.string(company.entity_name)),
        #("taxonomy", json.string(xbrl.taxonomy(concept.id))),
        #("tag", json.string(xbrl.tag(concept.id))),
        #("label", json.string(concept.label)),
        #("description", json.string(concept.description)),
        #("totalMatching", json.int(selection.total)),
        #("truncated", json.bool(selection.truncated)),
        #("duplicatesPreserved", json.bool(True)),
        #("facts", json.array(selection.facts, selected_fact_json)),
      ],
    ),
  )
}

fn provider_fields(source: String) -> List(#(String, json.Json)) {
  list.append(us_track_fields(), [
    #("provider", json.string("SEC EDGAR XBRL")),
    #("source", json.string(source)),
    #("access", json.string("read_only_public_data")),
    #("entitlement", json.string("sec_public_data_fair_access_terms_apply")),
    #(
      "freshness",
      json.string("sec_xbrl_real_time_typical_delay_under_one_minute"),
    ),
    #(
      "coverage",
      json.string("non_custom_taxonomies_and_entity_wide_facts_only"),
    ),
    #(
      "warning",
      json.string(
        "Raw reported facts are not normalized metrics; units, periods, forms, amendments, frames, and duplicates must be interpreted explicitly",
      ),
    ),
  ])
}

fn us_track_fields() -> List(#(String, json.Json)) {
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: "us_sec_xbrl_company_facts",
      venue_mic: None,
      board: None,
      timezone: None,
      source_language: "en-US",
      providers: ["SEC EDGAR XBRL"],
      entitlement: "sec_public_data_fair_access_terms_apply",
      limitations: ["non_custom_taxonomies_only", "entity_wide_facts_only"],
    )
  track_json.result_fields(value)
}

fn concept_match_json(value: concept_search.Match) -> json.Json {
  json.object([
    #("taxonomy", json.string(xbrl.taxonomy(value.concept.id))),
    #("tag", json.string(xbrl.tag(value.concept.id))),
    #("label", json.string(value.concept.label)),
    #("description", json.string(value.concept.description)),
    #(
      "units",
      json.array(value.concept.units, fn(unit) { json.string(unit.unit) }),
    ),
    #("match", json.string(concept_search.reason_name(value.reason))),
  ])
}

fn selected_fact_json(value: fact_selection.SelectedFact) -> json.Json {
  json.object([
    #("value", json.string(fact_value_text(value.fact.value))),
    #("valueKind", json.string(fact_value_kind(value.fact.value))),
    #("unit", json.string(value.unit)),
    #("start", optional_json(value.fact.start)),
    #("end", json.string(value.fact.end)),
    #(
      "periodKind",
      json.string(case value.fact.start {
        Some(_) -> "duration"
        None -> "instant"
      }),
    ),
    #("accession", json.string(value.fact.accession)),
    #("fiscalYear", optional_json(value.fact.fiscal_year)),
    #("fiscalPeriod", optional_json(value.fact.fiscal_period)),
    #("form", json.string(value.fact.form)),
    #("amendment", json.bool(string.ends_with(value.fact.form, "/A"))),
    #("filed", json.string(value.fact.filed)),
    #("frame", optional_json(value.fact.frame)),
  ])
}

fn fact_value_text(value: FactValue) -> String {
  case value {
    xbrl.Numeric(raw) -> raw
    xbrl.Text(value) -> value
    xbrl.Boolean(True) -> "true"
    xbrl.Boolean(False) -> "false"
  }
}

fn fact_value_kind(value: FactValue) -> String {
  case value {
    xbrl.Numeric(_) -> "numeric_exact_lexeme"
    xbrl.Text(_) -> "text"
    xbrl.Boolean(_) -> "boolean"
  }
}

fn period_text(start: Option(String), end: String) -> String {
  case start {
    Some(start) -> start <> " to " <> end
    None -> end
  }
}

fn optional_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn unit_names(concept: Concept) -> String {
  concept.units
  |> list.map(fn(value) { value.unit })
  |> string.join(", ")
}
