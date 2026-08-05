pub type Status {
  Experimental
}

/// The complete set of user-visible market tracks supported by this project.
///
/// Provider-neutral and cross-market workflows are scopes, not extra tracks.
pub type Track {
  Cn
  Hk
  Us
}

pub type TrackError {
  UnknownTrack(received: String)
}

/// Shared Pi event-bus channel emitted when the active finance track is
/// established or changes. The payload is the strict `cn`, `hk`, or `us`
/// string.
pub const changed_channel = "pi-sparkles.finance.track.changed"

pub fn status() -> Status {
  Experimental
}

pub fn name(track: Track) -> String {
  case track {
    Cn -> "cn"
    Hk -> "hk"
    Us -> "us"
  }
}

/// Decode a wire-level track identifier.
///
/// Parsing is deliberately strict: aliases such as `china`, `mainland`,
/// `hong_kong`, `usa`, and `global` are not additional runtime identities.
pub fn from_name(value: String) -> Result(Track, TrackError) {
  case value {
    "cn" -> Ok(Cn)
    "hk" -> Ok(Hk)
    "us" -> Ok(Us)
    other -> Error(UnknownTrack(other))
  }
}

pub fn label(track: Track) -> String {
  case track {
    Cn -> "Mainland China"
    Hk -> "Hong Kong"
    Us -> "United States"
  }
}

pub fn command_prefix(track: Track) -> String {
  "/" <> name(track) <> "-"
}

pub fn tool_prefix(track: Track) -> String {
  name(track) <> "_"
}
