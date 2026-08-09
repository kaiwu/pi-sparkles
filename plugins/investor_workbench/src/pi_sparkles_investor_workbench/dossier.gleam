import finance_calendar/date
import finance_core/time.{type Date}
import finance_provenance/identity
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_investor_workbench/decode

pub type Response {
  Response(summary: String, details: Json)
}

pub type Error {
  InvalidField(field: String, reason: String)
  InvalidReceipt(field: String)
  DuplicateValue(field: String, value: String)
  InvalidReviewChain(reason: String)
}

type PreparedStatement {
  PreparedStatement(
    input: decode.StatementInput,
    period_start: Date,
    period_end: Date,
    issues: List(String),
  )
}

pub fn error_message(value: Error) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid investor dossier field " <> field <> ": " <> reason
    InvalidReceipt(field) ->
      "Invalid SHA-256 receipt in investor dossier field " <> field
    DuplicateValue(field, value) ->
      "Investor dossier field " <> field <> " repeats " <> value
    InvalidReviewChain(reason) ->
      "Investor dossier review chain is invalid: " <> reason
  }
}

pub fn inspect(input: decode.InspectInput) -> Result(Response, Error) {
  use _ <- result.try(nonblank("dossierId", input.dossier_id))
  use dossier_as_of <- result.try(parse_date("dossierAsOf", input.dossier_as_of))
  use _ <- result.try(case input.reviewed_at_unix_ms >= 0 {
    True -> Ok(Nil)
    False ->
      Error(InvalidField("reviewedAtUnixMilliseconds", "must be non-negative"))
  })
  use _ <- result.try(validate_identity(input.identity, dossier_as_of))
  use _ <- result.try(validate_related_listings(
    input.related_listings,
    input.identity.instrument_id,
  ))
  use _ <- result.try(validate_sections(input.sections))
  use _ <- result.try(validate_reporting_basis(
    input.sections.reporting_basis,
    input.reporting_basis,
    input.identity,
  ))
  use statements <- result.try(prepare_statements(
    input.statements,
    input.identity,
  ))
  use _ <- result.try(validate_statement_presence(
    input.sections.statement_set,
    statements,
  ))
  use _ <- result.try(validate_reviews(
    input.reviews,
    input.dossier_as_of,
    input.reviewed_at_unix_ms,
  ))

  let latest_annual = latest_statement(statements, ["annual"])
  let latest_interim =
    latest_statement(statements, ["interim", "quarter", "semi_annual"])
  let insufficient_reasons =
    statement_insufficiency(statements, latest_annual, dossier_as_of)
  let unknown_count =
    section_state_count(input.sections, [
      "not_obtained",
      "not_available",
      "stale",
      "incompatible",
    ])
  let conflict_count = section_state_count(input.sections, ["conflicting"])
  let latest_review = case list.reverse(input.reviews) {
    [value, ..] -> Some(value)
    [] -> None
  }

  Ok(Response(
    "Inspected caller-supplied dossier "
      <> input.dossier_id
      <> " for exact "
      <> input.identity.track
      <> " listing "
      <> input.identity.instrument_id
      <> "; returned 16 evidence states and mechanical statement/review facts without a reviewability or investment verdict.",
    json.object([
      #("schema", json.string("pi-sparkles/investor-dossier-inspection")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("inspect_dossier")),
      #("dossierId", json.string(input.dossier_id)),
      #("dossierAsOf", json.string(input.dossier_as_of)),
      #("reviewedAtUnixMilliseconds", json.int(input.reviewed_at_unix_ms)),
      #("identity", identity_json(input.identity)),
      #(
        "relatedListings",
        json.array(input.related_listings, related_listing_json),
      ),
      #("sectionStates", sections_json(input.sections)),
      #(
        "matrixMeaning",
        json.string(
          "contract_evidence_states_only_not_completeness_quality_or_reviewability",
        ),
      ),
      #("unknownOrUnavailableSectionCount", json.int(unknown_count)),
      #("conflictingSectionCount", json.int(conflict_count)),
      #(
        "statementCoverage",
        json.object([
          #("statementCount", json.int(list.length(statements))),
          #(
            "latestAnnual",
            json.nullable(latest_annual, statement_summary_json),
          ),
          #(
            "latestInterim",
            json.nullable(latest_interim, statement_summary_json),
          ),
          #(
            "amendmentCount",
            json.int(statement_kind_count(statements, "amendment")),
          ),
          #("restatementCount", json.int(restatement_count(statements))),
          #(
            "incompatibleStatements",
            json.array(
              list.filter(statements, fn(value) { value.issues != [] }),
              statement_issue_json,
            ),
          ),
          #("mechanicalEvidenceState", case insufficient_reasons {
            [] -> json.string("no_session_19_insufficiency_condition_detected")
            _ -> json.string("insufficient_evidence")
          }),
          #(
            "insufficientEvidenceReasons",
            json.array(insufficient_reasons, json.string),
          ),
        ]),
      ),
      #(
        "reportingBasis",
        json.nullable(input.reporting_basis, reporting_basis_json),
      ),
      #(
        "reviewHistory",
        json.object([
          #("reviewCount", json.int(list.length(input.reviews))),
          #("latestReview", json.nullable(latest_review, review_json)),
          #("chainState", json.string("ordered_prior_links_validated")),
          #(
            "diffMeaning",
            json.string(
              "caller_supplied_receipt_deltas_with_structure_and_chain_validated",
            ),
          ),
        ]),
      ),
      #(
        "availableOperations",
        json.array(
          ["inspect_dossier", "dossier_metric", "dossier_valuation"],
          json.string,
        ),
      ),
      #(
        "sourceLimitation",
        json.string(
          "the_container_validates_supplied_receipt_identifiers_but_does_not_fetch_or_reauthenticate_underlying_sources",
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #("investmentVerdict", json.null()),
      #("reviewabilityVerdict", json.null()),
    ]),
  ))
}

