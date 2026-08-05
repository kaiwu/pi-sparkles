# Adding a market track

This guide describes how to add another user-visible stock-market track, such
as Japan (`jp`) or Germany (`de`), without weakening the isolation, evidence,
or functional architecture of the existing `cn`, `hk`, and `us` tracks.

The current runtime track set is intentionally closed. Adding a track is a
public product and wire-contract migration, not an alias added to a provider or
a new value inferred from a ticker. Complete the decisions and migration below
in one coherent change.

## What a track means

A track is the market context the user has deliberately chosen to work in. It
controls navigation, market-specific commands and tools, interaction defaults,
and which isolated market packages are available. It does not rewrite source
evidence.

The following are not interchangeable with a track:

- a country, exchange, MIC, provider, security identifier, or listing venue;
- a currency, timezone, locale, or document language;
- a portfolio, watchlist, “global” search, or cross-market calculation;
- the market inferred from a ticker-shaped string.

One track can contain multiple venues, currencies, timezones, or rule regimes.
Conversely, one instrument can have listings or relationships across tracks.
Those facts stay explicit in listing keys, observations, evidence, and
cross-track legs.

Changing the active track is navigation only. It must never relabel an existing
observation, exchange currency, substitute a provider, reinterpret a calendar,
or move persisted market-owned state.

## Decide the boundary before writing code

Record a new market ledger or roadmap section before creating plugin
directories. Resolve at least these questions:

| Decision | Required answer |
| --- | --- |
| Stable ID | A short lowercase wire ID such as `jp` or `de`. It cannot later be repurposed. |
| User label | The unambiguous name shown in output and setup views. |
| Boundary | Included and excluded venues, instruments, boards/segments, and rule regimes. |
| Defaults | Display currency, IANA timezone, and source language used only for interaction defaults. |
| Identity | Authoritative security-master source, identifier types, MICs, aliases, and ambiguity behavior. |
| Calendar | Authoritative source, licence, timezone semantics, venues, coverage interval, and update process. |
| Rules | Effective-dated trading, settlement, lot, price-limit, suspension, and eligibility sources. |
| Disclosures | Official source, document identity/versioning, language, corrections, and accounting scope. |
| Market data | Named provider, entitlement, redistribution, pacing, cache, outage, and fallback policy. |
| Cross-track behavior | Explicit relationships or workflows and the evidence retained for every leg. |

Do not start with “use the same behavior as US.” Reuse provider-neutral laws
and infrastructure, then state which market facts differ. If an authoritative
source or its licence is undecided, keep that capability blocked and test the
domain against clearly labelled synthetic fixtures. An undocumented public web
endpoint is not a temporary provider contract.

## Reuse and ownership

New tracks should compose the existing foundations rather than clone them:

| Reuse as-is | Market-owned implementation |
| --- | --- |
| `finance_core` observations, exact values, identifiers, source and time types | Security identity, venue, board/segment, alias and listing laws |
| `finance_track` context, result fields, profile channel and cross-track legs | The new closed-track constructor and its profile defaults |
| `finance_evidence` compatibility, as-of, licence and redistribution gates | Market-specific evidence sources and entitlement decisions |
| `finance_listing` track/MIC keys, effective aliases and relationships | `finance_<id>_identity` constructors and resolution policies |
| `finance_calendar` and `finance_market_calendar` engines | `finance_<id>_calendar` datasets and venue-specific semantics |
| `finance_http` request bounds, cancellation, pacing, retry and cassettes | Named provider request plans, decoders, limits and licence policy |
| `finance_math`, `finance_series`, `finance_provenance`, `finance_table` and `finance_testkit` | Effective-dated rules, documents, accounting mappings and plugin policy |
| `pi_gleam` and thin Pi effect-shell patterns | Track-named commands, tools, setup, status copy and persisted namespaces |

Market packages must not import `pi_gleam`. Plugins may compose independent
finance packages, but one plugin must not use another plugin as its domain
library. Decode at the shell, run pure total transitions, then interpret typed
effects.

Use these naming conventions for a track whose ID is `<id>`:

```text
finance/finance_<id>_identity/
finance/finance_<id>_calendar/
finance/finance_<id>_rules/          when implementation starts
finance/finance_<provider>/          for a reusable provider boundary
plugins/<id>_<capability>/
pi_sparkles_<id>_<capability>        Gleam plugin package
/<id>-<command>
<id>_<tool>
```

Provider packages follow source boundaries. Do not hide several unrelated
official sources or vendors behind a generic `finance_<id>` client, and do not
build a separate HTTP stack inside every plugin.

## Expand the closed track contract

The compiler's exhaustive cases are the first migration checklist. Add the new
constructor to `finance_track.Track`, then update every deliberate projection:

