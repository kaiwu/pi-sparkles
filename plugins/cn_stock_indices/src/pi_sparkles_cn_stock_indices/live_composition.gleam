import finance_sse_index/composition.{type Composition, type Sector}
import finance_sse_index/query.{type Query}
import finance_sse_index/request
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import pi_sparkles_cn_stock_indices/track_applicability

pub fn content(query: Query, value: Composition) -> String {
  let heading =
    "Official SSE "
    <> query.code(query)
    <> " "
    <> query.name(query)
    <> " industry composition, effective "
    <> composition.effective_date(value)
  let rows =
    value
    |> composition.sectors
    |> list.map(fn(sector) {
      composition.name(sector)
      <> ": members="
      <> int.to_string(composition.security_count(sector))
      <> " weight="
      <> composition.weight_raw(sector)
      <> "%"
    })
  [heading, ..rows] |> string.join("\n")
}

pub fn details(
  query: Query,
  value: Composition,
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
    #("effectiveDate", json.string(composition.effective_date(value))),
    #("sectors", value |> composition.sectors |> json.array(sector_json)),
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
          "current_aggregate_only",
          "provider_industry_taxonomy",
          "weights_are_exact_provider_lexemes",
          "no_per_stock_sector_mapping",
          "no_price_performance_or_causal_attribution",
        ],
        json.string,
      ),
    ),
  ])
}

fn sector_json(sector: Sector) -> json.Json {
  json.object([
    #("sectorCode", json.string(composition.code(sector))),
    #("name", json.string(composition.name(sector))),
    #("englishName", json.string(composition.english_name(sector))),
    #("securityCount", json.int(composition.security_count(sector))),
    #("weightPercentRaw", json.string(composition.weight_raw(sector))),
  ])
}