fn validate_identity(
  value: decode.IdentityInput,
  as_of: Date,
) -> Result(Nil, Error) {
  use _ <- result.try(nonblank("identity.instrumentId", value.instrument_id))
  use _ <- result.try(nonblank(
    "identity.reportingEntity",
    value.reporting_entity,
  ))
  use _ <- result.try(nonblank("identity.currency", value.currency))
  use _ <- result.try(validate_track_mic("identity", value.track, value.mic))
  use _ <- result.try(validate_fiscal_year_end(
    "identity.fiscalYearEnd",
    value.fiscal_year_end,
  ))
  use start <- result.try(parse_date(
    "identity.listingStart",
    value.listing_start,
  ))
  use _ <- result.try(case date.compare(start, as_of) {
    Gt -> Error(InvalidField("identity.listingStart", "is after dossierAsOf"))
    _ -> Ok(Nil)
  })
  use _ <- result.try(case value.listing_end {
    None -> Ok(Nil)
    Some(text) -> {
      use end <- result.try(parse_date("identity.listingEnd", text))
      case date.compare(end, start), date.compare(end, as_of) {
        Lt, _ ->
          Error(InvalidField("identity.listingEnd", "precedes listingStart"))
        _, Lt ->
          Error(InvalidField("identity.listingEnd", "precedes dossierAsOf"))
        _, _ -> Ok(Nil)
      }
    }
  })
  case value.status {
    "trading" | "suspended" | "delisted" -> Ok(Nil)
    _ -> Error(InvalidField("identity.status", "unknown listing status"))
  }
}

fn validate_related_listings(
  values: List(decode.RelatedListingInput),
  primary_id: String,
) -> Result(Nil, Error) {
  use _ <- result.try(validate_unique_strings(
    "relatedListings[].instrumentId",
    list.map(values, fn(value) { value.instrument_id }),
  ))
  list.try_each(values, fn(value) {
    use _ <- result.try(nonblank(
      "relatedListings[].instrumentId",
      value.instrument_id,
    ))
    use _ <- result.try(case value.instrument_id == primary_id {
      True ->
        Error(InvalidField(
          "relatedListings[].instrumentId",
          "must not repeat the primary listing leg",
        ))
      False -> Ok(Nil)
    })
    use _ <- result.try(validate_track_mic(
      "relatedListings[]",
      value.track,
      value.mic,
    ))
    nonblank("relatedListings[].currency", value.currency)
  })
}

