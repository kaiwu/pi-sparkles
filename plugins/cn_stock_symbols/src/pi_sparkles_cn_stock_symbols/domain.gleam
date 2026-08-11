import finance_core/time
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_tushare/query
import finance_tushare/request
import finance_tushare/response
import finance_tushare/stock_basic.{type Security}
import finance_tushare/table
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type SearchPlan {
  SearchPlan(
    query: query.StockBasicQuery,
    maximum_candidates: Int,
    query_text: String,
  )
}

pub opaque type AliasPlan {
  AliasPlan(query: query.SecurityQuery, identity_evidence_id: String)
}

pub opaque type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack
  InvalidQueryKind
  InvalidVenue
  InvalidQuery
  InvalidListStatus
  InvalidCandidateLimit
  ExactCodeRequiresVenue
  InvalidIdentityEvidenceId
  InvalidProviderQuery
  InvalidAliasTable(table.DecodeError)
  InvalidAliasRow(index: Int)
  IdentityMismatch
}

pub fn search_plan(
  track: String,
  query_kind: String,
  query_text: String,
  venue: Option(String),
  list_status: String,
  maximum_candidates: Int,
) -> Result(SearchPlan, Error) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use exchange <- result.try(optional_exchange(venue))
  use status <- result.try(status_from_name(list_status))
  use _ <- result.try(
    case maximum_candidates >= 1 && maximum_candidates <= 100 {
      True -> Ok(Nil)
      False -> Error(InvalidCandidateLimit)
    },
  )
  let provider_limit = case query_kind {
    "code" -> 10
    _ -> 6000
  }
  let provider_query = case query_kind, exchange {
    "code", None -> Error(ExactCodeRequiresVenue)
    "code", Some(exchange) ->
      query.stock_basic(
        finance_track.Cn,
        Some(exchange),
        Some(query_text),
        status,
        provider_limit,
      )
      |> result.map_error(fn(_) { InvalidQuery })
    "name", exchange ->
      query.stock_basic_name(
        finance_track.Cn,
        exchange,
        query_text,
        status,
        provider_limit,
      )
      |> result.map_error(fn(_) { InvalidQuery })
    _, _ -> Error(InvalidQueryKind)
  }
  provider_query
  |> result.map(fn(value) { SearchPlan(value, maximum_candidates, query_text) })
}

pub fn alias_plan(
  track: String,
  venue: String,
  code: String,
  identity_evidence_id: String,
  maximum_rows: Int,
) -> Result(AliasPlan, Error) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use exchange <- result.try(exchange_from_name(venue))
  use _ <- result.try(case valid_evidence_id(identity_evidence_id) {
    True -> Ok(Nil)
    False -> Error(InvalidIdentityEvidenceId)
  })
  query.security(finance_track.Cn, exchange, code, maximum_rows)
  |> result.map(fn(value) { AliasPlan(value, identity_evidence_id) })
  |> result.map_error(fn(_) { InvalidProviderQuery })
}

pub fn search_query(value: SearchPlan) -> query.StockBasicQuery {
  value.query
}

pub fn alias_query(value: AliasPlan) -> query.SecurityQuery {
  value.query
}

