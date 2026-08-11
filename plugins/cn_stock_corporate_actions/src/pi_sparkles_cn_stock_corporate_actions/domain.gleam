import finance_core/decimal
import finance_core/time
import finance_provenance/identity.{type Sha256}
import finance_track
import finance_tushare/query
import finance_tushare/request
import finance_tushare/response
import finance_tushare/table
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Plan {
  Plan(query: query.SecurityQuery, identity_evidence_id: String)
}

pub opaque type Action {
  Action(
    ts_code: String,
    period_end: String,
    announcement_date: String,
    process: String,
    stock_distribution_per_share: Option(String),
    bonus_share_rate_per_share: Option(String),
    capitalization_rate_per_share: Option(String),
    cash_dividend_after_tax_per_share: Option(String),
    cash_dividend_before_tax_per_share: Option(String),
    record_date: Option(String),
    ex_date: Option(String),
    payment_date: Option(String),
    stock_listing_date: Option(String),
    implementation_announcement_date: Option(String),
    base_date: Option(String),
    base_shares_ten_thousand: Option(String),
  )
}

pub opaque type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack
  InvalidVenue
  InvalidCode
  UnsupportedShareClass
  InvalidIdentityEvidenceId
  InvalidLimit
  InvalidProviderQuery
  InvalidTable(table.DecodeError)
  InvalidRow(index: Int)
  IdentityMismatch(expected: String, received: String)
}

pub fn plan(
  track: String,
  venue: String,
  code: String,
  share_class: String,
  identity_evidence_id: String,
  maximum_rows: Int,
) -> Result(Plan, Error) {
  use _ <- result.try(case track {
    "cn" -> Ok(Nil)
    _ -> Error(WrongTrack)
  })
  use exchange <- result.try(exchange_from_name(venue))
  use _ <- result.try(case share_class {
    "a_share" -> Ok(Nil)
    _ -> Error(UnsupportedShareClass)
  })
  use _ <- result.try(case valid_evidence_id(identity_evidence_id) {
    True -> Ok(Nil)
    False -> Error(InvalidIdentityEvidenceId)
  })
  use _ <- result.try(case maximum_rows >= 1 && maximum_rows <= 1000 {
    True -> Ok(Nil)
    False -> Error(InvalidLimit)
  })
  query.security(finance_track.Cn, exchange, code, maximum_rows)
  |> result.map(fn(value) { Plan(value, identity_evidence_id) })
  |> result.map_error(fn(error) {
    case error {
      query.InvalidCode -> InvalidCode
      _ -> InvalidProviderQuery
    }
  })
}

pub fn provider_query(value: Plan) -> query.SecurityQuery {
  value.query
}