fn validate_sections(value: decode.SectionsInput) -> Result(Nil, Error) {
  use _ <- result.try(
    list.try_each(section_pairs(value), fn(pair) {
      validate_evidence_state(pair.0, pair.1)
    }),
  )
  case value.identity.state {
    "provided" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "sections.identity.state",
        "identity must be provided; no other evidence state forms a dossier identity",
      ))
  }
}

fn validate_evidence_state(
  name: String,
  value: decode.EvidenceStateInput,
) -> Result(Nil, Error) {
  use _ <- result.try(validate_receipts(name <> ".receipts", value.receipts))
  use _ <- result.try(validate_receipts(
    name <> ".alternatives",
    value.alternatives,
  ))
  use _ <- result.try(validate_unique_strings(
    name <> ".missingParts",
    value.missing_parts,
  ))
  case value.state {
    "provided" -> require_nonempty(name <> ".receipts", value.receipts)
    "partially_provided" -> {
      use _ <- result.try(require_nonempty(name <> ".receipts", value.receipts))
      require_nonempty(name <> ".missingParts", value.missing_parts)
    }
    "not_obtained" | "not_available" | "incompatible" ->
      require_optional_text(name <> ".reason", value.reason)
      |> result.map(fn(_) { Nil })
    "stale" -> {
      use _ <- result.try(require_nonempty(name <> ".receipts", value.receipts))
      use as_of <- result.try(require_optional_text(
        name <> ".evidenceAsOf",
        value.evidence_as_of,
      ))
      use cutoff <- result.try(require_optional_text(
        name <> ".cutoff",
        value.cutoff,
      ))
      use as_of <- result.try(parse_date(name <> ".evidenceAsOf", as_of))
      use cutoff <- result.try(parse_date(name <> ".cutoff", cutoff))
      case date.compare(as_of, cutoff) {
        Lt -> Ok(Nil)
        _ -> Error(InvalidField(name, "stale evidenceAsOf must precede cutoff"))
      }
    }
    "conflicting" ->
      case list.length(value.alternatives) >= 2 {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            name <> ".alternatives",
            "requires at least two receipts",
          ))
      }
    "caller_declared" ->
      require_optional_text(
        name <> ".declarationSource",
        value.declaration_source,
      )
      |> result.map(fn(_) { Nil })
    _ -> Error(InvalidField(name <> ".state", "unknown evidence state"))
  }
}

fn validate_reporting_basis(
  state: decode.EvidenceStateInput,
  value: Option(decode.ReportingBasisInput),
  identity_value: decode.IdentityInput,
) -> Result(Nil, Error) {
  case state.state, value {
    "provided", None | "partially_provided", None | "stale", None ->
      Error(InvalidField(
        "reportingBasis",
        "is required when the reporting-basis section carries evidence",
      ))
    "not_obtained", Some(_)
    | "not_available", Some(_)
    | "caller_declared", Some(_)
    | "incompatible", Some(_)
    ->
      Error(InvalidField(
        "reportingBasis",
        "must be null when the section does not carry provided facts",
      ))
    _, None -> Ok(Nil)
    _, Some(basis) -> {
      use _ <- result.try(nonblank(
        "reportingBasis.accountingStandard",
        basis.accounting_standard,
      ))
      use _ <- result.try(validate_fiscal_year_end(
        "reportingBasis.fiscalYearEnd",
        basis.fiscal_year_end,
      ))
      use _ <- result.try(
        case basis.fiscal_year_end == identity_value.fiscal_year_end {
          True -> Ok(Nil)
          False ->
            Error(InvalidField(
              "reportingBasis.fiscalYearEnd",
              "does not match identity.fiscalYearEnd",
            ))
        },
      )
      use _ <- result.try(validate_audit_opinion(
        "reportingBasis.auditOpinion",
        basis.audit_opinion,
      ))
      validate_consolidation(
        "reportingBasis.consolidation",
        basis.consolidation,
      )
    }
  }
}

