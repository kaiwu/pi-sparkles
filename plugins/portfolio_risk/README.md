# portfolio_risk

Experimental, stateless Pi calculation shell for the light `CG-PORTFOLIO`
contract resolved by trading-course
[Session 18](../../../trading-course/sessions/18_cg_portfolio_light_calculation_contract_20260809.md).
It consumes caller/LLM-supplied account and position facts and registers one
parallel-safe tool:

- `portfolio_risk` calculates only the requested position count, gross/net
  long exposure, NLV-denominated position weights, signed portfolio heat, heat
  percentage, largest known weight, per-position contributions,
  reconciliation, temporal coherence, unknown/conflict counts, and receipt
  handle.

The implementation is deliberately plugin logic, not a new portfolio
framework. Its pure domain imports the existing `finance_risk` information
states and expression records, and `finance_math` exact sums/ratios. The root
module only defines the Pi schema and registers the tool. There is no provider,
FFI, storage, network, clock, account import, or mutable state.

## Exact first-slice contract

- Cash equities are long-only and single-currency. `cn`, `hk`, and `us` remain
  exact supplied tracks; the plugin neither resolves identity nor moves a
  position between tracks.
- Quantities are exact decimals. `shares` are direct; `lots` require an
  explicit information-state lot-size fact in `shares_per_lot`. A negative
  quantity on a long position is preserved, reported as a mechanical mismatch,
  and its absolute quantity is used for the requested arithmetic.
- Gross exposure is `abs(quantity_in_shares) × current_mark`. Net exposure is
  the same in this long-only slice. Position weight uses an exact supplied NLV
  and is unperformed when NLV is missing, conflicting, stale under the explicit
  cutoff, or non-positive.
- `heat_mark_basis_v1` is
  `abs(quantity_in_shares) × (current_mark - desired_stop)`.
  `heat_entry_basis_v1` is the separately named entry-price variant. Session
  18's invariant table and worked cases control over its earlier contradictory
  `abs(mark - stop)` shorthand: a stop at or above the selected basis returns
  zero or negative heat plus a mechanical fact; it is never silently zeroed.
- Heat percentage has no default denominator. The caller must select exactly
  `denom_nlv_v1`, `denom_gross_v1`, or `denom_caller_v1`; caller capital is
  required only for the last variant. Non-positive denominators are
  unperformed.
- `partial_totals_v1` returns the known sum with explicit unresolved
  contributors and `partial: true`. `all_or_nothing_v1` unperforms the total
  while retaining calculable per-position results.
- Exact duplicate position rows collapse once and report `duplicateCount`.
  Different rows sharing a position ID become one conflicting position with
  every alternative retained. Different IDs for one listing remain separate;
  listing aggregation is not implemented by this slice.
- Every known mark and stop requires its explicit matching observation time.
  Temporal output retains earliest/latest position/account snapshots and the
  exact millisecond span. Without a cutoff stale facts remain usable and their
  age is reported. With an explicit cutoff, affected calculation facts are
  projected as `not_obtained: exceeds_staleness_cutoff`; other positions remain
  available.
- Currency, weight, percentage, intermediate scale, and rounding are explicit.
  This permits money, fraction, and percentage output to retain distinct
  caller-selected precisions without hidden rounding defaults.
- Only names in `requestedSummaryFields` enter the result. Compact and receipt
  projections share one canonical SHA-256 semantic result; the receipt's own
  hash field is explicitly excluded from its payload hash.

Account cash and liabilities are retained as optional sourced facts but are not
silently inserted into exposure or NLV. The first slice does not implement the
separately named liabilities-adjusted leverage calculation.

## Decision boundary

The plugin returns arithmetic, provenance, missing/conflicting inputs,
mechanical facts, partiality, and reconciliation deltas. A non-zero delta,
negative heat, large weight, or stale observation is a fact. The plugin never
labels a position concentrated, heat excessive, diversification adequate, or a
portfolio acceptable. It selects no threshold, response, position reduction,
rebalance, recommendation, authorization, or next action.

Shorts, FX/multi-currency aggregation, cross-listing aggregation, leverage and
margin, correlation/covariance, concentration filters, factors, liquidity,
stress, VaR/CVaR, provider/account imports, persistence, optimization,
rebalancing, and orders remain incremental and require their concrete workflow
trigger.

Run the focused suites with:

```sh
bun run test:unit -- portfolio_risk
bun run build -- portfolio_risk
bun test test/binding/portfolio_risk.test.js
```

Twelve pure tests cover the Session 18 exact examples and invariants. Five
bundled-boundary cases cover the real Pi tool registration, partial facts,
receipt projection identity, long/currency fail-closed behavior, and exact
denominator selection. Architecture, artifact export, installed-Pi smoke, and
the full repository regression pass.
