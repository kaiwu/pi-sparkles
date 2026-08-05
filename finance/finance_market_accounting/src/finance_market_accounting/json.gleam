import finance_core/decimal
import finance_core/time
import finance_market_accounting/fact
import finance_market_documents/document
import finance_market_documents/wire
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{None}

pub const schema_version = 1

pub fn encode(value: fact.Fact) -> String {
  value |> to_json |> json.to_string
}

pub fn to_json(value: fact.Fact) -> Json {
  json.object([
    #("schemaVersion", json.int(schema_version)),
    #("listing", wire.listing_json(fact.listing(value))),
    #(
      "documentId",
      value |> fact.document_id |> document.document_id_value |> json.string,
    ),
    #("lineCode", json.nullable(fact.line_code(value), json.string)),
    #("originalLabel", json.string(fact.original_label(value))),
    #("value", reported_value_json(fact.value(value))),
    #("reportedUnit", json.string(fact.reported_unit(value))),
    #("scale", scale_json(fact.reported_scale(value))),
    #(
      "normalizedUnit",
      json.nullable(fact.normalized_unit(value), wire.unit_json),
    ),
    #("accountingStandard", json.string(fact.accounting_standard(value))),
    #("statementScope", scope_json(fact.statement_scope(value))),
    #("period", period_json(fact.period(value))),
    #("reportClass", json.string(fact.report_class(value))),
    #("auditState", json.string(audit_tag(fact.audit_state(value)))),
    #(
      "restatementState",
      json.string(restatement_tag(fact.restatement_state(value))),
    ),
    #("evidenceId", wire.evidence_id_json(fact.evidence_id(value))),
  ])
}

pub fn decode(input: String) -> Result(fact.Fact, json.DecodeError) {
  json.parse(input, decoder())
}

pub fn decoder() -> decode.Decoder(fact.Fact) {
  use _version <- decode.field("schemaVersion", version_decoder())
  use listing <- decode.field("listing", wire.listing_decoder())
  use document_id_value <- decode.field("documentId", decode.string)
  use line_code <- decode.field("lineCode", decode.optional(decode.string))
  use label <- decode.field("originalLabel", decode.string)
  use value <- decode.field("value", reported_value_decoder())
  use reported_unit <- decode.field("reportedUnit", decode.string)
  use scale <- decode.field("scale", scale_decoder())
  use normalized_unit <- decode.field(
    "normalizedUnit",
    decode.optional(wire.unit_decoder()),
  )
  use standard <- decode.field("accountingStandard", decode.string)
  use scope <- decode.field("statementScope", scope_decoder())
  use period <- decode.field("period", period_decoder())
  use report_class <- decode.field("reportClass", decode.string)
  use audit <- decode.field("auditState", audit_decoder())
  use restatement <- decode.field("restatementState", restatement_decoder())
  use evidence <- decode.field("evidenceId", wire.evidence_id_decoder())
  case document.document_id(document_id_value) {
    Error(_) -> decode.failure(placeholder(), "valid market accounting fact")
    Ok(document_id) ->
      case
        fact.new(
          listing: listing,
          document_id: document_id,
          line_code: line_code,
          original_label: label,
          value: value,
          reported_unit: reported_unit,
          scale: scale,
          normalized_unit: normalized_unit,
          accounting_standard: standard,
          statement_scope: scope,
          period: period,
          report_class: report_class,
          audit_state: audit,
          restatement_state: restatement,
          evidence_id: evidence,
        )
      {
        Ok(value) -> decode.success(value)
        Error(_) ->
          decode.failure(placeholder(), "valid market accounting fact")
      }
  }
}

fn reported_value_json(value: fact.ReportedValue) -> Json {
  case fact.reported_value_view(value) {
    fact.NumericValue(raw) -> tagged_value("numeric", raw)
    fact.TextValue(text) -> tagged_value("text", text)
    fact.BooleanValue(value) ->
      json.object([
        #("tag", json.string("boolean")),
        #("value", json.bool(value)),
      ])
    fact.MissingValue(reason) -> tagged_value("missing", reason)
  }
}

fn reported_value_decoder() -> decode.Decoder(fact.ReportedValue) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "numeric" -> {
      use value <- decode.field("value", decode.string)
      case fact.numeric(value) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(placeholder_value(), "exact decimal string")
      }
    }
    "text" -> {
      use value <- decode.field("value", decode.string)
      case fact.text(value) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(placeholder_value(), "non-empty exact text")
      }
    }
    "boolean" -> {
      use value <- decode.field("value", decode.bool)
      decode.success(fact.boolean(value))
    }
    "missing" -> {
      use value <- decode.field("value", decode.string)
      case fact.missing(value) {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(placeholder_value(), "valid missing reason")
      }
    }
    _ -> decode.failure(placeholder_value(), "known reported value kind")
  }
}

fn scale_json(value: fact.Scale) -> Json {
  json.object([
    #("originalLabel", json.string(fact.scale_label(value))),
    #(
      "multiplier",
      value |> fact.scale_multiplier |> decimal.to_string |> json.string,
    ),
  ])
}

fn scale_decoder() -> decode.Decoder(fact.Scale) {
  use label <- decode.field("originalLabel", decode.string)
  use multiplier <- decode.field("multiplier", decimal_decoder())
  case fact.scale(label, multiplier) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_scale(), "positive reported scale")
  }
}