1. In `finance/finance_track/src/finance_track.gleam`, add the constructor,
   exact lowercase `name`, user-facing `label`, and command/tool prefixes.
   Parsing remains strict; names such as `japan`, `germany`, `tokyo`, `xetra`,
   and `global` are not aliases.
2. In `finance/finance_track/src/finance_track/profile.gleam`, add the display
   currency, IANA timezone, and source-language defaults. These are UI defaults,
   never validation shortcuts for provider observations.
3. In `finance/finance_track/src/finance_track/json.gleam`, update the decoder,
   schema description, placeholder values, and exact error messages. Preserve
   unknown-value failures.
4. Update the complete-set, prefix, profile, context, cross-track, and JSON
   round-trip tests under `finance/finance_track/test/`.
5. Audit every exhaustive `case track` and every literal list of supported
   tracks. A useful starting search is:

   ```sh
   rg 'Cn|Hk|Us|cn.*hk.*us|cn\|hk\|us|cn, hk, or us' finance plugins test scripts README.md ROADMAP.md AGENTS.md CN_TRACK.md
   ```

`finance_track` is currently Experimental. Even so, adding an enum value means
older strict decoders will reject new-track results. Document that compatibility
impact in the change. Do not rename or repurpose an existing ID. If this schema
is stabilized before another track is added, define a version transition and
forward-compatibility policy rather than silently widening the old contract.

## Keep the active track visible and switchable

Extend `plugins/finance_track_status/` in the same change as the closed track
contract. A supported track is not complete if a user can enter it but cannot
see or leave it.

The status plugin must provide all of the following for the new ID:

- a statusline such as `JP · JPY · Asia/Tokyo · agent:<contact>`;
- `/finance-track <id>` plus a direct `/<id>-track` command;
- the new value in `--finance-track`, `finance_track_switch`, and their schemas;
- strict parsing, help and error copy listing the complete supported set;
- a non-secret agent-contact display and unchanged secret-redaction behavior;
- branch-scoped persistence and publication on
  `pi-sparkles.finance.track.changed`;
- status, switching, restoration, malformed-state, unit, binding, and README
  coverage.

Track switching is an event for cooperating UI and setup views. It is not a
global mutable provider configuration. Market plugins retain market-prefixed
commands/tools and independently validate the track context of their inputs.
Results are labelled by their actual source context, not whichever track is
active when they are rendered.

## Build market identity first

Add `finance_<id>_identity` over `finance_listing` before quote, fundamental, or
screening plugins depend on market symbols.

The identity package must:

- key listings by track and MIC; a display code alone is insufficient;
- preserve leading zeroes and exact provider/source identifier lexemes;
- model venue, board/segment, currency and listing status explicitly;
- validate effective intervals for symbols, names, aliases and relationships;
- return ambiguity instead of choosing by preferred venue or provider order;
- retain evidence for cross-listings, depositary relationships and historical
  migrations without merging the instruments;
- use synthetic examples until an accepted security master can be redistributed
  or deterministically fixture-tested.

Do not promote a market-specific board, price-limit class, security suffix, or
listing rule into `finance_core` merely because the first new track needs it.
Promote only a concept whose laws are genuinely shared by multiple markets.

## Add bounded, sourced calendars

Construct `finance_<id>_calendar` over `finance_market_calendar`. Every dataset
must declare track, venue, IANA timezone, source, licence, version, coverage
start/end, sessions, and dated overrides. Queries outside coverage return an
error; they never extrapolate the last known holiday pattern.

Test at least:

- ordinary open/close and exact boundary instants;
- holidays and exceptional closures;
- shortened, auction, or split sessions where the market exposes them;
- transitions around the dataset coverage edges;
- conversion across relevant daylight-saving transitions;
- venue differences inside the track;
- joint-calendar behavior only where a named workflow requests it.

A profile timezone is not a calendar. Use real IANA timezone semantics at the
effect boundary and retain the timezone in canonical observations. If the track
contains venues with different sessions or timezones, keep separate datasets
instead of inventing one national session.

## Add rules and providers behind evidence gates

Market rules must be effective-dated pure data with their source and scope.
Avoid timeless constants for lot sizes, settlement, price limits, eligibility,
board treatment, or document requirements.

Every provider adapter must be an independent finance package with:

- opaque credentials and validated read-only request plans;
- allowlisted hosts and methods, bounded bodies, cancellation, request/page
  budgets, and safe retry/rate behavior;
- deterministic fixture-tested decoding that preserves unknown fields as
  unknown rather than inventing defaults;
- explicit entitlement, licence, cache, attribution and redistribution policy;
- source-specific identifiers, timestamps, units, adjustment and quality;
- documented outage behavior and no invisible fallback to another provider or
  track.

Provider values enter plugins as `finance_core.Observation(a)`. Keep source,
as-of/retrieval time, timezone, freshness, unit, adjustment, quality and
entitlement intact. Use `finance_evidence` with same-track composition by
default. Cross-track work must opt into a named policy and retain every
independently labelled leg.

