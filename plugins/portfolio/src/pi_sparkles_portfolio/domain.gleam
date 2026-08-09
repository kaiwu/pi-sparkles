import finance_core/decimal.{type Decimal}
import finance_core/time.{type Instant}
import finance_provenance/identity.{type Sha256}
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_portfolio/raw

pub const maximum_file_bytes = 10_000_000

pub const maximum_rows = 10_000

pub const maximum_columns = 100

pub const maximum_field_bytes = 4096

pub const maximum_json_depth = 10

pub const maximum_json_elements = 10_000

pub const maximum_session_snapshots = 8

pub type AccountVisibility {
  Redacted
  ReviewVisible
}

pub type ImportPlan {
  ImportPlan(
    path: String,
    format: raw.Format,
    delimiter: raw.Delimiter,
    decimal_convention: raw.DecimalConvention,
    budgets: raw.Budgets,
    maximum_file_bytes: Int,
    tolerance: Decimal,
    tolerance_lexeme: String,
    account_visibility: AccountVisibility,
  )
}

pub type TextField {
  TextKnown(value: String, source_lexeme: String, provenance: String)
  TextExplicitNull(provenance: String)
  TextBlankLexeme(provenance: String)
  TextAbsentColumn
  TextUnavailable(source_lexeme: String, provenance: String)
  TextDecodeFailure(source: json.Json, reason: String, provenance: String)
}

pub type DecimalField {
  DecimalKnown(value: Decimal, source_lexeme: String, provenance: String)
  DecimalExplicitNull(provenance: String)
  DecimalBlankLexeme(provenance: String)
  DecimalAbsentColumn
  DecimalUnavailable(source_lexeme: String, provenance: String)
  DecimalDecodeFailure(source: json.Json, reason: String, provenance: String)
}

pub type Position {
  Position(
    source_index: Int,
    position_id: TextField,
    track: TextField,
    listing_id: TextField,
    mic: TextField,
    source_symbol: TextField,
    security_name: TextField,
    security_type: TextField,
    direction: TextField,
    quantity: DecimalField,
    quantity_unit: TextField,
    settled_quantity: DecimalField,
    available_quantity: DecimalField,
    avg_cost: DecimalField,
    cost_basis_total: DecimalField,
    current_mark: DecimalField,
    mark_time: TextField,
    market_value: DecimalField,
    position_currency: TextField,
    accrued_income: DecimalField,
    unrealized_pnl: DecimalField,
    realized_pnl: DecimalField,
    source_row_id: TextField,
    extra_columns: Dict(String, raw.Value),
    duplicate_count: Int,
    conflicting_position_id: Bool,
    identity_resolved: Bool,
    unsupported: Bool,
    unsupported_reason: Option(String),
    formula_cells: List(String),
    decode_failure_count: Int,
    calculated_market_value: Result(Decimal, String),
    fingerprint: String,
  )
}

pub type Snapshot {
  Snapshot(
    snapshot_id: String,
    source_kind: String,
    account_id: TextField,
    account_type: TextField,
    custodian: TextField,
    base_currency: String,
    source_as_of: TextField,
    retrieval_time: TextField,
    statement_period: TextField,
    entitlement: String,
    environment: TextField,
    supersedes: TextField,
    source_declared_total: DecimalField,
    source_total_currency: TextField,
    import_time: Instant,
    source_file_sha256: Sha256,
    source_content_bytes: Int,
    source_file_bytes: Int,
    format: raw.Format,
    decimal_convention: raw.DecimalConvention,
    tolerance: Decimal,
    tolerance_lexeme: String,
    account_visibility: AccountVisibility,
    positions: List(Position),
    total_source_rows: Int,
    duplicate_rows_collapsed: Int,
    truncation: raw.Truncation,
    top_level_extras: Dict(String, raw.Value),
  )
}

pub type State {
  State(snapshots: List(Snapshot))
}

pub type ImportError {
  InvalidPath
  InvalidFormat
  InvalidDelimiter
  InvalidDecimalConvention
  InvalidBudget(String)
  InvalidTolerance
  InvalidVisibility
  InvalidDocument(raw.Error)
  InvalidSnapshot(String)
  SnapshotIdConflict(String)
  SessionSnapshotBudgetReached
}

pub type StoreOutcome {
  Stored(State, Snapshot)
  Existing(State, Snapshot)
}

pub type PositionFilter {
  PositionFilter(
    position_id: Option(String),
    source_row_id: Option(String),
    track: Option(String),
    currency: Option(String),
    security_type: Option(String),
    identity_resolved: Option(Bool),
    unsupported: Option(Bool),
    conflicting: Option(Bool),
    has_decode_failure: Option(Bool),
  )
}

type CurrencyTotal {
  CurrencyTotal(
    currency: String,
    position_value: Decimal,
    cash: Decimal,
    liabilities: Decimal,
    included_rows: Int,
    omitted_rows: Int,
  )
}

type Counts {
  Counts(
    total_source_rows: Int,
    retained_rows: Int,
    positions: Int,
    cash_rows: Int,
    liability_rows: Int,
    unsupported: Int,
    identity_unresolved: Int,
    duplicates_collapsed: Int,
    conflicts: Int,
    decode_failure_rows: Int,
    formula_cells: Int,
  )
}

pub fn new_state() -> State {
  State([])
}

pub fn import_plan(
  path: String,
  format: String,
  delimiter: String,
  decimal_convention: String,
  maximum_bytes: Int,
  rows: Int,
  columns: Int,
  field_bytes: Int,
  json_depth: Int,
  json_elements: Int,
  tolerance: String,
  visibility: String,
) -> Result(ImportPlan, ImportError) {
  use Nil <- result.try(case valid_path(path) {
    True -> Ok(Nil)
    False -> Error(InvalidPath)
  })
  use format <- result.try(case format {
    "csv" -> Ok(raw.Csv)
    "json" -> Ok(raw.Json)
    _ -> Error(InvalidFormat)
  })
  use delimiter <- result.try(case delimiter {
    "comma" -> Ok(raw.Comma)
    "tab" -> Ok(raw.Tab)
    "semicolon" -> Ok(raw.Semicolon)
    _ -> Error(InvalidDelimiter)
  })
  use convention <- result.try(case decimal_convention {
    "plain_dot" -> Ok(raw.PlainDot)
    "comma_grouped_dot_decimal" -> Ok(raw.CommaGroupedDot)
    "space_grouped_comma_decimal" -> Ok(raw.SpaceGroupedComma)
    _ -> Error(InvalidDecimalConvention)
  })
  use Nil <- result.try(validate_budgets(
    maximum_bytes,
    rows,
    columns,
    field_bytes,
    json_depth,
    json_elements,
  ))
  use tolerance_value <- result.try(
    parse_decimal(tolerance, convention)
    |> result.map_error(fn(_) { InvalidTolerance }),
  )
  use Nil <- result.try(case decimal.compare(tolerance_value, decimal.zero()) {
    Lt -> Error(InvalidTolerance)
    Eq | Gt -> Ok(Nil)
  })
  use account_visibility <- result.try(case visibility {
    "redacted" -> Ok(Redacted)
    "review_visible" -> Ok(ReviewVisible)
    _ -> Error(InvalidVisibility)
  })
  Ok(ImportPlan(
    path,
    format,
    delimiter,
    convention,
    raw.Budgets(rows, columns, field_bytes, json_depth, json_elements),
    maximum_bytes,
    tolerance_value,
    tolerance,
    account_visibility,
  ))
}

