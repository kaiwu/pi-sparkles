import finance_capco.{type Snapshot}
import finance_capco/classification.{type Classification, type Level}
import finance_capco/response.{type Capture}
import finance_core/observation
import finance_core/observation_json
import finance_core/source
import finance_core/time
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub type Plan {
  Plan(snapshot: Snapshot, listing_code: String)
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack(received: String)
  UnsupportedResultPeriod(received: String)
  InvalidListingCode
  CapturePeriodMismatch
  ClassificationRejected(classification.ParseError)
  InvalidSource(source.SourceError)
}

pub fn plan(
  track: String,
  result_period: String,
  listing_code: String,
) -> Result(Plan, Error) {
  use Nil <- result.try(case track {
    "cn" -> Ok(Nil)
    value -> Error(WrongTrack(value))
  })
  use snapshot <- result.try(
    finance_capco.select(result_period)
    |> result.map_error(fn(_) { UnsupportedResultPeriod(result_period) }),
  )
  case valid_listing_code(listing_code) {
    True -> Ok(Plan(snapshot, listing_code))
    False -> Error(InvalidListingCode)
  }
}

pub fn assemble(plan: Plan, capture: Capture) -> Result(Output, Error) {
  use Nil <- result.try(
    case
      capture.snapshot.result_period == plan.snapshot.result_period,
      capture.snapshot.expected_sha256 == plan.snapshot.expected_sha256
    {
      True, True -> Ok(Nil)
      _, _ -> Error(CapturePeriodMismatch)
    },
  )
  use row <- result.try(
    classification.find(capture.extraction, plan.listing_code)
    |> result.map_error(ClassificationRejected),
  )
  use source_ref <- result.try(
    source.new(
      provider: "China Association for Public Companies (CAPCO)",
      reference: capture.source_reference,
      kind: source.Official,
    )
    |> result.map_error(InvalidSource),
  )
  let observed =
    observation.Observation(
      value: row,
      as_of: capture.retrieved_at,
      retrieved_at: capture.retrieved_at,
      timezone: None,
      source: source_ref,
      evidence_id: Some(capture.evidence_id),
      freshness: observation.UnknownFreshness,
      entitlement: observation.UnknownEntitlement,
      quality: observation.Reported,
      unit: None,
      adjustment: None,
      session: None,
    )
  let details =
    json.object([
      #("schema", json.string("pi-sparkles/cn-industry-classification-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("cn_industry_classification")),
      #("track", json.string("cn")),
      #("resultPeriod", json.string(capture.snapshot.result_period)),
      #(
        "listing",
        json.object([
          #("code", json.string(row.listing_code)),
          #("name", json.string(row.listing_name)),
        ]),
      ),
      #("classification", classification_json(row)),
      #("observation", observation_json.to_json(observed, classification_json)),
      #(
        "dateFacts",
        json.object([
          #(
            "taxonomyEffective",
            json.object([
              #("value", json.string(capture.snapshot.taxonomy_effective)),
              #("semantics", json.string("guideline_effective_date")),
            ]),
          ),
          #(
            "resultPeriod",
            json.object([
              #("value", json.string(capture.snapshot.result_period)),
              #("semantics", json.string("capco_half_year_result_label")),
            ]),
          ),
          #(
            "publishedOn",
            json.object([
              #("value", json.string(capture.snapshot.published_on)),
              #(
                "semantics",
                json.string("date_only_earliest_knowledge_availability"),
              ),
            ]),
          ),
          #(
            "retrievedAtUnixMs",
            capture.retrieved_at
              |> time.unix_milliseconds
              |> int.to_string
              |> json.string,
          ),
        ]),
      ),
      #(
        "taxonomy",
        json.object([
          #("name", json.string(capture.snapshot.taxonomy)),
          #("effectiveOn", json.string(capture.snapshot.taxonomy_effective)),
          #(
            "referenceStandard",
            json.string(capture.snapshot.reference_standard),
          ),
          #(
            "publishedLevels",
            json.array(["门类", "大类", "manufacturing_only_次类"], json.string),
          ),
          #("中类", json.null()),
        ]),
      ),
      #(
        "identity",
        json.object([
          #("track", json.string("cn")),
          #(
            "mic",
            unknown(
              "CAPCO publishes stock code only; MIC is not stated in the PDF",
            ),
          ),
          #(
            "instrumentId",
            unknown(
              "CAPCO publishes stock code only; resolve exact identity separately with finance_cn_identity evidence",
            ),
          ),
        ]),
      ),
      #(
        "membershipValidity",
        json.object([
          #(
            "validFrom",
            unknown(
              "CAPCO does not publish per-company effective dates; guideline work-start dates and result period are not membership effective dates",
            ),
          ),
          #(
            "validTo",
            unknown(
              "CAPCO does not publish per-company validity end dates; the next result period supersedes this one upon publication",
            ),
          ),
        ]),
      ),
      #(
        "correctionLineage",
        json.object([
          #("state", json.string("none_published_for_pinned_artifact")),
          #(
            "upstreamByteChange",
            json.string("fail_closed_pending_source_review"),
          ),
        ]),
      ),
      #(
        "source",
        json.object([
          #(
            "provider",
            json.string("China Association for Public Companies (CAPCO)"),
          ),
          #("resultPageUrl", json.string(capture.snapshot.result_page_url)),
          #("pdfUrl", json.string(capture.source_reference)),
          #(
            "legalStatementUrl",
            json.string(capture.snapshot.legal_statement_url),
          ),
          #("evidenceId", json.string(capture.evidence_id)),
          #("sourceFingerprint", json.string(capture.source_fingerprint)),
          #("mediaType", json.string(capture.media_type)),
          #("responseByteLength", json.int(capture.response_byte_length)),
          #("contentSha256", json.string(capture.content_sha256)),
          #("pageCount", json.int(capture.extraction.page_count)),
          #("parser", json.string(capture.extraction.parser)),
          #("parserVersion", json.string(capture.extraction.parser_version)),
          #(
            "rights",
            json.object([
              #("licence", json.string("CAPCO legal statement")),
              #("intendedUse", json.string("internal_analysis")),
              #("redistribution", json.string("no_redistribution")),
              #("attributionRequired", json.bool(True)),
              #(
                "attributionText",
                json.string("China Association for Public Companies (CAPCO)"),
              ),
            ]),
          ),
        ]),
      ),
      #(
        "knowledgeUse",
        json.object([
          #(
            "eligibleWhen",
            json.string("knowledge_cutoff_on_or_after_published_on"),
          ),
          #(
            "publishedOnGranularity",
            json.string("date_only_no_publication_time_inferred"),
          ),
          #(
            "observationAsOfSemantics",
            json.string("retrieval_time_only_not_membership_effective_time"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "The classification is a CAPCO half-year-labelled published snapshot; per-company effective dates are not stated.",
            "The stock code is published without a MIC or instrument identifier; no venue is inferred from its prefix.",
            "Only 门类, 大类, and manufacturing 次类 are published in this result; 中类 is not published.",
            "No mapping to GICS, ICB, SIC, CSRC-2012, exchange, concept, or vendor taxonomies is performed.",
            "A missing code proves only no matching row in this pinned PDF, not that the company or classification is absent elsewhere.",
          ],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ])
  Ok(Output(summary(row, capture), details))
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack(received) ->
      "cn_industry_classification supports exact track cn, received "
      <> received
    UnsupportedResultPeriod(received) ->
      "cn_industry_classification supports reviewed resultPeriod 2025-H2, received "
      <> received
    InvalidListingCode ->
      "cn_industry_classification listingCode must be exactly six ASCII digits"
    CapturePeriodMismatch ->
      "CAPCO capture did not match the exact requested result period and reviewed artifact"
    ClassificationRejected(error) ->
      "CAPCO classification row was rejected safely: " <> string.inspect(error)
    InvalidSource(_) -> "CAPCO source reference was invalid"
  }
}

fn classification_json(value: Classification) -> json.Json {
  json.object([
    #("门类", level_json(value.section)),
    #("大类", level_json(value.division)),
    #("次类", case value.manufacturing_subclass {
      Some(level) -> level_json(level)
      None -> json.null()
    }),
    #("中类", json.null()),
  ])
}

fn level_json(value: Level) -> json.Json {
  json.object([
    #("code", json.string(value.code)),
    #("label", json.string(value.label)),
  ])
}

fn unknown(reason: String) -> json.Json {
  json.object([
    #("state", json.string("unknown")),
    #("reason", json.string(reason)),
  ])
}

fn summary(value: Classification, capture: Capture) -> String {
  "CAPCO "
  <> capture.snapshot.result_period
  <> " classification for "
  <> value.listing_code
  <> " "
  <> value.listing_name
  <> ": 门类 "
  <> value.section.code
  <> " "
  <> value.section.label
  <> ", 大类 "
  <> value.division.code
  <> " "
  <> value.division.label
  <> ". Membership effective dates and MIC are not published."
}

fn valid_listing_code(value: String) -> Bool {
  string.length(value) == 6
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789", character) })
  }
}
