import finance_core/identifier
import finance_core/time
import finance_track
import finance_track/context
import finance_track/json as track_json
import finance_track/profile
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_track.status()
  |> should.equal(finance_track.Experimental)
}

pub fn track_identity_is_closed_and_strict_test() {
  [finance_track.Cn, finance_track.Hk, finance_track.Us]
  |> should.equal([
    parse("cn"),
    parse("hk"),
    parse("us"),
  ])
  finance_track.from_name("china")
  |> should.equal(Error(finance_track.UnknownTrack("china")))
  finance_track.from_name("global")
  |> should.equal(Error(finance_track.UnknownTrack("global")))
  finance_track.command_prefix(finance_track.Cn) |> should.equal("/cn-")
  finance_track.tool_prefix(finance_track.Hk) |> should.equal("hk_")
}

pub fn context_validates_track_scope_and_board_venue_test() {
  context.new(
    track: finance_track.Cn,
    market_scope: "us_sec_filings",
    venue_mic: None,
    board: None,
    timezone: Some(zone("Asia/Shanghai")),
    source_language: "zh-CN",
    providers: ["SSE"],
    entitlement: "public_reference_data",
    limitations: [],
  )
  |> should.equal(Error(context.MarketScopeTrackMismatch("cn_")))

  context.new(
    track: finance_track.Cn,
    market_scope: "cn_listings",
    venue_mic: None,
    board: Some("Main Board"),
    timezone: Some(zone("Asia/Shanghai")),
    source_language: "zh-CN",
    providers: ["SSE"],
    entitlement: "public_reference_data",
    limitations: [],
  )
  |> should.equal(Error(context.BoardRequiresVenue))
}

pub fn context_rejects_duplicate_metadata_test() {
  context.new(
    track: finance_track.Us,
    market_scope: "us_sec_filings",
    venue_mic: None,
    board: None,
    timezone: None,
    source_language: "en-US",
    providers: ["SEC", "SEC"],
    entitlement: "public_reference_data",
    limitations: [],
  )
  |> should.equal(Error(context.DuplicateProvider("SEC")))

  context.new(
    track: finance_track.Us,
    market_scope: "us_sec_filings",
    venue_mic: None,
    board: None,
    timezone: None,
    source_language: "en-US",
    providers: ["SEC"],
    entitlement: "public_reference_data",
    limitations: ["entity_wide_only", "entity_wide_only"],
  )
  |> should.equal(Error(context.DuplicateLimitation("entity_wide_only")))
}

pub fn every_track_context_round_trips_test() {
  let contexts = [
    make_context(
      finance_track.Cn,
      "cn_sse_main_board",
      Some(mic("XSHG")),
      Some("Main Board"),
      Some(zone("Asia/Shanghai")),
      "zh-CN",
      ["SSE"],
    ),
    make_context(
      finance_track.Hk,
      "hk_hkex_equities",
      Some(mic("XHKG")),
      Some("Main Board"),
      Some(zone("Asia/Hong_Kong")),
      "zh-HK",
      ["HKEX"],
    ),
    make_context(finance_track.Us, "us_sec_filings", None, None, None, "en-US", [
      "SEC EDGAR",
    ]),
  ]

  contexts
  |> list.each(fn(value) {
    value |> track_json.encode |> track_json.decode |> should.equal(Ok(value))
  })
}

pub fn json_rejects_unknown_track_test() {
  track_json.decode(
    "{\"schemaVersion\":1,\"track\":\"global\",\"marketScope\":\"us_test\",\"venueMic\":null,\"board\":null,\"timezone\":null,\"sourceLanguage\":\"en-US\",\"providers\":[\"test\"],\"entitlement\":\"unknown\",\"limitations\":[]}",
  )
  |> should.be_error
}

pub fn cross_track_leg_mapping_preserves_context_test() {
  let original =
    context.leg(
      make_context(
        finance_track.Hk,
        "hk_connect_leg",
        Some(mic("XHKG")),
        None,
        Some(zone("Asia/Hong_Kong")),
        "zh-HK",
        ["HKEX"],
      ),
      2,
    )
  context.map_leg(original, fn(value) { value * 3 })
  |> should.equal(context.Leg(original.context, 6))
}

pub fn active_track_profiles_are_visible_and_isolated_test() {
  let assert Ok(cn) =
    profile.defaults(finance_track.Cn, "research@example.test")
  let assert Ok(hk) =
    profile.defaults(finance_track.Hk, "research@example.test")
  let assert Ok(us) =
    profile.defaults(finance_track.Us, "research@example.test")

  profile.status_line(cn)
  |> should.equal("CN · CNY · Asia/Shanghai · agent:research@example.test")
  profile.status_line(hk)
  |> should.equal("HK · HKD · Asia/Hong_Kong · agent:research@example.test")
  profile.status_line(us)
  |> should.equal("US · USD · America/New_York · agent:research@example.test")
  profile.defaults(finance_track.Cn, "bad\ncontact")
  |> should.equal(Error(profile.InvalidAgentContact))
}

fn make_context(
  track: finance_track.Track,
  scope: String,
  venue: Option(identifier.Mic),
  board: Option(String),
  timezone: Option(time.Timezone),
  language: String,
  providers: List(String),
) -> context.Context {
  let assert Ok(value) =
    context.new(
      track: track,
      market_scope: scope,
      venue_mic: venue,
      board: board,
      timezone: timezone,
      source_language: language,
      providers: providers,
      entitlement: "public_reference_data",
      limitations: ["fixture_only"],
    )
  value
}

fn parse(value: String) -> finance_track.Track {
  let assert Ok(value) = finance_track.from_name(value)
  value
}

fn mic(value: String) -> identifier.Mic {
  let assert Ok(value) = identifier.mic(value)
  value
}

fn zone(value: String) -> time.Timezone {
  let assert Ok(value) = time.timezone(value)
  value
}