fn prepare_statements(
  values: List(decode.StatementInput),
  identity_value: decode.IdentityInput,
) -> Result(List(PreparedStatement), Error) {
  use _ <- result.try(validate_unique_strings(
    "statements[].statementId",
    list.map(values, fn(value) { value.statement_id }),
  ))
  use prepared <- result.try(
    list.try_map(values, fn(value) {
      use _ <- result.try(nonblank(
        "statements[].statementId",
        value.statement_id,
      ))
      use _ <- result.try(nonblank("statements[].formType", value.form_type))
      use _ <- result.try(nonblank(
        "statements[].filingEntity",
        value.filing_entity,
      ))
      use start <- result.try(parse_date(
        "statements[].periodStart",
        value.period_start,
      ))
      use end <- result.try(parse_date(
        "statements[].periodEnd",
        value.period_end,
      ))
      use _ <- result.try(validate_optional_date(
        "statements[].filingDate",
        value.filing_date,
      ))
      use _ <- result.try(validate_optional_date(
        "statements[].acceptanceDate",
        value.acceptance_date,
      ))
      use _ <- result.try(validate_audit_opinion(
        "statements[].auditOpinion",
        value.audit_opinion,
      ))
      use _ <- result.try(validate_consolidation(
        "statements[].consolidation",
        value.consolidation,
      ))
      use _ <- result.try(validate_receipt(
        "statements[].sourceReceipt",
        value.source_receipt,
      ))
      use _ <- result.try(case value.period_kind {
        "annual" | "interim" | "quarter" | "semi_annual" -> Ok(Nil)
        _ ->
          Error(InvalidField("statements[].periodKind", "unknown period kind"))
      })
      use _ <- result.try(case value.amendment {
        "original" | "amendment" -> Ok(Nil)
        _ ->
          Error(InvalidField(
            "statements[].amendment",
            "unknown amendment state",
          ))
      })
      use _ <- result.try(case value.restatement {
        "not_restated" | "restated" -> Ok(Nil)
        _ ->
          Error(InvalidField(
            "statements[].restatement",
            "unknown restatement state",
          ))
      })
      let actual_duration = date.days_between(start, end) + 1
      let issues =
        [
          case
            actual_duration == value.inclusive_duration_days
            && actual_duration > 0
          {
            True -> None
            False -> Some("inclusive_duration_mismatch")
          },
          case value.filing_entity == identity_value.reporting_entity {
            True -> None
            False -> Some("filing_entity_differs_from_dossier_reporting_entity")
          },
          case value.currency == identity_value.currency {
            True -> None
            False -> Some("statement_currency_differs_from_dossier_currency")
          },
          case value.restatement, value.restatement_reason {
            "restated", None -> Some("restatement_reason_missing")
            _, _ -> None
          },
          case value.amendment, value.original_statement_id {
            "original", Some(_) ->
              Some("original_statement_has_original_statement_id")
            "amendment", None -> Some("amendment_missing_original_statement_id")
            _, _ -> None
          },
        ]
        |> list.filter_map(fn(value) {
          case value {
            Some(text) -> Ok(text)
            None -> Error(Nil)
          }
        })
      Ok(PreparedStatement(value, start, end, issues))
    }),
  )
  Ok(
    list.map(prepared, fn(value) {
      case amendment_issue(value, prepared) {
        None -> value
        Some(issue) ->
          PreparedStatement(..value, issues: [issue, ..value.issues])
      }
    }),
  )
}

fn amendment_issue(
  value: PreparedStatement,
  all: List(PreparedStatement),
) -> Option(String) {
  case value.input.amendment, value.input.original_statement_id {
    "amendment", Some(original_id) ->
      case
        list.find(all, fn(candidate) {
          candidate.input.statement_id == original_id
        })
      {
        Error(_) -> Some("amendment_original_not_found")
        Ok(original) ->
          case
            original.input.amendment == "original"
            && original.input.filing_entity == value.input.filing_entity
            && original.input.period_start == value.input.period_start
            && original.input.period_end == value.input.period_end
          {
            True -> None
            False -> Some("amendment_original_context_mismatch")
          }
      }
    _, _ -> None
  }
}

fn validate_statement_presence(
  state: decode.EvidenceStateInput,
  statements: List(PreparedStatement),
) -> Result(Nil, Error) {
  case state.state, statements {
    "provided", [] | "partially_provided", [] | "stale", [] ->
      Error(InvalidField(
        "statements",
        "cannot be empty when the statement-set section carries evidence",
      ))
    _, _ -> Ok(Nil)
  }
}

