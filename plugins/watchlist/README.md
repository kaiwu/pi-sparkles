# pi_sparkles_watchlist

`watchlist` is the first Experimental persistent workflow-state slice. It
registers `/watch`, `watchlist_add`, `watchlist_remove`, and
`watchlist_snapshot`.

Every member is keyed by the complete caller-supplied tuple:

```text
track | MIC | symbol | namespaced instrument ID
```

The only track values are `cn`, `hk`, and `us`. Instrument IDs must be
namespaced, for example `figi:BBG000B9XRY4`, `cninfo:000001`, or
`hkex:00700`. Symbols and MICs are stored exactly after strict uppercase
validation. The plugin never resolves a symbol, infers a venue, moves a member
between tracks, or presents caller-supplied identity as authoritative.
Mainland entries are limited to six-digit `XSHG`/`XSHE`/`XBSE` keys, Hong Kong
entries to five-digit `XHKG` keys, and US entries to the explicitly supported
US exchange MIC set. A syntactically valid but cross-track MIC fails closed.

`watchlist_add` creates a lowercase named watchlist when needed and adds or
updates its exact listing member. A member may carry one compact note, one
HTTPS thesis link, and bounded lowercase tags. Repeating the identical input is
idempotent and does not append another persistence event. `watchlist_remove`
requires the same complete listing key; removal by symbol alone is unavailable.

Persistence uses versioned mutation entries on Pi's active session branch.
State is restored by replaying every matching entry in branch order with
strictly contiguous revisions. Resume and inherited fork history work; moving
to another branch immediately restores that branch's state. Malformed,
missing-payload, non-contiguous, or invalid events lock mutation instead of
being ignored or overwritten.

This first slice deliberately does **not** provide cross-session `/new`
durability. A fresh session starts empty. User-owned directory/database storage,
import, merge/conflict handling, and cryptographic snapshot binding need a
separate reviewed storage capability. `watchlist_snapshot` returns a stable
versioned JSON result suitable for explicit export, but it is not yet an import
format or evidence manifest.

Hard bounds are 20 named lists, 200 members per list, 1,000 members in total,
20 tags per member, and 10,000 mutations per branch. The plugin performs no
provider or model request and has no environment-variable dependency.

```sh
bun run check -- watchlist
bun run test:unit -- watchlist
bun run build -- watchlist
bun run test:pi -- watchlist
```