pub fn decode_document(
  plan: ImportPlan,
  text: String,
  byte_count: Int,
  total_file_bytes: Int,
  byte_truncated: Bool,
  digest: Sha256,
  imported_at: Instant,
) -> Result(Snapshot, ImportError) {
  use document <- result.try(
    case plan.format {
      raw.Csv ->
        raw.decode_csv(text, plan.delimiter, plan.budgets, case byte_truncated {
          True -> Some(#(byte_count, total_file_bytes))
          False -> None
        })
      raw.Json -> raw.decode_json(text, plan.budgets, byte_truncated)
    }
    |> result.map_error(InvalidDocument),
  )
  use snapshot_id <- result.try(required_meta(document.snapshot, "snapshot_id"))
  use source_kind <- result.try(required_meta(document.snapshot, "source_kind"))
  use Nil <- result.try(case valid_source_kind(source_kind) {
    True -> Ok(Nil)
    False -> Error(InvalidSnapshot("invalid source_kind"))
  })
  use base_currency <- result.try(required_meta(
    document.snapshot,
    "base_currency",
  ))
  use Nil <- result.try(case valid_currency(base_currency) {
    True -> Ok(Nil)
    False -> Error(InvalidSnapshot("invalid base_currency"))
  })
  use entitlement <- result.try(required_meta(document.snapshot, "entitlement"))
  let decoded =
    document.rows
    |> list.map(fn(row) { decode_position(row, plan.decimal_convention) })
  let #(positions, duplicates) = collapse_duplicates(decoded)
  Ok(Snapshot(
    snapshot_id,
    source_kind,
    text_field(document.snapshot, "account_id"),
    text_field(document.snapshot, "account_type"),
    text_field(document.snapshot, "custodian"),
    base_currency,
    text_field(document.snapshot, "source_as_of"),
    text_field(document.snapshot, "retrieval_time"),
    text_field(document.snapshot, "statement_period"),
    entitlement,
    text_field(document.snapshot, "environment"),
    text_field(document.snapshot, "supersedes"),
    decimal_field(
      document.snapshot,
      "source_declared_total",
      plan.decimal_convention,
    ),
    text_field(document.snapshot, "source_total_currency"),
    imported_at,
    digest,
    byte_count,
    total_file_bytes,
    plan.format,
    plan.decimal_convention,
    plan.tolerance,
    plan.tolerance_lexeme,
    plan.account_visibility,
    positions,
    document.total_rows,
    duplicates,
    document.truncation,
    redact_sensitive(document.top_level_extras),
  ))
}

pub fn store_snapshot(
  state: State,
  snapshot: Snapshot,
) -> Result(StoreOutcome, ImportError) {
  let State(snapshots) = state
  case find_snapshot(snapshots, snapshot.snapshot_id) {
    Some(existing) ->
      case existing.source_file_sha256 == snapshot.source_file_sha256 {
        True -> Ok(Existing(state, existing))
        False -> Error(SnapshotIdConflict(snapshot.snapshot_id))
      }
    None ->
      case list.length(snapshots) >= maximum_session_snapshots {
        True -> Error(SessionSnapshotBudgetReached)
        False -> {
          let next = State([snapshot, ..snapshots])
          Ok(Stored(next, snapshot))
        }
      }
  }
}

pub fn lookup(state: State, snapshot_id: String) -> Option(Snapshot) {
  let State(snapshots) = state
  find_snapshot(snapshots, snapshot_id)
}

pub fn empty_filter() -> PositionFilter {
  PositionFilter(None, None, None, None, None, None, None, None, None)
}

pub fn summary(snapshot: Snapshot, operation: String) -> json.Json {
  let totals = currency_totals(snapshot.positions)
  let currencies =
    totals
    |> list.map(fn(value) { value.currency })
    |> list.sort(string.compare)
  let counts = count_positions(snapshot)
  json.object([
    #("schema", json.string("pi-sparkles/portfolio-snapshot-summary")),
    #("schemaVersion", json.int(1)),
    #("operation", json.string(operation)),
    #("snapshotId", json.string(snapshot.snapshot_id)),
    #("sourceKind", json.string(snapshot.source_kind)),
    #("baseCurrency", json.string(snapshot.base_currency)),
    #("sourceAsOf", text_field_json(snapshot.source_as_of)),
    #(
      "importTimeUnixMs",
      snapshot.import_time
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #(
      "accountId",
      private_text_json(snapshot.account_id, snapshot.account_visibility),
    ),
    #("accountType", text_field_json(snapshot.account_type)),
    #("custodian", text_field_json(snapshot.custodian)),
    #("entitlement", json.string(snapshot.entitlement)),
    #("environment", text_field_json(snapshot.environment)),
    #("supersedes", text_field_json(snapshot.supersedes)),
    #(
      "sourceFile",
      json.object([
        #("path", json.string("redacted")),
        #("name", json.string("redacted")),
        #("byteLength", json.int(snapshot.source_file_bytes)),
        #("hashedByteLength", json.int(snapshot.source_content_bytes)),
        #("hashScope", case snapshot.truncation {
          raw.TruncatedByBytes(_, _, _) -> json.string("retained_utf8_prefix")
          _ -> json.string("complete_file")
        }),
        #(
          "contentSha256",
          snapshot.source_file_sha256
            |> identity.sha256_value
            |> json.string,
        ),
        #(
          "digestMeaning",
          json.string(
            "content_binding_not_broker_authentication_or_correctness_proof",
          ),
        ),
        #("authentication", json.string("unauthenticated_import")),
        #("format", json.string(raw.format_name(snapshot.format))),
      ]),
    ),
    #("counts", counts_json(counts)),
    #("currencies", json.array(currencies, json.string)),
    #("subtotals", json.array(totals, currency_total_json)),
    #("reconciliation", reconciliation_json(snapshot, totals)),
    #("temporalCoherence", temporal_json(snapshot.positions)),
    #("truncation", truncation_json(snapshot.truncation)),
    #("topLevelExtras", raw_object_json(snapshot.top_level_extras)),
    #(
      "storage",
      json.object([
        #("kind", json.string("bounded_session_local_memory")),
        #("durable", json.bool(False)),
        #("survivesReload", json.bool(False)),
        #("maximumSnapshots", json.int(maximum_session_snapshots)),
      ]),
    ),
    #(
      "availableOperations",
      json.array(
        [
          "portfolio_summary(snapshotId)",
          "portfolio_positions(snapshotId,cursor,limit,filters)",
          "request_portfolio_risk_with_explicit_supported_facts",
        ],
        json.string,
      ),
    ),
    #(
      "limitations",
      json.array(
        [
          "Parsing does not prove broker origin, correctness, completeness, settlement, freshness, tradability, or portfolio sufficiency.",
          "Ticker text never infers track, MIC, listing identity, provider, or currency.",
          "Currency legs remain separate; no FX conversion or cross-currency total is performed.",
          "Source-reported value and P&L remain source facts; realized P&L is never derived.",
          "No broker, durable storage, automatic aggregation, review, optimization, rebalance, recommendation, authorization, or next-action effect exists.",
        ],
        json.string,
      ),
    ),
    #("decisionOwner", json.string("llm_user")),
    #("pluginDecisionFields", json.array([], json.string)),
  ])
}