fn validate_reviews(
  values: List(decode.ReviewInput),
  current_as_of: String,
  current_reviewed_at: Int,
) -> Result(Nil, Error) {
  case values {
    [] -> Error(InvalidReviewChain("at least one review event is required"))
    _ -> {
      use _ <- result.try(validate_review_sequence(values, None, None, None))
      let assert [latest, ..] = list.reverse(values)
      case
        latest.dossier_as_of == current_as_of,
        latest.reviewed_at_unix_ms == current_reviewed_at
      {
        True, True -> Ok(Nil)
        False, _ ->
          Error(InvalidReviewChain(
            "latest dossierAsOf does not match the current dossier",
          ))
        _, False ->
          Error(InvalidReviewChain(
            "latest reviewedAtUnixMilliseconds does not match the current dossier",
          ))
      }
    }
  }
}

fn validate_review_sequence(
  values: List(decode.ReviewInput),
  prior_id: Option(String),
  prior_time: Option(Int),
  prior_as_of: Option(Date),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(nonblank("reviews[].reviewId", value.review_id))
      use _ <- result.try(nonblank("reviews[].reviewerRef", value.reviewer_ref))
      use as_of <- result.try(parse_date(
        "reviews[].dossierAsOf",
        value.dossier_as_of,
      ))
      use _ <- result.try(case value.reviewer_kind {
        "user_declared" | "llm_declared" -> Ok(Nil)
        _ -> Error(InvalidReviewChain("unknown reviewerKind"))
      })
      use _ <- result.try(case value.prior_review_id == prior_id {
        True -> Ok(Nil)
        False ->
          Error(InvalidReviewChain(
            "priorReviewId does not match the immediately preceding review",
          ))
      })
      use _ <- result.try(case prior_time {
        Some(previous) ->
          case value.reviewed_at_unix_ms > previous {
            True -> Ok(Nil)
            False ->
              Error(InvalidReviewChain(
                "reviewedAt values are not strictly increasing",
              ))
          }
        _ -> Ok(Nil)
      })
      use _ <- result.try(case prior_as_of {
        Some(previous) ->
          case date.compare(as_of, previous) {
            Lt -> Error(InvalidReviewChain("dossierAsOf moved backwards"))
            _ -> Ok(Nil)
          }
        _ -> Ok(Nil)
      })
      use _ <- result.try(validate_unique_strings(
        "reviews[].changes[].section",
        list.map(value.changes, fn(change) { change.section }),
      ))
      use _ <- result.try(list.try_each(value.changes, validate_review_change))
      validate_review_sequence(
        rest,
        Some(value.review_id),
        Some(value.reviewed_at_unix_ms),
        Some(as_of),
      )
    }
  }
}

fn validate_review_change(
  value: decode.ReviewChangeInput,
) -> Result(Nil, Error) {
  use _ <- result.try(case list.contains(section_names(), value.section) {
    True -> Ok(Nil)
    False ->
      Error(InvalidReviewChain("change names an unknown dossier section"))
  })
  use _ <- result.try(validate_receipts(
    "reviews[].changes[].addedReceipts",
    value.added_receipts,
  ))
  use _ <- result.try(validate_receipts(
    "reviews[].changes[].removedReceipts",
    value.removed_receipts,
  ))
  case value.kind, value.added_receipts, value.removed_receipts {
    "added", [], _ ->
      Error(InvalidReviewChain("added change has no added receipt"))
    "added", _, [] -> Ok(Nil)
    "removed", _, [] ->
      Error(InvalidReviewChain("removed change has no removed receipt"))
    "removed", [], _ -> Ok(Nil)
    "changed", [], [] ->
      Error(InvalidReviewChain("changed entry has no receipt delta"))
    "changed", _, _ -> Ok(Nil)
    "added", _, _ | "removed", _, _ ->
      Error(InvalidReviewChain(
        "added/removed change mixes both receipt directions",
      ))
    _, _, _ -> Error(InvalidReviewChain("unknown review change kind"))
  }
}

