# pi_sparkles_stock_screener

Status: **Experimental — Session 17 rank-6 predicate increment complete 2026-08-08** · version:
`0.1.0` · target: JavaScript/Bun

`stock_screener` combines two deliberately separate surfaces:

- the existing provider-backed `stock_universe` acquisition tool, which copies
  bounded Alpaca US-equity asset-master rows without screening or ranking; and
- the new stateless `screen` calculation, which evaluates exact
  caller/LLM-supplied numeric predicates over caller-supplied point-in-time
  universe, dataset, market, and technical facts.

The controlling professional stop point is
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md):
`screen(predicates, universe, date_range)` returns matching listings with
predicate facts, while the LLM supplies every predicate and no built-in screen
or rank exists. [Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md)
controls completed-daily fact states, [Session 12](../../../trading-course/sessions/12_cg_tech_indicator_calculations_20260807.md)
controls technical-calculation evidence, and
[Session 16](../../../trading-course/sessions/16_cg_quant_shared_replay_information_contract_20260807.md)
controls point-in-time universe/dataset manifests and reproducible handles.

## Decision boundary

The LLM chooses the track, universe, dataset, date range, source cutoff,
technical receipts, candidate rows, predicates, field, operator, threshold,
units, relation policy, result partition, page, interpretation, and next
operation. The calculation does not fetch predicate inputs or choose a
universe, source, correction vintage, predicate, threshold, missing-data rule,
match interpretation, rank, recommendation, or follow-up.

The first predicate slice supports exact decimal field-versus-constant
comparisons only: `greater_than`, `greater_than_or_equal`, `less_than`,
`less_than_or_equal`, `equal`, and `not_equal`. Both operands and their units
are explicit. Unsupported formulas, unit mismatches, missing fields, unknowns,
decode failures, and conflicts remain visible facts; there is no coercion,
imputation, source merge, alternative selection, or provider/track fallback.

Every result reports `decisionOwner: "llm"` and
`pluginDecisionFields: []`. A mechanically matched row is not a qualified,
suitable, attractive, actionable, or recommended security.

## `screen` request

The tool requires one immutable request containing:

- `instructionRef`, an exact SHA-256 reference to the LLM/user instruction;
- exactly one `cn`, `hk`, or `us` track and an inclusive Gregorian date range;
- an explicit `sourceCutoffUnixMilliseconds` used only to expose facts known
  after the requested cutoff;
- the exact canonical `finance_replay` universe and dataset JSON envelopes,
  each accompanied by its matching SHA-256 manifest handle;
- zero or more exact technical semantic-receipt handles. A technical fact must
  cite at least one of these handles; a dataset fact must cite the exact
  selected observation content hash;
- one to 20 ordered predicates with unique IDs. Each predicate names a field,
  unit, operator, and exact decimal threshold lexeme;
- one to 2,000 ordered, non-duplicated dated rows. Every row names an exact
  universe listing/MIC, dataset observation ID, and zero to 100 uniquely named
  values;
- every value's exact unit, source kind (`dataset_observation` or
  `technical_receipt`), known-at time, evidence roots, and one explicit fact
  state: known exact lexeme, unknown, not obtained, not applicable, decode
  failure with raw text, or conflicting alternatives with exact lexemes;
- the explicit relation policies `all_predicates_observed_true_v1` and
  `preserve_unresolved_separately_v1`; and
- a caller-selected `matched`, `not_matched`, `unresolved`, or `all` partition,
  plus offset and limit. Paging never changes canonical row order.

The boundary verifies both manifest envelopes are canonical and content-bound,
their tracks equal the request track, the requested range is inside the dataset
coverage interval, every row date is inside that range, every row has an exact
dated universe membership and dataset observation binding, row keys and
predicate IDs are unique, and numeric/evidence bounds are respected. It never
looks up a manifest or receipt from ambient state.

## Mechanical relation

For each row, the pure calculation exposes an exact universe-membership
binding, exact dataset-observation binding, and one predicate fact per supplied
predicate in caller order.

- A predicate is `observed_true` or `observed_false` only when the named value
  is known, its evidence binding is exact, its known-at time does not exceed
  the caller's cutoff, its unit exactly matches the threshold unit, and exact
  decimal comparison succeeds.
- Missing fields, unit mismatches, unavailable fact states, late-known values,
  and evidence-binding failures are `unavailable` with their reasons.
- Conflicting input alternatives remain `conflicting`; the result shows the
  exact alternatives and each parseable alternative's comparison without
  choosing one.
