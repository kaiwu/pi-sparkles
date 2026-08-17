# finance_charts

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`pi_sparkles_finance_charts` renders one bounded, responsive ASCII view from
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

Pure Gleam code validates inputs and produces renderer-neutral structured
details. Pi's effect shell registers a native result component whose
`render(width)` method selects the latest contiguous suffix at two terminal
columns per bar. Widening the pane reveals earlier bars; it never downsamples,
aggregates, interpolates, changes interval, or infers gaps.

The ASCII chart is ordinary inline tool output, not an overlay, image, file, or
attachment. Exact decimal strings and source facts in structured details remain
controlling; terminal coordinates are not a new observation, analytics result,
or evidence claim. DSH consumes the same validated result but owns a separate
inline browser renderer described in [`../../CHARTS.md`](../../CHARTS.md).

## Verification

Eleven pure domain tests cover track, chronology, OHLC, units, gaps, omissions,
warm-up, unmatched trades, flat ranges, cutoff, and deterministic structured
behavior. Seven bundled scenarios verify text-only results, exact details,
width-bounded/latest-suffix ASCII, expanded fallback, failures, and
cancellation. The current focused package and binding lanes pass; tier maturity
still follows the normative tier gate rather than this package-level evidence.
