import finance_cninfo
import finance_cninfo/disclosure
import finance_cninfo/discovery_runtime
import finance_cninfo/request
import finance_cninfo/security_master.{type Security}
import finance_core/time
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
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_disclosures/effect/environment
import pi_sparkles_cn_disclosures/selection

pub type SecurityInput {
  SecurityInput(code: String)
}

pub type DisclosureInput {
  DisclosureInput(
    code: String,
    organization_id: Option(String),
    start_date: time.Date,
    end_date: time.Date,
    category: disclosure.Category,
    page: Int,
    page_size: Int,
  )
}

type Provider {
  Ready(access: finance_cninfo.Access, runtime: discovery_runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  tool.register(
    api,
    "cn_security_search",
    "CN security search",
    "Look up an exact six-digit mainland code in CNINFO's public catalogue and preserve every organization candidate without guessing a venue",
    "Resolve CNINFO organization identity before searching mainland disclosures",
    tool.parameters(security_schema(), security_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_security_master(
            provider_runtime,
            access,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(values) -> {
              let resolution =
                security_master.resolve_code(values, code: input.code)
              let candidates = selection.candidates(resolution)
              tool.text_result(
                render_security(input.code, candidates),
                security_json(input.code, candidates),
              )
              |> promise.resolve
            }
          }
        }
      }
    },
  )

  tool.register(
    api,
    "cn_disclosure_search",
    "CN disclosure search",
    "Search CNINFO announcement metadata after proving an exact catalogue code/organization association; preserve exact PDF identity and source fields",
    "Find mainland issuer announcements and periodic reports without guessing venue or document identity",
    tool.parameters(disclosure_schema(), disclosure_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
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
            Ok(#(security, page)) ->
              tool.text_result(
                render_disclosures(security, page),
                disclosure_json(security, input, page),
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
  case finance_cninfo.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "CNINFO access requires CNINFO_USER_AGENT_CONTACT (for example ops@example.com); CNINFO_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case discovery_runtime.new(access) {
        Error(_) ->
          InvalidConfiguration(
            "CNINFO discovery runtime could not initialize safely",
          )
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch_security_master(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_cninfo.Access,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(List(Security), String)) {
  case request.security_master(access) {
    Error(_) -> promise.resolve(Error("CNINFO security request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(discovery_runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_body(outcome, "security catalogue") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case security_master.decode(body) {
            Error(_) ->
              promise.resolve(Error(
                "CNINFO returned an invalid security catalogue",
              ))
            Ok(values) -> promise.resolve(Ok(values))
          }
      }
    }
  }
}

fn fetch_disclosures(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_cninfo.Access,
  input: DisclosureInput,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(#(Security, disclosure.Page), String)) {
  use master <- promise.await(fetch_security_master(
    provider_runtime,
    access,
    id <> "-identity",
    cancellation,
  ))
  case master {
    Error(message) -> promise.resolve(Error(message))
    Ok(values) -> {
      let resolution = security_master.resolve_code(values, code: input.code)
      case selection.select(resolution, input.organization_id) {
        Error(selection.NoCandidate) ->
          promise.resolve(Error(
            "CNINFO catalogue found no exact candidate for " <> input.code,
          ))
        Error(selection.AmbiguousCandidates(count)) ->
          promise.resolve(Error(
            "CNINFO catalogue returned "
            <> int.to_string(count)
            <> " exact code candidates; supply organizationId",
          ))
        Error(selection.OrganizationIdMismatch) ->
          promise.resolve(Error(
            "organizationId does not match an exact CNINFO code candidate",
          ))
        Ok(security) ->
          case
            disclosure.query(
              code: input.code,
              organization_id: security_master.organization_id(security),
              start_date: input.start_date,
              end_date: input.end_date,
              category: input.category,
              page: input.page,
              page_size: input.page_size,
            )
          {
            Error(_) ->
              promise.resolve(Error("CNINFO disclosure query was invalid"))
            Ok(plan) ->
              case request.announcements(access, plan) {
                Error(_) ->
                  promise.resolve(Error("CNINFO disclosure request was invalid"))
                Ok(request_value) -> {
                  use outcome <- promise.await(discovery_runtime.send(
                    provider_runtime,
                    id: id <> "-announcements",
                    request: request_value,
                    cancellation: cancellation,
                  ))
                  case checked_body(outcome, "announcement query") {
                    Error(message) -> promise.resolve(Error(message))
                    Ok(body) ->
                      case disclosure.decode_page(body) {
                        Error(_) ->
                          promise.resolve(Error(
                            "CNINFO returned invalid announcement metadata",
                          ))
                        Ok(page) -> promise.resolve(Ok(#(security, page)))
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
        "CNINFO "
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
            "CNINFO "
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
        |> schema.with_string_length(6, 6)
        |> schema.described("Exact six-digit mainland security code"),
    ),
  ])
}

fn disclosure_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(6, 6)
        |> schema.described("Exact six-digit mainland security code"),
    ),
    schema.Optional(
      "organizationId",
      schema.string()
        |> schema.with_string_length(1, 100)
        |> schema.described(
          "Exact CNINFO organization ID when code candidates are ambiguous",
        ),
    ),
    schema.Required(
      "startDate",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Inclusive Gregorian date YYYY-MM-DD"),
    ),
    schema.Required(
      "endDate",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Inclusive Gregorian date YYYY-MM-DD"),
    ),
    schema.Optional(
      "category",
      schema.string_enum([
        "all",
        "annual",
        "half_year",
        "first_quarter",
        "third_quarter",
      ]),
    ),
    schema.Optional(
      "page",
      schema.integer() |> schema.with_number_range(1.0, 1000.0),
    ),
    schema.Optional(
      "pageSize",
      schema.integer() |> schema.with_number_range(1.0, 30.0),
    ),
  ])
}

fn security_decoder() -> decode.Decoder(SecurityInput) {
  use code <- decode.field("code", decode.string)
  case valid_code(code) {
    True -> decode.success(SecurityInput(code))
    False -> decode.failure(SecurityInput("000001"), "valid six-digit CN code")
  }
}

fn disclosure_decoder() -> decode.Decoder(DisclosureInput) {
  use code <- decode.field("code", decode.string)
  use organization_id <- optional_string_field("organizationId")
  use start_text <- decode.field("startDate", decode.string)
  use end_text <- decode.field("endDate", decode.string)
  use category_text <- decode.optional_field("category", "all", decode.string)
  use page <- decode.optional_field("page", 1, decode.int)
  use page_size <- decode.optional_field("pageSize", 20, decode.int)
  let assert Ok(placeholder_date) = time.date(2000, 1, 1)
  let placeholder =
    DisclosureInput(
      "000001",
      None,
      placeholder_date,
      placeholder_date,
      disclosure.All,
      1,
      20,
    )
  case
    valid_code(code),
    parse_date(start_text),
    parse_date(end_text),
    disclosure.category_from_name(category_text),
    page >= 1 && page <= 1000,
    page_size >= 1 && page_size <= 30
  {
    True, Ok(start), Ok(end), Ok(category), True, True ->
      case
        disclosure.query(
          code: code,
          organization_id: option.unwrap(organization_id, "placeholder"),
          start_date: start,
          end_date: end,
          category: category,
          page: page,
          page_size: page_size,
        )
      {
        Ok(_) ->
          decode.success(DisclosureInput(
            code,
            organization_id,
            start,
            end,
            category,
            page,
            page_size,
          ))
        Error(disclosure.InvalidOrganizationId) ->
          case organization_id {
            None ->
              decode.success(DisclosureInput(
                code,
                organization_id,
                start,
                end,
                category,
                page,
                page_size,
              ))
            Some(_) ->
              decode.failure(placeholder, "valid CNINFO organization ID")
          }
        Error(_) -> decode.failure(placeholder, "valid CNINFO disclosure query")
      }
    _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid CNINFO disclosure query")
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
  }
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn render_security(code: String, candidates: List(Security)) -> String {
  "CN track | CNINFO public catalogue\n"
  <> case candidates {
    [] -> "No exact CNINFO candidate for " <> code <> "; do not infer a venue"
    values ->
      "Exact-code candidates ("
      <> int.to_string(list.length(values))
      <> "):\n"
      <> values
      |> list.map(fn(value) {
        "- "
        <> security_master.code(value)
        <> " | "
        <> security_master.short_name(value)
        <> " | organizationId "
        <> security_master.organization_id(value)
        <> " | "
        <> security_master.category(value)
      })
      |> string.join("\n")
  }
}

fn render_disclosures(security: Security, page: disclosure.Page) -> String {
  "CN track | CNINFO announcements\n"
  <> security_master.code(security)
  <> " "
  <> security_master.short_name(security)
  <> " | organizationId "
  <> security_master.organization_id(security)
  <> " | page records "
  <> int.to_string(list.length(disclosure.announcements(page)))
  <> " / total "
  <> int.to_string(disclosure.total_announcements(page))
}

fn security_json(code: String, candidates: List(Security)) -> json.Json {
  json.object(
    list.append(
      cn_track_fields("cn_cninfo_security_reference", [
        "code_does_not_prove_venue_board_share_class_currency_or_status",
        "catalogue_source_timestamp_not_supplied",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("CNINFO")),
        #(
          "source",
          json.string("https://www.cninfo.com.cn/new/data/szse_stock.json"),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #("queryCode", json.string(code)),
        #("resolution", json.string(resolution_name(candidates))),
        #("candidates", json.array(candidates, security_candidate_json)),
      ],
    ),
  )
}

fn security_candidate_json(value: Security) -> json.Json {
  json.object([
    #("code", json.string(security_master.code(value))),
    #("organizationId", json.string(security_master.organization_id(value))),
    #("shortName", json.string(security_master.short_name(value))),
    #("category", json.string(security_master.category(value))),
    #("pinyin", json.string(security_master.pinyin(value))),
    #("venueMic", json.null()),
    #("board", json.null()),
  ])
}

fn disclosure_json(
  security: Security,
  input: DisclosureInput,
  page: disclosure.Page,
) -> json.Json {
  json.object(
    list.append(
      cn_track_fields("cn_cninfo_disclosure_search", [
        "cninfo_repository_does_not_by_itself_prove_exchange_origin",
        "provider_time_semantics_not_verified_as_exchange_publication_time",
        "response_retrieval_time_not_yet_captured",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("CNINFO")),
        #(
          "source",
          json.string("https://www.cninfo.com.cn/new/hisAnnouncement/query"),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #("code", json.string(security_master.code(security))),
        #(
          "organizationId",
          json.string(security_master.organization_id(security)),
        ),
        #("shortName", json.string(security_master.short_name(security))),
        #("category", json.string(disclosure.category_name(input.category))),
        #("page", json.int(input.page)),
        #("pageSize", json.int(input.page_size)),
        #("totalAnnouncements", json.int(disclosure.total_announcements(page))),
        #("totalPages", json.int(disclosure.total_pages(page))),
        #("hasMore", json.bool(disclosure.has_more(page))),
        #(
          "announcements",
          json.array(disclosure.announcements(page), announcement_json),
        ),
      ],
    ),
  )
}

fn announcement_json(value: disclosure.Announcement) -> json.Json {
  json.object([
    #("code", json.string(disclosure.announcement_code(value))),
    #("shortName", json.string(disclosure.announcement_short_name(value))),
    #(
      "organizationId",
      json.string(disclosure.announcement_organization_id(value)),
    ),
    #("announcementId", json.string(disclosure.announcement_id(value))),
    #("title", json.string(disclosure.announcement_title(value))),
    #(
      "providerTimeMilliseconds",
      json.int(disclosure.announcement_provider_time_milliseconds(value)),
    ),
    #("providerTimeMeaning", json.string("unverified_cninfo_source_field")),
    #(
      "documentUrl",
      json.string(
        finance_cninfo.canonical_url(disclosure.announcement_document(value)),
      ),
    ),
    #("sizeKilobytes", json.int(disclosure.announcement_size_kilobytes(value))),
    #(
      "typeCodes",
      option_json(disclosure.announcement_type_codes(value), json.string),
    ),
  ])
}

fn cn_track_fields(
  market_scope: String,
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: market_scope,
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "zh-CN",
      providers: ["CNINFO"],
      entitlement: "read_only_public_local_analysis_no_redistribution",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn resolution_name(values: List(Security)) -> String {
  case values {
    [] -> "no_match"
    [_] -> "unique"
    [_, _, ..] -> "ambiguous"
  }
}

fn option_json(value: Option(a), encode: fn(a) -> json.Json) -> json.Json {
  case value {
    Some(value) -> encode(value)
    None -> json.null()
  }
}
