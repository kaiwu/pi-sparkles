import finance_core/identifier
import finance_core/time
import finance_http/request
import finance_openfigi.{type Access}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type IdType {
  Ticker
  Figi
  CompositeFigi
  Isin
  Cusip
  Sedol
}

pub opaque type Job {
  Job(id_type: IdType, id_value: String, mic_code: Option(String))
}

pub type JobError {
  EmptyIdentifier
  InvalidMic
  UnsupportedIdType
}

pub type RequestError {
  EmptyBatch
  BatchTooLarge(actual: Int, maximum: Int)
  InvalidHttpRequest(request.RequestError)
  InvalidAccess(finance_openfigi.AccessError)
}

pub fn id_type(name: String) -> Result(IdType, JobError) {
  case name {
    "TICKER" -> Ok(Ticker)
    "ID_BB_GLOBAL" -> Ok(Figi)
    "COMPOSITE_ID_BB_GLOBAL" -> Ok(CompositeFigi)
    "ID_ISIN" -> Ok(Isin)
    "ID_CUSIP" -> Ok(Cusip)
    "ID_SEDOL" -> Ok(Sedol)
    _ -> Error(UnsupportedIdType)
  }
}

pub fn id_type_name(value: IdType) -> String {
  case value {
    Ticker -> "TICKER"
    Figi -> "ID_BB_GLOBAL"
    CompositeFigi -> "COMPOSITE_ID_BB_GLOBAL"
    Isin -> "ID_ISIN"
    Cusip -> "ID_CUSIP"
    Sedol -> "ID_SEDOL"
  }
}

pub fn job(
  id_type id_type_value: IdType,
  id_value id_value: String,
  mic_code mic_code: Option(String),
) -> Result(Job, JobError) {
  case string.trim(id_value) {
    "" -> Error(EmptyIdentifier)
    value -> {
      use normalized_mic <- result.try(validate_mic(mic_code))
      Ok(Job(id_type_value, value, normalized_mic))
    }
  }
}

pub fn request(
  access: Access,
  jobs: List(Job),
) -> Result(request.Request, RequestError) {
  let maximum =
    finance_openfigi.limits(access, finance_openfigi.Mapping).maximum_mapping_jobs
  let count = list.length(jobs)
  case count == 0, count > maximum {
    True, _ -> Error(EmptyBatch)
    _, True -> Error(BatchTooLarge(count, maximum))
    False, False -> {
      let body = jobs |> json.array(job_json) |> json.to_string
      build_request(access, body)
    }
  }
}

fn build_request(
  access: Access,
  body: String,
) -> Result(request.Request, RequestError) {
  use base <- result.try(
    request.new(
      method: request.Post,
      origin: finance_openfigi.origin,
      path: "/v3/mapping",
      idempotency_key: None,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  use repeatable <- result.try(
    request.as_repeatable_read(base)
    |> result.map_error(InvalidHttpRequest),
  )
  use with_body <- result.try(
    request.with_text_body(
      repeatable,
      content_type: "application/json",
      value: body,
      safe_variant: "openfigi-v3-mapping:" <> body,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  let assert Ok(timeout) = time.duration(10_000)
  use bounded <- result.try(
    request.with_limits(
      with_body,
      timeout: timeout,
      maximum_response_bytes: 500_000,
    )
    |> result.map_error(InvalidHttpRequest),
  )
  finance_openfigi.authorize(access, bounded)
  |> result.map_error(InvalidAccess)
}

fn job_json(value: Job) -> json.Json {
  let Job(id_type_value, id_value, mic_code) = value
  [
    #("idType", id_type_value |> id_type_name |> json.string),
    #("idValue", json.string(id_value)),
  ]
  |> list.append(optional_property("micCode", mic_code))
  |> json.object
}

fn validate_mic(value: Option(String)) -> Result(Option(String), JobError) {
  case value {
    None -> Ok(None)
    Some(value) ->
      case identifier.mic(value) {
        Error(_) -> Error(InvalidMic)
        Ok(value) -> Ok(Some(identifier.mic_value(value)))
      }
  }
}

fn optional_property(
  name: String,
  value: Option(String),
) -> List(#(String, json.Json)) {
  case value {
    Some(value) -> [#(name, json.string(value))]
    None -> []
  }
}
