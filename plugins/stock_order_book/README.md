# stock_order_book

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`stock_order_book` is the provider-neutral Pi boundary for inspecting one exact
top-of-book packet on the `cn`, `hk`, or `us` track. It is the bounded
multi-report and stream-integrity companion to `stock_quote`: it accepts facts
already produced by a caller or provider adapter and does not make a network
request.

## First-slice user story

`stock_top_of_book` accepts one exact listing and first-slice MIC plus one to 25
source records and one to 100 top-of-book reports. Each report retains:

- exact currency, condition codes, source lexemes, provider publication time,
  local receipt time, and reported or unknown exchange time;
- bid and ask as independently observed, unavailable, or conflicting states;
- exact raw and normalized non-negative price and displayed-size lexemes for
  every observed or conflicting candidate;
- the candidate's exact reported MIC or provider venue code;
- a caller-declared and unverified size unit;
- reported or unknown sequence number and listing/feed-global sequence scope;
- explicit no-gap-reported, sequence-gap, sequence-reset, or unknown gap state;
- single-venue, consolidated, provider-defined, or unknown aggregation, its
  exact included venue set, method label where applicable, and declared
  complete/partial/unknown coverage; and
- canonical source, entitlement, licence, acquisition receipt, and redacted
  source-reference metadata.

The result is input-ordered and stably paged. It reports exact counts and keeps
each report in a `finance_core.Observation` envelope. It does not merge reports
or choose one. A content-bound calculation receipt covers the normalized
packet projection even though no price or execution calculation is performed.

## Input and validation contract

The listing contains exact `listingId`, `symbol`, `mic`, and currency. The
first slice accepts only `XSHG`, `XSHE`, or `XBSE` on `cn`; `XHKG` on `hk`; and
`XNYS` or `XNAS` on `us`. Identity and currency are caller-supplied and remain
unverified.

Every source has a unique `sourceId`, provider, feed, source kind/reference,
declared entitlement, licence, and SHA-256 acquisition receipt. Unsafe URL
credentials and query secrets are redacted before a reference is returned. A
matching receipt is not provider authentication or a redistribution grant.

Every report has a unique `reportId` and references exactly one supplied
source. Provider time must not follow receipt time. Exchange time may be
reported or explicitly unknown; no ordering conclusion is drawn from clocks
that the shell has not synchronized.

An observed side contains one candidate and no alternatives. An unavailable
side contains only a reason. A conflicting side contains a reason and two to
ten distinct candidates, each with its own SHA-256 evidence ID. Candidates
retain exact price, displayed size, and venue. Price and size must be valid
non-negative decimals, but zero is preserved rather than interpreted.

Aggregation is a declaration, not a venue-authority or best-price proof.
`single_venue` requires one included venue. `consolidated` and
`provider_defined` require one to 25 unique included venues; provider-defined
aggregation also requires its exact method label. Each observed or conflicting
candidate venue must occur in that report's included venue set when the
aggregation kind supplies such a set. `unknown` aggregation retains candidate
venues without claiming how they were aggregated; it requires a reason and
forbids a venue set or method label.
`declared_complete`, `declared_partial`, and `unknown` aggregation coverage are
retained verbatim and never upgraded into an NBBO or whole-market claim.

Reported sequence state requires a non-negative safe integer and an exact
`listing` or `feed_global` scope. Unknown sequence state requires a reason.
`sequence_gap` retains inclusive missing `fromSequence` and `toSequence`;
for `sequence_reset`, those fields retain the prior and reset-at values and the
output labels those semantics explicitly. No-gap-reported carries no stronger
continuity or recovery claim. Gaps and resets are never repaired.

The output always warns that displayed size can change or disappear, does not
describe hidden liquidity, is not durable, and is not an executable-price or
fill promise.

## Public package surface

- `pi_sparkles_stock_order_book.extension` registers `stock_top_of_book` as a
  parallel read-only Pi tool.
- `pi_sparkles_stock_order_book/decode` owns the untrusted JSON boundary.
- `pi_sparkles_stock_order_book/domain` owns pure validation, canonical
  observation construction, stable paging, receipt projection, and JSON
  rendering.

The domain shell uses `finance_core`, `finance_provenance`, and `finance_track`.
It does not import another market-owned package and has no JavaScript FFI or
mutable business state.

## Explicit non-goals

This slice performs no provider/feed selection, fallback, authentication,
acquisition, retry, cache, persistence, stream subscription, event reordering,
gap repair, snapshot/delta application, depth reconstruction, NBBO inference,
cross-track relabelling, source correctness or freshness verdict, spread or
midpoint calculation, hidden-liquidity estimate, queue-position estimate,
durability claim, executable-price promise, fill prediction, routing, ranking,
signal, recommendation, order, or trade action.

Depth levels, deltas, auction books, and order-by-order feeds remain later
`stock_depth`/`/book` work. Provider-specific pacing, outage, licence, and
authentication behavior belongs in a separate adapter and must remain explicit
when its facts enter this shell.

## Permissions and lifecycle

The tool is non-interactive, network-free, secret-free, and read-only. It uses
only call-local immutable values, so reload, new/resume/fork, compaction, and
shutdown retain no hidden state and require no cleanup. The caller owns any
durable packet or cursor storage.

## Verification and distribution

Seven pure tests cover all side states, venue/aggregation laws, sequence gaps
and resets, clock bounds, exact decimal preservation, track/MIC isolation,
source redaction, and stable paging. Three Bun binding scenarios cover
successful multi-report output, unavailable/conflicting stream facts, and
rejected track/aggregation contracts. Architecture, warnings-as-errors,
artifact default-export, installed-Pi smoke, acceptance, and the full repository
suite pass.

The package targets the repository's tested Pi `0.83.0` binding. Hex source will
contain `gleam.toml`, `README.md`, and Gleam `src/` modules; generated `build/`,
`dist/`, and `manifest.toml` remain excluded. Users build the Pi adapter with:

```sh
bun run build -- stock_order_book
```

The focused local commands are:

```sh
bun run test:unit -- stock_order_book
bun run build -- stock_order_book
```
