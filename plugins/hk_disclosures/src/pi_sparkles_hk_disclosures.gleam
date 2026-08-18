import finance_core/identifier
import finance_core/time
import finance_hkex
import finance_hkex/current_security_reference
import finance_hkex/discovery_runtime
import finance_hkex/full_list
import finance_hkex/listing_runtime
import finance_hkex/recent_listing
import finance_hkex/recent_listing_reference
import finance_hkex/request
import finance_hkex/securities_runtime
import finance_hkex/security_profile_reference
import finance_hkex/security_search.{type Security}
import finance_hkex/title_search
import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_hk_disclosures/effect/environment
import pi_sparkles_hk_disclosures/selection

pub type SecurityInput {
  SecurityInput(code: String)
}

pub type DisclosureInput {
  DisclosureInput(code: String, stock_id: Option(Int), limit: Int)
}

type Provider {
  Ready(
    access: finance_hkex.Access,
    discovery: discovery_runtime.Runtime,
    securities: securities_runtime.Runtime,
    listing: listing_runtime.Runtime,
  )
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  tool.register(
    api,
    "hk_security_search",
    "HK security search",
    "Look up an exact five-digit current-security code through HKEXnews and preserve every exact internal stock identity candidate",
    "Resolve an HKEXnews stock ID before searching Hong Kong disclosures",
    tool.parameters(security_schema(), security_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime, _, _) -> {
          use outcome <- promise.await(fetch_security_candidates(
            provider_runtime,
            access,
            input.code,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(reference) ->
              tool.text_result(
                render_security(
                  input.code,
                  current_security_reference.candidates(reference),
                ),
                security_json(reference),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  tool.register(
    api,
    "hk_security_profile",
    "HK security profile",
    "Look up an exact five-digit code in HKEX's current Full List of Securities and preserve its exchange-owned category, sub-category, board lot, ISIN, eligibility markers, trading currency, and RMB counter",
    "Inspect a current HKEX security profile without treating catalogue membership as a listing interval or positive trading status",
    tool.parameters(security_schema(), security_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, _, provider_runtime, _) -> {
          use outcome <- promise.await(fetch_security_profile(
            provider_runtime,
            access,
            input.code,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(reference) ->
              tool.text_result(
                render_security_profile(reference),
                security_profile_json(reference),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  tool.register(
    api,
    "hk_recent_listing_event",
    "HK recent listing event",
    "Look up an exact five-digit code on HKEX's rolling current-two-week newly listed/traded page and preserve the exchange row as content-bound evidence",
    "Establish a listing start only for an exact, non-tentative New Listing row; listing end and trading status remain unknown",
    tool.parameters(security_schema(), security_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, _, _, provider_runtime) -> {
          use outcome <- promise.await(fetch_recent_listing(
            provider_runtime,
            access,
            input.code,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(reference) ->
              tool.text_result(
                render_recent_listing(reference),
                recent_listing_json(reference),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  tool.register(
    api,
    "hk_disclosure_search",
    "HK disclosure search",
    "Search HKEXnews listed-company titles after resolving the exact current-security stock ID; return bounded initial-page metadata and exact PDF identities",
    "Find Hong Kong issuer announcements and reports without guessing an HKEXnews stock ID; if this controlled source fails, preserve the result as unavailable instead of substituting generic web evidence",
    tool.parameters(disclosure_schema(), disclosure_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime, _, _) -> {
          let cancellation = transport.from_abort_signal(raw.dynamic(signal))
          use outcome <- promise.await(fetch_disclosures(
            provider_runtime,
            access,
            input,
            id,
            cancellation,
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(#(security, reference, page)) ->
              tool.text_result(
                render_disclosures(security, page),
                disclosure_json(security, reference, page),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_hkex.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "HKEXnews access requires AGENT_CONTACT (for example ops@example.com)",
      )
    Ok(access) ->
      case
        discovery_runtime.new(access),
        securities_runtime.new(access),
        listing_runtime.new(access)
      {
        Error(_), _, _ ->
          InvalidConfiguration(
            "HKEXnews discovery runtime could not initialize safely",
          )
        _, Error(_), _ ->
          InvalidConfiguration(
            "HKEX securities runtime could not initialize safely",
          )
        _, _, Error(_) ->
          InvalidConfiguration(
            "HKEX recent-listing runtime could not initialize safely",
          )
        Ok(discovery), Ok(securities), Ok(listing) ->
          Ready(access, discovery, securities, listing)
      }
  }
}

fn fetch_recent_listing(
  provider_runtime: listing_runtime.Runtime,
  access: finance_hkex.Access,
  code: String,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(recent_listing_reference.Reference, String)) {
  case security_search.query(code), request.recent_listings(access) {
    Error(_), _ ->
      promise.resolve(Error("HKEX recent-listing query was invalid"))
    _, Error(_) ->
      promise.resolve(Error("HKEX recent-listing request was invalid"))
    Ok(query), Ok(request_value) -> {
      use outcome <- promise.await(listing_runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case outcome {
        Error(error) ->
          promise.resolve(Error(
            "HKEX recent-listing request failed safely: "
            <> string.inspect(error),
          ))
        Ok(response_value) ->
          case time.instant(environment.now_milliseconds()) {
            Error(_) ->
              promise.resolve(Error(
                "HKEX recent-listing retrieval clock was invalid",
              ))
            Ok(retrieved_at) ->
              case
                recent_listing_reference.capture(
                  query,
                  response_value,
                  retrieved_at,
                )
              {
                Error(error) ->
                  promise.resolve(Error(
                    "HKEX recent-listing page could not be captured and decoded as exact exchange evidence: "
                    <> string.inspect(error),
                  ))
                Ok(reference) -> promise.resolve(Ok(reference))
              }
          }
      }
    }
  }
}

fn fetch_security_profile(
  provider_runtime: securities_runtime.Runtime,
  access: finance_hkex.Access,
  code: String,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(security_profile_reference.Reference, String)) {
  case security_search.query(code), request.full_list(access) {
    Error(_), _ ->
      promise.resolve(Error("HKEX Full List security query was invalid"))
    _, Error(_) -> promise.resolve(Error("HKEX Full List request was invalid"))
    Ok(query), Ok(request_value) -> {
      use outcome <- promise.await(securities_runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case outcome {
        Error(error) ->
          promise.resolve(Error(
            "HKEX Full List request failed safely: " <> string.inspect(error),
          ))
        Ok(response_value) ->
          case time.instant(environment.now_milliseconds()) {
            Error(_) ->
              promise.resolve(Error(
                "HKEX Full List retrieval clock was invalid",
              ))
            Ok(retrieved_at) -> {
              use captured <- promise.await(security_profile_reference.capture(
                query,
                response_value,
                retrieved_at,
                cancellation,
              ))
              case captured {
                Error(error) ->
                  promise.resolve(Error(
                    "HKEX Full List could not be captured and decoded as exact exchange evidence: "
                    <> string.inspect(error),
                  ))
                Ok(reference) -> promise.resolve(Ok(reference))
              }
            }
          }
      }
    }
  }
}

fn fetch_security_candidates(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_hkex.Access,
  code: String,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(current_security_reference.Reference, String)) {
  case security_search.query(code) {
    Error(_) -> promise.resolve(Error("HKEXnews security query was invalid"))
    Ok(query) ->
      case request.security_prefix(access, query) {
        Error(_) ->
          promise.resolve(Error("HKEXnews security request was invalid"))
        Ok(request_value) -> {
          use outcome <- promise.await(discovery_runtime.send(
            provider_runtime,
            id: id,
            request: request_value,
            cancellation: cancellation,
          ))
          case outcome {
            Error(error) ->
              promise.resolve(Error(
                "HKEXnews security lookup request failed safely: "
                <> string.inspect(error),
              ))
            Ok(response_value) -> {
              let retrieved_at = environment.now_milliseconds()
              case time.instant(retrieved_at) {
                Error(_) ->
                  promise.resolve(Error(
                    "HKEXnews security retrieval clock was invalid",
                  ))
                Ok(retrieved_at) ->
                  case
                    current_security_reference.capture(
                      query,
                      response_value,
                      retrieved_at,
                    )
                  {
                    Error(error) ->
                      promise.resolve(Error(
                        "HKEXnews security lookup could not be captured as exact current-catalogue evidence: "
                        <> string.inspect(error),
                      ))
                    Ok(reference) -> promise.resolve(Ok(reference))
                  }
              }
            }
          }
        }
      }
  }
}

fn fetch_disclosures(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_hkex.Access,
  input: DisclosureInput,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(
  Result(
    #(Security, current_security_reference.Reference, title_search.Page),
    String,
  ),
) {
  use candidates <- promise.await(fetch_security_candidates(
    provider_runtime,
    access,
    input.code,
    id <> "-identity",
    cancellation,
  ))
  case candidates {
    Error(message) -> promise.resolve(Error(message))
    Ok(reference) -> {
      let values = current_security_reference.candidates(reference)
      let resolution = identifier.resolve(values)
      case selection.select(resolution, input.stock_id) {
        Error(selection.NoCandidate) ->
          promise.resolve(Error(
            "HKEXnews found no exact current-security candidate for "
            <> input.code,
          ))
        Error(selection.AmbiguousCandidates(count)) ->
          promise.resolve(Error(
            "HKEXnews returned "
            <> int.to_string(count)
            <> " exact candidates; supply stockId",
          ))
        Error(selection.StockIdMismatch) ->
          promise.resolve(Error(
            "stockId does not match an exact HKEXnews code candidate",
          ))
        Ok(security) ->
          case
            title_search.plan(
              security_search.stock_id(security),
              security_search.code(security),
              input.limit,
            )
          {
            Error(_) ->
              promise.resolve(Error("HKEXnews title-search plan was invalid"))
            Ok(plan) ->
              case request.titles(access, plan) {
                Error(_) ->
                  promise.resolve(Error(
                    "HKEXnews title-search request was invalid",
                  ))
                Ok(request_value) -> {
                  use outcome <- promise.await(discovery_runtime.send(
                    provider_runtime,
                    id: id <> "-titles",
                    request: request_value,
                    cancellation: cancellation,
                  ))
                  case checked_body(outcome, "title search") {
                    Error(message) -> promise.resolve(Error(message))
                    Ok(body) ->
                      case title_search.decode(body, plan) {
                        Error(_) ->
                          promise.resolve(Error(
                            "HKEXnews returned an invalid title-search page",
                          ))
                        Ok(page) ->
                          promise.resolve(Ok(#(security, reference, page)))
                      }
                  }
                }
              }
          }
      }
    }
  }
}

fn checked_body(
  outcome: Result(http_response.Response, pool.PoolError),
  resource: String,
) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "HKEXnews "
        <> resource
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(value))
        False ->
          Error(
            "HKEXnews "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn security_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(5, 5)
        |> schema.described("Exact five-digit HKEX security code"),
    ),
  ])
}

fn disclosure_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(5, 5)
        |> schema.described("Exact five-digit current HKEX security code"),
    ),
    schema.Optional(
      "stockId",
      schema.integer()
        |> schema.with_number_range(1.0, 999_999_999.0)
        |> schema.described(
          "Exact HKEXnews internal stock ID if candidates are ambiguous",
        ),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 100.0)
        |> schema.described("Maximum initial-page rows; defaults to 20"),
    ),
  ])
}

fn security_decoder() -> decode.Decoder(SecurityInput) {
  use code <- decode.field("code", decode.string)
  case valid_code(code) {
    True -> decode.success(SecurityInput(code))
    False -> decode.failure(SecurityInput("00700"), "valid five-digit HK code")
  }
}

fn disclosure_decoder() -> decode.Decoder(DisclosureInput) {
  use code <- decode.field("code", decode.string)
  use stock_id <- optional_int_field("stockId")
  use limit <- decode.optional_field("limit", 20, decode.int)
  case
    valid_code(code),
    valid_optional_stock_id(stock_id),
    limit >= 1 && limit <= 100
  {
    True, True, True -> decode.success(DisclosureInput(code, stock_id, limit))
    _, _, _ ->
      decode.failure(
        DisclosureInput("00700", None, 20),
        "valid HKEXnews disclosure query",
      )
  }
}

fn optional_int_field(
  name: String,
  next: fn(Option(Int)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.int), next)
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn render_security(code: String, values: List(Security)) -> String {
  "HK track | HKEXnews current securities\n"
  <> case values {
    [] -> "No exact HKEXnews candidate for " <> code
    candidates ->
      "Exact-code candidates ("
      <> int.to_string(list.length(candidates))
      <> "):\n"
      <> candidates
      |> list.map(fn(value) {
        "- "
        <> security_search.code(value)
        <> " | "
        <> security_search.name(value)
        <> " | stockId "
        <> int.to_string(security_search.stock_id(value))
      })
      |> string.join("\n")
  }
}

fn render_security_profile(
  reference: security_profile_reference.Reference,
) -> String {
  let prefix =
    "HK track | HKEX Full List of Securities | updated "
    <> date_text(security_profile_reference.updated_as(reference))
    <> "\n"
  case security_profile_reference.candidates(reference) {
    [] ->
      prefix
      <> "No exact current Full List profile for "
      <> security_profile_reference.query_code(reference)
    [profile] ->
      prefix
      <> full_list.code(profile)
      <> " "
      <> full_list.name(profile)
      <> " | "
      <> full_list.category(profile)
      <> " | "
      <> full_list.subcategory(profile)
      <> " | "
      <> full_list.trading_currency(profile)
    values ->
      prefix
      <> "Conflicting exact-code profiles: "
      <> int.to_string(list.length(values))
  }
}

fn render_recent_listing(
  reference: recent_listing_reference.Reference,
) -> String {
  let prefix =
    "HK track | HKEX newly listed/traded securities | page updated "
    <> date_text(recent_listing_reference.updated_as(reference))
    <> "\n"
  case recent_listing_reference.candidates(reference) {
    [] ->
      prefix
      <> "No exact event in the rolling current-two-week window for "
      <> recent_listing_reference.query_code(reference)
    [event] ->
      prefix
      <> recent_listing.code(event)
      <> " "
      <> recent_listing.short_name(event)
      <> " | "
      <> recent_listing.corporate_action(event)
      <> " | event date "
      <> date_text(recent_listing.event_date(event))
      <> case recent_listing.tentative(event) {
        True -> " (tentative; no listing-start claim)"
        False -> ""
      }
    values ->
      prefix
      <> "Conflicting exact-code events: "
      <> int.to_string(list.length(values))
  }
}

fn render_disclosures(security: Security, page: title_search.Page) -> String {
  "HK track | HKEXnews listed-company titles\n"
  <> security_search.code(security)
  <> " "
  <> security_search.name(security)
  <> " | initial-page records "
  <> int.to_string(list.length(title_search.documents(page)))
  <> " / site total "
  <> int.to_string(title_search.total_records(page))
}

fn security_json(reference: current_security_reference.Reference) -> json.Json {
  let values = current_security_reference.candidates(reference)
  json.object(
    list.append(
      hk_track_fields("hk_hkexnews_security_reference", [
        "current_catalogue_at_retrieval_only",
        "stock_id_is_hkexnews_internal_identity",
        "listing_interval_board_share_class_currency_and_trading_status_unknown",
        "provider_more_marker_semantics_unverified",
        "provider_update_timestamp_not_supplied",
        "receipt_is_sha256_content_bound_not_provider_authenticated",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEXnews")),
        #(
          "source",
          json.string(current_security_reference.source_reference(reference)),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #(
          "queryCode",
          json.string(current_security_reference.query_code(reference)),
        ),
        #(
          "resolution",
          json.string(current_security_reference.resolution(reference)),
        ),
        #("candidates", json.array(values, security_candidate_json)),
        #("currentSecurityReceipt", current_security_receipt_json(reference)),
      ],
    ),
  )
}

fn security_profile_json(
  reference: security_profile_reference.Reference,
) -> json.Json {
  json.object(
    list.append(
      hk_profile_track_fields([
        "current_full_list_snapshot_only",
        "listing_effective_from_and_to_not_supplied",
        "catalogue_membership_is_not_positive_trading_status",
        "board_is_derived_only_from_exact_hkex_subcategory",
        "share_class_not_inferred",
        "xlsx_exact_entries_are_bounded_crc_checked_and_utf8_decoded",
        "receipt_is_sha256_content_bound_not_provider_authenticated",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEX")),
        #(
          "source",
          json.string(security_profile_reference.source_reference(reference)),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #(
          "queryCode",
          json.string(security_profile_reference.query_code(reference)),
        ),
        #(
          "workbookUpdatedAs",
          json.string(
            date_text(security_profile_reference.updated_as(reference)),
          ),
        ),
        #(
          "resolution",
          json.string(security_profile_reference.resolution(reference)),
        ),
        #(
          "candidates",
          json.array(
            security_profile_reference.candidates(reference),
            security_profile_candidate_json,
          ),
        ),
        #(
          "currentSecurityProfileReceipt",
          current_security_profile_receipt_json(reference),
        ),
      ],
    ),
  )
}

fn recent_listing_json(
  reference: recent_listing_reference.Reference,
) -> json.Json {
  json.object(
    list.append(
      hk_recent_listing_track_fields([
        "rolling_current_two_weeks_only",
        "listing_start_requires_exact_non_tentative_new_listing_row",
        "no_match_does_not_prove_absence_outside_the_window",
        "listing_effective_to_and_trading_status_not_supplied",
        "receipt_is_sha256_content_bound_not_provider_authenticated",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEX")),
        #(
          "source",
          json.string(recent_listing_reference.source_reference(reference)),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #(
          "queryCode",
          json.string(recent_listing_reference.query_code(reference)),
        ),
        #(
          "pageUpdatedAs",
          json.string(date_text(recent_listing_reference.updated_as(reference))),
        ),
        #("windowScope", json.string("rolling_current_two_weeks_only")),
        #(
          "resolution",
          json.string(recent_listing_reference.resolution(reference)),
        ),
        #(
          "candidates",
          json.array(
            recent_listing_reference.candidates(reference),
            recent_listing_candidate_json,
          ),
        ),
        #("recentListingEventReceipt", recent_listing_receipt_json(reference)),
      ],
    ),
  )
}

fn recent_listing_candidate_json(value: recent_listing.Event) -> json.Json {
  json.object([
    #("eventDate", json.string(date_text(recent_listing.event_date(value)))),
    #("tentative", json.bool(recent_listing.tentative(value))),
    #("shortName", json.string(recent_listing.short_name(value))),
    #("code", json.string(recent_listing.code(value))),
    #("venueMic", json.string("XHKG")),
    #("boardLot", json.string(recent_listing.board_lot(value))),
    #("ccassMarker", json.string(recent_listing.ccass_marker(value))),
    #("shortSellMarker", json.string(recent_listing.short_sell_marker(value))),
    #("stampDutyMarker", json.string(recent_listing.stamp_duty_marker(value))),
    #("auctionMarker", json.string(recent_listing.auction_marker(value))),
    #("corporateAction", json.string(recent_listing.corporate_action(value))),
    #("relatedCode", json.string(recent_listing.related_code(value))),
    #(
      "listingEffectiveFrom",
      option_date_json(recent_listing.listing_effective_from(value)),
    ),
    #("listingEffectiveTo", json.null()),
    #("tradingStatus", json.null()),
  ])
}

fn recent_listing_receipt_json(
  value: recent_listing_reference.Reference,
) -> json.Json {
  let retrieved_at =
    value
    |> recent_listing_reference.retrieved_at
    |> time.unix_milliseconds
  json.object([
    #("schema", json.string(recent_listing_reference.schema)),
    #("schemaVersion", json.int(recent_listing_reference.schema_version)),
    #("digestAlgorithm", json.string("sha256")),
    #(
      "canonicalDigest",
      json.string(recent_listing_reference.canonical_digest(value)),
    ),
    #("track", json.string("hk")),
    #("authorityId", json.string(recent_listing_reference.authority_id)),
    #("provider", json.string("HKEX")),
    #(
      "sourceReference",
      json.string(recent_listing_reference.source_reference(value)),
    ),
    #("queryCode", json.string(recent_listing_reference.query_code(value))),
    #(
      "pageUpdatedAs",
      json.string(date_text(recent_listing_reference.updated_as(value))),
    ),
    #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
    #("windowScope", json.string("rolling_current_two_weeks_only")),
    #("resolution", json.string(recent_listing_reference.resolution(value))),
    #(
      "candidates",
      json.array(
        recent_listing_reference.candidates(value),
        recent_listing_candidate_json,
      ),
    ),
    #(
      "evidence",
      json.object([
        #(
          "evidenceId",
          json.string(recent_listing_reference.evidence_id(value)),
        ),
        #(
          "sourceFingerprint",
          json.string(recent_listing_reference.source_fingerprint(value)),
        ),
        #("mediaType", json.string(recent_listing_reference.media_type(value))),
        #(
          "responseByteLength",
          json.int(recent_listing_reference.response_byte_length(value)),
        ),
        #(
          "contentSha256",
          json.string(recent_listing_reference.content_sha256(value)),
        ),
      ]),
    ),
    #(
      "claims",
      json.object([
        #(
          "recentListingEvent",
          json.bool(recent_listing_reference.resolution(value) == "unique"),
        ),
        #("venueMic", json.string("XHKG")),
        #(
          "listingEffectiveFrom",
          option_date_json(recent_listing_reference.listing_effective_from(
            value,
          )),
        ),
        #("listingEffectiveTo", json.null()),
        #("tradingStatus", json.null()),
      ]),
    ),
    #(
      "integrity",
      json.object([
        #("state", json.string("sha256_content_bound")),
        #("providerAuthenticated", json.bool(False)),
      ]),
    ),
  ])
}