## Expose isolated plugins

Create a plugin directory only when its implementation starts and its local
README can state the provider, rights, bounds, failure modes and user contract.
The plugin root remains a thin Pi/Promise effect shell; configuration, policy,
decoding, normalization and resolution live in pure namespaced modules.

Each market plugin must:

- use market-prefixed commands and tools, even when its domain implementation is
  shared;
- start human output with a visible track and venue label;
- emit `track` and `trackContext` through the shared `finance_track` JSON
  helpers rather than rebuilding them ad hoc;
- include venue/MIC and board/segment when applicable, plus timezone, source
  language, providers, entitlement and limitations;
- namespace configuration, storage, caches, account state and watch state;
- keep read-only, paper and live-trading capabilities separate;
- refuse an input whose evidence belongs to another track unless the tool is an
  explicitly named cross-track composition.

Generic discovery may require a track or return results grouped by track. It
must not silently search in the active track and present that result as global.

## Japan and Germany as starting examples

These entries are planning examples, not accepted market definitions or data
sources. Confirm every venue, rule and source against authoritative,
licence-compatible material before implementation.

| Candidate | Stable ID | Interaction defaults | Boundary decision that must be written down |
| --- | --- | --- | --- |
| Japan | `jp` | JPY, `Asia/Tokyo`, `ja-JP` | Whether the track covers only Tokyo-listed equities or additional Japanese venues and instrument classes; model MICs such as `XTKS` explicitly. |
| Germany | `de` | EUR, `Europe/Berlin`, `de-DE` | Whether the track is national or a named venue set; distinguish candidate MICs such as `XETR` and `XFRA`, their sessions, and their listing/quotation roles. |

Currency and timezone in this table are statusline defaults. A source listing
or observation can prove a different currency or venue context and remains
controlling.

For Japan, likely first pure packages are `finance_jp_identity` and
`finance_jp_calendar`; for Germany, `finance_de_identity` and
`finance_de_calendar`. Provider adapters should be named after the accepted
exchange, disclosure system, security master, or vendor—not after the track as
a whole.

## Architecture and test migration

Update repository-wide gates as part of the track change:

1. Add new pure identity, calendar and rules packages to the pure-foundation
   list in `test/architecture/functional.test.js`.
2. Expand or generalize architecture rules currently naming only `cn` and `hk`.
   A new market plugin must not import SEC or another market's domain package
   merely to reuse behavior.
3. Add every implemented plugin to artifact and Pi-load coverage. Add binding
   tests for typed result shapes, options, failures, callbacks and persistence.
4. Use provider fixtures or scripted transports only. Never put live requests,
   ambient credentials, real sleeps or mutable shared caches in unit tests.
5. Add laws for strict parsing, identity ambiguity, effective intervals,
   calendar coverage, evidence compatibility and same-track defaults.
6. Add explicit negative tests for wrong-track evidence, unsupported venues,
   unknown schema values, missing entitlement and cross-track composition
   without a declared policy.

Run the full repository verification before submission:

```sh
gleam format finance/finance_<id>_* plugins/<id>_*
bun run check
bun run test
git diff --check
```

Do not run a formatting glob until the expected package paths exist. Any new
live-provider lane must be opt-in, read-only, caller-identified, allowlisted,
request-budgeted, documented, and excluded from `bun run test`.

## Documentation and compatibility checklist

The same change must update every document that still declares the supported
track set, including `AGENTS.md`, `README.md`, `ROADMAP.md`, `CN_TRACK.md`, the
status plugin README, and relevant package/plugin READMEs. Add a dedicated
ledger for the new market when the work spans provider, rights, UX and domain
decisions.

The pull request should state:

- the exact track boundary and exclusions;
- public enum, JSON, command, tool, flag, event and persisted-state impact;
- provider/API assumptions and licence/redistribution decisions;
- which layers were reused and which market laws remain isolated;
- calendar source/version/coverage and identity ambiguity behavior;
- cross-track behavior, or an explicit statement that none is introduced;
- tests run and compatibility impact on older strict decoders.

## Definition of done

A new track is supported only when all of these are true:

- its stable ID, label and market boundary are documented and unambiguous;
- the closed track type, JSON contract, profiles and exhaustive tests include
  it;
- users can see, select, restore and switch away from it in the statusline;
- its identity and calendar layers are isolated, bounded and evidence-backed;
- its plugins and persisted state use track-owned names and namespaces;
- results retain canonical observations, source context and entitlement;
- same-track composition is the default and cross-track work is explicit;
- provider adapters meet the repository's bounds, cancellation, fixture,
  licensing and redaction requirements;
- architecture, binding, artifact, Pi-load and full repository tests pass;
- all supported-track documentation has been migrated together.

Until those conditions hold, keep the candidate in its ledger as a decision or
design item rather than accepting its ID in the runtime parser.
