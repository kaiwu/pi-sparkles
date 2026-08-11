import finance_cninfo
import finance_cninfo/current_security_reference
import finance_cninfo/disclosure
import finance_cninfo/discovery_runtime
import finance_cninfo/request
import finance_cninfo/security_master.{type Security}
import finance_core/identifier
import finance_core/time
import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_provenance/identity
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
import pi_sparkles_cn_stock_announcements/effect/environment
import pi_sparkles_cn_stock_announcements/selection

pub type Input {
  Input(
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
  Ready(finance_cninfo.Access, discovery_runtime.Runtime)
  Unavailable(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_stock_announcement_search",
    "CN stock announcements",
    "Search bounded official CNINFO announcement metadata after resolving an exact code and organization association",
    "Preserves Chinese titles, document identities, paging and receipts; ambiguity and malformed provider data fail closed",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        Unavailable(reason) -> tool.reject(reason)
        Ready(access, runtime) -> {
          use outcome <- promise.await(fetch(
            runtime,
            access,
            input,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(#(security, reference, page, retrieved_at, digest, byte_length)) ->
              tool.text_result(
                summary(security, page),
                details(
                  security,
                  reference,
                  input,
                  page,
                  retrieved_at,
                  digest,
                  byte_length,
                ),
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
      Unavailable(
        "CNINFO_USER_AGENT_CONTACT is required for responsible public access; it is operator identification, not a provider credential",
      )
    Ok(access) ->
      case discovery_runtime.new(access) {
        Error(_) ->
          Unavailable("CNINFO bounded discovery runtime could not initialize")
        Ok(runtime) -> Ready(access, runtime)
      }
  }
}

fn fetch(
  runtime: discovery_runtime.Runtime,
  access: finance_cninfo.Access,
  input: Input,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(
  Result(
    #(
      Security,
      current_security_reference.Reference,
      disclosure.Page,
      time.Instant,
      String,
      Int,
    ),
    String,
  ),
) {
  case request.security_master(access) {
    Error(_) -> promise.resolve(Error("CNINFO security request was invalid"))
    Ok(master_request) -> {
      use master_outcome <- promise.await(discovery_runtime.send(
        runtime,
        id: id <> "-identity",
        request: master_request,
        cancellation: cancellation,
      ))
      case master_outcome, time.instant(environment.now_milliseconds()) {
        Error(error), _ ->
          promise.resolve(Error(
            "CNINFO security catalogue failed safely: " <> string.inspect(error),
          ))
        _, Error(_) ->
          promise.resolve(Error("CNINFO retrieval clock was invalid"))
        Ok(master_response), Ok(master_retrieved_at) ->
          case
            current_security_reference.capture(
              input.code,
              master_response,
              master_retrieved_at,
            )
          {
            Error(error) ->
              promise.resolve(Error(
                "CNINFO security catalogue evidence was invalid: "
                <> string.inspect(error),
              ))
            Ok(reference) ->
              case
                reference
                |> current_security_reference.candidates
                |> identifier.resolve
                |> selection.select(input.organization_id)
              {
                Error(selection.NoCandidate) ->
                  promise.resolve(Error(
                    "CNINFO found no exact issuer candidate",
                  ))
                Error(selection.AmbiguousCandidates(count)) ->
                  promise.resolve(Error(
                    "CNINFO found "
                    <> int.to_string(count)
                    <> " exact-code issuers; supply organizationId",
                  ))
                Error(selection.OrganizationIdMismatch) ->
                  promise.resolve(Error(
                    "organizationId does not match the exact CNINFO code candidates",
                  ))
                Ok(security) ->
                  fetch_page(
                    runtime,
                    access,
                    input,
                    security,
                    reference,
                    id,
                    cancellation,
                  )
              }
          }
      }
    }
  }
}

fn fetch_page(
  runtime: discovery_runtime.Runtime,
  access: finance_cninfo.Access,
  input: Input,
  security: Security,
  reference: current_security_reference.Reference,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(
  Result(
    #(
      Security,
      current_security_reference.Reference,
      disclosure.Page,
      time.Instant,
      String,
      Int,
    ),
    String,
  ),
) {
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
    Error(_) -> promise.resolve(Error("CNINFO announcement query was invalid"))
    Ok(query) ->
      case request.announcements(access, query) {
        Error(_) ->
          promise.resolve(Error("CNINFO announcement request was invalid"))
        Ok(page_request) -> {
          use outcome <- promise.await(discovery_runtime.send(
            runtime,
            id: id <> "-announcements",
            request: page_request,
            cancellation: cancellation,
          ))
          case
            checked_response(outcome),
            time.instant(environment.now_milliseconds())
          {
            Error(message), _ -> promise.resolve(Error(message))
            _, Error(_) ->
              promise.resolve(Error("CNINFO retrieval clock was invalid"))
            Ok(response), Ok(retrieved_at) -> {
              let body = http_response.body(response)
              case disclosure.decode_page(body), hash.text(body) {
                Error(_), _ ->
                  promise.resolve(Error(
                    "CNINFO returned invalid announcement metadata",
                  ))
                _, Error(_) ->
                  promise.resolve(Error(
                    "CNINFO announcement response could not be hashed",
                  ))
                Ok(page), Ok(digest) ->
                  promise.resolve(
                    Ok(#(
                      security,
                      reference,
                      page,
                      retrieved_at,
                      identity.sha256_value(digest),
                      http_response.byte_length(response),
                    )),
                  )
              }
            }
          }
        }
      }
  }
}

fn checked_response(
  outcome: Result(http_response.Response, pool.PoolError),
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error(
        "CNINFO announcement request failed safely: " <> string.inspect(error),
      )
    Ok(response) ->
      case
        http_response.status(response) >= 200
        && http_response.status(response) < 300
      {
        True -> Ok(response)
        False ->
          Error(
            "CNINFO announcement request returned HTTP "
            <> int.to_string(http_response.status(response)),
          )
      }
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Optional(
      "organizationId",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Required(
      "startDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "endDate",
      schema.string() |> schema.with_string_length(10, 10),
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

fn input_decoder() -> decode.Decoder(Input) {
  use track <- decode.field("track", decode.string)
  use code <- decode.field("code", decode.string)
  use organization_id <- optional_string("organizationId")
  use start_text <- decode.field("startDate", decode.string)
  use end_text <- decode.field("endDate", decode.string)
  use category_text <- decode.optional_field("category", "all", decode.string)
  use page <- decode.optional_field("page", 1, decode.int)
  use page_size <- decode.optional_field("pageSize", 20, decode.int)
  let assert Ok(placeholder_date) = time.date(2000, 1, 1)
  let placeholder =
    Input(
      "000001",
      None,
      placeholder_date,
      placeholder_date,
      disclosure.All,
      1,
      20,
    )
  case
    track == "cn",
    valid_code(code),
    parse_date(start_text),
    parse_date(end_text),
    disclosure.category_from_name(category_text),
    page >= 1 && page <= 1000,
    page_size >= 1 && page_size <= 30
  {
    True, True, Ok(start), Ok(end), Ok(category), True, True ->
      case
        disclosure.query(
          code: code,
          organization_id: case organization_id {
            Some(value) -> value
            None -> "placeholder"
          },
          start_date: start,
          end_date: end,
          category: category,
          page: page,
          page_size: page_size,
        )
      {
        Ok(_) ->
          decode.success(Input(
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
              decode.success(Input(
                code,
                None,
                start,
                end,
                category,
                page,
                page_size,
              ))
            Some(_) ->
              decode.failure(placeholder, "valid CNINFO organizationId")
          }
        Error(_) -> decode.failure(placeholder, "valid bounded CNINFO query")
      }
    _, _, _, _, _, _, _ ->
      decode.failure(placeholder, "valid CN announcement query")
  }
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
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

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn summary(security: Security, page: disclosure.Page) -> String {
  "CN | CNINFO official repository | "
  <> security_master.code(security)
  <> " "
  <> security_master.short_name(security)
  <> " | page records "
  <> int.to_string(list.length(disclosure.announcements(page)))
  <> " / total "
  <> int.to_string(disclosure.total_announcements(page))
}

fn details(
  security: Security,
  reference: current_security_reference.Reference,
  input: Input,
  page: disclosure.Page,
  retrieved_at: time.Instant,
  digest: String,
  byte_length: Int,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/cn-stock-announcement-search")),
    #("schemaVersion", json.int(1)),
    #("track", json.string("cn")),
    #("marketScope", json.string("exact_cninfo_issuer_announcement_repository")),
    #("provider", json.string("CNINFO")),
    #(
      "source",
      json.string(request.discovery_origin <> request.announcement_query_path),
    ),
    #(
      "access",
      json.string("read_only_public_local_analysis_no_redistribution"),
    ),
    #("code", json.string(security_master.code(security))),
    #("organizationId", json.string(security_master.organization_id(security))),
    #("shortName", json.string(security_master.short_name(security))),
    #("category", json.string(disclosure.category_name(input.category))),
    #("page", json.int(input.page)),
    #("pageSize", json.int(input.page_size)),
    #("totalAnnouncements", json.int(disclosure.total_announcements(page))),
    #("totalPages", json.int(disclosure.total_pages(page))),
    #("hasMore", json.bool(disclosure.has_more(page))),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(time.unix_milliseconds(retrieved_at)),
    ),
    #("responseByteLength", json.int(byte_length)),
    #("responseContentSha256", json.string(digest)),
    #("identityReceipt", identity_receipt(reference)),
    #(
      "announcements",
      json.array(disclosure.announcements(page), announcement_json),
    ),
    #(
      "limitations",
      json.array(
        [
          "repository_listing_does_not_prove_exchange_origin_or_materiality",
          "provider_time_semantics_are_not_exchange_authenticated",
          "no_match_does_not_prove_repository_completeness",
          "document_body_ocr_translation_and_summary_are_not_performed",
        ],
        json.string,
      ),
    ),
  ])
}

fn identity_receipt(reference) {
  json.object([
    #("schema", json.string(current_security_reference.schema)),
    #("schemaVersion", json.int(current_security_reference.schema_version)),
    #("authorityId", json.string(current_security_reference.authority_id)),
    #(
      "canonicalDigest",
      json.string(current_security_reference.canonical_digest(reference)),
    ),
    #(
      "sourceReference",
      json.string(current_security_reference.source_reference(reference)),
    ),
    #(
      "retrievedAtUnixMilliseconds",
      json.int(
        time.unix_milliseconds(current_security_reference.retrieved_at(
          reference,
        )),
      ),
    ),
    #(
      "resolution",
      json.string(current_security_reference.resolution(reference)),
    ),
    #("providerAuthenticated", json.bool(False)),
  ])
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
    #("titleZhCn", json.string(disclosure.announcement_title(value))),
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
    #("typeCodes", case disclosure.announcement_type_codes(value) {
      Some(value) -> json.string(value)
      None -> json.null()
    }),
    #("reportPeriod", json.null()),
    #("correctionOf", json.null()),
    #("translation", json.null()),
  ])
}