pub fn positions_page(
  snapshot: Snapshot,
  cursor: Int,
  limit: Int,
  filter: PositionFilter,
) -> Result(json.Json, String) {
  case cursor >= 0, limit >= 1 && limit <= 200 {
    False, _ -> Error("cursor must be non-negative")
    _, False -> Error("limit must be between 1 and 200")
    True, True -> {
      let filtered =
        list.filter(snapshot.positions, fn(position) {
          matches_filter(position, filter)
        })
      let page = filtered |> list.drop(cursor) |> list.take(limit)
      let next = case cursor + list.length(page) < list.length(filtered) {
        True -> json.int(cursor + list.length(page))
        False -> json.null()
      }
      Ok(
        json.object([
          #("schema", json.string("pi-sparkles/portfolio-position-page")),
          #("schemaVersion", json.int(1)),
          #("operation", json.string("portfolio_positions")),
          #("snapshotId", json.string(snapshot.snapshot_id)),
          #("cursor", json.int(cursor)),
          #("limit", json.int(limit)),
          #("matchedCount", json.int(list.length(filtered))),
          #("returnedCount", json.int(list.length(page))),
          #("nextCursor", next),
          #("positions", json.array(page, position_json)),
          #("decisionOwner", json.string("llm_user")),
          #("pluginDecisionFields", json.array([], json.string)),
        ]),
      )
    }
  }
}

pub fn error_message(error: ImportError) -> String {
  case error {
    InvalidPath -> "portfolio import path was invalid"
    InvalidFormat -> "portfolio format must be csv or json"
    InvalidDelimiter -> "portfolio delimiter must be comma, tab, or semicolon"
    InvalidDecimalConvention -> "portfolio decimal convention was unsupported"
    InvalidBudget(name) -> "portfolio budget was invalid: " <> name
    InvalidTolerance -> "portfolio reconciliation tolerance was invalid"
    InvalidVisibility ->
      "portfolio account visibility must be redacted or review_visible"
    InvalidDocument(error) -> raw_error_message(error)
    InvalidSnapshot(reason) -> "portfolio snapshot was invalid: " <> reason
    SnapshotIdConflict(_) ->
      "portfolio snapshot ID already names different content in this session"
    SessionSnapshotBudgetReached ->
      "portfolio session snapshot budget was reached; reload before importing more"
  }
}

fn decode_position(
  row: raw.RawRow,
  convention: raw.DecimalConvention,
) -> Position {
  let raw.RawRow(source_index, fields) = row
  let position_id = text_field(fields, "position_id")
  let track = validated_track(text_field(fields, "track"))
  let listing_id = text_field(fields, "listing_id")
  let source_symbol = text_field(fields, "source_symbol")
  let security_type = text_field(fields, "security_type")
  let direction = validated_direction(text_field(fields, "direction"))
  let quantity = decimal_field(fields, "quantity", convention)
  let current_mark = decimal_field(fields, "current_mark", convention)
  let mark_time = text_field(fields, "mark_time")
  let currency =
    validated_currency_field(text_field(fields, "position_currency"))
  let source_row_id = case text_field(fields, "source_row_id") {
    TextAbsentColumn ->
      TextKnown(
        int.to_string(source_index),
        int.to_string(source_index),
        "source_row_number",
      )
    value -> value
  }
  let identity_resolved =
    text_known(track) && { text_known(listing_id) || text_known(source_symbol) }
  let #(unsupported, unsupported_reason) =
    unsupported_fact(security_type, direction)
  let calculated =
    calculated_market_value(quantity, current_mark, mark_time, currency)
  let extras =
    fields
    |> remove_names(position_fields())
    |> remove_names(raw.snapshot_fields())
    |> redact_sensitive
  let formula_cells =
    fields
    |> dict.to_list
    |> list.filter_map(fn(entry) {
      case entry.1 {
        raw.Text("=" <> _) -> Ok(entry.0)
        _ -> Error(Nil)
      }
    })
  let decoded_fields = [
    decimal_failure(quantity),
    decimal_failure(decimal_field(fields, "settled_quantity", convention)),
    decimal_failure(decimal_field(fields, "available_quantity", convention)),
    decimal_failure(decimal_field(fields, "avg_cost", convention)),
    decimal_failure(decimal_field(fields, "cost_basis_total", convention)),
    decimal_failure(current_mark),
    decimal_failure(decimal_field(fields, "market_value", convention)),
    decimal_failure(decimal_field(fields, "accrued_income", convention)),
    decimal_failure(decimal_field(fields, "unrealized_pnl", convention)),
    decimal_failure(decimal_field(fields, "realized_pnl", convention)),
    text_failure(track),
    text_failure(direction),
    text_failure(currency),
  ]
  let fingerprint = raw_fingerprint(fields)
  Position(
    source_index,
    position_id,
    track,
    listing_id,
    text_field(fields, "mic"),
    source_symbol,
    text_field(fields, "security_name"),
    security_type,
    direction,
    quantity,
    text_field(fields, "quantity_unit"),
    decimal_field(fields, "settled_quantity", convention),
    decimal_field(fields, "available_quantity", convention),
    decimal_field(fields, "avg_cost", convention),
    decimal_field(fields, "cost_basis_total", convention),
    current_mark,
    mark_time,
    decimal_field(fields, "market_value", convention),
    currency,
    decimal_field(fields, "accrued_income", convention),
    decimal_field(fields, "unrealized_pnl", convention),
    decimal_field(fields, "realized_pnl", convention),
    source_row_id,
    extras,
    1,
    False,
    identity_resolved,
    unsupported,
    unsupported_reason,
    formula_cells,
    decoded_fields |> list.filter(fn(value) { value }) |> list.length,
    calculated,
    fingerprint,
  )
}