fn security_profile_candidate_json(value: full_list.Profile) -> json.Json {
  json.object([
    #("code", json.string(full_list.code(value))),
    #("name", json.string(full_list.name(value))),
    #("venueMic", json.string("XHKG")),
    #("category", json.string(full_list.category(value))),
    #("subCategory", json.string(full_list.subcategory(value))),
    #("board", option_json(full_list.board(value))),
    #("boardLot", json.string(full_list.board_lot(value))),
    #("isin", json.string(full_list.isin(value))),
    #("expiryDate", json.string(full_list.expiry_date(value))),
    #("subjectToStampDuty", json.string(full_list.stamp_duty(value))),
    #("shortsellEligible", json.string(full_list.short_sell(value))),
    #("casEligible", json.string(full_list.cas(value))),
    #("vcmEligible", json.string(full_list.vcm(value))),
    #("admittedToCcass", json.string(full_list.ccass(value))),
    #("debtBoardLotNominal", json.string(full_list.debt_board_lot(value))),
    #("debtInvestorType", json.string(full_list.debt_investor_type(value))),
    #("posEligible", json.string(full_list.pos(value))),
    #("spreadTable", json.string(full_list.spread_table(value))),
    #("tradingCurrency", json.string(full_list.trading_currency(value))),
    #("rmbCounter", json.string(full_list.rmb_counter(value))),
    #("listingEffectiveFrom", json.null()),
    #("listingEffectiveTo", json.null()),
    #("tradingStatus", json.null()),
  ])
}