- A row is `matched` only when both manifest bindings are exact and every
  predicate is `observed_true`; it is `not_matched` when the bindings are exact
  and at least one predicate is `observed_false`; otherwise it is
  `unresolved`. These exact relation rules are named in the request rather than
  hidden as defaults.

The caller-selected partition controls only which row facts are paged. Counts
for all three relation states always remain visible. The response returns
stable request and semantic-result handles, exact manifest and supplied
technical handles, the requested date range and policies, page metadata,
predicate definitions, row-level facts, neutral available partitions, and
limitations. Equal semantic requests have equal handles regardless of page or
partition.

## Existing `stock_universe` acquisition slice

`stock_universe` fetches Alpaca's US-equity asset-master array using an explicit
caller-selected paper/live environment, status, exchange, and maximum row
budget. Every result preserves provider row order, duplicates, asset ID, class,
exchange, symbol, name, status, capability booleans, attributes, request ID,
retrieval time, query URL, exact response hash, and request-plus-response
universe hash. Rows that conflict with the requested provider filter remain
visible. Exceeding the response-byte or row budget fails rather than
truncating.

Required environment variables:

- `ALPACA_API_KEY_ID`
- `ALPACA_API_SECRET_KEY`
- `ALPACA_USER_AGENT_CONTACT`

`ALPACA_USER_AGENT_PRODUCT` is optional and defaults to
`pi-sparkles-stock-screener/0.1`.

Provider reference:

- <https://docs.alpaca.markets/us/reference/get-v2-assets-1>

The endpoint has no historical as-of parameter and its catalogue is not an
authoritative listing/security master. The acquisition slice does not persist
screens, infer MICs, authenticate provider origin from a content hash, grant
redistribution rights, or fall back among environments, statuses, exchanges,
providers, or tracks. Normal tests use exact fixture bytes and mocked `fetch`;
they make no live provider call.

## Architecture

```text
                         Pi extension effect shell
                            │                │
                            ▼                ▼
                 stateless screen      Alpaca acquisition
                            │                │
                            ▼                ▼
                   typed decoder       bounded runtime
                            │                │
                            ▼                ▼
               pure predicate domain   exact provider copy
                   │            │
                   ▼            ▼
          finance_replay    finance_core decimal
             manifests         comparison
```

- `pi_sparkles_stock_screener.gleam` registers both tools and confines
  Promise/network behavior to the Alpaca shell.
- `pi_sparkles_stock_screener/decode.gleam` decodes untrusted screen values
  into immutable boundary values.
- `pi_sparkles_stock_screener/screen.gleam` performs canonical-manifest
  validation, exact decimal comparisons, relation calculation, content
  hashing, paging, and deterministic rendering without effects.
- The existing `domain.gleam` remains the pure Alpaca-plan/result projection.
- No CN/HK/US market-owned package is imported by the shared screen domain;
  one call carries one exact track leg.

## Lifecycle, scorecard, and stop point

| Scorecard field | Rank-6 predicate increment |
| --- | --- |
| `professional_tasks_enabled` | Calculate caller-supplied field/constant predicates across exact dated universe rows and page matching/non-matching/unresolved facts |
| `personas_served` | Swing and quant workflow lenses |
| `provider_backed` | Screen: false; exact inputs supplied by caller. Existing acquisition: Alpaca US asset master |
| `track_coverage` | Screen: explicit `cn`, `hk`, or `us`, one leg per call. Acquisition: `us` only |
| `shell_depth` | Thin |
| `durable_state` | False; deterministic replay by immutable request |
| `effect_risk` | Screen: none beyond Pi result delivery. Acquisition: bounded read-only HTTP and environment credentials |
| `source_dependency` | Screen: none. Acquisition: credentialed Alpaca Trading Assets |
| `gate_dependency` | Resolved by Sessions 11, 12, 16, and 17 |
| `last_tutor_run` | None for the predicate increment; it introduces no new workflow, provider, persistent effect, or three-plugin handoff |

The first increment stops after one stateless `screen` tool, six exact
field-versus-constant operators, explicit three-way relation facts, stable
partition paging, and canonical handles. It does not add built-in screens,
field-to-field/formula predicates, ranking/scoring, ties, persistence,
watchlists, alerts, provider fetching, correction selection, cross-track
aggregation, backtests, charts, recommendations, or trade planning.

The package moved to **Experimental** on 2026-08-08 after 10 focused tests, a
bundled exact-predicate scenario, both preserved Alpaca boundary scenarios,
artifact export, installed-Pi loading, architecture checks, and full repository
regression passed. The implementation also corrected and covered the canonical
`finance_replay` known-membership wire state (`state`, not `kind`) needed for
non-empty universe-manifest round trips. No tutor run or `/tmp/QA01.md` was
needed.