fn collapse_duplicates(positions: List(Position)) -> #(List(Position), Int) {
  let grouped =
    positions
    |> list.fold(dict.new(), fn(groups, position) {
      let key = case text_value(position.position_id) {
        Some(value) -> "id:" <> value
        None -> "row:" <> int.to_string(position.source_index)
      }
      let values = dict.get(groups, key) |> result.unwrap([])
      dict.insert(groups, key, [position, ..values])
    })
  let collapsed =
    grouped
    |> dict.values
    |> list.flat_map(collapse_group)
    |> list.sort(fn(left, right) {
      int.compare(left.source_index, right.source_index)
    })
  #(collapsed, list.length(positions) - list.length(collapsed))
}

fn collapse_group(values: List(Position)) -> List(Position) {
  let unique = list.fold(list.reverse(values), [], merge_duplicate)
  let conflict = list.length(unique) > 1
  case conflict {
    True ->
      list.map(unique, fn(value) {
        Position(..value, conflicting_position_id: True)
      })
    False -> unique
  }
}

fn merge_duplicate(
  accumulator: List(Position),
  value: Position,
) -> List(Position) {
  case accumulator {
    [] -> [value]
    [existing, ..rest] if existing.fingerprint == value.fingerprint -> [
      Position(
        ..existing,
        duplicate_count: existing.duplicate_count + value.duplicate_count,
      ),
      ..rest
    ]
    [existing, ..rest] -> [existing, ..merge_duplicate(rest, value)]
  }
}

fn text_field(fields: Dict(String, raw.Value), name: String) -> TextField {
  let provenance = "source_field:" <> name
  case dict.get(fields, name) {
    Error(_) -> TextAbsentColumn
    Ok(raw.Absent) -> TextAbsentColumn
    Ok(raw.Null) -> TextExplicitNull(provenance)
    Ok(raw.Text(value)) ->
      case string.trim(value) == "", unavailable_lexeme(value) {
        True, _ -> TextBlankLexeme(provenance)
        _, True -> TextUnavailable(value, provenance)
        False, False -> TextKnown(value, value, provenance)
      }
    Ok(value) ->
      TextDecodeFailure(raw.value_json(value), "expected_string", provenance)
  }
}

fn decimal_field(
  fields: Dict(String, raw.Value),
  name: String,
  convention: raw.DecimalConvention,
) -> DecimalField {
  let provenance = "source_field:" <> name
  case dict.get(fields, name) {
    Error(_) -> DecimalAbsentColumn
    Ok(raw.Absent) -> DecimalAbsentColumn
    Ok(raw.Null) -> DecimalExplicitNull(provenance)
    Ok(raw.Text(value)) ->
      case string.trim(value) == "", unavailable_lexeme(value), value {
        True, _, _ -> DecimalBlankLexeme(provenance)
        _, True, _ -> DecimalUnavailable(value, provenance)
        _, _, "=" <> _ ->
          DecimalDecodeFailure(
            json.string(value),
            "formula_text_not_evaluated",
            provenance,
          )
        False, False, _ ->
          case parse_decimal(value, convention) {
            Ok(decimal) -> DecimalKnown(decimal, value, provenance)
            Error(_) ->
              DecimalDecodeFailure(
                json.string(value),
                "not_an_exact_decimal",
                provenance,
              )
          }
      }
    Ok(value) ->
      DecimalDecodeFailure(
        raw.value_json(value),
        "exact_numeric_field_must_be_a_string",
        provenance,
      )
  }
}

fn validated_track(value: TextField) -> TextField {
  case value {
    TextKnown(track, raw, provenance)
      if track == "cn" || track == "hk" || track == "us"
    -> TextKnown(track, raw, provenance)
    TextKnown(_, raw, provenance) ->
      TextDecodeFailure(
        json.string(raw),
        "track_must_be_cn_hk_or_us",
        provenance,
      )
    other -> other
  }
}

fn validated_direction(value: TextField) -> TextField {
  case value {
    TextKnown(direction, raw, provenance)
      if direction == "Long" || direction == "Short"
    -> TextKnown(direction, raw, provenance)
    TextKnown(_, raw, provenance) ->
      TextDecodeFailure(
        json.string(raw),
        "direction_must_be_Long_or_Short",
        provenance,
      )
    other -> other
  }
}

fn validated_currency_field(value: TextField) -> TextField {
  case value {
    TextKnown(currency, raw, provenance) ->
      case valid_currency(currency) {
        True -> TextKnown(currency, raw, provenance)
        False ->
          TextDecodeFailure(json.string(raw), "invalid_currency", provenance)
      }
    other -> other
  }
}

fn unsupported_fact(
  security_type: TextField,
  direction: TextField,
) -> #(Bool, Option(String)) {
  case text_value(direction), text_value(security_type) {
    Some("Short"), _ -> #(True, Some("short_not_yet_supported"))
    _, Some("Option") | _, Some("Derivative") | _, Some("Warrant") -> #(
      True,
      Some("derivative_not_yet_supported"),
    )
    _, Some(value) ->
      case supported_security_type(value) {
        True -> #(False, None)
        False -> #(True, Some("unrecognized_instrument_type"))
      }
    _, None -> #(True, Some("security_type_unresolved"))
  }
}

fn supported_security_type(value: String) -> Bool {
  list.contains(
    [
      "CommonStock",
      "ETF",
      "ADR",
      "Bond",
      "Cash",
      "Liability",
      "Accrual",
      "PendingTransfer",
      "UnsettledTrade",
    ],
    value,
  )
}

fn calculated_market_value(
  quantity: DecimalField,
  mark: DecimalField,
  mark_time: TextField,
  currency: TextField,
) -> Result(Decimal, String) {
  case
    decimal_value(quantity),
    decimal_value(mark),
    text_value(mark_time),
    text_value(currency)
  {
    Some(quantity), Some(mark), Some(_), Some(_) ->
      Ok(decimal.multiply(quantity, mark))
    None, _, _, _ -> Error("missing_or_invalid_quantity")
    _, None, _, _ -> Error("missing_or_invalid_current_mark")
    _, _, None, _ -> Error("missing_or_invalid_mark_time")
    _, _, _, None -> Error("missing_or_invalid_position_currency")
  }
}

