import finance_track
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_watchlist/watchlist

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn add_update_remove_is_exact_and_revisioned_test() {
  let input = member(finance_track.Us, "figi:BBG000B9XRY4", "AAPL", "XNAS")
  let assert Ok(#(one, watchlist.Added(added))) =
    watchlist.add(watchlist.empty(), "core", input)
  watchlist.revision(one) |> should.equal(1)
  watchlist.member_key(added)
  |> should.equal("us|XNAS|AAPL|figi:BBG000B9XRY4")
  watchlist.member_tags(added) |> should.equal(["quality", "us-tech"])

  let assert Ok(#(unchanged, watchlist.Unchanged(_))) =
    watchlist.add(one, "core", input)
  watchlist.revision(unchanged) |> should.equal(1)

  let updated_input =
    watchlist.MemberInput(
      finance_track.Us,
      "figi:BBG000B9XRY4",
      "AAPL",
      "XNAS",
      Some("Reviewed after filing"),
      Some("https://research.example.test/aapl"),
      ["updated"],
    )
  let assert Ok(#(two, watchlist.Updated(updated))) =
    watchlist.add(unchanged, "core", updated_input)
  watchlist.revision(two) |> should.equal(2)
  watchlist.member_note(updated) |> should.equal(Some("Reviewed after filing"))

  let identity =
    watchlist.IdentityInput(
      finance_track.Us,
      "figi:BBG000B9XRY4",
      "AAPL",
      "XNAS",
    )
  let assert Ok(#(three, watchlist.Removed(removed))) =
    watchlist.remove(two, "core", identity)
  watchlist.member_key(removed)
  |> should.equal("us|XNAS|AAPL|figi:BBG000B9XRY4")
  watchlist.revision(three) |> should.equal(3)
  watchlist.watchlists(three) |> should.equal([])
}

pub fn identity_and_metadata_validation_fail_closed_test() {
  watchlist.add(
    watchlist.empty(),
    "Core",
    member(finance_track.Us, "figi:BBG000B9XRY4", "AAPL", "XNAS"),
  )
  |> should.equal(Error(watchlist.InvalidWatchlistName))

  watchlist.add(
    watchlist.empty(),
    "core",
    member(finance_track.Us, "BBG000B9XRY4", "AAPL", "XNAS"),
  )
  |> should.equal(Error(watchlist.InvalidInstrumentId))

  watchlist.add(
    watchlist.empty(),
    "core",
    member(finance_track.Us, "figi:BBG000B9XRY4", "aapl", "XNAS"),
  )
  |> should.equal(Error(watchlist.InvalidSymbol))

  watchlist.add(
    watchlist.empty(),
    "core",
    member(finance_track.Cn, "cninfo:000001", "000001", "XNAS"),
  )
  |> should.equal(Error(watchlist.TrackMicMismatch("cn", "XNAS")))

  watchlist.add(
    watchlist.empty(),
    "core",
    member(finance_track.Hk, "hkex:700", "700", "XHKG"),
  )
  |> should.equal(Error(watchlist.InvalidTrackSymbol("hk", "700")))

  let unsafe_link =
    watchlist.MemberInput(
      finance_track.Us,
      "figi:BBG000B9XRY4",
      "AAPL",
      "XNAS",
      None,
      Some("javascript:alert(1)"),
      [],
    )
  watchlist.add(watchlist.empty(), "core", unsafe_link)
  |> should.equal(Error(watchlist.InvalidThesisLink))

  let duplicate_tags =
    watchlist.MemberInput(
      finance_track.Us,
      "figi:BBG000B9XRY4",
      "AAPL",
      "XNAS",
      None,
      None,
      ["quality", "quality"],
    )
  watchlist.add(watchlist.empty(), "core", duplicate_tags)
  |> should.equal(Error(watchlist.DuplicateTag("quality")))
}

pub fn versioned_events_replay_the_exact_branch_state_test() {
  let us = member(finance_track.Us, "figi:BBG000B9XRY4", "AAPL", "XNAS")
  let cn = member(finance_track.Cn, "cninfo:000001", "000001", "XSHE")
  let assert Ok(#(one, watchlist.Added(us_member))) =
    watchlist.add(watchlist.empty(), "core", us)
  let first =
    watchlist.event_for_add(one, "core", us_member)
    |> watchlist.encode_event
  let assert Ok(#(two, watchlist.Added(cn_member))) =
    watchlist.add(one, "asia", cn)
  let second =
    watchlist.event_for_add(two, "asia", cn_member)
    |> watchlist.encode_event

  watchlist.replay([first, second]) |> should.equal(Ok(two))

  let skipped =
    watchlist.AddEvent(3, "asia", cn)
    |> watchlist.encode_event
  watchlist.replay([first, skipped])
  |> should.equal(Error(watchlist.NonContiguousRevision(2, 3)))

  watchlist.replay([first, "not json"])
  |> should.equal(Error(watchlist.InvalidEventJson))
}

pub fn deterministic_snapshot_keeps_track_legs_separate_test() {
  let assert Ok(#(one, _)) =
    watchlist.add(
      watchlist.empty(),
      "us_focus",
      member(finance_track.Us, "figi:BBG000B9XRY4", "AAPL", "XNAS"),
    )
  let assert Ok(#(two, _)) =
    watchlist.add(
      one,
      "asia",
      member(finance_track.Hk, "hkex:00700", "00700", "XHKG"),
    )
  let encoded = watchlist.encode_snapshot(two, watchlist.watchlists(two))
  string.contains(encoded, "\"revision\":2") |> should.be_true
  string.contains(encoded, "\"name\":\"asia\"") |> should.be_true
  string.contains(encoded, "\"track\":\"hk\"") |> should.be_true
  string.contains(encoded, "\"track\":\"us\"") |> should.be_true
  string.contains(encoded, "\"identityStatus\":\"caller_declared_unverified\"")
  |> should.be_true
}

fn member(
  track: finance_track.Track,
  instrument_id: String,
  symbol: String,
  mic: String,
) -> watchlist.MemberInput {
  watchlist.MemberInput(track, instrument_id, symbol, mic, None, None, [
    "us-tech",
    "quality",
  ])
}
