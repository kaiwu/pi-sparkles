# pi_sparkles_trade_plan

Status: **Experimental — Session 17 rank 3 complete 2026-08-07** · version: `0.1.0` · target:
JavaScript/Bun

`trade_plan` is a thin, stateless, calculation-only Pi shell over
`finance_risk`. It lets the LLM request exact single-leg long planned-loss
facts, independent quantity bounds, caller-requested bound intersections, and
one focused projection onto an exact trade-unit fact.

The professional risk-information contract is
[Session 13](../../../trading-course/sessions/13_cg_risk_calculation_contract_20260807.md).
The breadth priority, first-slice stop point, and verification cadence are
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md).
Exact calculation, fact-state, grid, request, and semantic-receipt laws come
from [`finance_risk`](../../finance/finance_risk/README.md).

## Decision boundary

The LLM chooses every query, account/listing scope, entry, stop, named budget or
ceiling, denominator, constraint, scenario representation, branch, trade-unit
fact, intersection request, rounding policy, projection, interpretation,
quantity, and next action. The plugin decodes those exact inputs, invokes the
requested `finance_risk` operation, and returns calculations, operands,
intermediates, independent bounds, projections, tight-bound ties, unperformed
expressions, provenance, alternatives, receipt handles, and available tools.

It never chooses or emits:

- a risk fraction, budget, account field, entry, stop, scenario, fee, FX rate,
  denominator, constraint, trade unit, lot rule, branch, bound intersection,
  rounding value, or fallback;
- correctness, prudence, conservatism, aggressiveness, adequacy, sufficiency,
  readiness, acceptance, rejection, safety, compliance, recommendation,
  authorization, or next-action conclusions; or
- a selected/recommended quantity, order instruction, fill prediction,
  provider fetch, account mutation, persisted plan, or execution action.

Every result includes `decisionOwner: "llm"` and
`pluginDecisionFields: []`. A negative/zero planned loss, zero grid projection,
division by zero, missing trade unit, false requested comparison, or tightest
bound is a mechanical fact. The LLM alone decides what to do with it.

## Professional routine

1. The LLM obtains or declares exact account, policy, plan-price, and market-rule
   facts with their evidence and information state. This plugin does not observe
   another tool or account automatically.
2. The LLM calls `plan_loss` for one exact desired-entry/desired-stop pair. The
   plugin calculates `long_planned_loss_per_unit_v1`, retaining both operands
   even when the result is zero, negative, conflicting, or unavailable.
3. The LLM calls `plan_bounds` with one or more independently named numerator /
   denominator constraints and one explicit trade-unit fact. Each raw,
   whole-share, and grid result is returned; no constraint is omitted or
   preferred. An intersection appears only when the same request supplies its
   exact selected bound IDs.
4. The LLM calls `plan_grid_projection` when it wants a compact focused result
   for one named bound and one supplied trade-unit fact, including an alternate
   or previously unavailable lot rule. The plugin does not choose which bound
   to project.
5. The LLM compares the facts, selects any quantity or follow-up operation, and
   authors any plan or order outside this plugin.

Every operation is stateless. Repeating equal ordered inputs produces the same
`finance_risk` request and semantic receipt handles.

## Tool surface

### `plan_loss`

Inputs:

- common calculation context, rounding, branch policy, execution budgets, and
  output projection;
- an explicit `operationId`;
- one exact entry-price fact; and
- one exact desired-stop fact.

The only formula is `long_planned_loss_per_unit_v1`, with direction fixed to
the first-slice `long` scope. The compact result includes state, exact rounded
value when calculated, currency/unit, ordered operands, and intermediate
values. Unknown, not-obtained, conflicting, or decode-failure operands produce
the core's exact unperformed expression rather than a substituted value.

### `plan_bounds`

Inputs:

- common calculation context, rounding, branch policy, execution budgets, and
  output projection;
- one to 50 ordered bound requests;
- one exact trade-unit fact shared by this exact listing query; and
- an intersection request with state `not_requested` or `requested`. The latter
  supplies an exact operation ID and one or more bound IDs from the same call.

Each bound request includes:

- `boundId`, explicit formula variant, and numerator operand name;
- one exact numerator fact representing the LLM-selected currency budget,
  ceiling, cash, buying power, remaining heat, or other named amount; and
- one explicit denominator variant:
  - `long_planned_loss_per_unit_v1`, with exact entry and stop facts; or
  - `supplied_denominator_v1`, with an explicit operand name, formula label,
    output unit, and exact denominator fact such as entry price or scenario
    loss per unit.

`finance_risk.bound.quantity_bound` returns raw decimal, whole-share floor, and
grid projection for every request. The common trade-unit fact can be known,
unknown, not obtained, conflicting, or a decode failure. An unavailable grid
does not discard the raw or whole-share facts. When requested, intersection is
calculated only over the named bounds after their supplied-grid projections;
unknown IDs, duplicates, or an empty selection fail explicitly.

The numerator is already an exact sourced amount. Percentage-of-equity budget
derivation remains a separate explicit calculation/core receipt; this shell
does not silently derive an amount from an account field or percentage.

### `plan_grid_projection`

Inputs:

- common calculation context, rounding, branch policy, execution budgets, and
  output projection;
- one exact bound request using the same numerator/denominator contract; and
- one exact trade-unit fact.

The tool returns that bound's raw, whole-share, and grid projections and no
intersection. It is a focused replay path, not a different formula and not a
quantity recommendation.

## Common calculation context

Every call explicitly supplies:

