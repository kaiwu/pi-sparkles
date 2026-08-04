import finance_core/time
import finance_http/request
import finance_sec.{type Access, type Cik}
import finance_sec/xbrl.{type ConceptId}
import gleam/option.{None}
import gleam/result

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_sec.AccessError)
}

pub fn company_tickers(
  access: Access,
) -> Result(request.Request, RequestError) {
  build(access, "https://www.sec.gov", "/files/company_tickers.json", 2_000_000)
}

pub fn submissions(
  access: Access,
  cik: Cik,
) -> Result(request.Request, RequestError) {
  build(
    access,
    "https://data.sec.gov",
    "/submissions/CIK" <> finance_sec.cik_value(cik) <> ".json",
    5_000_000,
  )
}

pub fn company_facts(
  access: Access,
  cik: Cik,
) -> Result(request.Request, RequestError) {
  build(
    access,
    "https://data.sec.gov",
    "/api/xbrl/companyfacts/CIK" <> finance_sec.cik_value(cik) <> ".json",
    20_000_000,
  )
}

pub fn company_concept(
  access: Access,
  cik: Cik,
  concept: ConceptId,
) -> Result(request.Request, RequestError) {
  build(
    access,
    "https://data.sec.gov",
    "/api/xbrl/companyconcept/CIK"
      <> finance_sec.cik_value(cik)
      <> "/"
      <> xbrl.taxonomy(concept)
      <> "/"
      <> xbrl.tag(concept)
      <> ".json",
    5_000_000,
  )
}

fn build(
  access: Access,
  origin: String,
  path: String,
  maximum_bytes: Int,
) -> Result(request.Request, RequestError) {
  use base <- result.try(
    request.new(
      method: request.Get,
      origin: origin,
      path: path,
      idempotency_key: None,
    )
    |> result.map_error(InvalidHttp),
  )
  let assert Ok(timeout) = time.duration(15_000)
  use bounded <- result.try(
    request.with_limits(
      base,
      timeout: timeout,
      maximum_response_bytes: maximum_bytes,
    )
    |> result.map_error(InvalidHttp),
  )
  finance_sec.authorize(access, bounded) |> result.map_error(InvalidAccess)
}
