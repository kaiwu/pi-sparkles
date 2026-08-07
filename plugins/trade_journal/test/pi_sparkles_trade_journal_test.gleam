import finance_core/time
import finance_journal/event
import finance_journal/information
import finance_journal/state
import finance_provenance/identity
import finance_track
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_trade_journal/domain
import pi_sparkles_trade_journal/render

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_user_declaration_keeps_identity_and_attribution_test() {
  let assert Ok(value) = domain.build_event(exact_entry())
  event.attribution(value)
  |> should.equal(event.UserDeclared("user-local"))
  case value |> event.scope |> event.identity_scope {
    event.ExactListing(
      finance_track.Cn,
      "cn-listing-1",
      "XSHG",
      information.Known("600000"),
    ) -> Nil
    _ -> should.fail()
  }
}

pub fn unresolved_identity_keeps_absent_slots_unknown_test() {
  let domain.EntryData(
    journal,
    id,
    kind,
    _,
    workflow,
    position,
    review,
    attribution,
    stage,
    payload,
    occurrence,
    recording,
    timezone,
    privacy,
    references,
    supersedes,
    imported,
    key,
  ) = exact_entry()
  let input =
    domain.EntryData(
      journal,
      id,
      kind,
      domain.IdentityInput("unresolved_listing", None, None, None, None),
      workflow,
      position,
      review,
      attribution,
      stage,
      payload,
      occurrence,
      recording,
      timezone,
      privacy,
      references,
      supersedes,
      imported,
      key,
    )
  let assert Ok(value) = domain.build_event(input)
  case value |> event.scope |> event.identity_scope {
    event.UnresolvedListing(
      information.Unknown("track_not_supplied"),
      information.Unknown("listing_id_not_supplied"),
      information.Unknown("mic_not_supplied"),
      information.Unknown("symbol_not_supplied"),
    ) -> Nil
    _ -> should.fail()
  }
}

pub fn attribution_shape_rejects_fields_that_would_be_silently_dropped_test() {
  let domain.EntryData(
    journal,
    id,
    kind,
    identity,
    workflow,
    position,
    review,
    _,
    stage,
    payload,
    occurrence,
    recording,
    timezone,
    privacy,
    references,
    supersedes,
    imported,
    key,
  ) = exact_entry()
  let input =
    domain.EntryData(
      journal,
      id,
      kind,
      identity,
      workflow,
      position,
      review,
      domain.AttributionInput(
        "user_declared",
        Some("user-local"),
        None,
        None,
        Some(hash()),
      ),
      stage,
      payload,
      occurrence,
      recording,
      timezone,
      privacy,
      references,
      supersedes,
      imported,
      key,
    )
  domain.build_event(input)
  |> should.equal(Error(domain.InvalidAttributionShape("user_declared")))
}

pub fn private_search_projection_omits_payload_without_explicit_request_test() {
  let assert Ok(value) = domain.build_event(exact_entry())
  let assert Ok(#(journal, _)) = state.append(state.empty(), value)
  let result = state.query(journal, state.Query(None, [], [], [], True, 10))
  let rendered = render.search_json(journal, result, False) |> json.to_string
  rendered |> string.contains("payload_omitted\":true") |> should.be_true
  rendered |> string.contains("user prose") |> should.be_false
}

pub fn explicit_private_search_projection_returns_exact_event_test() {
  let assert Ok(value) = domain.build_event(exact_entry())
  let assert Ok(#(journal, _)) = state.append(state.empty(), value)
  let result = state.query(journal, state.Query(None, [], [], [], True, 10))
  let rendered = render.search_json(journal, result, True) |> json.to_string
  rendered |> string.contains("user prose") |> should.be_true
  rendered |> string.contains("canonical_content_hash") |> should.be_true
}

fn exact_entry() -> domain.EntryData {
  domain.EntryData(
    "journal-main",
    "event-1",
    "declaration",
    domain.IdentityInput(
      "exact_listing",
      Some(finance_track.Cn),
      Some("cn-listing-1"),
      Some("XSHG"),
      Some("600000"),
    ),
    Some("workflow-1"),
    None,
    None,
    domain.AttributionInput(
      "user_declared",
      Some("user-local"),
      None,
      None,
      None,
    ),
    Some("pre_plan"),
    "user prose",
    Some(instant(10)),
    instant(20),
    Some("Asia/Shanghai"),
    event.Private,
    [],
    None,
    None,
    "key-1",
  )
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn hash() {
  let assert Ok(value) =
    identity.sha256(
      "1111111111111111111111111111111111111111111111111111111111111111",
    )
  value
}
