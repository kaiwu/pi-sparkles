import finance_eastmoney/overview as provider
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub opaque type Output {
  Output(summary: String, content: String, details: json.Json)
}

pub type Error {
  InvalidRetrievalTime
  InvalidResponseBytes
  MissingBreadthLeg(code: String)
  InvalidBreadthCount(code: String, field: String, raw: String)
}

type Breadth {
  Breadth(advanced: Int, declined: Int, unchanged: Int)
}

pub fn assemble(
  value: provider.Overview,
  retrieved_at: Int,
  response_bytes: Int,
  content_sha256: Sha256,
) -> Result(Output, Error) {
  use _ <- result.try(case retrieved_at > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidRetrievalTime)
  })
  use _ <- result.try(case response_bytes > 0 && response_bytes <= 200_000 {
    True -> Ok(Nil)
    False -> Error(InvalidResponseBytes)
  })
  use sse <- result.try(
    provider.shanghai_breadth(value)
    |> option_result(MissingBreadthLeg("000001")),
  )
  use szse <- result.try(
    provider.shenzhen_breadth(value)
    |> option_result(MissingBreadthLeg("399001")),
  )
  use sse_breadth <- result.try(breadth(sse))
  use szse_breadth <- result.try(breadth(szse))
  let combined =
    Breadth(
      sse_breadth.advanced + szse_breadth.advanced,
      sse_breadth.declined + szse_breadth.declined,
      sse_breadth.unchanged + szse_breadth.unchanged,
    )
  let digest = identity.sha256_value(content_sha256)
  let summary =
    "CN track | Eastmoney SSE/SZSE provider overview | 4 benchmarks | breadth "
    <> int.to_string(combined.advanced)
    <> " advanced, "
    <> int.to_string(combined.declined)
    <> " declined, "
    <> int.to_string(combined.unchanged)
    <> " unchanged | completeness and latency unknown"
  let rows =
    provider.benchmarks(value)
    |> list.map(benchmark_content)
    |> string.join("\n")
  let content =
    summary
    <> "\n"
    <> rows
    <> "\nEvidence boundaries: breadth is the provider's index-associated SSE/SZSE scope, not exchange-authenticated full-market membership. No intraday ordering, fund flow, sector rotation, prior-session amount comparison, or verified turnover semantics is supplied."
  Ok(Output(
    summary,
    content,
    json.object([
      #("schema", json.string("pi-sparkles/cn-market-overview-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("acquire_current_overview")),
      #("track", json.string("cn")),
      #("provider", json.string("eastmoney")),
      #("route", json.string("direct")),
      #(
        "marketScope",
        json.string("sse_szse_provider_index_associated_overview"),
      ),
      #("retrievedAtUnixMilliseconds", json.int(retrieved_at)),
      #("responseBytes", json.int(response_bytes)),
      #(
        "acquisitionReceipt",
        json.object([
          #("canonicalSha256", json.string(digest)),
          #("scope", json.string("exact_response_body_v1")),
          #("providerAuthenticated", json.bool(False)),
        ]),
      ),
      #("benchmarks", json.array(provider.benchmarks(value), benchmark_json)),
      #("marketBreadth", breadth_json(combined, sse_breadth, szse_breadth)),
      #(
        "providerReportedAmounts",
        json.object([
          #("state", json.string("observed")),
          #("currency", json.string("CNY")),
          #(
            "semantics",
            json.string("provider_index_associated_amount_unverified"),
          ),
          #(
            "trendVersusPriorSession",
            unavailable_json("prior_session_amount_not_acquired"),
          ),
        ]),
      ),
      #("intradaySequence", unavailable_json("no_intraday_sequence_fields")),
      #("fundFlow", unavailable_json("no_fund_flow_fields")),
      #("sectorRotation", unavailable_json("no_sector_classification_fields")),
      #("providerTimestamp", unavailable_json("endpoint_did_not_supply_it")),
      #("latency", json.string("unknown")),
      #("entitlement", json.string("public_web_local_analysis")),
      #("licence", json.string("unknown")),
      #("redistribution", json.string("unknown")),
      #(
        "limitations",
        json.array(
          [
            "vendor_origin_not_exchange_evidence",
            "provider_index_associated_breadth_scope_not_independently_verified",
            "full_market_membership_completeness_unknown",
            "provider_reported_amount_semantics_unverified",
            "provider_volume_unit_unverified",
            "realtime_and_delay_status_unknown",
            "no_intraday_ordering_evidence",
            "no_fund_flow_or_sector_rotation_evidence",
            "no_prior_session_amount_comparison",
            "service_level_licence_and_redistribution_unknown",
            "no_fallback",
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

pub fn content(value: Output) -> String {
  value.content
}

pub fn details(value: Output) -> json.Json {
  value.details
}

pub fn error_message(error: Error) -> String {
  case error {
    InvalidRetrievalTime -> "retrieval time was invalid"
    InvalidResponseBytes -> "overview response byte count was invalid"
    MissingBreadthLeg(code) -> "overview omitted required breadth leg " <> code
    InvalidBreadthCount(code, field, raw) ->
      "overview returned invalid breadth count "
      <> code
      <> "."
      <> field
      <> "="
      <> raw
  }
}

fn breadth(value: provider.Benchmark) -> Result(Breadth, Error) {
  use advanced <- result.try(count(value, "advanced", provider.advanced(value)))
  use declined <- result.try(count(value, "declined", provider.declined(value)))
  use unchanged <- result.try(count(
    value,
    "unchanged",
    provider.unchanged(value),
  ))
  Ok(Breadth(advanced, declined, unchanged))
}

fn count(
  benchmark: provider.Benchmark,
  field: String,
  value: provider.Fact,
) -> Result(Int, Error) {
  case value {
    provider.Unavailable(reason) ->
      Error(InvalidBreadthCount(provider.code(benchmark), field, reason))
    provider.Observed(raw) ->
      case int.parse(raw) {
        Ok(value) if value >= 0 -> Ok(value)
        _ -> Error(InvalidBreadthCount(provider.code(benchmark), field, raw))
      }
  }
}

fn benchmark_content(value: provider.Benchmark) -> String {
  provider.code(value)
  <> " "
  <> provider.name(value)
  <> " last="
  <> fact_text(provider.last(value))
  <> " change="
  <> fact_text(provider.change(value))
  <> " changePercent="
  <> fact_text(provider.change_percent(value))
  <> "% providerReportedAmount="
  <> fact_text(provider.provider_reported_amount(value))
}

fn benchmark_json(value: provider.Benchmark) -> json.Json {
  json.object([
    #("code", json.string(provider.code(value))),
    #("name", json.string(provider.name(value))),
    #("instrumentKind", json.string("benchmark_index")),
    #("providerMarketId", json.string(provider.provider_market_id(value))),
    #("scope", json.string(benchmark_scope(provider.code(value)))),
    #("last", fact_json(provider.last(value), "CNY")),
    #("change", fact_json(provider.change(value), "CNY")),
    #("changePercent", fact_json(provider.change_percent(value), "percent")),
    #("open", fact_json(provider.open(value), "CNY")),
    #("high", fact_json(provider.high(value), "CNY")),
    #("low", fact_json(provider.low(value), "CNY")),
    #("previousClose", fact_json(provider.previous_close(value), "CNY")),
    #(
      "providerVolume",
      fact_json(provider.provider_volume(value), "provider_unit_unknown"),
    ),
    #(
      "providerReportedAmount",
      fact_json(
        provider.provider_reported_amount(value),
        "declared_CNY_semantics_unverified",
      ),
    ),
    #(
      "breadth",
      json.object([
        #("advanced", fact_json(provider.advanced(value), "count")),
        #("declined", fact_json(provider.declined(value), "count")),
        #("unchanged", fact_json(provider.unchanged(value), "count")),
        #(
          "scope",
          json.string("provider_index_associated_membership_unverified"),
        ),
      ]),
    ),
  ])
}

