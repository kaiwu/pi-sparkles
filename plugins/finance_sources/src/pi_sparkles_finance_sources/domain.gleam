import finance_core/currency
import finance_core/decimal
import finance_core/money
import finance_core/source
import finance_core/time
import finance_provenance/assumption
import finance_provenance/canonical
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_provenance/manifest.{type Manifest}
import finance_provenance/redact
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_finance_sources/decode

const maximum_assumptions = 500

const maximum_evidence = 500

const maximum_roots = 500

const maximum_sensitive_keys = 100

const maximum_manifest_bytes = 5_000_000

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  GraphFailure(reason: String)
  ReceiptNotFound(receipt_hash: String)
  ManifestBudgetExceeded(actual: Int, maximum: Int)
}

type PreparedEntry {
  PreparedEntry(item: evidence.Evidence, reference_redacted: Bool)
}

type Prepared {
  Prepared(
    instruction_ref: String,
    manifest: Manifest,
    entries: List(PreparedEntry),
    canonical_json: String,
    manifest_handle: String,
  )
}

type BuildState {
  BuildState(manifest: Manifest, entries: List(PreparedEntry))
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit finance-sources field " <> field <> ": " <> reason
    GraphFailure(reason) ->
      "The supplied provenance catalogue could not be constructed: " <> reason
    ReceiptNotFound(receipt_hash) ->
      "The exact receipt hash was not present in the supplied catalogue: "
      <> receipt_hash
    ManifestBudgetExceeded(actual, maximum) ->
      "The canonical manifest requires "
      <> int.to_string(actual)
      <> " bytes, exceeding the explicit "
      <> int.to_string(maximum)
      <> " byte budget; nothing was truncated"
  }
}

pub fn run_list(value: decode.ListInput) -> Result(Response, DomainError) {
  use _ <- result.try(integer_range("offset", value.offset, 0, maximum_evidence))
  use _ <- result.try(integer_range("limit", value.limit, 1, 200))
  use prepared <- result.try(prepare(value.catalogue))
  let count = list.length(prepared.entries)
  use _ <- result.try(integer_range("offset", value.offset, 0, count))
  let page =
    prepared.entries |> list.drop(value.offset) |> list.take(value.limit)
  let returned = list.length(page)
  let omitted = count - returned
  let next_offset = case value.offset + returned < count {
    True -> Some(value.offset + returned)
    False -> None
  }
  Ok(Response(
    "Listed "
      <> int.to_string(returned)
      <> " of "
      <> int.to_string(count)
      <> " exact provenance receipts from the supplied catalogue",
    common(prepared, "list_sources", [
      #("offset", json.int(value.offset)),
      #("limit", json.int(value.limit)),
      #("returnedCount", json.int(returned)),
      #("omittedCount", json.int(omitted)),
      #("nextOffset", json.nullable(next_offset, json.int)),
      #("sources", json.array(page, compact_entry_json)),
    ]),
  ))
}

pub fn run_inspect(
  value: decode.InspectInput,
) -> Result(Response, DomainError) {
  use requested <- result.try(sha("receiptHash", value.receipt_hash))
  use prepared <- result.try(prepare(value.catalogue))
  let requested_value = identity.sha256_value(requested)
  case
    prepared.entries
    |> list.find(fn(entry) {
      identity.evidence_id_value(entry.item.id) == requested_value
    })
  {
    Error(_) -> Error(ReceiptNotFound(requested_value))
    Ok(entry) -> {
      let linked_assumptions =
        entry.item.assumptions
        |> list.filter_map(fn(id) {
          prepared.manifest
          |> manifest.assumptions
          |> list.find(fn(item) { item.id == id })
        })
      Ok(Response(
        "Inspected exact provenance receipt " <> requested_value,
        common(prepared, "inspect_source", [
          #("source", complete_entry_json(entry)),
          #(
            "linkedAssumptions",
            json.array(linked_assumptions, assumption_json),
          ),
        ]),
      ))
    }
  }
}

