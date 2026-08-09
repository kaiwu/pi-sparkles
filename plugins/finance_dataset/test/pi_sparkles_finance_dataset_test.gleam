import finance_core/time
import finance_provenance/hash as provenance_hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact
import finance_replay/manifest
import finance_track
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_dataset/decode
import pi_sparkles_finance_dataset/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn inspect_reports_exact_coverage_counts_states_and_omissions_test() {
  let assert Ok(response) =
    domain.run_inspect(decode.InspectInput(dataset_input()))
  let text = response_text(response)
  text |> string.contains("\"manifestId\":\"dataset-us\"") |> should.be_true
  text |> string.contains("\"track\":\"us\"") |> should.be_true
  text
  |> string.contains(
    "\"coverage\":{\"start\":\"2026-02-01\",\"end\":\"2026-02-28\"}",
  )
  |> should.be_true
  text |> string.contains("\"observations\":3") |> should.be_true
  text |> string.contains("\"distinctObservationDates\":2") |> should.be_true
  text |> string.contains("\"suppliedOmissions\":1") |> should.be_true
  text |> string.contains("\"providerOmission\":1") |> should.be_true
  text |> string.contains("\"conflicting\":1") |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn drill_preserves_original_then_corrected_manifest_order_with_paging_test() {
  let first =
    decode.DrillInput(dataset_input(), "listing:A", "2026-02-24", 0, 1)
  let assert Ok(first_response) = domain.run_drill(first)
  let first_text = response_text(first_response)
  first_text |> string.contains("\"matchedCount\":2") |> should.be_true
  first_text |> string.contains("\"nextOffset\":1") |> should.be_true
  first_text
  |> string.contains("\"observationId\":\"obs-original\"")
  |> should.be_true
  first_text |> string.contains("obs-corrected") |> should.be_false

  let second =
    decode.DrillInput(dataset_input(), "listing:A", "2026-02-24", 1, 1)
  let assert Ok(second_response) = domain.run_drill(second)
  let second_text = response_text(second_response)
  second_text |> string.contains("\"nextOffset\":null") |> should.be_true
  second_text
  |> string.contains("\"observationId\":\"obs-corrected\"")
  |> should.be_true
  second_text
  |> string.contains(
    "\"correctionLineage\":[\"" <> sha_text("obs-original") <> "\"]",
  )
  |> should.be_true
}

pub fn drill_returns_exact_omission_without_synthesizing_an_observation_test() {
  let input =
    decode.DrillInput(dataset_input(), "listing:A", "2026-02-25", 0, 10)
  let assert Ok(response) = domain.run_drill(input)
  let text = response_text(response)
  text |> string.contains("\"matchedCount\":1") |> should.be_true
  text |> string.contains("\"kind\":\"omission\"") |> should.be_true
  text
  |> string.contains("\"state\":\"provider_omission\"")
  |> should.be_true
  text
  |> string.contains("caller_supplied_finance_ohlcv_gap_projection")
  |> should.be_true
  text |> string.contains("\"kind\":\"observation\"") |> should.be_false
}

pub fn vintage_listing_retains_all_fact_states_and_uses_exact_filters_test() {
  let input =
    decode.VintagesInput(
      dataset_input(),
      Some("listing:A"),
      Some("2026-02-24"),
      0,
      10,
    )
  let assert Ok(response) = domain.run_vintages(input)
  let text = response_text(response)
  text |> string.contains("\"matchedCount\":2") |> should.be_true
  text |> string.contains("obs-original") |> should.be_true
  text |> string.contains("obs-corrected") |> should.be_true
  text
  |> string.contains(
    "\"correctionVintage\":{\"state\":\"known\",\"value\":\"original\"}",
  )
  |> should.be_true
  text |> string.contains("\"preferredVintage\"") |> should.be_false
  text |> string.contains("\"latestVintage\"") |> should.be_false
}

pub fn unknown_and_conflicting_vintage_facts_remain_explicit_test() {
  let input =
    decode.VintagesInput(
      dataset_input(),
      Some("listing:A"),
      Some("2026-02-26"),
      0,
      10,
    )
  let assert Ok(response) = domain.run_vintages(input)
  let text = response_text(response)
  text
  |> string.contains(
    "\"availabilityTime\":{\"state\":\"unknown\",\"reason\":\"provider availability time absent\"}",
  )
  |> should.be_true
  text
  |> string.contains(
    "\"knowledgeTime\":{\"state\":\"not_obtained\",\"reason\":\"knowledge receipt absent\"}",
  )
  |> should.be_true
  text
  |> string.contains(
    "\"correctionVintage\":{\"state\":\"conflicting\",\"alternatives\":[\"original\",\"corrected\"]",
  )
  |> should.be_true
}

pub fn manifest_hash_canonicality_and_decode_failures_are_exact_test() {
  let value = dataset_input()
  case
    domain.run_inspect(decode.InspectInput(
      decode.DatasetInput(..value, manifest_hash: string.repeat("f", 64)),
    ))
  {
    Error(domain.ManifestHashMismatch(_, _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run_inspect(decode.InspectInput(
      decode.DatasetInput(..value, manifest_json: value.manifest_json <> " "),
    ))
  {
    Error(domain.ManifestNotCanonical) -> Nil
    _ -> should.fail()
  }
  case
    domain.run_inspect(decode.InspectInput(
      decode.DatasetInput(..value, manifest_json: "{}"),
    ))
  {
    Error(domain.ManifestDecodeFailure(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn invalid_dates_out_of_coverage_gaps_and_missing_selectors_fail_test() {
  let value = dataset_input()
  let outside =
    decode.OmissionInput("listing:A", "2026-03-01", "provider_omission", None)
  case
    domain.run_inspect(decode.InspectInput(
      decode.DatasetInput(..value, omissions: [outside]),
    ))
  {
    Error(domain.InvalidField("dataset.omissions[].observationDate", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run_drill(decode.DrillInput(value, "listing:A", "2026-2-24", 0, 10))
  {
    Error(domain.InvalidField("observationDate", _)) -> Nil
    _ -> should.fail()
  }
  domain.run_drill(decode.DrillInput(
    dataset_input(),
    "listing:missing",
    "2026-02-24",
    0,
    10,
  ))
  |> should.equal(
    Error(domain.SelectorNotFound("listing:missing", "2026-02-24")),
  )
}

pub fn inspection_projection_handle_is_stable_and_binds_supplements_test() {
  let assert Ok(first) =
    domain.run_inspect(decode.InspectInput(dataset_input()))
  let assert Ok(second) =
    domain.run_inspect(decode.InspectInput(dataset_input()))
  projection_handle(first) |> should.equal(projection_handle(second))

  let value = dataset_input()
  let changed = decode.DatasetInput(..value, receipt_roots: [sha_text("other")])
  let assert Ok(changed_response) =
    domain.run_inspect(decode.InspectInput(changed))
  projection_handle(first)
  |> should.not_equal(projection_handle(changed_response))

  let text = response_text(first)
  text |> string.contains("\"verdict\"") |> should.be_false
  text |> string.contains("\"recommended\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
  text |> string.contains("\"selectedVintage\"") |> should.be_false

  let secret = "do-not-leak"
  let unsafe_manifest =
    dataset_manifest_with_source(
      "https://user:password@example.test/data?api_key="
      <> secret
      <> "#fragment",
    )
  let unsafe_input =
    decode.DatasetInput(
      manifest.encode_dataset(unsafe_manifest),
      unsafe_manifest |> manifest.dataset_digest |> identity.sha256_value,
      [
        decode.OmissionInput(
          "listing:A",
          "2026-02-25",
          "provider_omission",
          Some("https://example.test/gap?token=" <> secret <> "#fragment"),
        ),
      ],
      [],
    )
  let assert Ok(unsafe_inspect) =
    domain.run_inspect(decode.InspectInput(unsafe_input))
  let inspect_text = response_text(unsafe_inspect)
  inspect_text |> string.contains(secret) |> should.be_false
  inspect_text |> string.contains("user:password") |> should.be_false
  inspect_text |> string.contains("#fragment") |> should.be_false
  inspect_text
  |> string.contains("\"sourceReferenceRedacted\":true")
  |> should.be_true
  let assert Ok(unsafe_drill) =
    domain.run_drill(decode.DrillInput(
      unsafe_input,
      "listing:A",
      "2026-02-25",
      0,
      10,
    ))
  let drill_text = response_text(unsafe_drill)
  drill_text |> string.contains(secret) |> should.be_false
  drill_text
  |> string.contains("\"evidenceReferenceRedacted\":true")
  |> should.be_true
}

fn dataset_input() -> decode.DatasetInput {
  let value = dataset_manifest()
  decode.DatasetInput(
    manifest.encode_dataset(value),
    value |> manifest.dataset_digest |> identity.sha256_value,
    [
      decode.OmissionInput(
        "listing:A",
        "2026-02-25",
        "provider_omission",
        Some(sha_text("gap-evidence")),
      ),
    ],
    [sha_text("receipt-root")],
  )
}

fn dataset_manifest() -> manifest.DatasetManifest {
  dataset_manifest_with_source("fixture://daily-bars")
}

fn dataset_manifest_with_source(source: String) -> manifest.DatasetManifest {
  let assert Ok(coverage) =
    manifest.interval(date(2026, 2, 1), date(2026, 2, 28))
  let assert Ok(value) =
    manifest.dataset(
      "dataset-us",
      "1.0.0",
      "fixture-provider",
      source,
      finance_track.Us,
      coverage,
      [original(), corrected(), uncertain()],
      ["fixture includes one caller-supplied omission projection"],
    )
  value
}

fn original() -> manifest.ObservationHandle {
  observation(
    "obs-original",
    date(2026, 2, 24),
    fact.Known(instant(100)),
    fact.Known(instant(110)),
    fact.Known("original"),
    [],
    fact.Known("reported"),
  )
}

fn corrected() -> manifest.ObservationHandle {
  observation(
    "obs-corrected",
    date(2026, 2, 24),
    fact.Known(instant(200)),
    fact.Known(instant(210)),
    fact.Known("corrected"),
    [sha("obs-original")],
    fact.Known("corrected"),
  )
}

fn uncertain() -> manifest.ObservationHandle {
  observation(
    "obs-uncertain",
    date(2026, 2, 26),
    fact.Unknown("provider availability time absent"),
    fact.NotObtained("knowledge receipt absent"),
    fact.Conflicting(["original", "corrected"], "two supplied vintage labels"),
    [],
    fact.Unknown("provider row state unavailable"),
  )
}

fn observation(
  id: String,
  observation_date: time.Date,
  availability_time: fact.Fact(time.Instant),
  knowledge_time: fact.Fact(time.Instant),
  correction_vintage: fact.Fact(String),
  correction_lineage: List(Sha256),
  state: fact.Fact(String),
) -> manifest.ObservationHandle {
  manifest.ObservationHandle(
    id,
    "listing:A",
    "XNAS",
    finance_track.Us,
    observation_date,
    fact.Known(instant(90)),
    fact.Known(instant(95)),
    availability_time,
    knowledge_time,
    instant(300),
    fact.Known(instant(250)),
    correction_vintage,
    correction_lineage,
    fact.Known("regular_full"),
    fact.Known(sha("calendar")),
    fact.Known(sha("status")),
    fact.Known("price"),
    fact.Known("USD"),
    fact.Known(4),
    fact.Known("America/New_York"),
    fact.Known("raw"),
    fact.Known("shares"),
    fact.Known("fixture-access"),
    fact.Unknown("licence terms not supplied"),
    state,
    sha(id),
    [sha("corporate-action")],
    [sha("transformation")],
  )
}

fn response_text(value: domain.Response) -> String {
  value |> domain.details |> json.to_string
}

fn projection_handle(value: domain.Response) -> String {
  let text = response_text(value)
  let prefix = "\"inspectionProjectionHandle\":\""
  let assert [_, remainder] = string.split(text, prefix)
  let assert [value, ..] = string.split(remainder, "\"")
  value
}

fn sha(value: String) -> Sha256 {
  let assert Ok(value) = provenance_hash.text(value)
  value
}

fn sha_text(value: String) -> String {
  value |> sha |> identity.sha256_value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