fn latest_statement(
  values: List(PreparedStatement),
  period_kinds: List(String),
) -> Option(PreparedStatement) {
  let initial: Option(PreparedStatement) = None
  list.fold(values, initial, fn(latest, candidate) {
    case
      list.contains(period_kinds, candidate.input.period_kind),
      candidate.issues
    {
      False, _ | _, [_, ..] -> latest
      True, [] ->
        case latest {
          None -> Some(candidate)
          Some(previous) ->
            case date.compare(candidate.period_end, previous.period_end) {
              Gt -> Some(candidate)
              _ -> latest
            }
        }
    }
  })
}

fn statement_insufficiency(
  statements: List(PreparedStatement),
  latest_annual: Option(PreparedStatement),
  dossier_as_of: Date,
) -> List(String) {
  let annual_reason = case latest_annual {
    None -> ["no_compatible_annual_statement"]
    Some(value) ->
      case date.add_months(value.period_end, 15, date.ClampDay) {
        Error(_) -> ["annual_freshness_window_could_not_be_formed"]
        Ok(cutoff) ->
          case date.compare(dossier_as_of, cutoff) {
            Gt -> ["latest_compatible_annual_statement_older_than_15_months"]
            _ -> []
          }
      }
  }
  let chain_reason = case
    list.any(statements, fn(value) {
      list.any(value.issues, fn(issue) {
        string.starts_with(issue, "amendment_")
      })
    })
  {
    True -> ["amendment_chain_unclear"]
    False -> []
  }
  list.append(annual_reason, chain_reason)
}

fn statement_kind_count(
  values: List(PreparedStatement),
  amendment: String,
) -> Int {
  values
  |> list.filter(fn(value) { value.input.amendment == amendment })
  |> list.length
}

fn restatement_count(values: List(PreparedStatement)) -> Int {
  values
  |> list.filter(fn(value) { value.input.restatement == "restated" })
  |> list.length
}

fn section_state_count(
  value: decode.SectionsInput,
  states: List(String),
) -> Int {
  value
  |> section_pairs
  |> list.filter(fn(pair) { list.contains(states, pair.1.state) })
  |> list.length
}

fn section_pairs(
  value: decode.SectionsInput,
) -> List(#(String, decode.EvidenceStateInput)) {
  [
    #("sections.identity", value.identity),
    #("sections.businessDescription", value.business_description),
    #("sections.reportingBasis", value.reporting_basis),
    #("sections.statementSet", value.statement_set),
    #("sections.segmentData", value.segment_data),
    #("sections.debtLiquidity", value.debt_liquidity),
    #("sections.cashFlowEarningsQuality", value.cash_flow_earnings_quality),
    #("sections.capitalAllocation", value.capital_allocation),
    #("sections.governanceManagement", value.governance_management),
    #("sections.industryPeers", value.industry_peers),
    #("sections.macroContext", value.macro_context),
    #("sections.corporateActions", value.corporate_actions),
    #("sections.valuation", value.valuation),
    #("sections.thesisRisks", value.thesis_risks),
    #("sections.portfolioFit", value.portfolio_fit),
    #("sections.reviewHistory", value.review_history),
  ]
}

fn validate_track_mic(
  field: String,
  track: String,
  mic: String,
) -> Result(Nil, Error) {
  case track, mic {
    "cn", "XSHG"
    | "cn", "XSHE"
    | "cn", "XBSE"
    | "hk", "XHKG"
    | "us", "XNYS"
    | "us", "XNAS"
    -> Ok(Nil)
    _, _ -> Error(InvalidField(field, "track and MIC are incompatible"))
  }
}

fn validate_audit_opinion(field: String, value: String) -> Result(Nil, Error) {
  case value {
    "unqualified" | "qualified" | "adverse" | "disclaimer" | "unknown" ->
      Ok(Nil)
    _ -> Error(InvalidField(field, "unknown audit opinion"))
  }
}

fn validate_consolidation(field: String, value: String) -> Result(Nil, Error) {
  case value {
    "consolidated" | "parent_only" | "segment" -> Ok(Nil)
    _ -> Error(InvalidField(field, "unknown consolidation scope"))
  }
}

