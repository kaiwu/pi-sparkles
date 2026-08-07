# pi_sparkles_trade_journal

Status: **Experimental**. Course gate `CG-PSYCHOLOGY` journal-information slice
resolved 2026-08-07 by
[Session 15](../../../trading-course/sessions/15_cg_psychology_journal_information_contract_20260807.md).

`trade_journal` is a thin Pi shell over `finance_journal`. It stores exact
attributed journal information in an explicit user-selected local JSONL file
and exposes it efficiently to the LLM. It never infers an emotion or bias,
diagnoses the user, evaluates discipline or process, judges correctness or
sufficiency, explains P&L, chooses a review prompt, changes risk, recommends a
response, authorizes a trade, or selects the next operation.

## Professional workflow

The routine path is intentionally short:

1. `/journal <path>` or `journal_context` loads compact counts and stable drill
   operations without prose.
2. `journal_search` retrieves a bounded exact working set. Private payloads are
   omitted unless the caller explicitly requests them.
3. `journal_entry` appends a user/LLM declaration, observation reference,
   checklist response, review conclusion, correction, redaction, or marker.
   `trade_review` is the review-conclusion-specific entry surface.
4. `journal_compare` and `journal_stats` perform only the comparison or realized
   net-P&L calculation explicitly requested by the LLM.
5. `journal_export` and `journal_import` move canonical events without changing
   attribution, identity, privacy, hashes, or correction lineage.

Swing and other workbenches may retain journal event IDs. They do not copy the
payload or treat branch-local state as durable journal storage.

## Commands and tools

| Surface | Information contract |
| --- | --- |
| `/journal <local-jsonl-path>` | Compact revision/event counts; never payload prose |
| `journal_context` | Content-bound compact context, omission counts, and neutral available operations |
| `journal_entry` | One exact immutable attributed event with expected revision and idempotency key |
| `trade_review` | The same append contract restricted structurally to `review_conclusion` |
| `journal_search` | Explicit kind/author/privacy/workflow filters and result/byte bounds |
| `journal_compare` | Requested exact equality or decimal delta over supplied plan/observation states |
| `journal_stats` | Requested `long_cash_realized_net_pnl_v1` over exact fill/cost lexemes |
| `journal_export` | Caller-selected privacy/supersession JSONL projection; writes no destination |
| `journal_import` | Atomic bounded canonical JSONL batch import with per-event stored/already-stored outcomes |

All mutation tools are sequential in one Pi extension instance. Every append
also uses the caller's expected revision and a generic compare-and-replace
storage effect, so another process yields a visible conflict rather than a
chosen retry.

## Storage, privacy, and trust boundary

The initial backend is local-first JSONL at the exact path supplied on every
call. Reads and replacements are bounded. Replacement uses a mode-0600
temporary file, fsync, atomic rename, and a mode-0600 exclusive sidecar lock.
There is no automatic retry or stale-lock policy; a busy lock is a conflict fact
for the LLM/user. Existing symbolic links and non-regular files are rejected.
An existing malformed or over-budget file is never overwritten.

The result reports destination, backend, atomic-replace, concurrency, and
no-retry facts. Ownership, encryption at rest, access control, backup status,
and sync status are `not_obtained`; the plugin makes no “secure storage” claim.
No telemetry or network effect exists. Error strings never contain event
payloads. Redaction appends lineage and does not claim to erase prior exports or
backups.

JSONL contents are user-owned plaintext. The user is responsible for directory
permissions, backups, encryption, retention, and explicit export destination.

## Modules

| Module | Responsibility |
| --- | --- |
| `pi_sparkles_trade_journal` | Pi/Promise effect shell, tool schemas, bounded effect orchestration |
| `pi_sparkles_trade_journal_local_file` | Generic async local-file effect decoding only |
| `pi_sparkles_trade_journal/decode` | Runtime decoding into typed inputs |
| `pi_sparkles_trade_journal/domain` | Pure event construction and exact structural shape checks |
| `pi_sparkles_trade_journal/render` | Deterministic structured results, privacy omission, neutral operations |
| `finance_journal/*` | Pure events, replay, query/export, checklists, comparisons, metrics, context, receipts |

JavaScript contains only generic bounded file I/O, locking, compare-and-replace,
and atomic replacement. It contains no journal, psychology, finance, or workflow
logic.

## Lifecycle and failure behavior

Durability is independent of Pi branches. Reload, `/new`, fork, compaction, and
shutdown do not clone, rewrite, or delete the file. Each tool reloads and
validates the current file before use. Same idempotency key plus identical
semantic content returns the original event even after a lost acknowledgement;
the same key with different content is a structural conflict. Corrections and
redactions require an existing `supersedes` event. All imported writes are
computed in immutable memory and committed atomically.

Cancellation before rename leaves the journal unchanged. After rename, the
effect reports the committed replacement. I/O failures expose only a bounded
error code. The plugin never selects retry, merge, conflict resolution, or
deletion policy.

## Build and verification

```sh
bun run check -- trade_journal
bun run test:unit -- trade_journal
bun run build -- trade_journal
bun run test:pi -- trade_journal
bun test test/binding/trade_journal.test.js
```

The first slice has five plugin pure tests, twenty `finance_journal` core tests,
four binding scenarios with thirty assertions, functional-architecture checks,
artifact verification, and Pi smoke loading. Tests use temporary local files;
they perform no live network call, real sleep, ambient credential access, or
shared mutable cache.

## Known limitations

The backend currently rewrites the bounded JSONL file per committed batch and
does not implement pagination cursors, bounded partial import, hard deletion,
stale-lock recovery, database indexes, or encrypted storage. Only realized
long-cash net P&L and explicit pairwise comparison are exposed as calculation
tools. Streak projections, MFE/MAE, holding duration, R-multiple, periodic review
packets, and additional adapters remain incremental.

No current or future gap authorizes plugin-owned psychology, process, market,
workflow, correctness, sufficiency, or trade decisions. The LLM remains the
sole decision maker.

Hex distributes this Gleam and FFI source. Consumers must compile it to
JavaScript and generate Pi's default-export adapter; this repository's Bun
builder produces `dist/trade_journal/index.js`.