fn current_security_profile_receipt_json(
  value: security_profile_reference.Reference,
) -> json.Json {
  let retrieved_at =
    value
    |> security_profile_reference.retrieved_at
    |> time.unix_milliseconds
  json.object([
    #("schema", json.string(security_profile_reference.schema)),
    #("schemaVersion", json.int(security_profile_reference.schema_version)),
    #("digestAlgorithm", json.string("sha256")),
    #(
      "canonicalDigest",
      json.string(security_profile_reference.canonical_digest(value)),
    ),
    #("track", json.string("hk")),
    #("authorityId", json.string(security_profile_reference.authority_id)),
    #("provider", json.string("HKEX")),
    #(
      "sourceReference",
      json.string(security_profile_reference.source_reference(value)),
    ),
    #("queryCode", json.string(security_profile_reference.query_code(value))),
    #(
      "workbookUpdatedAs",
      json.string(date_text(security_profile_reference.updated_as(value))),
    ),
    #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
    #("catalogueScope", json.string("current_full_list_exact_code_only")),
    #("resolution", json.string(security_profile_reference.resolution(value))),
    #(
      "candidates",
      json.array(
        security_profile_reference.candidates(value),
        security_profile_candidate_json,
      ),
    ),
    #(
      "evidence",
      json.object([
        #(
          "evidenceId",
          json.string(security_profile_reference.evidence_id(value)),
        ),
        #(
          "sourceFingerprint",
          json.string(security_profile_reference.source_fingerprint(value)),
        ),
        #(
          "mediaType",
          json.string(security_profile_reference.media_type(value)),
        ),
        #(
          "responseByteLength",
          json.int(security_profile_reference.response_byte_length(value)),
        ),
        #(
          "contentSha256",
          json.string(security_profile_reference.content_sha256(value)),
        ),
      ]),
    ),
    #(
      "archive",
      json.object([
        #(
          "entryCount",
          json.int(security_profile_reference.archive_entry_count(value)),
        ),
        #(
          "totalUncompressedBytes",
          json.int(security_profile_reference.total_uncompressed_bytes(value)),
        ),
        #(
          "extractedEntries",
          json.array(
            security_profile_reference.extracted_entries(value),
            extracted_entry_json,
          ),
        ),
      ]),
    ),
    #(
      "claims",
      json.object([
        #("currentFullListProfile", json.bool(True)),
        #("venueMic", json.string("XHKG")),
        #("listingEffectiveFrom", json.null()),
        #("listingEffectiveTo", json.null()),
        #("tradingStatus", json.null()),
      ]),
    ),
    #(
      "integrity",
      json.object([
        #("state", json.string("sha256_content_bound_crc32_entries")),
        #("providerAuthenticated", json.bool(False)),
      ]),
    ),
  ])
}

