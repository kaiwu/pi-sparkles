# quant_research

Experimental, stateless Pi shell over the resolved `finance_replay`
shared-research information contract. It registers exactly three tools:

- `inspect_trial_ledger` reconstructs the supplied append-only core ledger,
  verifies the caller-declared complete population counts, returns compact
  status and parameter facts, and pages events in their original order.
- `request_metric` executes one explicitly requested core calculation:
  `net_return`, `win_loss_counts`, `drawdown_series`, or `trade_list`.
- `compare_runs` verifies two exact canonical `finance_replay` run definitions
  and reports their mechanical input and caller-supplied output differences.

## Trial-ledger contract

The caller supplies an attributed hypothesis declaration, a population ID, the
ordered trial-ledger events, expected counts for all seven core states, and an
explicit `caller_declared_complete_population_v1` policy. The plugin verifies
the hypothesis content hash, reconstructs every `trial.Definition` and
`trial.LedgerEvent`, applies the core idempotency/conflict laws, and requires the
actual counts to equal the declaration. It cannot independently prove that an
external caller omitted no trials; that limitation remains visible.

Compact pages retain trial/event IDs, definition and envelope handles, status,
parameter values, output receipts, and error facts. Full trial envelopes are
included only when `includeTrialPayloads` is explicitly true. Hypothesis prose
is included only when `includeHypothesisText` is true. Stable paging uses the
core ledger cursor, which does not change with offset or limit. Failed,
cancelled, truncated, duplicate, and unperformed trials remain visible and are
never pruned or relabelled.

## Metric and comparison contract

Every metric request declares request/formula/version/unit/scale/rounding,
missing/conflict policy, sample population, ordering, benchmark fact, and
source receipts. Metric-specific operands preserve exact decimal lexemes and
receipts. The plugin calls the corresponding `finance_replay.metric` function;
it does not choose a metric, formula, rounding policy, sample, zero policy,
peak convention, benchmark, or trade population.

Run comparison requires the exact canonical definition JSON and matching digest
for both sides. Output fields are exact caller-selected name/value/receipt
triples with unique names per side. `finance_replay.comparison` reports only
mechanical differences and retains both receipt sets. It does not attribute
causality, prefer a run, or interpret a result.

## Stop point

This first slice performs no fetch, storage, append effect, search, parameter
generation, optimization, model training, statistical-significance test,
research grading, edge/robustness claim, deployment choice, or next-operation
selection. `pi_backtest` remains a separate later shell for run submission,
event drill-down, and reproduction export.

Lifecycle: **Experimental**. Additional metrics or statistics require an exact
caller workflow and preserve the same calculation-only boundary. A new tutor
gate is required if scope expands into research search/optimization, validation
verdicts, or deployment decisions.

Verification covers complete status accounting, failures and idempotency
conflicts, stable paging and payload omission, every named metric including an
unperformed result, canonical run-definition checking, output alignment,
decision-boundary fields, bundled tool interaction, artifact export,
architecture, installed-Pi loading, and full repository regression.

Build and test with:

```sh
bun run test:unit -- quant_research
bun run build -- quant_research
```
