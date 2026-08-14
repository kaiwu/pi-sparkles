# pi_sparkles_finance_track_status

Experimental Pi extension providing a persistent, visible active-finance-track
statusline and explicit switching among exactly `cn`, `hk`, and `us`.

The TUI statusline renders:

```text
CN · CNY · Asia/Shanghai · src:65% · feat:100%
```

`src` and `feat` are deliberately separate:

- `src` is the equal-weight evidence-maturity score for the track's versioned
  canonical source stack. A verified criterion contributes 100%, a partial
  criterion 50%, and a missing criterion 0%. It is **not** the probability that
  a source statement is true, and a critical criterion must be fully verified
  before the source stack is operationally credible.
- `feat` is the installed end-user feature coverage reported by
  `finance_provider_strategy/coverage`. It is computed from active tools for
  the selected track only. A US tool can never increase CN or HK coverage.

The compact percentage is only navigation telemetry. `finance_track_status`
returns the denominator, basis-point score, readiness state, every source
criterion and evidence note, contributing source groups, covered requirements,
missing requirements, and critical gaps. Consumers should use those structured
receipts—not the display number—for decisions.

The version-1 feature denominator has ten equally weighted requirements:
navigation context, source registry, security identity, market calendar,
effective rules, quotes/history, disclosure discovery, raw fundamentals,
normalized fundamentals, and reproducible derivations. Navigation is supplied
by this plugin; all other credit requires a matching installed track surface.
The operational target is 85%, with source registry and security identity
remaining critical. With the matching setup, identity, calendar, effective
rules, quote/history, disclosure, raw-fundamental, normalized-fundamental, and
derived-metric tools installed, CN and HK each report 100%. Current US also
reports 100% when its independently installed source, identity, NYSE/Nasdaq
calendar, effective-rule, paired quote/history, disclosure, raw/normalized
fundamental, and derivation surfaces are active. This is workflow breadth, not
data completeness, comprehensive OHLCV gap coverage, broad rule coverage, or
source-credibility parity. The separate US gap compositor can classify only
fully evidenced copied 2026 receipts and changes no feature score. Removing any
required track-owned tool immediately reopens the corresponding structured gap.

The interaction defaults are CN/CNY/`Asia/Shanghai`,
HK/HKD/`Asia/Hong_Kong`, and US/USD/`America/New_York`. They are navigation and
reporting defaults only; switching never relabels an observation, changes a
provider, converts currency, substitutes a calendar, or moves persisted state
between market plugins.

## Interface

- `--finance-track=cn|hk|us` selects the initial track; invalid values fail safe
  to `us`.
- `AGENT_CONTACT=<label>` supplies the shared operator identity used by provider
  adapters. Status tools report only whether it is validly configured and never
  expose the value to the model or session log.
- `/finance-track` shows status; `/finance-track cn` switches strictly.
- `/cn-track`, `/hk-track`, and `/us-track` are explicit shortcuts.
- `finance_track_status` gives headless agents the same structured state.
- `finance_track_switch` performs a typed sequential switch.

The pre-agent routing policy sends today's broad Shanghai/Shenzhen overview to
`cn_market_overview` once, current CN provider-ranked movers requests to
`cn_market_movers` once, and broad CN industry/板块 trend requests through the
composed `cn_sector_series` then `compare_series_returns` handoff. It forbids
benchmark/sector code probing and duplicate short/long history windows, and keeps price-relative sector comparisons
separate from unavailable fund-flow, constituent-breadth, causal-rotation,
theme, stabilization, top, and reversal claims.

The policy also records that provider-ranked movers acquisition is currently
`track_partial` for HK and US; it never relabels or substitutes the CN page for
another track. The return calculator itself remains shared across all three
tracks when a track-owned acquisition supplies its exact receipt-bound inputs.
For a general movers-list analysis, the policy stops after descriptive
comparison of the acquired rows. Optional identity, classification, history,
indicator, disclosure, or fundamental tools are composed only for a requested
dimension whose credential and exact-input preconditions are already met. It
forbids per-row fallback cascades, treating unresolved numeric fields as
convertible amounts, and inferring price limits, board regimes, or abnormal
activity from percentage/code patterns.

Track choices persist as extension-owned custom entries on the active session
branch. Resumed/forked branches restore their own latest choice; a new session
uses the configured initial track. Malformed state falls back visibly. Every
change emits `pi-sparkles.finance.track.changed` with only the strict track ID
so sibling plugins can refresh without sharing a mutable store.

The status tool returns the standard top-level `track` and versioned
`trackContext` plus effective currency/timezone, contact-configuration validity,
and persistence scope. It also returns `sourceCredibility` and
`featureCoverage` receipts plus their display percentages. Headless mode has no
UI statusline but remains fully operable through tools.
