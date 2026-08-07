import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_sources/decode
import pi_sparkles_finance_sources/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn list_is_explicitly_paged_and_preserves_topological_order_test() {
  let input = decode.ListInput(catalogue(), 1, 1)
  let assert Ok(response) = domain.run_list(input)
  let text = response |> domain.details |> json.to_string
  text
  |> string.contains("\"receiptHash\":\"" <> hash("4") <> "\"")
  |> should.be_true
  text
  |> string.contains("\"receiptHash\":\"" <> hash("3") <> "\"")
  |> should.be_false
  text |> string.contains("\"offset\":1") |> should.be_true
  text |> string.contains("\"returnedCount\":1") |> should.be_true
  text |> string.contains("\"omittedCount\":1") |> should.be_true
  text |> string.contains("\"nextOffset\":null") |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn inspect_returns_exact_receipt_and_linked_assumption_test() {
  let input = decode.InspectInput(catalogue(), hash("4"))
  let assert Ok(response) = domain.run_inspect(input)
  let text = response |> domain.details |> json.to_string
  text
  |> string.contains("\"receiptHash\":\"" <> hash("4") <> "\"")
  |> should.be_true
  text
  |> string.contains("\"parents\":[\"" <> hash("3") <> "\"]")
  |> should.be_true
  text |> string.contains("\"id\":\"method-scale\"") |> should.be_true
  text
  |> string.contains("\"state\":\"verification_failed\"")
  |> should.be_true
  text |> string.contains("provider omitted checksum header") |> should.be_true
}

pub fn canonical_export_is_deterministic_for_assumption_order_test() {
  let first = decode.ExportInput(catalogue(), 100_000)
  let reordered = {
    let value = catalogue()
    decode.ExportInput(
      decode.CatalogueInput(..value, assumptions: [
        boolean_assumption(),
        decimal_assumption(),
      ]),
      100_000,
    )
  }
  let assert Ok(first_response) = domain.run_export(first)
  let assert Ok(second_response) = domain.run_export(reordered)
  manifest_handle(first_response)
  |> should.equal(manifest_handle(second_response))
  canonical_manifest(first_response)
  |> should.equal(canonical_manifest(second_response))
  let text = first_response |> domain.details |> json.to_string
  text |> string.contains("\"truncated\":false") |> should.be_true
  text |> string.contains("\"signed\":false") |> should.be_true
}

pub fn source_secrets_are_never_returned_or_exposed_in_errors_test() {
  let secret = "do-not-leak"
  let value = catalogue()
  let assert [first, second] = value.evidence
  let unsafe_source =
    decode.SourceInput(
      "fixture-provider",
      "https://user:password@example.test/data?api_key="
        <> secret
        <> "&custom_secret=also-secret#fragment",
      "licensed_vendor",
      None,
    )
  let unsafe_evidence = [
    decode.EvidenceInput(..first, source: unsafe_source),
    second,
  ]
  let request =
    decode.ListInput(
      decode.CatalogueInput(
        ..value,
        additional_sensitive_query_keys: ["custom_secret"],
        evidence: unsafe_evidence,
      ),
      0,
      2,
    )
  let assert Ok(response) = domain.run_list(request)
  let text = response |> domain.details |> json.to_string
  text |> string.contains(secret) |> should.be_false
  text |> string.contains("also-secret") |> should.be_false
  text |> string.contains("user:password") |> should.be_false
  text |> string.contains("#fragment") |> should.be_false
  text |> string.contains("redacted-reference:sha256:") |> should.be_true
  text |> string.contains("\"referenceRedacted\":true") |> should.be_true
}

pub fn missing_receipt_has_no_nearest_fallback_test() {
  domain.run_inspect(decode.InspectInput(catalogue(), hash("f")))
  |> should.equal(Error(domain.ReceiptNotFound(hash("f"))))
}

pub fn export_budget_fails_without_truncation_test() {
  case domain.run_export(decode.ExportInput(catalogue(), 1)) {
    Error(domain.ManifestBudgetExceeded(actual, 1)) ->
      should.be_true(actual > 1)
    _ -> should.fail()
  }
}

pub fn graph_rejects_missing_parent_and_conflicting_duplicate_test() {
  let value = catalogue()
  let assert [first, second] = value.evidence
  let missing_parent = decode.EvidenceInput(..first, parents: [hash("e")])
  case
    domain.run_list(decode.ListInput(
      decode.CatalogueInput(..value, evidence: [missing_parent, second]),
      0,
      2,
    ))
  {
    Error(domain.GraphFailure(reason)) ->
      reason |> string.contains("MissingParent") |> should.be_true
    _ -> should.fail()
  }

  let conflicting = decode.EvidenceInput(..first, media_type: "text/csv")
  case
    domain.run_list(decode.ListInput(
      decode.CatalogueInput(..value, evidence: [first, conflicting, second]),
      0,
      3,
    ))
  {
    Error(domain.GraphFailure(reason)) ->
      reason |> string.contains("ConflictingEvidence") |> should.be_true
    _ -> should.fail()
  }
}

pub fn results_expose_facts_without_source_or_workflow_verdicts_test() {
  let assert Ok(response) =
    domain.run_inspect(decode.InspectInput(catalogue(), hash("3")))
  let text = response |> domain.details |> json.to_string
  text |> string.contains("\"correct\"") |> should.be_false
  text |> string.contains("\"quality\"") |> should.be_false
  text |> string.contains("\"trusted\"") |> should.be_false
  text |> string.contains("\"rank\"") |> should.be_false
  text |> string.contains("\"recommended\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
}

fn catalogue() -> decode.CatalogueInput {
  decode.CatalogueInput(
    hash("1"),
    [],
    [decimal_assumption(), boolean_assumption()],
    [
      decode.EvidenceInput(
        hash("3"),
        hash("5"),
        decode.SourceInput(
          "fixture-exchange",
          "https://example.test/source/one",
          "exchange",
          None,
        ),
        decode.LicenceInput(
          "Fixture terms",
          "attribution_required",
          Some("Attribution required by supplied metadata"),
        ),
        1_770_000_000_000,
        1_770_000_000_100,
        "application/json",
        120,
        hash("6"),
        [],
        ["method-scale"],
        decode.AvailabilityInput("available", None, None),
      ),
      decode.EvidenceInput(
        hash("4"),
        hash("7"),
        decode.SourceInput(
          "fixture-calculation",
          "calculation://exact-output",
          "synthetic",
          None,
        ),
        decode.LicenceInput("Unknown terms", "unknown", None),
        1_770_000_000_100,
        1_770_000_000_200,
        "application/json",
        80,
        hash("8"),
        [hash("3")],
        ["method-scale", "caller-reviewed"],
        decode.AvailabilityInput(
          "verification_failed",
          Some("provider omitted checksum header"),
          None,
        ),
      ),
    ],
    [hash("4")],
  )
}

fn decimal_assumption() -> decode.AssumptionInput {
  decode.AssumptionInput(
    "method-scale",
    "Display scale",
    "method",
    "Exact decimal scale supplied by the caller",
    decode.AssumptionValueInput("decimal", None, Some("2"), None, None, None),
  )
}

fn boolean_assumption() -> decode.AssumptionInput {
  decode.AssumptionInput(
    "caller-reviewed",
    "Caller review state",
    "user",
    "Whether the caller reports having reviewed the supplied metadata",
    decode.AssumptionValueInput("boolean", None, None, None, None, Some(True)),
  )
}

fn manifest_handle(value: domain.Response) -> String {
  decode_string_field(value, "manifestHandle")
}

fn canonical_manifest(value: domain.Response) -> String {
  decode_string_field(value, "canonicalManifestJson")
}

fn decode_string_field(value: domain.Response, field: String) -> String {
  let value_decoder = {
    use value <- dynamic_decode.field(field, dynamic_decode.string)
    dynamic_decode.success(value)
  }
  let assert Ok(value) =
    value |> domain.details |> json.to_string |> json.parse(value_decoder)
  value
}

fn hash(digit: String) -> String {
  string.repeat(digit, 64)
}
