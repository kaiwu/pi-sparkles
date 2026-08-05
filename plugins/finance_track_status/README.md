# pi_sparkles_finance_track_status

Experimental Pi extension providing a persistent, visible active-finance-track
statusline and explicit switching among exactly `cn`, `hk`, and `us`.

The TUI statusline renders:

```text
CN · CNY · Asia/Shanghai · agent:research@example.test
```

The interaction defaults are CN/CNY/`Asia/Shanghai`,
HK/HKD/`Asia/Hong_Kong`, and US/USD/`America/New_York`. They are navigation and
reporting defaults only; switching never relabels an observation, changes a
provider, converts currency, substitutes a calendar, or moves persisted state
between market plugins.

## Interface

- `--finance-track=cn|hk|us` selects the initial track; invalid values fail safe
  to `us`.
- `--finance-agent-contact=<label>` supplies a non-secret status label. It is
  not read from SEC or provider environment variables and defaults visibly to
  `unconfigured`.
- `/finance-track` shows status; `/finance-track cn` switches strictly.
- `/cn-track`, `/hk-track`, and `/us-track` are explicit shortcuts.
- `finance_track_status` gives headless agents the same structured state.
- `finance_track_switch` performs a typed sequential switch.

Track choices persist as extension-owned custom entries on the active session
branch. Resumed/forked branches restore their own latest choice; a new session
uses the configured initial track. Malformed state falls back visibly. Every
change emits `pi-sparkles.finance.track.changed` with only the strict track ID
so sibling plugins can refresh without sharing a mutable store.

The status tool returns the standard top-level `track` and versioned
`trackContext` plus currency, timezone, agent contact, configuration validity,
and persistence scope. Headless mode has no UI statusline but remains fully
operable through tools.
