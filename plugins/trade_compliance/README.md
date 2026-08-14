# pi_sparkles_trade_compliance

Status: **Experimental implementation — owned by T6** · typed supplied-rule evaluation

The plugin exposes three pure non-executing tools:

- `evaluate_supplied_trade_rules` evaluates bounded effective-dated compound
  `predicate`/`all`/`any`/`not` expressions independently as True, False,
  Unknown, NotApplicable, or Conflict with full explanation trees;
- `explain_supplied_trade_predicate` explains one expression and retains every
  matched fact, exact duplicate, conflict, and unknown reason;
- `compare_supplied_trade_rule_versions` retains scope, interval, expression,
  severity, authority-receipt, and declared correction-lineage changes.

The rule source is an explicit external capability or caller-owned import. The
package performs no acquisition, authenticates no legal authority or
completeness claim, produces no aggregate legal verdict, and cannot mutate an
order. Focused coverage is in the package tests and
`test/binding/trade_compliance.test.js`.
