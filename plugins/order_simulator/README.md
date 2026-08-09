# pi_sparkles_order_simulator

Status: **Experimental — Session 17 rank 4 complete 2026-08-08** · version: `0.1.0` · target:
JavaScript/Bun

`order_simulator` is a thin, stateless execution-information shell over
`finance_execution`. Its first slice lets the LLM evaluate one exact desired
limit order against one caller-supplied completed-daily OHLC bar with the
versioned `bar_possible_paths_v1` model. It returns every compatible fill and
non-fill branch; it never selects or predicts a path.

The professional execution-information contract is
[Session 14](../../../trading-course/sessions/14_cg_day_execution_information_contract_20260807.md).
The breadth priority and first-slice stop point are
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md).
Desired-instruction, fact-state, simulation, request, budget, and semantic
receipt laws come from
[`finance_execution`](../../finance/finance_execution/README.md).

## Decision boundary

The LLM chooses the track, listing, account scope, side, intent, quantity,
desired order behavior, time in force, session, capability fact and policy,
bar, calculation policy, branch interpretation, and next operation. The plugin
decodes those exact inputs, invokes the requested core model when its operands
are available, and returns compatible branches, price ranges, sources,
unknowns, limitations, and stable receipt handles.

It never chooses or emits:

- a broker encoding, provider, venue route, order behavior, side, quantity,
  price, time in force, capability fallback, trigger rule, bar path, fill,
  probability, benchmark, cost, or next operation;
- a likely, expected, best, worst, conservative, prudent, correct, sufficient,
  ready, accepted, rejected, safe, compliant, recommended, or authorized
  conclusion; or
- an observed or paper-broker fill, order submission, account mutation,
  persisted simulation, or complete day-trading workflow.

Every result includes `decisionOwner: "llm"` and
`pluginDecisionFields: []`. A bar touch means only that a fill is compatible
with the daily range. The paired compatible non-fill branch remains whenever
the core returns it.

## Professional routine

1. The LLM obtains or declares one exact desired instruction, its account/rule/
   capability references, and one completed-daily OHLC bar with provenance.
2. The LLM supplies an exact sourced `desiredOrderSupported` fact and selects
   either `record_only_v1` or `require_known_true_v1`. The former records the
   fact without using it as an execution precondition. The latter mechanically
   leaves the model unperformed unless the fact is known `true`; the plugin
   does not infer support from order fields or choose a fallback.
3. The LLM calls `simulate_bar_paths` with the only implemented model and
   calculation policy: `bar_possible_paths_v1` plus `limit_touch_v1`.
4. For a known, geometrically valid bar and a desired `Limit` instruction, the
   shell calls `finance_execution.simulation.limit_possible_paths` and returns
   all core branches. For any unavailable bar, failed selected capability
   precondition, or other valid desired behavior, it returns an exact
   unperformed result while preserving the request and inputs.
5. The LLM interprets the alternatives and authors any journal, replay, plan,
   or follow-up outside this plugin.

Equal ordered inputs produce equal `finance_execution` request and semantic
receipt handles. Compact versus receipt projection does not change semantic
identity.

## Tool surface

### `simulate_bar_paths`

The sole tool accepts:

- one exact desired instruction;
- one sourced completed-daily bar fact;
- one sourced desired-order-supported capability fact;
- explicit simulation, capability, rounding, branch, currency, projection,
  and execution-budget policies; and
- exact request reference sets.

The only simulation model is `bar_possible_paths_v1`; the only calculation
policy is `limit_touch_v1`; the branch policy is `all_branches`. These names
are still explicit inputs so the request receipt records what the LLM asked
for and later variants cannot become silent defaults.

Performed results include:

- `resultKind: "hypothetical"`;
- the exact model name;
- every core branch in stable order;
- branch ID and outcome;
- `fillCompatibility` (`compatible_fill`, `compatible_non_fill`, or the exact
  core outcome name);
- any compatible price range; and
- the core's neutral branch note.

Unperformed results include the exact reason and input states. An unperformed
operation is still content-bound by request and semantic receipt handles.

## Desired instruction

The instruction maps directly to `finance_execution.instruction.DesiredInstruction`:

- `instructionId`, SHA-256 `instructionReceipt`, exact `track`, `listingId`,
  `mic`, `accountScope`, three-letter `currency`, `side`, optional `intent`,
  positive decimal `quantity`, and `quantityUnit`;
- a desired behavior variant: market, limit, stop, stop-limit, auction,
  market-on-close, limit-on-close, or trailing-stop;
- time in force, optional requested session, optional activation/expiry
  instants, IANA timezone, and rule/capability/account receipt references; and
- retained alternatives as either known descriptions or an explicit
  not-applicable reason.

The first slice is long-only cash equity: a desired `Sell` may close/reduce a
long position or leave intent unspecified, but `Sell` plus `Open` is rejected
as outside scope rather than simulated as a short sale.

All desired behaviors are representable because the desired instruction must
not be collapsed into the one implemented simulation. This slice performs
only `Limit(price)` under `limit_touch_v1`; every other behavior returns
`unperformed: unsupported_desired_behavior_for_limit_touch_v1`.

The instruction is desired behavior, not a broker-native payload. Capability
references and a caller-supplied support fact are evidence, not an encoding,
entitlement proof, authorization, or submission.

## Completed-daily bar fact