fn extracted_entry_json(
  value: security_profile_reference.ExtractedEntry,
) -> json.Json {
  json.object([
    #(
      "name",
      json.string(security_profile_reference.extracted_entry_name(value)),
    ),
    #(
      "byteLength",
      json.int(security_profile_reference.extracted_entry_byte_length(value)),
    ),
    #(
      "crc32",
      json.string(security_profile_reference.extracted_entry_crc32(value)),
    ),
  ])
}

fn security_candidate_json(value: Security) -> json.Json {
  json.object([
    #("stockId", json.int(security_search.stock_id(value))),
    #("code", json.string(security_search.code(value))),
    #("name", json.string(security_search.name(value))),
    #("venueMic", json.string("XHKG")),
  ])
}

fn disclosure_json(
  security: Security,
  reference: current_security_reference.Reference,
  page: title_search.Page,
) -> json.Json {
  json.object(
    list.append(
      hk_track_fields("hk_hkexnews_disclosure_search", [
        "initial_rendered_page_only_maximum_100_rows",
        "historical_results_can_be_truncated",
        "hkex_does_not_verify_issuer_materials",
        "title_response_retrieval_time_not_yet_captured",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEXnews")),
        #(
          "source",
          json.string("https://www1.hkexnews.hk/search/titlesearch.xhtml"),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #("stockId", json.int(security_search.stock_id(security))),
        #("code", json.string(title_search.requested_code(page))),
        #("name", json.string(title_search.requested_name(page))),
        #("currentSecurityReceipt", current_security_receipt_json(reference)),
        #("totalRecords", json.int(title_search.total_records(page))),
        #("truncated", json.bool(title_search.truncated(page))),
        #("documents", json.array(title_search.documents(page), document_json)),
      ],
    ),
  )
}

fn current_security_receipt_json(
  value: current_security_reference.Reference,
) -> json.Json {
  let retrieved_at =
    value
    |> current_security_reference.retrieved_at
    |> time.unix_milliseconds
  json.object([
    #("schema", json.string(current_security_reference.schema)),
    #("schemaVersion", json.int(current_security_reference.schema_version)),
    #("digestAlgorithm", json.string("sha256")),
    #(
      "canonicalDigest",
      json.string(current_security_reference.canonical_digest(value)),
    ),
    #("track", json.string("hk")),
    #("authorityId", json.string(current_security_reference.authority_id)),
    #("provider", json.string("HKEXnews")),
    #(
      "sourceReference",
      json.string(current_security_reference.source_reference(value)),
    ),
    #("queryCode", json.string(current_security_reference.query_code(value))),
    #("observedAtUnixMilliseconds", json.int(retrieved_at)),
    #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
    #("catalogueScope", json.string("current_security_prefix_exact_code_only")),
    #(
      "providerMoreMarker",
      json.string(current_security_reference.provider_more_marker(value)),
    ),
    #("resolution", json.string(current_security_reference.resolution(value))),
    #(
      "candidates",
      json.array(
        current_security_reference.candidates(value),
        security_candidate_json,
      ),
    ),
    #(
      "evidence",
      json.object([
        #(
          "evidenceId",
          json.string(current_security_reference.evidence_id(value)),
        ),
        #(
          "sourceFingerprint",
          json.string(current_security_reference.source_fingerprint(value)),
        ),
        #(
          "mediaType",
          json.string(current_security_reference.media_type(value)),
        ),
        #(
          "responseByteLength",
          json.int(current_security_reference.response_byte_length(value)),
        ),
        #(
          "contentSha256",
          json.string(current_security_reference.content_sha256(value)),
        ),
      ]),
    ),
    #(
      "claims",
      json.object([
        #("currentCatalogueResponseAtRetrieval", json.bool(True)),
        #("venueMic", json.string("XHKG")),
        #("board", json.null()),
        #("shareClass", json.null()),
        #("currency", json.null()),
        #("listingEffectiveFrom", json.null()),
        #("listingEffectiveTo", json.null()),
        #("tradingStatus", json.null()),
      ]),
    ),
    #(
      "integrity",
      json.object([
        #("state", json.string("sha256_content_bound")),
        #("providerAuthenticated", json.bool(False)),
      ]),
    ),
  ])
}

