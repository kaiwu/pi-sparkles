import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time.{type Date, type Instant}
import finance_hkex.{type Board, Gem, MainBoard}
import finance_hkex/request
import finance_http/response.{type Response}
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const schema = "pi-sparkles/hkex-board-meeting-calendar-receipt"

pub const schema_version = 1

pub const authority_id = "hk_hkex_board_meeting_calendar"

pub type Event {
  Event(
    board_meeting_date: Date,
    short_name: String,
    source_code: String,
    code: String,
    purpose: String,
    period: String,
  )
}

pub type Page {
  Page(page_date: Date, board: Board, events: List(Event))
}

pub type Capture {
  Capture(
    page: Page,
    source_reference: String,
    retrieved_at: Instant,
    evidence_id: String,
    source_fingerprint: String,
    media_type: String,
    response_byte_length: Int,
    content_sha256: String,
    canonical_digest: String,
  )
}

pub type DecodeError {
  InvalidEnvelope
  InvalidPageDate
  HeaderMismatch
  InvalidEventRow
  TooManyRows(maximum: Int)
}

pub type CaptureError {
  InvalidSnapshot(snapshot.CaptureError)
  InvalidPage(DecodeError)
  InvalidDigest(identity.IdentityError)
}

pub fn decode(body: String, board: Board) -> Result(Page, DecodeError) {
  use Nil <- result.try(validate_envelope(body))
  use page_date <- result.try(parse_page_date(body))
  use table <- result.try(
    between(body, "<table class=textfont>", "</table>")
    |> result.map_error(fn(_) { InvalidEnvelope }),
  )
  use Nil <- result.try(validate_headers(table))
  use events <- result.try(
    table
    |> string.split("<tr>")
    |> list.filter(fn(row) { string.contains(row, "<td width=75 valign=top>") })
    |> list.try_map(parse_event)
    |> result.map_error(fn(_) { InvalidEventRow }),
  )
  case list.length(events) <= 5000 {
    True -> Ok(Page(page_date, board, events))
    False -> Error(TooManyRows(5000))
  }
}

