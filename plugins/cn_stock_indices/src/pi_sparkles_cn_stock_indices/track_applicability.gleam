import gleam/json

/// Explicit applicability review for the current-index acquisition slice.
/// A CN adapter is never evidence that another track has the same capability.
pub fn details() -> json.Json {
  json.object([
    #(
      "cn",
      json.object([
        #("status", json.string("supported")),
        #("scope", json.string("exact_sse_000688_only")),
        #("provider", json.string("Shanghai Stock Exchange")),
      ]),
    ),
    #(
      "hk",
      json.object([
        #("status", json.string("track_partial")),
        #(
          "missingEvidence",
          json.array(
            [
              "reviewed_exact_index_identity_and_administrator_contract",
              "complete_current_membership_decoder",
              "effective_date_and_correction_contract",
              "licence_and_redistribution_decision",
            ],
            json.string,
          ),
        ),
        #("candidateAuthority", json.string("Hang Seng Indexes Company")),
        #("substitution", json.string("none")),
      ]),
    ),
    #(
      "us",
      json.object([
        #("status", json.string("track_partial")),
        #(
          "missingEvidence",
          json.array(
            [
              "reviewed_exact_benchmark_and_administrator_contract",
              "complete_current_membership_acquisition_and_decoder",
              "listing_identity_and_correction_contract",
              "licence_and_redistribution_decision",
            ],
            json.string,
          ),
        ),
        #("candidateAuthority", json.string("selected US index administrator")),
        #("substitution", json.string("none")),
      ]),
    ),
  ])
}