fn document_json(value: title_search.Document) -> json.Json {
  json.object([
    #("releaseTime", json.string(title_search.release_time(value))),
    #("releaseTimezone", json.string("Asia/Hong_Kong")),
    #("codes", json.array(title_search.codes(value), json.string)),
    #("names", json.array(title_search.names(value), json.string)),
    #("headlineHtml", json.string(title_search.headline_html(value))),
    #("title", json.string(title_search.title(value))),
    #(
      "documentUrl",
      json.string(finance_hkex.canonical_url(title_search.reference(value))),
    ),
    #("displayedFileSize", json.string(title_search.file_size(value))),
  ])
}

fn hk_track_fields(
  market_scope: String,
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: market_scope,
      venue_mic: Some(finance_hkex_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "en-HK",
      providers: ["HKEXnews"],
      entitlement: "read_only_public_local_analysis_no_redistribution",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn hk_profile_track_fields(
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: "hk_hkex_current_security_profile",
      venue_mic: Some(finance_hkex_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "en-HK",
      providers: ["HKEX"],
      entitlement: "read_only_public_local_analysis_no_redistribution",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn hk_recent_listing_track_fields(
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: "hk_hkex_recent_listing_event",
      venue_mic: Some(finance_hkex_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "en-HK",
      providers: ["HKEX"],
      entitlement: "read_only_public_local_analysis_no_redistribution",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn option_date_json(value: Option(time.Date)) -> json.Json {
  case value {
    Some(value) -> json.string(date_text(value))
    None -> json.null()
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn finance_hkex_mic() -> identifier.Mic {
  let assert Ok(value) = identifier.mic("XHKG")
  value
}

fn valid_optional_stock_id(value: Option(Int)) -> Bool {
  case value {
    None -> True
    Some(value) -> value > 0
  }
}