pub fn decode_and_assemble(
  plan: Plan,
  body: String,
  retrieved_at: time.Instant,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use source <- result.try(
    table.decode(
      body,
      request.dividend_fields,
      query.security_limit(plan.query),
    )
    |> result.map_error(InvalidTable),
  )
  use actions <- result.try(
    decode_rows(
      table.rows(source),
      query.ts_code(
        query.security_exchange(plan.query),
        query.security_code(plan.query),
      ),
      0,
      [],
    ),
  )
  let ts_code =
    query.ts_code(
      query.security_exchange(plan.query),
      query.security_code(plan.query),
    )
  Ok(Output(
    "CN "
      <> ts_code
      <> " | Tushare structured dividend distributions | "
      <> int.to_string(list.length(actions))
      <> " source rows",
    json.object([
      #("schema", json.string("pi-sparkles/cn-stock-corporate-actions-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("cn_stock_corporate_actions")),
      #("track", json.string("cn")),
      #(
        "listing",
        json.object([
          #("tsCode", json.string(ts_code)),
          #("code", json.string(query.security_code(plan.query))),
          #(
            "venue",
            json.string(
              query.exchange_name(query.security_exchange(plan.query)),
            ),
          ),
          #("shareClass", json.string("a_share")),
          #("identityEvidenceId", json.string(plan.identity_evidence_id)),
          #(
            "identityEvidenceAuthentication",
            json.string("not_authenticated_by_this_tool"),
          ),
        ]),
      ),
      #(
        "coverage",
        json.object([
          #(
            "supported",
            json.array(
              [
                "cash_dividend", "stock_distribution", "bonus_share",
                "capitalization_issue",
              ],
              json.string,
            ),
          ),
          #(
            "unsupportedFailClosed",
            json.array(
              [
                "rights_issue", "split", "consolidation", "merger",
                "symbol_change",
              ],
              json.string,
            ),
          ),
        ]),
      ),
      #("actions", json.array(actions, action_json)),
      #(
        "source",
        json.object([
          #("provider", json.string("Tushare Pro")),
          #("api", json.string("dividend")),
          #(
            "reference",
            json.string(query.security_source_reference(
              plan.query,
              request.dividend_api,
            )),
          ),
          #("kind", json.string("structured_vendor")),
          #("exchangeEvidence", json.bool(False)),
          #(
            "retrievedAtUnixMilliseconds",
            json.int(time.unix_milliseconds(retrieved_at)),
          ),
          #(
            "entitlement",
            json.string("caller_provider_account_permission_required"),
          ),
          #("redistribution", json.string("provider_controlled_unknown")),
        ]),
      ),
      #(
        "acquisitionReceipt",
        json.object([
          #("contentSha256", json.string(identity.sha256_value(content_sha256))),
          #("responseByteLength", json.int(response_bytes)),
          #(
            "integrity",
            json.string("sha256_content_bound_not_provider_authenticated"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "provider_rows_preserved_without_adjustment_factor_derivation",
            "process_rows_and_revisions_are_not_silently_collapsed",
            "dates_remain_separate_and_missing_dates_remain_unknown",
            "currency_not_defaulted_for_cash_fields",
            "unsupported_action_classes_fail_closed",
            "no_recommendation_or_trade_action",
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
    InvalidVenue -> "venue must be sse, szse, or bse"
    InvalidCode -> "code must be exactly six digits"
    UnsupportedShareClass -> "only a_share is supported"
    InvalidIdentityEvidenceId -> "identityEvidenceId is invalid"
    InvalidLimit -> "maximumRows must be between 1 and 1000"
    InvalidProviderQuery -> "provider query is invalid"
    InvalidTable(error) ->
      "Tushare dividend response is invalid: " <> string.inspect(error)
    InvalidRow(index) ->
      "Tushare dividend row is invalid at index " <> int.to_string(index)
    IdentityMismatch(_, _) ->
      "Tushare dividend row identity does not match the exact listing"
  }
}

fn decode_rows(rows, expected, index, decoded) {
  case rows {
    [] -> Ok(list.reverse(decoded))
    [row, ..rest] -> {
      use action <- result.try(
        decode_row(row) |> result.map_error(fn(_) { InvalidRow(index) }),
      )
      use _ <- result.try(case action.ts_code == expected {
        True -> Ok(Nil)
        False -> Error(IdentityMismatch(expected, action.ts_code))
      })
      decode_rows(rest, expected, index + 1, [action, ..decoded])
    }
  }
}

fn decode_row(row) -> Result(Action, Nil) {
  case row {
    [
      ts_code,
      period,
      announcement,
      process,
      stock,
      bonus,
      capitalization,
      cash_after,
      cash_before,
      record,
      ex,
      payment,
      listing,
      implementation,
      base_date,
      base_shares,
    ] -> {
      use ts_code <- result.try(response.text(ts_code))
      use period <- result.try(required_date(period))
      use announcement <- result.try(required_date(announcement))
      use process <- result.try(response.text(process))
      use stock <- result.try(optional_decimal(stock))
      use bonus <- result.try(optional_decimal(bonus))
      use capitalization <- result.try(optional_decimal(capitalization))
      use cash_after <- result.try(optional_decimal(cash_after))
      use cash_before <- result.try(optional_decimal(cash_before))
      use record <- result.try(optional_date(record))
      use ex <- result.try(optional_date(ex))
      use payment <- result.try(optional_date(payment))
      use listing <- result.try(optional_date(listing))
      use implementation <- result.try(optional_date(implementation))
      use base_date <- result.try(optional_date(base_date))
      use base_shares <- result.try(optional_decimal(base_shares))
      Ok(Action(
        ts_code,
        period,
        announcement,
        process,
        stock,
        bonus,
        capitalization,
        cash_after,
        cash_before,
        record,
        ex,
        payment,
        listing,
        implementation,
        base_date,
        base_shares,
      ))
    }
    _ -> Error(Nil)
  }
}

fn action_json(value: Action) -> json.Json {
  json.object([
    #("tsCode", json.string(value.ts_code)),
    #("periodEnd", json.string(value.period_end)),
    #("announcementDate", json.string(value.announcement_date)),
    #("process", json.string(value.process)),
    #(
      "stockDistributionPerShare",
      option_json(value.stock_distribution_per_share),
    ),
    #("bonusShareRatePerShare", option_json(value.bonus_share_rate_per_share)),
    #(
      "capitalizationRatePerShare",
      option_json(value.capitalization_rate_per_share),
    ),
    #(
      "cashDividendAfterTaxPerShare",
      option_json(value.cash_dividend_after_tax_per_share),
    ),
    #(
      "cashDividendBeforeTaxPerShare",
      option_json(value.cash_dividend_before_tax_per_share),
    ),
    #("cashDividendCurrency", json.null()),
    #("recordDate", option_json(value.record_date)),
    #("exDate", option_json(value.ex_date)),
    #("paymentDate", option_json(value.payment_date)),
    #("stockListingDate", option_json(value.stock_listing_date)),
    #(
      "implementationAnnouncementDate",
      option_json(value.implementation_announcement_date),
    ),
    #("baseDate", option_json(value.base_date)),
    #("baseSharesTenThousand", option_json(value.base_shares_ten_thousand)),
    #("correctionLineage", json.string("rows_preserved_no_collapse")),
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

fn optional_decimal(value) -> Result(Option(String), Nil) {
  use value <- result.try(response.optional_scalar(value))
  case value {
    None -> Ok(None)
    Some(raw) ->
      case decimal.parse(raw) {
        Ok(_) -> Ok(Some(raw))
        Error(_) -> Error(Nil)
      }
  }
}

fn required_date(value) -> Result(String, Nil) {
  use value <- result.try(response.text(value))
  case valid_compact_date(value) {
    True -> Ok(value)
    False -> Error(Nil)
  }
}

fn optional_date(value) -> Result(Option(String), Nil) {
  use value <- result.try(response.optional_text(value))
  case value {
    None -> Ok(None)
    Some(value) ->
      case valid_compact_date(value) {
        True -> Ok(Some(value))
        False -> Error(Nil)
      }
  }
}

fn valid_compact_date(value: String) -> Bool {
  string.length(value) == 8
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
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
