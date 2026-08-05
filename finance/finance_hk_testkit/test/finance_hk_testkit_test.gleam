import finance_calendar/local
import finance_core/instrument
import finance_core/time
import finance_hk_accounting/fact as hk_fact
import finance_hk_calendar/dataset as hk_calendar
import finance_hk_identity/identity
import finance_hk_rules/rule as hk_rule
import finance_hk_testkit
import finance_hk_testkit/scenario
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
  finance_hk_testkit.status() |> should.equal(finance_hk_testkit.Experimental)
}

pub fn generation_is_seed_stable_and_track_owned_test() {
  let assert Ok(first_seed) = seed.new(42)
  let assert Ok(second_seed) = seed.new(42)
  let #(first_next, first) = scenario.generate(first_seed)
  let #(second_next, second) = scenario.generate(second_seed)

  first |> should.equal(second)
  seed.value(first_next) |> should.equal(seed.value(second_next))
  scenario.algorithm_version |> should.equal(1)
}

pub fn catalogue_preserves_leading_zero_lots_status_languages_and_scale_test() {
  let assert Ok(seed) = seed.new(13)
  let cases =
    scenario.all_cases()
    |> list.map(fn(market_case) { scenario.for_case(market_case, seed) })

  cases |> list.length |> should.equal(6)
  let assert Ok(main) =
    list.find(cases, fn(value) { value.kind == scenario.MainBoard })
  identity.code(main.listing) |> should.equal("00001")
  let assert [main_rule] = main.rules
  main_rule |> hk_rule.common |> market_rule.buy_lot |> should.equal(500)

  let assert Ok(suspended) =
    list.find(cases, fn(value) { value.kind == scenario.Suspended })
  identity.status(suspended.listing) |> should.equal(instrument.Suspended)
  let assert [suspended_rule] = suspended.rules
  suspended_rule
  |> hk_rule.common
  |> market_rule.price_limit
  |> should.equal(market_rule.TradingProhibited)

  let assert Ok(parallel) =
    list.find(cases, fn(value) { value.kind == scenario.ParallelLanguageReport })
  let assert [relation] = parallel.relations
  market_document.relation_kind(relation)
  |> should.equal(market_document.ParallelLanguage)

  let assert [first_fact] = main.facts
  first_fact
  |> hk_fact.common
  |> market_fact.value
  |> market_fact.raw_numeric
  |> should.equal(Some("9007199254740993.0100"))
  first_fact
  |> hk_fact.common
  |> market_fact.reported_scale
  |> market_fact.scale_label
  |> should.equal("港幣千元")
}

pub fn every_scenario_calendar_preserves_hong_kong_midday_closure_test() {
  let assert Ok(seed) = seed.new(17)
  scenario.all_cases()
  |> list.map(fn(market_case) { scenario.for_case(market_case, seed) })
  |> list.all(fn(value) {
    market_calendar.session_at(value.calendar, zoned(2024, 6, 3, 12, 30))
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
      zone: hk_calendar.hong_kong_zone(),
      utc_offset_minutes: 480,
    )
  value
}