pub fn run_export(value: decode.ExportInput) -> Result(Response, DomainError) {
  use _ <- result.try(integer_range(
    "maximumManifestBytes",
    value.maximum_manifest_bytes,
    1,
    maximum_manifest_bytes,
  ))
  use prepared <- result.try(prepare(value.catalogue))
  let byte_count = string.byte_size(prepared.canonical_json)
  case byte_count > value.maximum_manifest_bytes {
    True ->
      Error(ManifestBudgetExceeded(byte_count, value.maximum_manifest_bytes))
    False ->
      Ok(Response(
        "Exported exact schema-v1 canonical provenance manifest within the supplied byte budget",
        common(prepared, "export_manifest", [
          #("maximumManifestBytes", json.int(value.maximum_manifest_bytes)),
          #("canonicalManifestJson", json.string(prepared.canonical_json)),
          #("truncated", json.bool(False)),
          #("signed", json.bool(False)),
        ]),
      ))
  }
}

fn prepare(value: decode.CatalogueInput) -> Result(Prepared, DomainError) {
  use instruction_ref <- result.try(sha(
    "catalogue.instructionRef",
    value.instruction_ref,
  ))
  use _ <- result.try(count_bound(
    "catalogue.additionalSensitiveQueryKeys",
    value.additional_sensitive_query_keys,
    maximum_sensitive_keys,
  ))
  use _ <- result.try(text_list(
    "catalogue.additionalSensitiveQueryKeys",
    value.additional_sensitive_query_keys,
  ))
  use _ <- result.try(count_bound(
    "catalogue.assumptions",
    value.assumptions,
    maximum_assumptions,
  ))
  use _ <- result.try(count_bound(
    "catalogue.evidence",
    value.evidence,
    maximum_evidence,
  ))
  use _ <- result.try(nonempty("catalogue.evidence", value.evidence))
  use _ <- result.try(count_bound("catalogue.roots", value.roots, maximum_roots))
  use with_assumptions <- result.try(
    list.try_fold(value.assumptions, manifest.new(), fn(current, input) {
      use item <- result.try(make_assumption(input))
      manifest.add_assumption(current, item)
      |> result.map_error(graph_error)
    }),
  )
  use built <- result.try(
    list.try_fold(
      value.evidence,
      BuildState(with_assumptions, []),
      fn(state, input) {
        use entry <- result.try(make_evidence(
          input,
          value.additional_sensitive_query_keys,
        ))
        let before = list.length(manifest.evidence(state.manifest))
        use next_manifest <- result.try(
          manifest.add_evidence(state.manifest, entry.item)
          |> result.map_error(graph_error),
        )
        let next_entries = case
          list.length(manifest.evidence(next_manifest)) > before
        {
          True -> list.append(state.entries, [entry])
          False -> state.entries
        }
        Ok(BuildState(next_manifest, next_entries))
      },
    ),
  )
  use final_manifest <- result.try(
    list.try_fold(value.roots, built.manifest, fn(current, input) {
      use id <- result.try(evidence_id("catalogue.roots[]", input))
      manifest.add_root(current, id) |> result.map_error(graph_error)
    }),
  )
  let canonical_json = canonical.encode_manifest(final_manifest)
  use manifest_sha <- result.try(
    hash.manifest(final_manifest)
    |> result.map_error(fn(_) {
      GraphFailure("canonical manifest hashing failed")
    }),
  )
  Ok(Prepared(
    identity.sha256_value(instruction_ref),
    final_manifest,
    built.entries,
    canonical_json,
    identity.sha256_value(manifest_sha),
  ))
}

fn make_assumption(
  value: decode.AssumptionInput,
) -> Result(assumption.Assumption, DomainError) {
  use id <- result.try(
    assumption.id(value.id)
    |> result.map_error(fn(_) {
      InvalidField(
        "catalogue.assumptions[].id",
        "expected trimmed non-empty text",
      )
    }),
  )
  use origin <- result.try(assumption_origin(value.origin))
  use assumption_value <- result.try(assumption_value(value.value))
  assumption.new(id, value.name, assumption_value, origin, value.explanation)
  |> result.map_error(fn(error) {
    InvalidField("catalogue.assumptions[]", string.inspect(error))
  })
}