fn required_meta(
  fields: Dict(String, raw.Value),
  name: String,
) -> Result(String, ImportError) {
  case text_field(fields, name) {
    TextKnown(value, _, _) ->
      case valid_identifier_text(value, 1024) {
        True -> Ok(value)
        False -> Error(InvalidSnapshot("missing or invalid " <> name))
      }
    _ -> Error(InvalidSnapshot("missing or invalid " <> name))
  }
}

fn raw_fingerprint(fields: Dict(String, raw.Value)) -> String {
  fields
  |> dict.to_list
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> list.map(fn(entry) {
    int.to_string(string.length(entry.0))
    <> ":"
    <> entry.0
    <> ":"
    <> { entry.1 |> raw.value_json |> json.to_string }
  })
  |> string.join("|")
}

fn remove_names(
  fields: Dict(String, value),
  names: List(String),
) -> Dict(String, value) {
  list.fold(names, fields, fn(current, name) { dict.delete(current, name) })
}

fn position_fields() -> List(String) {
  [
    "position_id",
    "track",
    "listing_id",
    "mic",
    "source_symbol",
    "security_name",
    "security_type",
    "direction",
    "quantity",
    "quantity_unit",
    "settled_quantity",
    "available_quantity",
    "avg_cost",
    "cost_basis_total",
    "current_mark",
    "mark_time",
    "market_value",
    "position_currency",
    "accrued_income",
    "unrealized_pnl",
    "realized_pnl",
    "source_row_id",
  ]
}

fn find_snapshot(values: List(Snapshot), id: String) -> Option(Snapshot) {
  case values {
    [] -> None
    [value, ..] if value.snapshot_id == id -> Some(value)
    [_, ..rest] -> find_snapshot(rest, id)
  }
}

fn count_positions(snapshot: Snapshot) -> Counts {
  let positions = snapshot.positions
  let cash =
    list.filter(positions, fn(value) {
      text_value(value.security_type) == Some("Cash")
    })
  let liabilities =
    list.filter(positions, fn(value) {
      let kind = text_value(value.security_type)
      kind == Some("Liability") || kind == Some("Accrual")
    })
  Counts(
    snapshot.total_source_rows,
    list.length(positions),
    list.length(positions) - list.length(cash) - list.length(liabilities),
    list.length(cash),
    list.length(liabilities),
    positions |> list.filter(fn(value) { value.unsupported }) |> list.length,
    positions
      |> list.filter(fn(value) { !value.identity_resolved })
      |> list.length,
    snapshot.duplicate_rows_collapsed,
    positions
      |> list.filter(fn(value) { value.conflicting_position_id })
      |> list.length,
    positions
      |> list.filter(fn(value) { value.decode_failure_count > 0 })
      |> list.length,
    positions
      |> list.flat_map(fn(value) { value.formula_cells })
      |> list.length,
  )
}

fn counts_json(value: Counts) -> json.Json {
  json.object([
    #("totalSourceRows", json.int(value.total_source_rows)),
    #("retainedRows", json.int(value.retained_rows)),
    #("positions", json.int(value.positions)),
    #("cashRows", json.int(value.cash_rows)),
    #("liabilityRows", json.int(value.liability_rows)),
    #("unsupported", json.int(value.unsupported)),
    #("identityUnresolved", json.int(value.identity_unresolved)),
    #("duplicatesCollapsed", json.int(value.duplicates_collapsed)),
    #("conflicts", json.int(value.conflicts)),
    #("decodeFailureRows", json.int(value.decode_failure_rows)),
    #("formulaCells", json.int(value.formula_cells)),
  ])
}

fn currency_totals(positions: List(Position)) -> List(CurrencyTotal) {
  positions
  |> list.fold(dict.new(), add_position_total)
  |> dict.values
  |> list.sort(fn(left, right) { string.compare(left.currency, right.currency) })
}

fn add_position_total(
  totals: Dict(String, CurrencyTotal),
  position: Position,
) -> Dict(String, CurrencyTotal) {
  case text_value(position.position_currency) {
    None -> totals
    Some(currency) -> {
      let current =
        dict.get(totals, currency)
        |> result.unwrap(CurrencyTotal(
          currency,
          decimal.zero(),
          decimal.zero(),
          decimal.zero(),
          0,
          0,
        ))
      let kind = text_value(position.security_type)
      let next = case
        kind,
        decimal_value(position.quantity),
        position.calculated_market_value,
        position.unsupported
      {
        Some("Cash"), Some(amount), _, _ ->
          CurrencyTotal(
            ..current,
            cash: decimal.add(current.cash, amount),
            included_rows: current.included_rows + 1,
          )
        Some("Liability"), Some(amount), _, _
        | Some("Accrual"), Some(amount), _, _
        ->
          CurrencyTotal(
            ..current,
            liabilities: decimal.add(current.liabilities, absolute(amount)),
            included_rows: current.included_rows + 1,
          )
        _, _, _, True ->
          CurrencyTotal(..current, omitted_rows: current.omitted_rows + 1)
        _, _, Ok(amount), False ->
          CurrencyTotal(
            ..current,
            position_value: decimal.add(current.position_value, amount),
            included_rows: current.included_rows + 1,
          )
        _, _, Error(_), False ->
          CurrencyTotal(..current, omitted_rows: current.omitted_rows + 1)
      }
      dict.insert(totals, currency, next)
    }
  }
}

fn currency_total_json(value: CurrencyTotal) -> json.Json {
  let calculated = calculated_total(value)
  json.object([
    #("currency", json.string(value.currency)),
    #("positionMarketValue", decimal_json(value.position_value)),
    #("cash", decimal_json(value.cash)),
    #("liabilities", decimal_json(value.liabilities)),
    #("formula", json.string("position_market_value + cash - liabilities")),
    #("calculatedTotal", decimal_json(calculated)),
    #("includedRows", json.int(value.included_rows)),
    #("omittedRows", json.int(value.omitted_rows)),
    #("complete", json.bool(value.omitted_rows == 0)),
  ])
}

fn calculated_total(value: CurrencyTotal) -> Decimal {
  decimal.subtract(
    decimal.add(value.position_value, value.cash),
    value.liabilities,
  )
}