fn scope_json(value: fact.StatementScope) -> Json {
  case value {
    fact.Consolidated -> tagged("consolidated")
    fact.ParentCompany -> tagged("parent_company")
    fact.OtherScope(value) -> tagged_value("other", value)
  }
}

fn scope_decoder() -> decode.Decoder(fact.StatementScope) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "consolidated" -> decode.success(fact.Consolidated)
    "parent_company" -> decode.success(fact.ParentCompany)
    "other" -> {
      use value <- decode.field("value", decode.string)
      decode.success(fact.OtherScope(value))
    }
    _ -> decode.failure(fact.Consolidated, "known statement scope")
  }
}

fn period_json(value: fact.Period) -> Json {
  case value {
    fact.Instant(date) ->
      json.object([
        #("tag", json.string("instant")),
        #("date", wire.date_json(date)),
      ])
    fact.Duration(start, end) ->
      json.object([
        #("tag", json.string("duration")),
        #("start", wire.date_json(start)),
        #("end", wire.date_json(end)),
      ])
  }
}

fn period_decoder() -> decode.Decoder(fact.Period) {
  use tag <- decode.field("tag", decode.string)
  case tag {
    "instant" -> {
      use date <- decode.field("date", wire.date_decoder())
      decode.success(fact.Instant(date))
    }
    "duration" -> {
      use start <- decode.field("start", wire.date_decoder())
      use end <- decode.field("end", wire.date_decoder())
      case date_number(start) <= date_number(end) {
        True -> decode.success(fact.Duration(start, end))
        False ->
          decode.failure(placeholder_period(), "ordered reporting period")
      }
    }
    _ -> decode.failure(placeholder_period(), "known reporting period kind")
  }
}

fn audit_tag(value: fact.AuditState) -> String {
  case value {
    fact.Audited -> "audited"
    fact.Reviewed -> "reviewed"
    fact.Unaudited -> "unaudited"
    fact.UnknownAuditState -> "unknown"
  }
}

fn audit_decoder() -> decode.Decoder(fact.AuditState) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "audited" -> decode.success(fact.Audited)
      "reviewed" -> decode.success(fact.Reviewed)
      "unaudited" -> decode.success(fact.Unaudited)
      "unknown" -> decode.success(fact.UnknownAuditState)
      _ -> decode.failure(fact.UnknownAuditState, "known audit state")
    }
  })
}

fn restatement_tag(value: fact.RestatementState) -> String {
  case value {
    fact.Original -> "original"
    fact.Restated -> "restated"
    fact.Corrected -> "corrected"
    fact.Superseded -> "superseded"
    fact.UnknownRestatementState -> "unknown"
  }
}

fn restatement_decoder() -> decode.Decoder(fact.RestatementState) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "original" -> decode.success(fact.Original)
      "restated" -> decode.success(fact.Restated)
      "corrected" -> decode.success(fact.Corrected)
      "superseded" -> decode.success(fact.Superseded)
      "unknown" -> decode.success(fact.UnknownRestatementState)
      _ ->
        decode.failure(fact.UnknownRestatementState, "known restatement state")
    }
  })
}

fn version_decoder() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(version) {
    case version == schema_version {
      True -> decode.success(version)
      False -> decode.failure(schema_version, "market accounting schema v1")
    }
  })
}

fn decimal_decoder() -> decode.Decoder(decimal.Decimal) {
  decode.string
  |> decode.then(fn(value) {
    case decimal.parse(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(decimal.zero(), "exact decimal string")
    }
  })
}

fn tagged(tag: String) -> Json {
  json.object([#("tag", json.string(tag))])
}

fn tagged_value(tag: String, value: String) -> Json {
  json.object([#("tag", json.string(tag)), #("value", json.string(value))])
}

fn date_number(value: time.Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}

fn placeholder_value() -> fact.ReportedValue {
  let assert Ok(value) = fact.missing("wire placeholder")
  value
}

fn placeholder_scale() -> fact.Scale {
  let assert Ok(one) = decimal.parse("1")
  let assert Ok(value) = fact.scale("unit", one)
  value
}

fn placeholder_period() -> fact.Period {
  let assert Ok(date) = time.date(1970, 1, 1)
  fact.Instant(date)
}

fn placeholder() -> fact.Fact {
  let listing = {
    let decoder = wire.listing_decoder()
    let assert Ok(value) =
      json.parse(
        "{\"track\":\"us\",\"instrumentId\":\"wire-placeholder\",\"symbol\":\"PLACEHOLDER\",\"mic\":\"XNAS\"}",
        decoder,
      )
    value
  }
  let assert Ok(document_id) = document.document_id("wire-placeholder")
  let assert Ok(evidence) =
    json.parse(
      "\"0000000000000000000000000000000000000000000000000000000000000000\"",
      wire.evidence_id_decoder(),
    )
  let assert Ok(value) =
    fact.new(
      listing: listing,
      document_id: document_id,
      line_code: None,
      original_label: "placeholder",
      value: placeholder_value(),
      reported_unit: "unit",
      scale: placeholder_scale(),
      normalized_unit: None,
      accounting_standard: "placeholder",
      statement_scope: fact.Consolidated,
      period: placeholder_period(),
      report_class: "placeholder",
      audit_state: fact.UnknownAuditState,
      restatement_state: fact.UnknownRestatementState,
      evidence_id: evidence,
    )
  value
}