fn assumption_origin(value: String) -> Result(assumption.Origin, DomainError) {
  case value {
    "user" -> Ok(assumption.User)
    "provider" -> Ok(assumption.Provider)
    "method" -> Ok(assumption.Method)
    "policy" -> Ok(assumption.Policy)
    _ ->
      Error(InvalidField(
        "catalogue.assumptions[].origin",
        "expected user, provider, method, or policy",
      ))
  }
}

fn assumption_value(
  value: decode.AssumptionValueInput,
) -> Result(assumption.Value, DomainError) {
  case
    value.kind,
    value.text,
    value.decimal,
    value.amount,
    value.currency,
    value.boolean
  {
    "text", Some(text), None, None, None, None -> Ok(assumption.TextValue(text))
    "decimal", None, Some(raw), None, None, None -> {
      use parsed <- result.try(parse_decimal(
        "catalogue.assumptions[].value.decimal",
        raw,
      ))
      Ok(assumption.DecimalValue(parsed))
    }
    "money", None, None, Some(raw), Some(code), None -> {
      use parsed <- result.try(parse_decimal(
        "catalogue.assumptions[].value.amount",
        raw,
      ))
      use parsed_currency <- result.try(
        currency.from_code(code)
        |> result.map_error(fn(_) {
          InvalidField(
            "catalogue.assumptions[].value.currency",
            "expected a three-letter currency code",
          )
        }),
      )
      Ok(assumption.MoneyValue(money.new(parsed, parsed_currency)))
    }
    "boolean", None, None, None, None, Some(value) ->
      Ok(assumption.BooleanValue(value))
    _, _, _, _, _, _ ->
      Error(InvalidField(
        "catalogue.assumptions[].value",
        "variant must supply exactly its named field(s) and no others",
      ))
  }
}

fn make_evidence(
  value: decode.EvidenceInput,
  sensitive_keys: List(String),
) -> Result(PreparedEntry, DomainError) {
  use id <- result.try(evidence_id(
    "catalogue.evidence[].receiptHash",
    value.receipt_hash,
  ))
  use fingerprint_sha <- result.try(sha(
    "catalogue.evidence[].sourceFingerprint",
    value.source_fingerprint,
  ))
  use source_kind <- result.try(source_kind(value.source))
  use source_result <- result.try(safe_source(
    value.source.provider,
    value.source.reference,
    source_kind,
    sensitive_keys,
  ))
  let #(source_ref, reference_redacted) = source_result
  use licence <- result.try(licence(value.licence))
  use as_of <- result.try(instant(
    "catalogue.evidence[].asOfUnixMilliseconds",
    value.as_of_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
    "catalogue.evidence[].retrievedAtUnixMilliseconds",
    value.retrieved_at_unix_ms,
  ))
  use content_hash <- result.try(sha(
    "catalogue.evidence[].contentHash",
    value.content_hash,
  ))
  use parents <- result.try(
    list.try_map(value.parents, fn(value) {
      evidence_id("catalogue.evidence[].parents[]", value)
    }),
  )
  use assumptions <- result.try(
    list.try_map(value.assumptions, fn(value) {
      assumption.id(value)
      |> result.map_error(fn(_) {
        InvalidField(
          "catalogue.evidence[].assumptions[]",
          "expected trimmed non-empty assumption ID",
        )
      })
    }),
  )
  use availability <- result.try(availability(value.availability))
  use item <- result.try(
    evidence.new(
      id,
      identity.source_fingerprint(fingerprint_sha),
      source_ref,
      licence,
      as_of,
      retrieved_at,
      value.media_type,
      value.byte_length,
      content_hash,
      parents,
      assumptions,
    )
    |> result.map_error(fn(error) {
      InvalidField("catalogue.evidence[]", string.inspect(error))
    }),
  )
  Ok(PreparedEntry(
    evidence.with_availability(item, availability),
    reference_redacted,
  ))
}