- `instructionRef`: SHA-256 of the LLM instruction authoring the query;
- `accountScope`, `portfolioScope`, exact `track` (`cn`, `hk`, or `us`),
  `listingId`, `asOfUnixMilliseconds`, native currency, and ordered evidence
  roots;
- rounding mode (`toward_zero`, `away_from_zero`, `half_up`, or `half_even`),
  output scale, intermediate scale, and the only implemented policy
  `final_only`;
- branch policy: `all_branches` or an exact `selected_branch` with branch ID
  and selection-instruction hash;
- `maximumOperations` and `maximumOutputs`, each from one through 100; and
- projection `compact` or `receipt`.

`compact` returns calculated/unperformed facts and stable request/semantic
handles. `receipt` returns the same compact facts and additionally includes the
exact canonical `finance_risk` request and semantic envelope strings. The
projection never changes semantic receipt identity.

## Exact sourced facts

Decimal and trade-unit inputs preserve the core information states:

- `known`: one typed value plus source;
- `unknown` or `not_obtained`: source plus exact reason;
- `conflicting`: two to 20 typed sourced alternatives, with no selected value;
- `decode_failure`: source, raw lexeme, and exact reason.

A decimal alternative contains an exact decimal string. A trade-unit
alternative contains positive integer `minimum` and `increment` values. Every
source carries:

- source kind: `provider_observation`, `market_rule`,
  `custodian_observation`, `caller_declared`, `llm_instruction`, or
  `calculated`;
- source-reference SHA-256;
- effective and retrieval instants;
- currency, unit, exact source lexeme, and scope; and
- zero to 100 retained alternative descriptions.

Caller declarations and LLM instructions retain those labels. A source hash
proves only content binding; the plugin does not authenticate or verify the
source. Fact metadata must not be used to carry credentials or secret text.

## Result and receipt contract

Every result is versioned and includes:

- operation and exact context projection;
- rounding and branch policy;
- ordered compact result facts;
- counts of calculated/unperformed expressions and unknown, not-obtained,
  conflicting, and decode-failure inputs;
- request and semantic receipt handles;
- the exact receipt envelopes only for projection `receipt`;
- neutral available tools;
- `decisionOwner: "llm"` and empty `pluginDecisionFields`; and
- limitations distinguishing arithmetic/content binding from correctness,
  prudence, authorization, source truth, or professional sufficiency.

The request/semantic receipts are produced by `finance_risk.request` and
`finance_risk.receipt`; the shell does not invent parallel receipt laws. Batch
and focused replay are deterministic for equal ordered inputs.

## Architecture

```text
untrusted Pi calculation query
          │
          ▼
typed boundary decoder
          │
          ▼
pure trade_plan fact/request/calculation projection
          │
          ▼
finance_risk fact / calculation / bound / request / receipt
          │
          ▼
Pi text + structured result
```

- `pi_sparkles_trade_plan.gleam` is the thin Pi/Promise registration shell.
- `pi_sparkles_trade_plan/decode.gleam` decodes untrusted values into immutable
  boundary types.
- `pi_sparkles_trade_plan/domain.gleam` constructs sourced facts, runs only the
  explicitly requested calculation, builds core receipts, and renders compact
  deterministic projections.
- No module performs network, filesystem, environment, clock, randomness,
  storage, account, broker, entitlement, or mutation effects.
- One call has exactly one explicit track and listing. No rule, fact, currency,
  or state can move silently among `cn`, `hk`, and `us`.

## Lifecycle and stop point

The package is **Experimental**. Its typed API may still change, but the
implemented first slice has passed its focused and repository verification
gates.

The first slice stops after single-leg long planned loss, generic independent
amount-over-denominator bounds, exact supplied-grid projection, and an
explicitly requested intersection. It does not add account/provider adapters,
percentage-budget derivation, scenario generation, gap forecasts, cost models,
portfolio heat, cross-currency aggregation, shorts, derivatives, margin,
multi-leg/scaling, correlation/liquidity/VaR calculations, plan storage,
execution, broker capability, or order submission.

Later depth requires a concrete Session 17 trigger, such as the swing workflow
being unable to obtain a required risk fact, two consumers needing the same
missing calculation/receipt, or a track-specific rule fact being absent.
Requests for automatic thresholds, selected quantities, plan verdicts, more
variants, or repeated correctness tests are not depth triggers.

## Verification

Nine focused pure tests cover:

- positive, zero, and negative long planned-loss facts without plan verdicts;
- known, unknown, not-obtained, conflicting, and decode-failure operands;
- independent stop-style and supplied-denominator bounds with raw,
  whole-share, and exact CN/HK/US-style supplied-grid projections;
- unknown trade units preserving raw and whole-share results;
- caller-requested intersection, tight-bound ties, zero grid points, and
  unknown/duplicate selected-bound failures;
- exact source metadata, retained alternatives, track/listing scope, rounding,
  and evidence roots in core receipts;
- stable semantic receipt identity across compact/receipt projections and
  changed identity when a policy/input changes;
- no plugin-selected constraint, threshold, intersection, quantity, status,
  recommendation, authorization, or next action; and
- boundary rejection for malformed hashes, decimals, fact variants, trade
  units, scales, operation budgets, and mismatched currencies.

Repository integration includes two bundled scenarios forming one three-tool
professional interaction contract, artifact registration, installed-Pi smoke
loading, architecture and secret-language checks, and full `bun run test`.

Session 17 does not require a real tutor-LLM run because this shell adds no
provider, persistence/effect, new professional workflow, or three-plugin
handoff.