pub fn capture(
  board board_value: Board,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(Capture, CaptureError) {
  use captured <- result.try(
    snapshot.capture(
      policy(board_value),
      response_value,
      as_of: retrieved_at_value,
      retrieved_at: retrieved_at_value,
    )
    |> result.map_error(InvalidSnapshot),
  )
  use page <- result.try(
    decode(snapshot.body(captured), board_value)
    |> result.map_error(InvalidPage),
  )
  let evidence = snapshot.evidence(captured)
  let source_reference = captured |> snapshot.source |> source.reference
  let evidence_id = evidence.id |> identity.evidence_id_value
  let source_fingerprint =
    evidence.source_fingerprint |> identity.source_fingerprint_value
  let content_sha256 = evidence.content_hash |> identity.sha256_value
  use digest <- result.try(
    canonical_text(
      page,
      source_reference,
      retrieved_at_value,
      evidence_id,
      source_fingerprint,
      evidence.media_type,
      evidence.byte_length,
      content_sha256,
    )
    |> hash.text
    |> result.map_error(InvalidDigest),
  )
  Ok(Capture(
    page,
    source_reference,
    retrieved_at_value,
    evidence_id,
    source_fingerprint,
    evidence.media_type,
    evidence.byte_length,
    content_sha256,
    identity.sha256_value(digest),
  ))
}

fn validate_envelope(body: String) -> Result(Nil, DecodeError) {
  case
    string.contains(body, "Board Meeting Notifications"),
    string.contains(
      body,
      "consolidated list of board meeting dates<br/>announced by listed issuers",
    ),
    string.contains(body, "This list may not be exhaustive"),
    string.contains(body, "only the start date of the board meeting")
  {
    True, True, True, True -> Ok(Nil)
    _, _, _, _ -> Error(InvalidEnvelope)
  }
}

fn validate_headers(table: String) -> Result(Nil, DecodeError) {
  case
    string.contains(table, ">BM Date</font>"),
    string.contains(table, ">Stock Short Name<td>"),
    string.contains(table, ">&nbsp;Code</font>"),
    string.contains(table, ">Purpose</font>"),
    string.contains(table, ">Period</font>")
  {
    True, True, True, True, True -> Ok(Nil)
    _, _, _, _, _ -> Error(HeaderMismatch)
  }
}

fn parse_page_date(body: String) -> Result(Date, DecodeError) {
  use raw <- result.try(
    between(body, "Date : ", "<br/>")
    |> result.map_error(fn(_) { InvalidPageDate }),
  )
  parse_date(raw) |> result.map_error(fn(_) { InvalidPageDate })
}

fn parse_event(row: String) -> Result(Event, Nil) {
  use cells <- result.try(
    row
    |> string.split("<td")
    |> list.drop(1)
    |> list.try_map(fn(fragment) {
      use content <- result.try(between(fragment, ">", "</td>"))
      html_text(content)
    }),
  )
  case cells {
    [raw_date, "", short_name, source_code, purpose, period] -> {
      use board_meeting_date <- result.try(parse_date(raw_date))
      use code <- result.try(normalize_code(source_code))
      case
        valid_text(short_name, 200),
        valid_text(purpose, 200),
        valid_optional_text(period, 200)
      {
        True, True, True ->
          Ok(Event(
            board_meeting_date,
            short_name,
            source_code,
            code,
            purpose,
            period,
          ))
        _, _, _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn normalize_code(value: String) -> Result(String, Nil) {
  let size = string.length(value)
  case
    size >= 1 && size <= 5,
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789", character) })
  {
    True, True -> Ok(string.repeat("0", times: 5 - size) <> value)
    _, _ -> Error(Nil)
  }
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "/") {
    [day_text, month_text, year_text] ->
      case
        int.parse(day_text),
        int.parse(month_text),
        int.parse(year_text),
        string.length(day_text),
        string.length(month_text),
        string.length(year_text)
      {
        Ok(day), Ok(month), Ok(year), 2, 2, 4 ->
          time.date(year, month, day) |> result.map_error(fn(_) { Nil })
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn html_text(value: String) -> Result(String, Nil) {
  case string.split(value, "<") {
    [] -> Ok("")
    [plain, ..tagged] -> {
      use tails <- result.try(
        list.try_map(tagged, fn(fragment) {
          case string.split_once(fragment, on: ">") {
            Ok(#(_, text)) -> Ok(text)
            Error(_) -> Error(Nil)
          }
        }),
      )
      [plain, ..tails]
      |> string.join("")
      |> string.replace("&amp;", "&")
      |> string.replace("&quot;", "\"")
      |> string.replace("&#x27;", "'")
      |> string.replace("&lt;", "<")
      |> string.replace("&gt;", ">")
      |> string.replace("&nbsp;", " ")
      |> normalize_text
      |> Ok
    }
  }
}

fn normalize_text(value: String) -> String {
  value
  |> string.replace("\r", " ")
  |> string.replace("\n", " ")
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(item) { item != "" })
  |> string.join(" ")
  |> string.trim
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != "" && string.trim(value) == value && string.length(value) <= maximum
}

fn valid_optional_text(value: String, maximum: Int) -> Bool {
  string.trim(value) == value && string.length(value) <= maximum
}

fn policy(board: Board) -> snapshot.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "HKEX",
      reference: source_reference(board),
      kind: source.Exchange,
    )
  let assert Ok(value) =
    snapshot.local_analysis_policy(
      track: finance_track.Hk,
      authority_id: authority_id,
      source: source_ref,
      allowed_media_types: ["text/html", "application/xhtml+xml"],
      maximum_bytes: 2_000_000,
    )
  value
}

fn source_reference(board: Board) -> String {
  request.board_meeting_origin
  <> case board {
    MainBoard -> request.main_board_meetings_path
    Gem -> request.gem_board_meetings_path
  }
}

fn canonical_text(
  page: Page,
  source_reference: String,
  retrieved_at: Instant,
  evidence_id: String,
  source_fingerprint: String,
  media_type: String,
  response_byte_length: Int,
  content_sha256: String,
) -> String {
  json.object([
    #("schema", json.string(schema)),
    #("schema_version", json.int(schema_version)),
    #("track", json.string("hk")),
    #("venue_mic", json.string("XHKG")),
    #("authority_id", json.string(authority_id)),
    #("provider", json.string("HKEX")),
    #("board", json.string(board_name(page.board))),
    #("source_reference", json.string(source_reference)),
    #("page_date", json.string(date_text(page.page_date))),
    #(
      "retrieved_at_unix_ms",
      retrieved_at |> time.unix_milliseconds |> int.to_string |> json.string,
    ),
    #("evidence_id", json.string(evidence_id)),
    #("source_fingerprint", json.string(source_fingerprint)),
    #("media_type", json.string(media_type)),
    #("response_byte_length", json.int(response_byte_length)),
    #("content_sha256", json.string(content_sha256)),
    #("events", json.array(page.events, event_json)),
    #("completeness", json.string("not_exhaustive_reference_only")),
    #("meeting_date_semantics", json.string("start_date_only")),
    #("publication_timestamp_claim", json.null()),
  ])
  |> json.to_string
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("board_meeting_date", json.string(date_text(value.board_meeting_date))),
    #("short_name", json.string(value.short_name)),
    #("source_code", json.string(value.source_code)),
    #("code", json.string(value.code)),
    #("purpose", json.string(value.purpose)),
    #("period", json.string(value.period)),
  ])
}

fn board_name(value: Board) -> String {
  case value {
    MainBoard -> "main"
    Gem -> "gem"
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn after(value: String, marker: String) -> Result(String, Nil) {
  case string.split_once(value, on: marker) {
    Ok(#(_, rest)) -> Ok(rest)
    Error(_) -> Error(Nil)
  }
}

fn between(
  value: String,
  start: String,
  finish: String,
) -> Result(String, Nil) {
  use rest <- result.try(after(value, start))
  case string.split_once(rest, on: finish) {
    Ok(#(found, _)) -> Ok(found)
    Error(_) -> Error(Nil)
  }
}