fn source_kind(
  value: decode.SourceInput,
) -> Result(source.SourceKind, DomainError) {
  case value.kind, value.other_kind {
    "official", None -> Ok(source.Official)
    "exchange", None -> Ok(source.Exchange)
    "regulator", None -> Ok(source.Regulator)
    "licensed_vendor", None -> Ok(source.LicensedVendor)
    "user_supplied", None -> Ok(source.UserSupplied)
    "synthetic", None -> Ok(source.Synthetic)
    "other", Some(kind) ->
      case kind != "" && string.trim(kind) == kind {
        True -> Ok(source.Other(kind))
        False ->
          Error(InvalidField(
            "catalogue.evidence[].source.otherKind",
            "other source kind requires trimmed non-empty otherKind",
          ))
      }
    "other", None ->
      Error(InvalidField(
        "catalogue.evidence[].source.otherKind",
        "other source kind requires trimmed non-empty otherKind",
      ))
    _, Some(_) ->
      Error(InvalidField(
        "catalogue.evidence[].source.otherKind",
        "otherKind is only allowed when kind is other",
      ))
    _, None ->
      Error(InvalidField(
        "catalogue.evidence[].source.kind",
        "unsupported explicit source kind",
      ))
  }
}

fn safe_source(
  provider: String,
  raw_reference: String,
  kind: source.SourceKind,
  sensitive_keys: List(String),
) -> Result(#(source.SourceRef, Bool), DomainError) {
  let projected = redact.url(raw_reference, sensitive_keys)
  case source.new(provider, projected, kind) {
    Ok(value) -> Ok(#(value, projected != raw_reference))
    Error(source.UnsafeReference) -> {
      use digest <- result.try(
        hash.text(raw_reference)
        |> result.map_error(fn(_) {
          InvalidField(
            "catalogue.evidence[].source.reference",
            "could not create a safe reference digest",
          )
        }),
      )
      let fallback =
        "redacted-reference:sha256:" <> identity.sha256_value(digest)
      source.new(provider, fallback, kind)
      |> result.map(fn(value) { #(value, True) })
      |> result.map_error(fn(_) {
        InvalidField(
          "catalogue.evidence[].source",
          "provider or reference is not trimmed non-empty text",
        )
      })
    }
    Error(_) ->
      Error(InvalidField(
        "catalogue.evidence[].source",
        "provider or reference is not trimmed non-empty text",
      ))
  }
}

fn licence(
  value: decode.LicenceInput,
) -> Result(evidence.Licence, DomainError) {
  use _ <- result.try(trimmed_text(
    "catalogue.evidence[].licence.label",
    value.label,
  ))
  use notes <- result.try(optional_trimmed_text(
    "catalogue.evidence[].licence.notes",
    value.notes,
  ))
  use redistribution <- result.try(redistribution(value.redistribution))
  Ok(evidence.Licence(value.label, redistribution, notes))
}

fn redistribution(
  value: String,
) -> Result(evidence.Redistribution, DomainError) {
  case value {
    "public_domain" -> Ok(evidence.PublicDomain)
    "attribution_required" -> Ok(evidence.AttributionRequired)
    "internal_use_only" -> Ok(evidence.InternalUseOnly)
    "no_redistribution" -> Ok(evidence.NoRedistribution)
    "unknown" -> Ok(evidence.UnknownRedistribution)
    _ ->
      Error(InvalidField(
        "catalogue.evidence[].licence.redistribution",
        "unsupported explicit redistribution state",
      ))
  }
}

fn availability(
  value: decode.AvailabilityInput,
) -> Result(evidence.Availability, DomainError) {
  case value.state, value.reason, value.superseded_by {
    "available", None, None -> Ok(evidence.Available)
    "unavailable", Some(reason), None -> {
      use _ <- result.try(trimmed_text(
        "catalogue.evidence[].availability.reason",
        reason,
      ))
      Ok(evidence.Unavailable(reason))
    }
    "expired", None, None -> Ok(evidence.Expired)
    "superseded", None, Some(by) -> {
      use id <- result.try(evidence_id(
        "catalogue.evidence[].availability.supersededBy",
        by,
      ))
      Ok(evidence.Superseded(id))
    }
    "verification_failed", Some(reason), None -> {
      use _ <- result.try(trimmed_text(
        "catalogue.evidence[].availability.reason",
        reason,
      ))
      Ok(evidence.VerificationFailed(reason))
    }
    _, _, _ ->
      Error(InvalidField(
        "catalogue.evidence[].availability",
        "state must supply exactly its required reason or supersededBy field",
      ))
  }
}

fn common(
  prepared: Prepared,
  operation: String,
  fields: List(#(String, Json)),
) -> Json {
  json.object(list.append(
    [
      #("schemaVersion", json.int(1)),
      #("operation", json.string(operation)),
      #("instructionRef", json.string(prepared.instruction_ref)),
      #("manifestHandle", json.string(prepared.manifest_handle)),
      #(
        "canonicalManifestBytes",
        json.int(string.byte_size(prepared.canonical_json)),
      ),
      #(
        "counts",
        json.object([
          #(
            "assumptions",
            json.int(list.length(manifest.assumptions(prepared.manifest))),
          ),
          #(
            "evidence",
            json.int(list.length(manifest.evidence(prepared.manifest))),
          ),
          #("roots", json.int(list.length(manifest.roots(prepared.manifest)))),
        ]),
      ),
      #(
        "availableOperations",
        json.array(
          ["list_sources", "inspect_source", "export_manifest"],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #(
        "pluginDecisionFields",
        json.array([], fn(value: String) { json.string(value) }),
      ),
      #(
        "limitations",
        json.array(
          [
            "Graph validity and matching hashes do not prove source truth, authority, quality, origin authentication, or professional sufficiency.",
            "Licence metadata is caller-supplied evidence and does not grant redistribution permission.",
            "The plugin does not fetch, verify, select, compare, rank, persist, sign, or recommend sources or next actions.",
          ],
          json.string,
        ),
      ),
    ],
    fields,
  ))
}

