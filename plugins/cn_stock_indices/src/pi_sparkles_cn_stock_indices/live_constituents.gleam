import finance_sse_index/constituents.{type Constituents, type Member}
import finance_sse_index/query.{type Query}
import finance_sse_index/request
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import pi_sparkles_cn_stock_indices/track_applicability

pub fn content(query: Query, value: Constituents) -> String {
  let heading =
    "Official SSE "
    <> query.code(query)
    <> " "
    <> query.name(query)
    <> " constituents, published "
    <> constituents.publication_date(value)
    <> " ("
    <> int.to_string(list.length(constituents.members(value)))
    <> ")"
  let rows =
    value
    |> constituents.members
    |> list.index_map(fn(member, index) {
      int.to_string(index + 1)
      <> ". "
      <> constituents.code(member)
      <> " "
      <> constituents.name(member)
    })
  [heading, ..rows] |> string.join("\n")
}

pub fn details(
  query: Query,
  value: Constituents,
  retrieved_at_milliseconds: Int,
  response_bytes: Int,
  response_sha256: String,
) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("track", json.string("cn")),
    #("provider", json.string("Shanghai Stock Exchange")),
    #("authorityScope", json.string("official_sse_public_index_service")),
    #("venue", json.string(query.venue(query))),
    #("mic", json.string(query.mic(query))),
    #("indexCode", json.string(query.code(query))),
    #("indexName", json.string(query.name(query))),
    #("publicationDate", json.string(constituents.publication_date(value))),
    #("providerOrder", json.string("sse_response_order")),
    #(
      "members",
      value
        |> constituents.members
        |> json.array(member_json),
    ),
    #("requestCount", json.int(1)),
    #("retrievedAtMilliseconds", json.int(retrieved_at_milliseconds)),
    #("responseBytes", json.int(response_bytes)),
    #("responseSha256", json.string(response_sha256)),
    #("sourceUrl", json.string(request.canonical_url(query))),
    #("trackApplicability", track_applicability.details()),
    #(
      "limitations",
      json.array(
        [
          "current_snapshot_only",
          "provider_order_is_not_weight_order",
          "weights_not_returned_by_this_operation",
          "no_historical_membership_reconstruction",
          "no_quote_or_event_enrichment",
        ],
        json.string,
      ),
    ),
  ])
}

fn member_json(member: Member) -> json.Json {
  json.object([
    #("venue", json.string("sse")),
    #("mic", json.string("XSHG")),
    #("code", json.string(constituents.code(member))),
    #("listingId", json.string("XSHG:" <> constituents.code(member))),
    #("name", json.string(constituents.name(member))),
    #("englishName", json.string(constituents.english_name(member))),
  ])
}
