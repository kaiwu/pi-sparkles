# pi_investor_workbench

Experimental rank-15 implementation of the minimum investor-dossier slice
authorized by trading-course
[Session 19](../../../trading-course/sessions/19_cg_fundamental_investor_dossier_contract_20260809.md).
It is a stateless, read-only Pi plugin over caller-supplied evidence. It does
not fetch providers, persist dossiers, select securities, or make investment
judgments.

## Tools

### `inspect_dossier`

Validates and compactly projects one dossier containing all 16 Session 19
sections:

1. identity and listing
2. business description
3. reporting basis
4. statement set
5. segment data
6. debt and liquidity
7. cash flow and earnings quality
8. capital allocation
9. governance and management
10. industry and peers
11. macro context
12. corporate actions
13. valuation
14. thesis and risks
15. portfolio fit
16. review history

Every section is explicit and carries exactly one of `provided`,
`partially_provided`, `not_obtained`, `not_available`, `stale`, `conflicting`,
`caller_declared`, or `incompatible`. Identity must be `provided`; absent
optional and expected sections remain visible in the matrix instead of causing
a whole-dossier rejection.

The tool validates exact `cn`/`hk`/`us` track-to-MIC scope, listing interval,
reporting entity, currency, fiscal-year end, related-listing separation,
receipt shapes, statement dates and inclusive durations, amendment links, and
the ordered `priorReviewId` chain. It mechanically reports:

- latest compatible annual and interim statement facts;
- amendment, restatement, and incompatible-statement facts;
- an `insufficient_evidence` reason when no compatible annual statement exists
  within 15 calendar months or an amendment chain is unclear;
- the latest caller-supplied receipt delta and evidence-state counts.

These are not a completeness, correctness, quality, or reviewability verdict.
The plugin validates review-delta structure and chain order; it does not claim
that the caller supplied every external source or change.

### `dossier_metric`

Calculates only the caller-selected metric using `finance_math` formula trees:

- current ratio, debt/equity, gross/operating/net margin, revenue growth,
  FCF conversion, interest coverage, BVPS, EPS, dividend yield, and payout
  ratio;
- bank net interest margin, insurance combined ratio, REIT FFO/AFFO,
  commodity reserve life, and pre-revenue cash runway.

Operands retain their exact decimal lexeme, entity, period, period kind,
inclusive duration, currency, unit, reported scale, basis, and source receipt.
The plugin rejects duplicate or unexpected operand names. Missing operands,
entity/period/unit/scale conflicts, malformed values, and non-positive
denominators produce `unperformed` with the exact reason. It never substitutes
a different metric; in particular, a bank request for gross margin remains an
unperformed gross-margin request until the caller explicitly selects a bank
metric.

### `dossier_valuation`

Projects up to 25 caller-labelled valuation rows. The caller selects one of
the Session 19 method labels and supplies that method's enterprise-value result,
its assumption package, net debt, and diluted shares. The plugin performs only:

```text
equity_value = enterprise_value - net_debt
per_share_value = equity_value / diluted_shares
```

All three operands must have the same entity, period end, currency, and
reported scale; their units must be `currency`, `currency`, and `shares`.
Each assumption retains a `statement_fact`, `consensus_estimate`,
`caller_declared`, or `historical_average` basis plus its source reference.
Incompatible rows remain beside calculated rows in the same grid.

This first slice does not calculate DCF cash-flow forecasts, WACC, terminal
value, comparable-company selection, historical ranges, NAV fair values, or
sector models. Its method result is explicitly caller supplied. A projected
per-share value is not an authoritative target price and is never labelled
cheap, expensive, fair, base, bull, or bear by the plugin.

## Judgment and source boundary

The LLM/user owns research questions, evidence sufficiency, business quality,
governance interpretation, peer choice, macro linkage, valuation assumptions,
thesis, portfolio fit, recommendation, and next action. FRED or other global
evidence may enter only as a separately labelled section receipt; it cannot
relabel the company track or prove company exposure, causality, or a forecast.

The plugin performs no network, storage, clock, credential, or mutation effect.
SHA-256 strings are shape-validated evidence references, not provider
authentication. Source adapters, dossier updating, section drill-down,
statement extraction, automated monitoring, thesis mutation, and portfolio
composition are not implemented here. Sessions 24, 26, 27, 29, 30, and 39 now
specify those separate future portfolio, comparative-research,
quality/growth/thesis, monitoring, company-intelligence, and macro-composition
contracts; they do not turn this stateless dossier shell into an orchestrator or
select any of those proposals for implementation.

## Verification

Deterministic Gleam tests cover the coherent amended-US case, incomplete CN
matrix, absent identity, unclear amendment chain, malformed review chain,
exact industrial and bank calculations, missing and non-positive operands, and
coherent/incompatible valuation rows. Bundled boundary tests exercise all three
Pi tools and artifact export without network access.
