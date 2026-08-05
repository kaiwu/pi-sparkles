import finance_core/currency.{type Currency}
import finance_core/time.{type Timezone}
import finance_track.{type Track}
import gleam/string

/// User-navigation defaults for one active track.
///
/// These values configure interaction and display. They never override an
/// observation's own currency, timezone, venue, or source evidence.
pub opaque type Profile {
  Profile(
    track: Track,
    currency: Currency,
    timezone: Timezone,
    agent_contact: String,
  )
}

pub type ProfileError {
  InvalidAgentContact
}

pub fn defaults(
  track track: Track,
  agent_contact agent_contact: String,
) -> Result(Profile, ProfileError) {
  case valid_contact(agent_contact) {
    False -> Error(InvalidAgentContact)
    True -> {
      let #(currency_code, timezone_name) = case track {
        finance_track.Cn -> #("CNY", "Asia/Shanghai")
        finance_track.Hk -> #("HKD", "Asia/Hong_Kong")
        finance_track.Us -> #("USD", "America/New_York")
      }
      let assert Ok(currency) = currency.from_code(currency_code)
      let assert Ok(timezone) = time.timezone(timezone_name)
      Ok(Profile(track, currency, timezone, agent_contact))
    }
  }
}

pub fn track(value: Profile) -> Track {
  value.track
}

pub fn currency(value: Profile) -> Currency {
  value.currency
}

pub fn timezone(value: Profile) -> Timezone {
  value.timezone
}

pub fn agent_contact(value: Profile) -> String {
  value.agent_contact
}

pub fn status_line(value: Profile) -> String {
  string.uppercase(finance_track.name(value.track))
  <> " · "
  <> currency.code(value.currency)
  <> " · "
  <> time.timezone_name(value.timezone)
  <> " · agent:"
  <> value.agent_contact
}

pub fn describe(value: Profile) -> String {
  "Active finance track: "
  <> string.uppercase(finance_track.name(value.track))
  <> " ("
  <> finance_track.label(value.track)
  <> ")\n"
  <> "currency="
  <> currency.code(value.currency)
  <> " timezone="
  <> time.timezone_name(value.timezone)
  <> " agentContact="
  <> value.agent_contact
}

fn valid_contact(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 120
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
  && !string.contains(value, "\t")
}
