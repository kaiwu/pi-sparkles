import finance_core/time.{type Date}
import finance_hkex.{type Board, Gem, MainBoard}
import finance_hkex/board_meeting.{type Capture, type Event}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Plan {
  Plan(board: Board, code: String, start_date: Date, end_date: Date)
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack(received: String)
  WrongVenue(received: String)
  InvalidBoard(received: String)
  InvalidCode
  InvalidStartDate
  InvalidEndDate
  ReversedRange
  MismatchedBoard
}

pub fn plan(
  track: String,
  venue: String,
  board: String,
  code: String,
  start_date: String,
  end_date: String,
) -> Result(Plan, Error) {
  use Nil <- result.try(case track {
    "hk" -> Ok(Nil)
    value -> Error(WrongTrack(value))
  })
  use Nil <- result.try(case venue {
    "XHKG" -> Ok(Nil)
    value -> Error(WrongVenue(value))
  })
  use board_value <- result.try(case board {
    "main" -> Ok(MainBoard)
    "gem" -> Ok(Gem)
    value -> Error(InvalidBoard(value))
  })
  use start <- result.try(
    parse_date(start_date) |> result.map_error(fn(_) { InvalidStartDate }),
  )
  use end <- result.try(
    parse_date(end_date) |> result.map_error(fn(_) { InvalidEndDate }),
  )
  case valid_code(code), date_key(start) <= date_key(end) {
    False, _ -> Error(InvalidCode)
    _, False -> Error(ReversedRange)
    True, True -> Ok(Plan(board_value, code, start, end))
  }
}

pub fn run(plan: Plan, captured: Capture) -> Result(Output, Error) {
  case captured.page.board == plan.board {
    False -> Error(MismatchedBoard)
    True -> {
      let source_rows =
        captured.page.events
        |> list.filter(fn(event) {
          event.code == plan.code
          && date_key(event.board_meeting_date) >= date_key(plan.start_date)
          && date_key(event.board_meeting_date) <= date_key(plan.end_date)
        })
      let events = list.filter(source_rows, results_marker_present)
      let excluded =
        list.filter(source_rows, fn(event) { !results_marker_present(event) })
      let next_date = earliest_date(events)
      Ok(Output(
        render_summary(plan, events, excluded, next_date),
        json.object([
          #("schema", json.string("pi-sparkles/stock-earnings-calendar-result")),
          #("schemaVersion", json.int(1)),
          #("operation", json.string("earnings_calendar")),
          #("track", json.string("hk")),
          #("venue", json.string("XHKG")),
          #("timezone", json.string("Asia/Hong_Kong")),
          #(
            "query",
            json.object([
              #("board", json.string(board_name(plan.board))),
              #("code", json.string(plan.code)),
              #("startDate", json.string(date_text(plan.start_date))),
              #("endDate", json.string(date_text(plan.end_date))),
            ]),
          ),
          #("resolution", json.string(resolution(events))),
          #("nextBoardMeetingDate", option_date_json(next_date)),
          #("matchedCount", json.int(list.length(events))),
          #("excludedSourceRowCount", json.int(list.length(excluded))),
          #("events", json.array(events, event_json)),
          #("excludedSourceRows", json.array(excluded, excluded_json)),
          #(
            "selectionRule",
            json.object([
              #("name", json.string("hkex_result_purpose_marker_v1")),
              #(
                "acceptedPurposeMarkers",
                json.array(
                  ["RESULTS", "INT RES", "FIN RES", "QUARTER RES"],
                  json.string,
                ),
              ),
              #(
                "unknownPurposeHandling",
                json.string("preserve_as_excluded_source_row"),
              ),
            ]),
          ),
          #(
            "source",
            json.object([
              #("provider", json.string("HKEX")),
              #("kind", json.string("exchange")),
              #("reference", json.string(captured.source_reference)),
              #("pageDate", json.string(date_text(captured.page.page_date))),
              #(
                "retrievedAtUnixMs",
                captured.retrieved_at
                  |> time.unix_milliseconds
                  |> int.to_string
                  |> json.string,
              ),
              #("evidenceId", json.string(captured.evidence_id)),
              #("sourceFingerprint", json.string(captured.source_fingerprint)),
              #("mediaType", json.string(captured.media_type)),
              #("responseByteLength", json.int(captured.response_byte_length)),
              #("contentSha256", json.string(captured.content_sha256)),
              #("canonicalDigest", json.string(captured.canonical_digest)),
              #(
                "licence",
                json.object([
                  #("label", json.string("official-public-local-analysis-only")),
                  #("redistribution", json.string("no_redistribution")),
                ]),
              ),
            ]),
          ),
          #(
            "scope",
            json.object([
              #("eventKind", json.string("issuer_announced_board_meeting")),
              #(
                "confirmationStatus",
                json.string("issuer_announced_board_meeting_date"),
              ),
              #("meetingDateSemantics", json.string("start_date_only")),
              #("publicationTimestamp", json.null()),
              #("completeness", json.string("not_exhaustive_reference_only")),
              #("absenceClaim", json.bool(False)),
            ]),
          ),
          #(
            "limitations",
            json.array(
              [
                "A board-meeting date is not an earnings publication timestamp.",
                "The HKEX consolidated page may not be exhaustive and is for reference only.",
                "Only the start date is shown when a meeting spans more than one day.",
                "No-match does not prove absence; inspect the issuer announcement.",
                "Purpose-marker selection is mechanical and retains every excluded exact-code row.",
              ],
              json.string,
            ),
          ),
          #("decisionOwner", json.string("llm")),
          #("pluginDecisionFields", json.array([], json.string)),
        ]),
      ))
    }
  }
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack(received) ->
      "earnings_calendar supports exact track hk, received " <> received
    WrongVenue(received) ->
      "earnings_calendar supports exact venue XHKG, received " <> received
    InvalidBoard(received) ->
      "earnings_calendar board must be main or gem, received " <> received
    InvalidCode -> "earnings_calendar code must be exactly five digits"
    InvalidStartDate ->
      "earnings_calendar startDate must be canonical YYYY-MM-DD"
    InvalidEndDate -> "earnings_calendar endDate must be canonical YYYY-MM-DD"
    ReversedRange -> "earnings_calendar startDate must not follow endDate"
    MismatchedBoard ->
      "earnings_calendar captured page did not match the requested board"
  }
}

