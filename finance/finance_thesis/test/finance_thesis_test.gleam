import finance_thesis as thesis
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn lifecycle_replay_and_version_compare_test() {
  let assert Ok(created) =
    thesis.new(draft("e1", "created", 1, None, "claim one", None))
  let assert Ok(#(state, thesis.Stored(_))) =
    thesis.append(thesis.empty(), created)
  let assert Ok(amended) =
    thesis.new(draft(
      "e2",
      "amended",
      2,
      Some("e1"),
      "claim amended",
      Some("new evidence"),
    ))
  let assert Ok(#(state, thesis.Stored(_))) = thesis.append(state, amended)
  let encoded = thesis.encode_state(state)
  let assert Ok(replayed) = thesis.decode_jsonl(encoded)
  thesis.revision(replayed) |> should.equal(2)
  let assert Ok(comparison) =
    thesis.compare_versions(replayed, "t1", 1, 2, True)
  comparison
  |> json.to_string
  |> string.contains("changedClaims")
  |> should.be_true
}

pub fn fork_and_identity_change_fail_closed_test() {
  let assert Ok(created) =
    thesis.new(draft("e1", "created", 1, None, "claim one", None))
  let assert Ok(#(state, _)) = thesis.append(thesis.empty(), created)
  let assert Ok(fork) =
    thesis.new(draft(
      "e2",
      "amended",
      2,
      Some("wrong"),
      "claim two",
      Some("reason"),
    ))
  thesis.append(state, fork) |> should.equal(Error(thesis.ParentMismatch))
}

fn draft(
  event_id: String,
  kind: String,
  version: Int,
  parent: Option(String),
  text: String,
  reason: Option(String),
) -> thesis.Draft {
  thesis.Draft(
    "journal-1",
    "t1",
    event_id,
    kind,
    version,
    parent,
    "user",
    "user-1",
    "2026-08-11T00:00:00Z",
    thesis.Subject("us", "CIK1", "US1", "XNAS", "TEST"),
    "3-5 years",
    [
      thesis.Claim("c1", text, "active", [
        thesis.EvidenceLink(
          "l1",
          "supporting",
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "current",
          None,
        ),
      ]),
    ],
    "review_visible",
    reason,
    "key-" <> event_id,
  )
}