pub fn assemble_search(
  plan: SearchPlan,
  values: List(Security),
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Output {
  let candidates = list.take(values, plan.maximum_candidates)
  let resolution = case values {
    [] -> "no_match"
    [_] -> "unique_candidate"
    [_, _, ..] -> "ambiguous_candidates"
  }
  Output(
    "CN symbol search "
      <> plan.query_text
      <> " | "
      <> int.to_string(list.length(values))
      <> " provider candidates | "
      <> resolution,
    json.object([
      #("schema", json.string("pi-sparkles/cn-stock-symbol-search-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("cn_stock_symbol_search")),
      #("track", json.string("cn")),
      #("query", json.string(plan.query_text)),
      #("resolution", json.string(resolution)),
      #("providerCandidateCount", json.int(list.length(values))),
      #("returnedCandidateCount", json.int(list.length(candidates))),
      #(
        "truncatedByCandidateBudget",
        json.bool(list.length(values) > plan.maximum_candidates),
      ),
      #("candidates", json.array(candidates, candidate_json)),
      #(
        "source",
        source_json("stock_basic", retrieved_at, response_bytes, content_sha256),
      ),
      #(
        "limitations",
        json.array(
          [
            "tushare_identity_fields_are_vendor_reported_not_exchange_authenticated",
            "code_or_name_match_does_not_by_itself_prove_issuer_relationships",
            "board_projection_uses_visible_tushare_market_and_exchange_labels",
            "ambiguity_is_preserved_and_never_silently_selected",
            "historical_aliases_require_the_separate_exact_listing_operation",
          ],
          json.string,
        ),
      ),
    ]),
  )
}

pub fn decode_aliases(
  plan: AliasPlan,
  body: String,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use source <- result.try(
    table.decode(
      body,
      request.namechange_fields,
      query.security_limit(plan.query),
    )
    |> result.map_error(InvalidAliasTable),
  )
  let expected =
    query.ts_code(
      query.security_exchange(plan.query),
      query.security_code(plan.query),
    )
  use aliases <- result.try(
    decode_alias_rows(table.rows(source), expected, 0, []),
  )
  Ok(Output(
    "CN "
      <> expected
      <> " | historical names | "
      <> int.to_string(list.length(aliases))
      <> " source rows",
    json.object([
      #("schema", json.string("pi-sparkles/cn-stock-alias-history-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("cn_stock_alias_history")),
      #("track", json.string("cn")),
      #("tsCode", json.string(expected)),
      #("identityEvidenceId", json.string(plan.identity_evidence_id)),
      #(
        "identityEvidenceAuthentication",
        json.string("not_authenticated_by_this_tool"),
      ),
      #("aliases", json.array(aliases, fn(value) { value })),
      #(
        "source",
        source_json("namechange", retrieved_at, response_bytes, content_sha256),
      ),
      #(
        "limitations",
        json.array(
          [
            "provider_alias_rows_preserved_without_silent_historical_to_current_substitution",
            "missing_effective_dates_remain_unknown",
            "cross_listing_and_issuer_relationships_not_inferred",
          ],
          json.string,
        ),
      ),
    ]),
  ))
}

pub fn summary(value: Output) -> String {
  value.summary
}

pub fn details(value: Output) -> json.Json {
  value.details
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack -> "track must be cn"
    InvalidQueryKind -> "queryKind must be code or name"
    InvalidVenue -> "venue must be sse, szse, or bse"
    InvalidQuery -> "query is invalid for the selected search kind"
    InvalidListStatus -> "listStatus must be listed, delisted, or paused"
    InvalidCandidateLimit -> "maximumCandidates must be between 1 and 100"
    ExactCodeRequiresVenue -> "exact code search requires an explicit venue"
    InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    InvalidProviderQuery -> "provider query is invalid"
    InvalidAliasTable(error) ->
      "Tushare name history response is invalid: " <> string.inspect(error)
    InvalidAliasRow(index) ->
      "Tushare name history row is invalid at index " <> int.to_string(index)
    IdentityMismatch ->
      "Tushare name history row identity does not match the exact listing"
  }
}