fn compact_entry_json(entry: PreparedEntry) -> Json {
  let item = entry.item
  json.object([
    #("receiptHash", json.string(identity.evidence_id_value(item.id))),
    #(
      "sourceFingerprint",
      json.string(identity.source_fingerprint_value(item.source_fingerprint)),
    ),
    #("provider", json.string(source.provider(item.source))),
    #("reference", json.string(source.reference(item.source))),
    #("sourceKind", json.string(source_kind_name(source.kind(item.source)))),
    #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(item.as_of))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(item.retrieved_at)),
    ),
    #("mediaType", json.string(item.media_type)),
    #("byteLength", json.int(item.byte_length)),
    #("contentHash", json.string(identity.sha256_value(item.content_hash))),
    #("licenceLabel", json.string(item.licence.label)),
    #(
      "redistribution",
      json.string(redistribution_name(item.licence.redistribution)),
    ),
    #("availability", availability_json(item.availability)),
    #("parentCount", json.int(list.length(item.parents))),
    #("assumptionCount", json.int(list.length(item.assumptions))),
    #("referenceRedacted", json.bool(entry.reference_redacted)),
  ])
}

fn complete_entry_json(entry: PreparedEntry) -> Json {
  let item = entry.item
  json.object([
    #("receiptHash", json.string(identity.evidence_id_value(item.id))),
    #(
      "sourceFingerprint",
      json.string(identity.source_fingerprint_value(item.source_fingerprint)),
    ),
    #(
      "source",
      json.object([
        #("provider", json.string(source.provider(item.source))),
        #("reference", json.string(source.reference(item.source))),
        #("kind", json.string(source_kind_name(source.kind(item.source)))),
        #("referenceRedacted", json.bool(entry.reference_redacted)),
      ]),
    ),
    #(
      "licence",
      json.object([
        #("label", json.string(item.licence.label)),
        #(
          "redistribution",
          json.string(redistribution_name(item.licence.redistribution)),
        ),
        #("notes", json.nullable(item.licence.notes, json.string)),
      ]),
    ),
    #("asOfUnixMilliseconds", json.int(time.unix_milliseconds(item.as_of))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(item.retrieved_at)),
    ),
    #("mediaType", json.string(item.media_type)),
    #("byteLength", json.int(item.byte_length)),
    #("contentHash", json.string(identity.sha256_value(item.content_hash))),
    #(
      "parents",
      json.array(item.parents, fn(id) {
        json.string(identity.evidence_id_value(id))
      }),
    ),
    #(
      "assumptionIds",
      json.array(item.assumptions, fn(id) {
        json.string(assumption.id_value(id))
      }),
    ),
    #("availability", availability_json(item.availability)),
  ])
}