fn render_summary(
  plan: Plan,
  events: List(Event),
  excluded: List(Event),
  next_date: Option(Date),
) -> String {
  let heading =
    "HKEX result-related board meetings for "
    <> plan.code
    <> " ("
    <> board_name(plan.board)
    <> "): "
    <> int.to_string(list.length(events))
    <> " matched, "
    <> int.to_string(list.length(excluded))
    <> " exact-code source rows excluded by the visible purpose rule."
  let next = case next_date {
    Some(value) -> " Next meeting date in range: " <> date_text(value) <> "."
    None ->
      " No result-related row was found on this non-exhaustive reference page."
  }
  let rows = case events {
    [] -> ""
    values ->
      "\n\n| Board meeting date | Source code | Short name | Purpose | Period |\n|---|---|---|---|---|\n"
      <> {
        values
        |> list.map(fn(event) {
          "| "
          <> date_text(event.board_meeting_date)
          <> " | "
          <> event.source_code
          <> " | "
          <> event.short_name
          <> " | "
          <> event.purpose
          <> " | "
          <> event.period
          <> " |"
        })
        |> string.join("\n")
      }
  }
  heading
  <> next
  <> " Dates are issuer-announced board-meeting start dates, not publication timestamps."
  <> rows
}

fn results_marker_present(value: Event) -> Bool {
  string.starts_with(value.purpose, "RESULTS")
  || string.starts_with(value.purpose, "INT RES")
  || string.starts_with(value.purpose, "FIN RES")
  || string.contains(value.purpose, "QUARTER RES")
}

fn resolution(values: List(Event)) -> String {
  case values {
    [] -> "no_match_on_non_exhaustive_page"
    [_] -> "unique"
    [_, _, ..] -> "multiple_preserved"
  }
}

fn earliest_date(values: List(Event)) -> Option(Date) {
  values
  |> list.fold(from: None, with: fn(current, event) {
    case current {
      None -> Some(event.board_meeting_date)
      Some(date) ->
        case date_key(event.board_meeting_date) < date_key(date) {
          True -> Some(event.board_meeting_date)
          False -> current
        }
    }
  })
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("boardMeetingDate", json.string(date_text(value.board_meeting_date))),
    #("sourceCode", json.string(value.source_code)),
    #("code", json.string(value.code)),
    #("shortName", json.string(value.short_name)),
    #("purpose", json.string(value.purpose)),
    #("period", json.string(value.period)),
    #("resultsMarkerPresent", json.bool(True)),
    #("confirmationStatus", json.string("issuer_announced_board_meeting_date")),
    #("publicationTimestamp", json.null()),
  ])
}

fn excluded_json(value: Event) -> json.Json {
  json.object([
    #("boardMeetingDate", json.string(date_text(value.board_meeting_date))),
    #("sourceCode", json.string(value.source_code)),
    #("code", json.string(value.code)),
    #("shortName", json.string(value.short_name)),
    #("purpose", json.string(value.purpose)),
    #("period", json.string(value.period)),
    #("reason", json.string("purpose_marker_not_recognized_as_results")),
  ])
}

fn option_date_json(value: Option(Date)) -> json.Json {
  case value {
    Some(value) -> json.string(date_text(value))
    None -> json.null()
  }
}

fn board_name(value: Board) -> String {
  case value {
    MainBoard -> "main"
    Gem -> "gem"
  }
}

fn parse_date(value: String) -> Result(Date, Nil) {
  case string.split(value, "-") {
    [year_text, month_text, day_text] ->
      case
        int.parse(year_text),
        int.parse(month_text),
        int.parse(day_text),
        string.length(year_text),
        string.length(month_text),
        string.length(day_text)
      {
        Ok(year), Ok(month), Ok(day), 4, 2, 2 ->
          time.date(year, month, day) |> result.map_error(fn(_) { Nil })
        _, _, _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn date_key(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
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