fn candidate_json(value: Security) -> json.Json {
  json.object([
    #("tsCode", json.string(stock_basic.ts_code(value))),
    #("code", json.string(stock_basic.symbol(value))),
    #("shortName", json.string(stock_basic.name(value))),
    #("legalName", option_json(stock_basic.full_name(value))),
    #("pinyin", option_json(stock_basic.pinyin(value))),
    #("providerMarket", json.string(stock_basic.market(value))),
    #("providerExchange", json.string(stock_basic.exchange(value))),
    #("venueMic", json.string(mic_from_exchange(stock_basic.exchange(value)))),
    #(
      "board",
      board_json(stock_basic.exchange(value), stock_basic.market(value)),
    ),
    #("currency", option_json(stock_basic.currency(value))),
    #("listingStatus", json.string(stock_basic.list_status(value))),
    #("listDate", json.string(stock_basic.list_date(value))),
    #("delistDate", option_json(stock_basic.delist_date(value))),
    #(
      "identityStatus",
      json.string("vendor_reported_not_exchange_authenticated"),
    ),
  ])
}

fn decode_alias_rows(rows, expected, index, decoded) {
  case rows {
    [] -> Ok(list.reverse(decoded))
    [row, ..rest] ->
      case row {
        [ts, name, start, end, announcement, reason] -> {
          use ts <- result.try(
            response.text(ts)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          use _ <- result.try(case ts == expected {
            True -> Ok(Nil)
            False -> Error(IdentityMismatch)
          })
          use name <- result.try(
            response.text(name)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          use start <- result.try(
            response.optional_text(start)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          use end <- result.try(
            response.optional_text(end)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          use announcement <- result.try(
            response.optional_text(announcement)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          use reason <- result.try(
            response.optional_text(reason)
            |> result.map_error(fn(_) { InvalidAliasRow(index) }),
          )
          let alias =
            json.object([
              #("nameOriginalZh", json.string(name)),
              #("effectiveStart", option_json(start)),
              #("effectiveEnd", option_json(end)),
              #("announcementDate", option_json(announcement)),
              #("changeReasonOriginalZh", option_json(reason)),
            ])
          decode_alias_rows(rest, expected, index + 1, [alias, ..decoded])
        }
        _ -> Error(InvalidAliasRow(index))
      }
  }
}

fn source_json(
  api: String,
  retrieved_at: time.Instant,
  bytes: Int,
  digest: Sha256,
) -> json.Json {
  json.object([
    #("provider", json.string("Tushare Pro")),
    #("api", json.string(api)),
    #("kind", json.string("structured_vendor")),
    #("exchangeEvidence", json.bool(False)),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(retrieved_at)),
    ),
    #("responseByteLength", json.int(bytes)),
    #("contentSha256", json.string(identity.sha256_value(digest))),
    #(
      "integrity",
      json.string("sha256_content_bound_not_provider_authenticated"),
    ),
    #("entitlement", json.string("caller_provider_account_permission_required")),
  ])
}

fn exchange_from_name(value: String) -> Result(query.Exchange, Error) {
  case value {
    "sse" -> Ok(query.Sse)
    "szse" -> Ok(query.Szse)
    "bse" -> Ok(query.Bse)
    _ -> Error(InvalidVenue)
  }
}

fn optional_exchange(
  value: Option(String),
) -> Result(Option(query.Exchange), Error) {
  case value {
    None -> Ok(None)
    Some(value) -> exchange_from_name(value) |> result.map(Some)
  }
}

fn status_from_name(value: String) -> Result(query.ListStatus, Error) {
  case value {
    "listed" -> Ok(query.Listed)
    "delisted" -> Ok(query.Delisted)
    "paused" -> Ok(query.Paused)
    _ -> Error(InvalidListStatus)
  }
}

fn mic_from_exchange(value: String) -> String {
  case value {
    "SSE" -> "XSHG"
    "SZSE" -> "XSHE"
    "BSE" -> "XBSE"
    _ -> "unknown"
  }
}

fn board_json(exchange: String, market: String) -> json.Json {
  let board = case exchange, market {
    "SSE", "主板" | "SZSE", "主板" -> Some("main")
    "SSE", "科创板" -> Some("star")
    "SZSE", "创业板" -> Some("chinext")
    "BSE", _ -> Some("beijing")
    _, _ -> None
  }
  option_json(board)
}

fn valid_evidence_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 256
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}
