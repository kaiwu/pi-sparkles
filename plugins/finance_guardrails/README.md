# pi_sparkles_finance_guardrails

Experimental F0 Pi extension that makes finance evidence policy executable. It
registers `/finance-policy`, `finance_validate_evidence`, and
`finance_check_freshness`.

## Policy ceiling

The plugin can reject internally incompatible evidence before a model combines
it. The first policy rejects missing sources, mixed currencies, mixed reporting
periods, mixed adjustment bases, stale values, negative ages, and invalid
entitlement labels. Unknown entitlement is preserved as a warning; it is never
silently promoted to real-time or redistributable data.

It cannot prove that a provider's claim is true, determine legal suitability,
or infer an acceptable maximum age. Callers must supply the use-case-specific
freshness threshold, and provider adapters must supply trustworthy metadata.
This is an evidence consistency gate, not investment advice or an execution
authorization system.

## Functional design

`policy.gleam` represents rules and outcomes as immutable values. Validation is
the composition of independent pure checks:

```text
EvidenceFacts
  |> source rule
  |> currency/period/adjustment consistency rules
  |> freshness rule backed by finance_core Observation.Freshness
  |> entitlement rule
  -> Decision(accepted, ordered issues)
```

All applicable issues accumulate deterministically, so a caller gets a complete
diagnosis rather than repairing one hidden failure at a time. Rules can later
be parameterized and combined without changing the Pi shell. Tests exercise
normalization, accumulation, exact freshness boundaries, and typed failures
without Pi, clocks, networking, or mocks.

The root module only decodes typed tool input, invokes the pure policy, and
encodes text plus structured JSON details. The current plugin has no state and
performs no HTTP, filesystem, environment, or subprocess effects.

## Interface

`finance_validate_evidence` accepts:

- a non-secret source reference;
- all currencies, periods, and adjustment bases in the proposed computation;
- evidence age and maximum age in milliseconds;
- `real_time`, `delayed`, `end_of_day`, or `unknown` entitlement.

Its structured result contains `accepted` plus ordered issues with stable codes,
severity, and messages. `finance_check_freshness` is the smaller reusable check.
The boundary is inclusive: age equal to maximum age remains fresh.

## Next design increments

Provider adapters should emit the canonical `finance_core.Observation(a)`
envelope. The provider-neutral `finance_evidence` package now owns the typed
unit, as-of order, quality/restatement, licence/redistribution, availability,
and track-compatibility gate for calculations. This plugin's existing
string-summary tool remains an Experimental compatibility surface until it
accepts those complete typed inputs. No live action is authorized by this
read-only plugin.

Local development uses path dependencies on `../../pi_gleam` and
`../../finance/finance_core`. Tested against Pi `0.83.0`.
