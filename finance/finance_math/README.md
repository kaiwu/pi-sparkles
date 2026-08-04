# finance_math

Status: **Implementing** · version: `0.1.0` · target: JavaScript/Bun

`finance_math` is the provider-neutral calculation substrate for finance
adapters and plugins. It supports open-ended metric composition instead of
encoding a closed list of ratios. The package contains no Pi, HTTP, storage,
clock, randomness, JavaScript FFI, or provider behavior.

The implemented base has two deliberately separate numerical domains:

- exact `finance_core.Decimal` arithmetic for reported values, accounting
  identities, ratios, margins, growth, multiples, per-share calculations, and
  other metrics whose rounding policy must be explicit; and
- explicitly approximate `Float` analytics for statistics, roots and
  fractional powers, where IEEE-754 behavior is part of the API contract.

The approximate layer now includes reliability-weighted estimators, empirical
tail/downside risk, annualized performance ratios, multi-factor ordinary least
squares, and fixed-income yield sensitivity. Every calculation still requires
its estimator, frequency, tolerance, compounding, or tail policy explicitly.

The exact formula evaluator propagates missing values, rejects unknown and
duplicate inputs, and makes every division scale and rounding mode visible.
Metric definitions declare their output unit and assumptions; calculated
results retain the referenced input names so provenance can be attached without
reverse-engineering a formatted expression.

## What “any metric” means

No finite library can contain every industry, jurisdiction, provider, or
user-defined metric. The extensibility guarantee is that new scalar metrics do
not require changes to this package when they can be expressed from:

- literals and named inputs;
- addition, subtraction, multiplication, negation, division, sum, mean,
  minimum, and maximum;
- injected lists for descriptive/relative statistics; or
- a bounded scalar function solved through bisection.

Named helpers in `finance_math/metrics` are compositions of the same public
formula tree. A plugin may define ROIC, ROE, margins, coverage, turnover,
valuation multiples, free cash flow, economic profit, factor scores, or a
provider-specific metric without adding an enum case to the evaluator.

Metrics that require time alignment, rolling windows, or resampling use the
local `finance_series` package. Calendar semantics additionally need
`finance_calendar`. Those packages own data alignment and market-time rules;
this package owns the calculation after inputs have been made comparable.

## Modules

| Module | Responsibility |
| --- | --- |
| `finance_math/error` | exhaustive numerical, input, domain, and convergence failures |
| `finance_math/exact` | exact sums, means, ratios, percentages, and growth |
| `finance_math/formula` | composable exact expression tree and strict input evaluation |
| `finance_math/metric` | named definitions, declared units, assumptions, and calculation traces |
| `finance_math/metrics` | reusable formula builders for finance metric families |
| `finance_math/statistics` | descriptive statistics, relative risk, returns, volatility, VaR, drawdown, and CAGR |
| `finance_math/weighted` | reliability-weighted mean, variance, covariance, and beta with population/sample correction |
| `finance_math/risk` | expected shortfall, downside deviation, Sharpe, Sortino, and Omega ratios |
| `finance_math/regression` | observation-major multi-factor OLS, diagnostics, prediction, and singularity detection |
| `finance_math/fixed_income` | discounted cash flows, Macaulay/modified duration, convexity, and DV01 |
| `finance_math/root` | pure bounded bisection over caller-supplied scalar functions |
| `finance_math/cashflow` | periodic/date-aware NPV and bounded IRR/XIRR |

## Exact formulas

External financial numbers enter as decimal strings and are parsed by
`finance_core/decimal`; the exact path never converts them through JavaScript
`Number`. Division requires an output scale and one of the core rounding modes.
Zero denominators are errors and missing inputs never become zero.

```gleam
let roic =
  metrics.ratio(
    formula.Reference("nopat"),
    formula.Subtract(
      formula.Add(formula.Reference("debt"), formula.Reference("equity")),
      formula.Reference("cash"),
    ),
    scale: 4,
    rounding: decimal.HalfEven,
  )
```

`metric.Definition` adds a stable name, output `Unit`, and explicit assumptions.
`metric.calculate` returns the decimal value alongside that metadata and the
deduplicated input names in first-reference order. Evidence and source records
remain owned by `finance_provenance`; callers join them using those names.

Units are declared, not inferred. The current package does not perform
dimensional algebra, currency conversion, inflation adjustment, share-basis
normalization, or accounting-standard reconciliation. Provider/domain adapters
must normalize compatible inputs before evaluation.