The bar preserves the core information states `known`, `unknown`,
`not_obtained`, `conflicting`, `decode_failure`, and `not_applicable`.

- A known value contains exact decimal `open`, `high`, `low`, and `close`
  lexemes plus one source.
- A conflicting value contains two through 20 complete sourced bar
  alternatives; no alternative is selected.
- Other states retain the source, reason, and raw value where applicable.
- Every source carries kind, SHA-256 reference, effective/retrieval instants,
  currency, unit, exact source lexeme, scope, and retained alternatives.

Known bars must satisfy the core geometry law: `high >= low`, and open/close
must lie within the range. Invalid geometry is a mechanical request error, not
a plugin verdict. The bar source may be provider-observed or caller-declared;
its content hash does not authenticate provider origin.

Daily OHLC proves neither intraday sequence nor the user's fill. No volume,
adjustment, calendar, listing-status, freshness, entitlement, or bar-completion
fact is invented when the caller omits it; those facts travel through explicit
references or remain outside this narrow shell.

## Capability support fact and policy

`desiredOrderSupported` is a sourced Boolean information fact with the same
states as the bar. It means only that the exact referenced capability evidence
states whether the desired behavior is supported for the declared scope. It is
not promoted to exchange-native availability, account entitlement, order
acceptance, or authorization.

The caller selects one policy:

- `record_only_v1`: retain the support fact and references, but daily-bar path
  calculation depends only on the desired limit and known bar; or
- `require_known_true_v1`: perform only when the fact is known `true`, otherwise
  return the exact mechanical unperformed state.

The plugin does not derive the Boolean from documentation, select a capability
candidate, or transform an unsupported behavior.

## Request policy and budgets

Every call explicitly supplies:

- `operationId`, `model: "bar_possible_paths_v1"`, and
  `calculationPolicy: "limit_touch_v1"`;
- `capabilityPolicy` and `branchPolicy: "all_branches"`;
- session scope, date/time scope, and currency policy;
- output scale and rounding mode for the core request receipt (the branch model
  itself performs no decimal rounding);
- reference arrays for capability, rule, calendar, market-event, lifecycle,
  position, risk, cost, and FX evidence;
- positive `maximumBranches`, `maximumOutputs`, `maximumBytes`, and
  `maximumOperations` budgets; and
- `compact` or `receipt` projection.

The shell supplies conservative positive constants for the core event, depth,
and fill budgets because this daily-bar model consumes none of those resources.
Caller budgets remain explicit for every resource the tool can return.

## Result and receipt contract

Every result is versioned and includes:

- the operation, desired-instruction summary, input fact states, exact policies,
  and performed or unperformed result;
- request and semantic receipt handles from `finance_execution`;
- exact receipt envelope strings only for projection `receipt`;
- neutral available operations: `simulate_bar_paths`, `supply_bar`,
  `supply_capability_fact`, `calculate_all_branches`, and `inspect_branch`;
- `decisionOwner: "llm"` and an empty `pluginDecisionFields`; and
- limitations separating compatibility calculation and content binding from
  actual sequence, fill, capability truth, source authenticity, execution
  quality, authorization, or professional sufficiency.

The shell does not define a parallel receipt format. Its compact JSON is a
projection of the same core instruction, facts, branch result, request, and
semantic receipt.

## Architecture and effects

```text
untrusted Pi simulation query
          │
          ▼
typed boundary decoder
          │
          ▼
pure desired instruction + sourced fact preparation
          │
          ▼
finance_execution instruction / simulation / request / receipt
          │
          ▼
Pi text + structured result
```

- `pi_sparkles_order_simulator.gleam` only registers the Pi tool.
- `pi_sparkles_order_simulator/decode.gleam` decodes untrusted input into
  immutable boundary values.
- `pi_sparkles_order_simulator/domain.gleam` validates exact variants,
  constructs core values, runs the explicitly requested model, and renders a
  deterministic projection.
- No module performs network, filesystem, environment, clock, randomness,
  storage, account, broker, entitlement, or mutation effects.
- One call has one exact track, listing, MIC, account scope, and native
  currency. Nothing can silently move among `cn`, `hk`, and `us`.

## Lifecycle, testing, and stop point

The plugin is stateless. `/new`, `/fork`, `/resume`, compaction, reload, and
shutdown require no restoration or cleanup. A caller persists any desired
instruction, receipt handle, selected branch, or journal link elsewhere.

The implemented slice passed eight focused pure/domain tests for touched and
untouched buy/sell limits, unavailable/conflicting bars, capability policies,
unsupported behaviors, invalid geometry, track isolation, receipt determinism,
budgets, and forbidden decision language. Two bundled boundary scenarios cover
the compact all-branch routine, receipt projection, exact unperformed states,
and malformed inputs. Artifact export, installed-Pi smoke, architecture checks,
and the full `bun run test` repository regression passed on 2026-08-08. Session
17 does not warrant a tutor-LLM run for this stateless thin shell.

The first slice stops after limit-order compatible paths over one supplied
completed-daily bar. It deliberately excludes stop/target ordering, stop-limit
activation, trailing logic, market/MOC/LOC/auction models, volume participation,
top-of-book, depth sweeps, queues, intraday sequences, costs, lifecycle replay,
provider adapters, persistence, paper mutation, and live submission. Those
require a named Session 17 depth trigger; complete intraday workflow and live
execution remain separately gated.