fn reconciliation_json(
  snapshot: Snapshot,
  totals: List(CurrencyTotal),
) -> json.Json {
  let base =
    list.find(totals, fn(value) { value.currency == snapshot.base_currency })
  let foreign =
    list.any(totals, fn(value) { value.currency != snapshot.base_currency })
  let calculation = case
    decimal_value(snapshot.source_declared_total),
    text_value(snapshot.source_total_currency),
    base,
    foreign
  {
    None, _, _, _ -> Error("source_declared_total_unavailable")
    _, None, _, _ -> Error("source_total_currency_unavailable")
    _, Some(currency), _, _ if currency != snapshot.base_currency ->
      Error("source_total_currency_differs_from_base_currency")
    _, _, _, True -> Error("foreign_currency_legs_not_aggregated")
    _, _, Error(_), _ -> Error("base_currency_total_unavailable")
    _, _, Ok(value), _ if value.omitted_rows > 0 ->
      Error("base_currency_total_is_partial")
    Some(source), Some(_), Ok(value), False -> {
      let calculated = calculated_total(value)
      let delta = decimal.subtract(source, calculated)
      Ok(#(source, calculated, delta))
    }
  }
  case calculation {
    Error(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #(
          "sourceDeclaredTotal",
          decimal_field_json(snapshot.source_declared_total),
        ),
        #(
          "sourceTotalCurrency",
          text_field_json(snapshot.source_total_currency),
        ),
        #("tolerance", decimal_json(snapshot.tolerance)),
        #("correctnessVerdict", json.null()),
      ])
    Ok(#(source, calculated, delta)) ->
      json.object([
        #("state", json.string("calculated")),
        #("sourceDeclaredTotal", decimal_json(source)),
        #("calculatedTotal", decimal_json(calculated)),
        #("delta", decimal_json(delta)),
        #("formula", json.string("source_total - calculated_total")),
        #("tolerance", decimal_json(snapshot.tolerance)),
        #(
          "withinTolerance",
          json.bool(decimal.compare(absolute(delta), snapshot.tolerance) != Gt),
        ),
        #("correctnessVerdict", json.null()),
      ])
  }
}

fn temporal_json(positions: List(Position)) -> json.Json {
  let known =
    positions
    |> list.filter_map(fn(value) {
      case text_value(value.mark_time) {
        Some(mark_time) -> Ok(mark_time)
        None -> Error(Nil)
      }
    })
    |> list.sort(string.compare)
  let unknown_count =
    positions
    |> list.filter(fn(value) { text_value(value.mark_time) == None })
    |> list.length
  json.object([
    #("earliestMark", case known {
      [first, ..] -> json.string(first)
      [] -> json.null()
    }),
    #("latestMark", case list.last(known) {
      Ok(value) -> json.string(value)
      Error(_) -> json.null()
    }),
    #("positionsWithUnknownMarkTime", json.int(unknown_count)),
    #(
      "stalenessAssessment",
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string("no_caller_freshness_cutoff")),
      ]),
    ),
    #(
      "meaning",
      json.string("source_mark_lexeme_range_not_freshness_or_coherence_verdict"),
    ),
  ])
}

fn truncation_json(value: raw.Truncation) -> json.Json {
  case value {
    raw.NotTruncated -> json.object([#("state", json.string("complete"))])
    raw.TruncatedByRows(maximum, total, next) ->
      json.object([
        #("state", json.string("truncated_by_row_budget")),
        #("maximumRows", json.int(maximum)),
        #("totalSourceRows", json.int(total)),
        #("nextSourceIndex", json.int(next)),
      ])
    raw.TruncatedByBytes(retained, total, next) ->
      json.object([
        #("state", json.string("truncated_by_byte_budget")),
        #("retainedBytes", json.int(retained)),
        #("totalFileBytes", json.int(total)),
        #("nextSourceIndex", json.int(next)),
        #(
          "meaning",
          json.string("complete_csv_records_only; final_prefix_record_omitted"),
        ),
      ])
  }
}

fn position_json(value: Position) -> json.Json {
  json.object([
    #("sourceIndex", json.int(value.source_index)),
    #("positionId", text_field_json(value.position_id)),
    #("track", text_field_json(value.track)),
    #("listingId", text_field_json(value.listing_id)),
    #("mic", text_field_json(value.mic)),
    #("sourceSymbol", text_field_json(value.source_symbol)),
    #("securityName", text_field_json(value.security_name)),
    #("securityType", text_field_json(value.security_type)),
    #("direction", text_field_json(value.direction)),
    #("quantity", decimal_field_json(value.quantity)),
    #("quantityUnit", text_field_json(value.quantity_unit)),
    #("settledQuantity", decimal_field_json(value.settled_quantity)),
    #("availableQuantity", decimal_field_json(value.available_quantity)),
    #("averageCost", decimal_field_json(value.avg_cost)),
    #("costBasisTotal", decimal_field_json(value.cost_basis_total)),
    #("currentMark", decimal_field_json(value.current_mark)),
    #("markTime", text_field_json(value.mark_time)),
    #("sourceReportedMarketValue", decimal_field_json(value.market_value)),
    #("positionCurrency", text_field_json(value.position_currency)),
    #("accruedIncome", decimal_field_json(value.accrued_income)),
    #("sourceReportedUnrealizedPnl", decimal_field_json(value.unrealized_pnl)),
    #("sourceReportedRealizedPnl", decimal_field_json(value.realized_pnl)),
    #("sourceRowId", text_field_json(value.source_row_id)),
    #("fieldProvenance", json.string("retained_per_field")),
    #("extraColumns", raw_object_json(value.extra_columns)),
    #("duplicateCount", json.int(value.duplicate_count)),
    #("conflictingPositionId", json.bool(value.conflicting_position_id)),
    #("identityResolved", json.bool(value.identity_resolved)),
    #("unsupportedInFirstSlice", json.bool(value.unsupported)),
    #("unsupportedReason", case value.unsupported_reason {
      Some(reason) -> json.string(reason)
      None -> json.null()
    }),
    #("formulaCells", json.array(value.formula_cells, json.string)),
    #("decodeFailureCount", json.int(value.decode_failure_count)),
    #("calculatedMarketValue", case value.calculated_market_value {
      Ok(amount) ->
        json.object([
          #("state", json.string("calculated")),
          #("value", decimal_json(amount)),
          #("formula", json.string("quantity * current_mark")),
          #("currency", case text_value(value.position_currency) {
            Some(currency) -> json.string(currency)
            None -> json.null()
          }),
        ])
      Error(reason) ->
        json.object([
          #("state", json.string("unperformed")),
          #("reason", json.string(reason)),
        ])
    }),
    #("marketValueReconciliation", market_value_reconciliation(value)),
    #("unrealizedPnlReconciliation", unrealized_pnl_reconciliation(value)),
    #("riskCalculation", case value.unsupported_reason {
      Some(reason) ->
        json.object([
          #("state", json.string("unsupported_in_first_slice")),
          #("reason", json.string(reason)),
        ])
      None -> json.object([#("state", json.string("not_requested"))])
    }),
  ])
}