fn breadth_json(combined: Breadth, sse: Breadth, szse: Breadth) -> json.Json {
  json.object([
    #("state", json.string("observed_provider_aggregate")),
    #("scope", json.string("sse_and_szse_index_associated_counts")),
    #("completeness", json.string("unknown")),
    #("advanced", json.int(combined.advanced)),
    #("declined", json.int(combined.declined)),
    #("unchanged", json.int(combined.unchanged)),
    #(
      "venueLegs",
      json.array([#("sse", sse), #("szse", szse)], fn(item) {
        json.object([
          #("venue", json.string(item.0)),
          #("advanced", json.int(item.1.advanced)),
          #("declined", json.int(item.1.declined)),
          #("unchanged", json.int(item.1.unchanged)),
        ])
      }),
    ),
    #("excludedTracks", json.array([], json.string)),
    #("excludedCnVenue", json.string("bse")),
  ])
}

fn fact_json(value: provider.Fact, unit: String) -> json.Json {
  case value {
    provider.Observed(raw) ->
      json.object([
        #("state", json.string("observed")),
        #("raw", json.string(raw)),
        #("unit", json.string(unit)),
      ])
    provider.Unavailable(reason) ->
      json.object([
        #("state", json.string("unavailable")),
        #("reason", json.string(reason)),
        #("unit", json.string(unit)),
      ])
  }
}

fn unavailable_json(reason: String) -> json.Json {
  json.object([
    #("state", json.string("unavailable")),
    #("reason", json.string(reason)),
  ])
}

fn fact_text(value: provider.Fact) -> String {
  case value {
    provider.Observed(raw) -> raw
    provider.Unavailable(reason) -> "unavailable(" <> reason <> ")"
  }
}

fn benchmark_scope(code: String) -> String {
  case code {
    "000001" -> "sse_composite_provider_scope"
    "399001" -> "szse_component_provider_scope"
    "399006" -> "chinext_provider_scope"
    "000300" -> "csi300_cross_venue_provider_scope"
    _ -> "unexpected_benchmark_scope"
  }
}

fn option_result(value, error) {
  case value {
    Some(value) -> Ok(value)
    None -> Error(error)
  }
}