fn assumption_json(value: assumption.Assumption) -> Json {
  json.object([
    #("id", json.string(assumption.id_value(value.id))),
    #("name", json.string(value.name)),
    #("origin", json.string(origin_name(value.origin))),
    #("value", assumption_value_json(value.value)),
    #("explanation", json.string(value.explanation)),
  ])
}

fn assumption_value_json(value: assumption.Value) -> Json {
  case value {
    assumption.TextValue(value) ->
      json.object([
        #("kind", json.string("text")),
        #("text", json.string(value)),
      ])
    assumption.DecimalValue(value) ->
      json.object([
        #("kind", json.string("decimal")),
        #("decimal", json.string(decimal.to_string(value))),
      ])
    assumption.MoneyValue(value) ->
      json.object([
        #("kind", json.string("money")),
        #("amount", json.string(decimal.to_string(value.amount))),
        #("currency", json.string(currency.code(value.currency))),
      ])
    assumption.BooleanValue(value) ->
      json.object([
        #("kind", json.string("boolean")),
        #("boolean", json.bool(value)),
      ])
  }
}

fn availability_json(value: evidence.Availability) -> Json {
  case value {
    evidence.Available -> json.object([#("state", json.string("available"))])
    evidence.Unavailable(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
      ])
    evidence.Expired -> json.object([#("state", json.string("expired"))])
    evidence.Superseded(by) ->
      json.object([
        #("state", json.string("superseded")),
        #("supersededBy", json.string(identity.evidence_id_value(by))),
      ])
    evidence.VerificationFailed(reason) ->
      json.object([
        #("state", json.string("verification_failed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(kind) -> "other:" <> kind
  }
}

fn redistribution_name(value: evidence.Redistribution) -> String {
  case value {
    evidence.PublicDomain -> "public_domain"
    evidence.AttributionRequired -> "attribution_required"
    evidence.InternalUseOnly -> "internal_use_only"
    evidence.NoRedistribution -> "no_redistribution"
    evidence.UnknownRedistribution -> "unknown"
  }
}

fn origin_name(value: assumption.Origin) -> String {
  case value {
    assumption.User -> "user"
    assumption.Provider -> "provider"
    assumption.Method -> "method"
    assumption.Policy -> "policy"
  }
}

fn sha(field: String, value: String) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected an exact SHA-256 hexadecimal string")
  })
}

fn evidence_id(
  field: String,
  value: String,
) -> Result(identity.EvidenceId, DomainError) {
  use digest <- result.try(sha(field, value))
  Ok(identity.evidence_id(digest))
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "instant is outside the supported range")
  })
}

fn parse_decimal(
  field: String,
  value: String,
) -> Result(decimal.Decimal, DomainError) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected an exact decimal string")
  })
}

fn graph_error(value: manifest.ManifestError) -> DomainError {
  GraphFailure(string.inspect(value))
}

fn integer_range(
  field: String,
  value: Int,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  case value >= minimum && value <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "expected an integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn count_bound(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, DomainError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "at most " <> int.to_string(maximum) <> " values are supported",
      ))
  }
}

fn nonempty(field: String, values: List(value)) -> Result(Nil, DomainError) {
  case values {
    [] -> Error(InvalidField(field, "at least one value is required"))
    _ -> Ok(Nil)
  }
}

fn text_list(field: String, values: List(String)) -> Result(Nil, DomainError) {
  list.try_each(values, fn(value) { trimmed_text(field <> "[]", value) })
}

fn trimmed_text(field: String, value: String) -> Result(Nil, DomainError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "expected trimmed non-empty text"))
  }
}

fn optional_trimmed_text(
  field: String,
  value: Option(String),
) -> Result(Option(String), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> {
      use _ <- result.try(trimmed_text(field, value))
      Ok(Some(value))
    }
  }
}
