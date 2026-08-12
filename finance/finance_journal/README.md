# finance_journal

`finance_journal` is the Experimental pure information core for the resolved
`CG-PSYCHOLOGY` journal-information slice. It preserves exact attributed events,
unknowns, conflicts, privacy classification, correction lineage, requested
calculations, and content-bound receipts. It never infers psychology, evaluates
process, labels discipline, explains performance, recommends a risk response,
or decides a trade or next operation. The LLM owns all of those decisions.

## First slice

- `finance_journal/event` defines immutable declarations, observation
  references, checklist responses, review conclusions, corrections, redactions,
  and import/export markers. Attribution distinguishes user, LLM, imported,
  provider, broker, system, and calculated facts.
- `finance_journal/information` preserves known, unknown, not-asked,
  not-obtained, declined, not-applicable, conflicting, decode-failure, redacted,
  and superseded states.
- `finance_journal/state` provides pure append, atomic in-memory batch append,
  idempotency, replay, current and point-in-time projections, bounded query, and
  caller-selected JSONL export. Contradictory events remain separate facts.
  Append/replay uses immutable ID and idempotency indexes plus reverse internal
  storage, while every public projection remains chronological.
- `finance_journal/checklist` records versioned definitions and partial answer
  states without pass/fail, prompt selection, or scoring.
- `finance_journal/comparison` calculates only caller-requested exact equality
  or decimal deltas and retains both planned and observed states.
- `finance_journal/metric` implements only the explicitly requested
  `long_cash_realized_net_pnl_v1` expression over exact fill/cost lexemes and
  source receipts.
- `finance_journal/context` returns counts, omission counts, and neutral drill
  operations without journal prose.
- `finance_journal/receipt` produces non-self-referential SHA-256 envelopes.

Identity may be journal-wide, track-wide, an exact track/listing/MIC, or an
explicit unresolved listing. A journal never silently changes `cn`, `hk`, or
`us`, and a display symbol is not treated as permanent identity.

## Effects and portability

This package performs no file, Pi, clock, network, or storage effect. The
[`trade_journal`](../../plugins/trade_journal/README.md) shell interprets the
first local JSONL backend. It loads a bounded file, replays it here, computes a
complete immutable next state here, and persists only after the whole pure
transition succeeds. JSONL export/import preserves each canonical event
envelope exactly.

The current bounded core supports 100,000 total events, 65,536 characters per
event payload, and 64 receipt references per event. Callers additionally choose
query, import, export, and storage byte bounds at the shell.

## Verification

```sh
gleam format --check src test
gleam check
gleam test --target javascript
```

Twenty-one deterministic tests cover wire/hash round trips, attribution and
unresolved identity, correction/redaction structure, idempotency conflicts,
atomic batch transitions, historical projections, replay failures, privacy
selection, query bounds, partial checklists, requested comparisons and P&L,
compact context, same-symbol cross-track isolation, and a 5,000-event ordered
batch.

## Known incremental work

Additional requested metrics, streak projections, pagination continuations,
bounded partial import, deletion effects, database adapters, and persona review
templates remain incremental. Expectancy, Sharpe, significance, causal claims,
and deployability belong to `CG-QUANT`; portfolio attribution belongs to
`CG-PORTFOLIO`; live-trading integration belongs to `CG-LIVE`. Their absence is
information for the LLM, not a reason for this package to decide correctness.
