# finance_track

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_track` defines the repository's user-visible market-track contract.
The complete runtime set is `cn` (mainland China), `hk` (Hong Kong), and `us`
(United States). “Global” and “Greater China” may be explicit cross-track scopes,
but they are not additional track identities.

The package is provider-neutral, contains no Pi or network code, and depends
only on `finance_core`. Plugins compose it into structured results so a market
contract cannot disappear behind a generic tool name.

## Contract

`finance_track.Track` is a closed sum type with strict wire names. Aliases such
as `china`, `hong_kong`, `usa`, and `global` are rejected. The command and tool
prefix helpers return `/cn-`/`cn_`, `/hk-`/`hk_`, and `/us-`/`us_`.

`finance_track/context.Context` adds validated result metadata:

- a track-prefixed market scope;
- optional MIC, board, and timezone, preserving unknown facts as absent;
- source language;
- one or more named providers;
- an explicit entitlement label; and
- stable limitation identifiers.

A board requires a venue. Providers and limitations cannot be empty, malformed,
or duplicated. The context does not contain price limits, sessions, accounting
rules, or provider access behavior; those belong to track/provider packages.

`finance_track/json` owns schema v1 encoding and decoding. `result_fields`
adds both a top-level `track` for routing and an independently versioned
`trackContext` to existing Pi details without forcing an immediate rewrite of
provider metadata.

Cross-track results retain a separate context per leg. They never construct a
synthetic fourth track or flatten currencies, calendars, venues, entitlements,
or evidence.

`finance_track/profile` supplies typed interaction defaults used by the track
statusline: CN uses CNY/`Asia/Shanghai`, HK uses HKD/`Asia/Hong_Kong`, and US
uses USD/`America/New_York`. These are navigation/reporting defaults only and
never overwrite an observation's own currency, timezone, venue, or evidence.
Profiles require a visible, newline-free agent-contact label. The shared event
channel `pi-sparkles.finance.track.changed` carries only strict track IDs.

## Testing and distribution

Tests cover the closed track set, exact prefixes, scope/track coherence,
board/venue rules, duplicate rejection, all-track JSON round trips, and unknown
track failures. The package has no FFI, promises, ambient configuration, or live
tests. Local path dependencies must become released Hex constraints before
publication.