fn validate_optional_date(
  field: String,
  value: Option(String),
) -> Result(Nil, Error) {
  case value {
    None -> Ok(Nil)
    Some(text) -> parse_date(field, text) |> result.map(fn(_) { Nil })
  }
}

fn validate_fiscal_year_end(
  field: String,
  value: String,
) -> Result(Nil, Error) {
  parse_date(field, "2000-" <> value) |> result.map(fn(_) { Nil })
}

fn parse_date(field: String, value: String) -> Result(Date, Error) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] ->
      case
        string.length(year_text) == 4,
        string.length(month_text) == 2,
        string.length(day_text) == 2
      {
        True, True, True -> {
          use year <- result.try(
            int.parse(year_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          use month <- result.try(
            int.parse(month_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          use day <- result.try(
            int.parse(day_text)
            |> result.map_error(fn(_) {
              InvalidField(field, "must be YYYY-MM-DD")
            }),
          )
          time.date(year, month, day)
          |> result.map_error(fn(_) {
            InvalidField(field, "is not a Gregorian date")
          })
        }
        _, _, _ -> Error(InvalidField(field, "must be YYYY-MM-DD"))
      }
    _ -> Error(InvalidField(field, "must be YYYY-MM-DD"))
  }
}

fn nonblank(field: String, value: String) -> Result(Nil, Error) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "must be non-empty without surrounding whitespace",
      ))
  }
}

fn require_optional_text(
  field: String,
  value: Option(String),
) -> Result(String, Error) {
  case value {
    None -> Error(InvalidField(field, "is required for this evidence state"))
    Some(text) -> nonblank(field, text) |> result.map(fn(_) { text })
  }
}

fn require_nonempty(field: String, values: List(value)) -> Result(Nil, Error) {
  case values {
    [] -> Error(InvalidField(field, "must not be empty"))
    _ -> Ok(Nil)
  }
}

fn validate_receipt(field: String, value: String) -> Result(Nil, Error) {
  identity.sha256(value)
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { InvalidReceipt(field) })
}

fn validate_receipts(
  field: String,
  values: List(String),
) -> Result(Nil, Error) {
  use _ <- result.try(
    list.try_each(values, fn(value) { validate_receipt(field, value) }),
  )
  validate_unique_strings(field, values)
}

fn validate_unique_strings(
  field: String,
  values: List(String),
) -> Result(Nil, Error) {
  validate_unique_strings_loop(field, values, [])
}

fn validate_unique_strings_loop(
  field: String,
  values: List(String),
  seen: List(String),
) -> Result(Nil, Error) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case list.contains(seen, value) {
        True -> Error(DuplicateValue(field, value))
        False -> validate_unique_strings_loop(field, rest, [value, ..seen])
      }
  }
}

fn section_names() -> List(String) {
  [
    "identity",
    "business_description",
    "reporting_basis",
    "statement_set",
    "segment_data",
    "debt_liquidity",
    "cash_flow_earnings_quality",
    "capital_allocation",
    "governance_management",
    "industry_peers",
    "macro_context",
    "corporate_actions",
    "valuation",
    "thesis_risks",
    "portfolio_fit",
    "review_history",
  ]
}

fn identity_json(value: decode.IdentityInput) -> Json {
  json.object([
    #("instrumentId", json.string(value.instrument_id)),
    #("mic", json.string(value.mic)),
    #("track", json.string(value.track)),
    #("symbol", json.nullable(value.symbol, json.string)),
    #("shareClass", json.nullable(value.share_class, json.string)),
    #("reportingEntity", json.string(value.reporting_entity)),
    #("entityType", json.nullable(value.entity_type, json.string)),
    #("currency", json.string(value.currency)),
    #("fiscalYearEnd", json.string(value.fiscal_year_end)),
    #("isin", json.nullable(value.isin, json.string)),
    #("localId", json.nullable(value.local_id, json.string)),
    #("listingStart", json.string(value.listing_start)),
    #("listingEnd", json.nullable(value.listing_end, json.string)),
    #("status", json.string(value.status)),
  ])
}

fn related_listing_json(value: decode.RelatedListingInput) -> Json {
  json.object([
    #("instrumentId", json.string(value.instrument_id)),
    #("mic", json.string(value.mic)),
    #("track", json.string(value.track)),
    #("currency", json.string(value.currency)),
    #("relationship", json.string(value.relationship)),
    #("factsMergedIntoPrimary", json.bool(False)),
  ])
}

