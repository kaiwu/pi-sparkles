import finance_calendar/local
import finance_cn_accounting/fact as cn_fact
import finance_cn_calendar/dataset as cn_calendar
import finance_cn_identity/identity
import finance_cn_rules/rule as cn_rule
import finance_cn_testkit
import finance_cn_testkit/scenario
import finance_core/currency
import finance_core/instrument
import finance_core/time
import finance_market_accounting/fact as market_fact
import finance_market_calendar/dataset as market_calendar
import finance_market_documents/document as market_document
import finance_market_rules/rule as market_rule
import finance_testkit/seed
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_cn_testkit.status() |> should.equal(finance_cn_testkit.Experimental)
}

pub fn generation_is_seed_stable_and_labelled_synthetic_test() {
  let assert Ok(first_seed) = seed.new(42)
  let assert Ok(second_seed) = seed.new(42)
  let #(first_next, first) = scenario.generate(first_seed)
  let #(second_next, second) = scenario.generate(second_seed)

  first |> should.equal(second)
  seed.value(first_next) |> should.equal(seed.value(second_next))
  scenario.algorithm_version |> should.equal(1)
}

pub fn catalogue_covers_market_owned_identity_rule_and_document_edges_test() {
  let assert Ok(seed) = seed.new(7)
  let cases =
    scenario.all_cases()
    |> list.map(fn(market_case) { scenario.for_case(market_case, seed) })

  cases |> list.length |> should.equal(6)
  let assert Ok(suspended) =
    list.find(cases, fn(value) { value.kind == scenario.Suspended })
  identity.status(suspended.listing) |> should.equal(instrument.Suspended)
  let assert [suspended_rule] = suspended.rules
  cn_rule.market_status(suspended_rule) |> should.equal(cn_rule.Suspended)
  suspended_rule
  |> cn_rule.common
  |> market_rule.price_limit
  |> should.equal(market_rule.TradingProhibited)

  let assert Ok(b_share) =
    list.find(cases, fn(value) { value.kind == scenario.BShareCurrency })
  b_share.listing |> identity.currency |> currency.code |> should.equal("USD")

  let assert Ok(corrected) =
    list.find(cases, fn(value) { value.kind == scenario.CorrectedAnnualReport })
  corrected.relations |> list.length |> should.equal(1)
  let assert [relation] = corrected.relations
  market_document.relation_kind(relation)
  |> should.equal(market_document.Correction)
  let assert [first_fact, ..] = corrected.facts
  first_fact
  |> cn_fact.common
  |> market_fact.value
  |> market_fact.raw_numeric
  |> should.equal(Some("9007199254740993.0100"))
}

pub fn every_scenario_calendar_preserves_midday_closure_test() {
  let assert Ok(seed) = seed.new(9)
  scenario.all_cases()
  |> list.map(fn(market_case) { scenario.for_case(market_case, seed) })
  |> list.all(fn(value) {
    market_calendar.session_at(value.calendar, zoned(2024, 6, 3, 12, 0))
    == Ok(None)
  })
  |> should.be_true
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn zoned(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
) -> local.ZonedDateTime {
  let assert Ok(clock) = time.time_of_day(hour, minute)
  let assert Ok(value) =
    local.zoned_date_time(
      date: civil(year, month, day),
      time: clock,
      zone: cn_calendar.shanghai_zone(),
      utc_offset_minutes: 480,
    )
  value
}