fn market_value_reconciliation(value: Position) -> json.Json {
  case decimal_value(value.market_value), value.calculated_market_value {
    Some(source), Ok(calculated) -> {
      let delta = decimal.subtract(source, calculated)
      json.object([
        #("state", json.string("calculated")),
        #("sourceReported", decimal_json(source)),
        #("independentlyCalculated", decimal_json(calculated)),
        #("delta", decimal_json(delta)),
        #("formula", json.string("source_reported - quantity * current_mark")),
        #("correctnessVerdict", json.null()),
      ])
    }
    None, _ -> unperformed_json("source_reported_market_value_unavailable")
    _, Error(reason) -> unperformed_json(reason)
  }
}

fn unrealized_pnl_reconciliation(value: Position) -> json.Json {
  case
    decimal_value(value.unrealized_pnl),
    decimal_value(value.market_value),
    decimal_value(value.cost_basis_total)
  {
    Some(reported), Some(market), Some(cost) -> {
      let calculated = decimal.subtract(market, cost)
      let delta = decimal.subtract(reported, calculated)
      json.object([
        #("state", json.string("calculated")),
        #("sourceReported", decimal_json(reported)),
        #("independentlyCalculated", decimal_json(calculated)),
        #("delta", decimal_json(delta)),
        #(
          "formula",
          json.string(
            "source_unrealized_pnl - (source_market_value - cost_basis_total)",
          ),
        ),
        #("correctnessVerdict", json.null()),
      ])
    }
    None, _, _ -> unperformed_json("source_reported_unrealized_pnl_unavailable")
    _, None, _ -> unperformed_json("source_reported_market_value_unavailable")
    _, _, None -> unperformed_json("cost_basis_total_unavailable")
  }
}

fn unperformed_json(reason: String) -> json.Json {
  json.object([
    #("state", json.string("unperformed")),
    #("reason", json.string(reason)),
  ])
}

fn text_field_json(value: TextField) -> json.Json {
  case value {
    TextKnown(value, lexeme, provenance) ->
      json.object([
        #("state", json.string("known")),
        #("value", json.string(value)),
        #("sourceLexeme", json.string(lexeme)),
        #("provenance", json.string(provenance)),
      ])
    TextExplicitNull(provenance) ->
      state_with_provenance("explicit_null", provenance)
    TextBlankLexeme(provenance) ->
      state_with_provenance("blank_lexeme", provenance)
    TextAbsentColumn -> json.object([#("state", json.string("absent_column"))])
    TextUnavailable(lexeme, provenance) ->
      json.object([
        #("state", json.string("unavailable")),
        #("sourceLexeme", json.string(lexeme)),
        #("provenance", json.string(provenance)),
      ])
    TextDecodeFailure(source, reason, provenance) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("source", source),
        #("reason", json.string(reason)),
        #("provenance", json.string(provenance)),
      ])
  }
}

fn decimal_field_json(value: DecimalField) -> json.Json {
  case value {
    DecimalKnown(value, lexeme, provenance) ->
      json.object([
        #("state", json.string("known")),
        #("value", decimal_json(value)),
        #("sourceLexeme", json.string(lexeme)),
        #("provenance", json.string(provenance)),
      ])
    DecimalExplicitNull(provenance) ->
      state_with_provenance("explicit_null", provenance)
    DecimalBlankLexeme(provenance) ->
      state_with_provenance("blank_lexeme", provenance)
    DecimalAbsentColumn ->
      json.object([#("state", json.string("absent_column"))])
    DecimalUnavailable(lexeme, provenance) ->
      json.object([
        #("state", json.string("unavailable")),
        #("sourceLexeme", json.string(lexeme)),
        #("provenance", json.string(provenance)),
      ])
    DecimalDecodeFailure(source, reason, provenance) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("source", source),
        #("reason", json.string(reason)),
        #("provenance", json.string(provenance)),
      ])
  }
}

fn state_with_provenance(state: String, provenance: String) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("provenance", json.string(provenance)),
  ])
}

fn private_text_json(
  value: TextField,
  visibility: AccountVisibility,
) -> json.Json {
  case visibility, value {
    Redacted, TextKnown(_, _, _) ->
      json.object([
        #("state", json.string("redacted")),
        #("reason", json.string("account_visibility_not_review_visible")),
      ])
    _, _ -> text_field_json(value)
  }
}

