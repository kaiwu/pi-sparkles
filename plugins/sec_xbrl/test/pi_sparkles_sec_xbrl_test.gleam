import finance_sec/xbrl.{Concept, Fact, Numeric, UnitFacts}
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_sec_xbrl/concept_search
import pi_sparkles_sec_xbrl/fact_selection

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn concept_search_ranks_exact_tags_and_filters_taxonomy_test() {
  let revenue = concept("us-gaap", "Revenue", "Revenue", "Sales")
  let other = concept("dei", "EntityRevenue", "Entity revenue", "Revenue")
  let assert Ok(plan) = concept_search.plan("revenue", Some("US-GAAP"), 10)
  let assert [match] = concept_search.find([other, revenue], plan)
  match.concept |> should.equal(revenue)
  match.reason |> should.equal(concept_search.ExactTag)
}

pub fn fact_selection_preserves_duplicates_and_orders_latest_filing_test() {
  let first = fact("a", "2025-02-01", "10-K", "100")
  let amended = fact("b", "2025-02-02", "10-K/A", "101")
  let concept =
    Concept(id("us-gaap", "Revenue"), "Revenue", "Sales", [
      UnitFacts("USD", [first, amended]),
    ])
  let assert Ok(plan) = fact_selection.plan(Some("USD"), None, 10)
  let selection = fact_selection.select(concept, plan)
  selection.total |> should.equal(2)
  selection.truncated |> should.be_false
  let assert [latest, original] = selection.facts
  latest.fact.accession |> should.equal("b")
  original.fact.accession |> should.equal("a")
}

pub fn exact_form_filter_and_limit_are_explicit_test() {
  let concept =
    Concept(id("us-gaap", "Assets"), "Assets", "Total assets", [
      UnitFacts("USD", [
        fact("a", "2025-01-01", "10-K", "100"),
        fact("b", "2025-02-01", "10-Q", "110"),
      ]),
    ])
  let assert Ok(plan) = fact_selection.plan(None, Some("10-q"), 1)
  let selection = fact_selection.select(concept, plan)
  selection.total |> should.equal(1)
  let assert [selected] = selection.facts
  selected.fact.form |> should.equal("10-Q")
  fact_selection.plan(None, None, 101)
  |> should.equal(Error(fact_selection.InvalidLimit))
}

fn concept(
  taxonomy: String,
  tag: String,
  label: String,
  description: String,
) -> xbrl.Concept {
  Concept(id(taxonomy, tag), label, description, [])
}

fn id(taxonomy: String, tag: String) -> xbrl.ConceptId {
  let assert Ok(value) = xbrl.concept_id(taxonomy, tag)
  value
}

fn fact(
  accession: String,
  filed: String,
  form: String,
  value: String,
) -> xbrl.Fact {
  Fact(
    None,
    "2024-12-31",
    Numeric(value),
    accession,
    Some("2024"),
    Some("FY"),
    form,
    filed,
    None,
  )
}