## Approximate analytics

`statistics` functions accept already-normalized `Float` samples. Population
and sample estimators are distinct. Paired calculations reject length mismatch;
correlation and beta reject zero variance. Historical VaR uses the documented
nearest-rank empirical loss quantile and makes confidence explicit. Drawdown
requires positive price/index levels.

`weighted` uses non-negative reliability weights that need not be normalized.
Its sample estimator applies the effective reliability-weight correction
`sum(w) - sum(w²)/sum(w)`; zero or negative weights fail explicitly.

`risk` defines empirical expected shortfall as the mean of the worst
`ceil((1-confidence) * n)` losses. Sharpe and Sortino accept per-period targets
and an explicit periods-per-year annualization factor. Omega fails rather than
returning infinity when there are no losses below its threshold.

`regression.ordinary_least_squares` consumes one predictor row per dependent
observation. It uses normal equations and Gauss-Jordan elimination with partial
pivoting under a caller-supplied singularity tolerance. Results expose
intercept, ordered factor coefficients, fitted values, residuals, R², adjusted
R², and sample count. Models with an intercept use centered R²; models without
one use uncentered R². It is suitable for deterministic moderate-sized factor
models, not ill-conditioned high-dimensional numerical research.

`fixed_income` supports periodic or continuous compounding over explicitly timed
cash flows. Sensitivity returns price, Macaulay duration, modified duration,
convexity, and DV01 with respect to the supplied annual yield. Coupon schedule,
day-count, and settlement construction remain calendar/domain responsibilities.

`root.bisection` requires a bracket, positive tolerance, and finite iteration
budget. IRR and XIRR use it rather than an unbounded or nondeterministic solver.
XIRR requires ordered timestamps and an explicit day-count basis. Multiple-IRR
cash-flow patterns may have multiple roots: the caller’s bracket selects the
root being requested, and failure to bracket is visible.

Float outputs are estimates. Consumers must retain method, estimator, sample
frequency, day-count basis, bracket, and tolerance as metric assumptions.
Binary floats must never be used to parse provider monetary values or silently
replace exact accounting formulas.

## Functional design

All state is passed as immutable data. Formula evaluation, statistical folds,
discounting, and root iterations are pure and deterministic for the same
inputs. Expected failures are `MetricError`; no function throws, reads a global
clock, samples randomness, performs I/O, or emits logs.

This lets tests exercise formula identities, missing-data behavior, estimator
choices, pathological cash flows, and convergence budgets without providers or
Pi. Named metrics should remain thin builders so their complete behavior is
visible as data and can be property-tested independently.

## Acceptance criteria

- Arbitrary algebraic finance formulas compose without modifying the evaluator.
- Exact paths never pass reported decimals through binary floating point.
- Missing, unknown, duplicate, and zero-denominator inputs are explicit errors.
- Every calculated exact metric carries a declared unit, input names, and
  assumptions.
- Approximate functions document estimator/domain policy and have bounded
  numerical methods.
- Weighted estimators, downside/tail risk, multi-factor regression, and
  fixed-income sensitivity have deterministic known-answer tests.
- Statistics cover descriptive, relative-risk, return, drawdown, volatility,
  and empirical quantile primitives.
- Cash-flow calculations cover periodic NPV/IRR and date-aware NPV/XIRR.
- Formatting, warnings-as-errors build, deterministic tests, and Hex tarball
  audit pass.

## Remaining 0.1 work

- finite-value validation for every `Float` input and output;
- quantile interpolation alternatives, higher moments, robust estimators, and
  parametric/Monte-Carlo tail models;
- regression standard errors, confidence intervals, heteroskedasticity/HAC
  corrections, regularization, and numerically stronger QR/SVD solvers;
- yield-to-maturity solving over dated coupon schedules, key-rate duration,
  spread measures, and curve interpolation;
- portfolio optimization, constrained solvers, and option-pricing primitives;
- Newton/secant alternatives with explicit derivative/convergence contracts;
- reusable property/law suites and package tarball audit; and
- integration contracts with `finance_series`, `finance_calendar`, and
  provenance-backed analytical results.

## Non-goals

- No provider field mapping, accounting-policy judgment, forecasts, market
  calendar, portfolio optimizer, option-pricing convention, or trading advice.
- No implicit annualization, missing-value deletion, FX conversion, stale-data
  fallback, or selection of an IRR root.
- No claim that a mathematically valid formula uses economically comparable or
  licensed inputs.