fn raw_object_json(values: Dict(String, raw.Value)) -> json.Json {
  values
  |> dict.to_list
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> list.map(fn(entry) { #(entry.0, raw.value_json(entry.1)) })
  |> json.object
}

fn redact_sensitive(
  values: Dict(String, raw.Value),
) -> Dict(String, raw.Value) {
  values
  |> dict.to_list
  |> list.map(fn(entry) {
    case sensitive_key(entry.0) {
      True -> #(entry.0, raw.Redacted)
      False -> entry
    }
  })
  |> dict.from_list
}

fn sensitive_key(value: String) -> Bool {
  let normalized = string.lowercase(value)
  list.contains(
    [
      "tax_id",
      "taxid",
      "ssn",
      "personal_name",
      "customer_name",
      "address",
      "email",
      "phone",
      "account_number",
    ],
    normalized,
  )
}

fn decimal_json(value: Decimal) -> json.Json {
  value |> decimal.to_string |> json.string
}

fn matches_filter(value: Position, filter: PositionFilter) -> Bool {
  optional_equals(filter.position_id, text_value(value.position_id))
  && optional_equals(filter.source_row_id, text_value(value.source_row_id))
  && optional_equals(filter.track, text_value(value.track))
  && optional_equals(filter.currency, text_value(value.position_currency))
  && optional_equals(filter.security_type, text_value(value.security_type))
  && optional_bool(filter.identity_resolved, value.identity_resolved)
  && optional_bool(filter.unsupported, value.unsupported)
  && optional_bool(filter.conflicting, value.conflicting_position_id)
  && optional_bool(filter.has_decode_failure, value.decode_failure_count > 0)
}

fn optional_equals(expected: Option(String), actual: Option(String)) -> Bool {
  case expected {
    None -> True
    Some(value) -> actual == Some(value)
  }
}

fn optional_bool(expected: Option(Bool), actual: Bool) -> Bool {
  case expected {
    None -> True
    Some(value) -> value == actual
  }
}

fn text_value(value: TextField) -> Option(String) {
  case value {
    TextKnown(value, _, _) -> Some(value)
    _ -> None
  }
}

fn text_known(value: TextField) -> Bool {
  text_value(value) != None
}

fn decimal_value(value: DecimalField) -> Option(Decimal) {
  case value {
    DecimalKnown(value, _, _) -> Some(value)
    _ -> None
  }
}

fn text_failure(value: TextField) -> Bool {
  case value {
    TextDecodeFailure(_, _, _) -> True
    _ -> False
  }
}

fn decimal_failure(value: DecimalField) -> Bool {
  case value {
    DecimalDecodeFailure(_, _, _) -> True
    _ -> False
  }
}

fn absolute(value: Decimal) -> Decimal {
  case decimal.compare(value, decimal.zero()) {
    Lt -> decimal.negate(value)
    Eq | Gt -> value
  }
}

fn valid_path(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 4096
  && !string.contains(value, "\u{0000}")
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn validate_budgets(
  bytes: Int,
  rows: Int,
  columns: Int,
  field_bytes: Int,
  json_depth: Int,
  json_elements: Int,
) -> Result(Nil, ImportError) {
  case
    bytes >= 1 && bytes <= maximum_file_bytes,
    rows >= 1 && rows <= maximum_rows,
    columns >= 1 && columns <= maximum_columns,
    field_bytes >= 1 && field_bytes <= maximum_field_bytes,
    json_depth >= 1 && json_depth <= maximum_json_depth,
    json_elements >= 1 && json_elements <= maximum_json_elements
  {
    False, _, _, _, _, _ -> Error(InvalidBudget("maximumBytes"))
    _, False, _, _, _, _ -> Error(InvalidBudget("maximumRows"))
    _, _, False, _, _, _ -> Error(InvalidBudget("maximumColumns"))
    _, _, _, False, _, _ -> Error(InvalidBudget("maximumFieldBytes"))
    _, _, _, _, False, _ -> Error(InvalidBudget("maximumJsonDepth"))
    _, _, _, _, _, False -> Error(InvalidBudget("maximumJsonElements"))
    True, True, True, True, True, True -> Ok(Nil)
  }
}

fn parse_decimal(
  value: String,
  convention: raw.DecimalConvention,
) -> Result(Decimal, Nil) {
  let #(sign, unsigned) = split_sign(value)
  let normalized = case convention {
    raw.PlainDot ->
      case valid_plain(unsigned, ".") {
        True -> Ok(value)
        False -> Error(Nil)
      }
    raw.CommaGroupedDot ->
      case valid_grouped_decimal(unsigned, ",", ".") {
        True -> Ok(sign <> string.replace(unsigned, ",", ""))
        False -> Error(Nil)
      }
    raw.SpaceGroupedComma ->
      case valid_grouped_decimal(unsigned, " ", ",") {
        True ->
          Ok(
            sign
            <> {
              unsigned |> string.replace(" ", "") |> string.replace(",", ".")
            },
          )
        False -> Error(Nil)
      }
  }
  use normalized <- result.try(normalized)
  decimal.parse(normalized) |> result.map_error(fn(_) { Nil })
}

fn split_sign(value: String) -> #(String, String) {
  case value {
    "-" <> rest -> #("-", rest)
    "+" <> rest -> #("+", rest)
    _ -> #("", value)
  }
}

fn valid_plain(unsigned: String, decimal_separator: String) -> Bool {
  case string.split(unsigned, on: decimal_separator) {
    [whole] -> all_digits(whole)
    [whole, fraction] -> all_digits(whole) && all_digits(fraction)
    _ -> False
  }
}

fn valid_grouped_decimal(
  unsigned: String,
  group_separator: String,
  decimal_separator: String,
) -> Bool {
  case string.split(unsigned, on: decimal_separator) {
    [whole] -> valid_grouped_whole(whole, group_separator)
    [whole, fraction] ->
      valid_grouped_whole(whole, group_separator) && all_digits(fraction)
    _ -> False
  }
}

fn valid_grouped_whole(value: String, separator: String) -> Bool {
  case string.split(value, on: separator) {
    [whole] -> all_digits(whole)
    [first, ..rest] ->
      string.length(first) >= 1
      && string.length(first) <= 3
      && all_digits(first)
      && rest != []
      && list.all(rest, fn(group) {
        string.length(group) == 3 && all_digits(group)
      })
    [] -> False
  }
}

fn all_digits(value: String) -> Bool {
  value != ""
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_currency(value: String) -> Bool {
  string.length(value) == 3
  && value == string.uppercase(value)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ", character)
  })
}

fn valid_source_kind(value: String) -> Bool {
  list.contains(
    ["BrokerExport", "CallerSupplied", "ManualEntry", "ImportedFile"],
    value,
  )
}

fn valid_identifier_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn unavailable_lexeme(value: String) -> Bool {
  let normalized = value |> string.trim |> string.uppercase
  normalized == "N/A"
  || normalized == "NA"
  || normalized == "UNAVAILABLE"
  || normalized == "UNKNOWN"
}

fn raw_error_message(error: raw.Error) -> String {
  case error {
    raw.InvalidCsv ->
      "portfolio CSV was malformed or byte-truncated before a complete record"
    raw.InvalidJson(_) -> "portfolio JSON was malformed"
    raw.InvalidJsonShape ->
      "portfolio JSON did not match the canonical snapshot/positions shape"
    raw.JsonByteTruncation ->
      "portfolio JSON exceeded maximumBytes and cannot be partially decoded safely"
    raw.MissingHeader -> "portfolio CSV requires a header row"
    raw.DuplicateHeader(_) -> "portfolio CSV contains a duplicate header"
    raw.EmptyHeader -> "portfolio CSV contains an empty header"
    raw.TooManyColumns(maximum, received) ->
      "portfolio input had "
      <> int.to_string(received)
      <> " columns; maximum is "
      <> int.to_string(maximum)
    raw.FieldTooLarge(maximum, received) ->
      "portfolio input field had "
      <> int.to_string(received)
      <> " bytes; maximum is "
      <> int.to_string(maximum)
    raw.ControlCharacter ->
      "portfolio CSV contained a forbidden control character"
    raw.JsonTooDeep(maximum, received) ->
      "portfolio JSON nesting depth "
      <> int.to_string(received)
      <> " exceeded "
      <> int.to_string(maximum)
    raw.TooManyJsonElements(maximum, received) ->
      "portfolio JSON element count "
      <> int.to_string(received)
      <> " exceeded "
      <> int.to_string(maximum)
    raw.MissingSnapshotField(_) -> "portfolio snapshot metadata was incomplete"
    raw.ConflictingSnapshotField(_) ->
      "portfolio CSV repeated conflicting snapshot metadata"
  }
}