fn reporting_basis_json(value: decode.ReportingBasisInput) -> Json {
  json.object([
    #("accountingStandard", json.string(value.accounting_standard)),
    #("fiscalYearEnd", json.string(value.fiscal_year_end)),
    #("auditorName", json.nullable(value.auditor_name, json.string)),
    #("auditOpinion", json.string(value.audit_opinion)),
    #("consolidation", json.string(value.consolidation)),
  ])
}

fn sections_json(value: decode.SectionsInput) -> Json {
  json.object([
    #("identity", evidence_state_json(value.identity)),
    #("businessDescription", evidence_state_json(value.business_description)),
    #("reportingBasis", evidence_state_json(value.reporting_basis)),
    #("statementSet", evidence_state_json(value.statement_set)),
    #("segmentData", evidence_state_json(value.segment_data)),
    #("debtLiquidity", evidence_state_json(value.debt_liquidity)),
    #(
      "cashFlowEarningsQuality",
      evidence_state_json(value.cash_flow_earnings_quality),
    ),
    #("capitalAllocation", evidence_state_json(value.capital_allocation)),
    #("governanceManagement", evidence_state_json(value.governance_management)),
    #("industryPeers", evidence_state_json(value.industry_peers)),
    #("macroContext", evidence_state_json(value.macro_context)),
    #("corporateActions", evidence_state_json(value.corporate_actions)),
    #("valuation", evidence_state_json(value.valuation)),
    #("thesisRisks", evidence_state_json(value.thesis_risks)),
    #("portfolioFit", evidence_state_json(value.portfolio_fit)),
    #("reviewHistory", evidence_state_json(value.review_history)),
  ])
}

fn evidence_state_json(value: decode.EvidenceStateInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("receipts", json.array(value.receipts, json.string)),
    #("missingParts", json.array(value.missing_parts, json.string)),
    #("reason", json.nullable(value.reason, json.string)),
    #("evidenceAsOf", json.nullable(value.evidence_as_of, json.string)),
    #("cutoff", json.nullable(value.cutoff, json.string)),
    #("alternatives", json.array(value.alternatives, json.string)),
    #("declarationSource", json.nullable(value.declaration_source, json.string)),
  ])
}

fn statement_summary_json(value: PreparedStatement) -> Json {
  json.object([
    #("statementId", json.string(value.input.statement_id)),
    #("formType", json.string(value.input.form_type)),
    #("periodStart", json.string(value.input.period_start)),
    #("periodEnd", json.string(value.input.period_end)),
    #("periodKind", json.string(value.input.period_kind)),
    #("filingDate", json.nullable(value.input.filing_date, json.string)),
    #("amendment", json.string(value.input.amendment)),
    #("restatement", json.string(value.input.restatement)),
    #("sourceReceipt", json.string(value.input.source_receipt)),
  ])
}

fn statement_issue_json(value: PreparedStatement) -> Json {
  json.object([
    #("statementId", json.string(value.input.statement_id)),
    #("issues", json.array(value.issues, json.string)),
    #("interpretation", json.null()),
  ])
}

fn review_json(value: decode.ReviewInput) -> Json {
  json.object([
    #("reviewId", json.string(value.review_id)),
    #("reviewedAtUnixMilliseconds", json.int(value.reviewed_at_unix_ms)),
    #("reviewerKind", json.string(value.reviewer_kind)),
    #("reviewerRef", json.string(value.reviewer_ref)),
    #("dossierAsOf", json.string(value.dossier_as_of)),
    #("priorReviewId", json.nullable(value.prior_review_id, json.string)),
    #("changes", json.array(value.changes, review_change_json)),
    #("conclusionRef", json.nullable(value.conclusion_ref, json.string)),
  ])
}

fn review_change_json(value: decode.ReviewChangeInput) -> Json {
  json.object([
    #("section", json.string(value.section)),
    #("kind", json.string(value.kind)),
    #("addedReceipts", json.array(value.added_receipts, json.string)),
    #("removedReceipts", json.array(value.removed_receipts, json.string)),
  ])
}
