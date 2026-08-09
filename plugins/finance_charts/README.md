# finance_charts

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`pi_sparkles_finance_charts` renders one bounded, deterministic PNG view from
exact caller-supplied OHLCV bars, already-calculated indicator points, and
trade markers. The same result always includes a compact `finance_table`
Markdown fallback and every exact input row in structured details.

## First slice

`chart_ohlcv` accepts 1–240 completed-daily bars, up to four indicator series,
and up to 240 trade markers. Price overlays must use the price unit. Lower-panel
indicators must share one explicit unit. Warm-up and unperformed indicator
points, market gaps, unmatched trade dates, source cutoff, adjustment basis,
entitlement, and fallback omissions remain visible.

The plugin validates exact `cn`/`hk`/`us` track, MIC, and timezone combinations;
strictly increasing unique Gregorian dates; exact decimal lexemes; OHLC and
non-negative volume invariants; receipt hashes; units; indicator dates; and
trade identifiers. It performs no fetching, indicator calculation, adjustment,
interpolation, ranking, signal interpretation, or trade decision.

## Rendering boundary

Pure Gleam code validates inputs and produces integer pixel primitives. A small
effect interpreter rasterizes only those primitives and encodes a non-animated
PNG. It contains no finance policy or calculation. Fixed dimensions and colors
make equal validated input byte-deterministic.

The PNG is an inspection aid. Exact decimal strings and source facts in
structured details remain controlling; integer pixel projection is not a new
observation, analytics result, or evidence claim.

## Verification

Eleven pure domain tests cover track, chronology, OHLC, units, gaps, omissions,
warm-up, unmatched trades, flat ranges, cutoff, and deterministic-plan behavior.
Five bundled scenarios verify actual deterministic PNG bytes and dimensions,
structured fallback, failures, and cancellation. Architecture, artifact,
installed-Pi smoke, and full `bun run test` passed on 2026-08-08.
