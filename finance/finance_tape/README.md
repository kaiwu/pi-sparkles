# finance_tape

`finance_tape` is the private, provider-neutral transaction-tape core being
prepared for T6. It is pure Gleam: it imports no Pi API, performs no network or
storage effect, and cannot subscribe to a feed or mutate a broker account.

The package validates one bounded `cn`, `hk`, or `us` listing/MIC/session packet
and preserves exact transaction, sequence, condition, venue, entitlement,
licence, clock, and receipt fields. Its review reports:

- identical duplicates and conflicting reuse of an event ID;
- arbitrary-length decimal sequence gaps, duplicates, out-of-order values,
  scope changes, explicit reset boundaries, and reset predecessor mismatches;
- missing, ambiguous, self, mismatched-trade, cancel-target, and time-reversed
  correction/cancel references without reconstructing missing state;
- exchange/provider/retrieval clock ordering and signed clock differences;
- exact condition-code counts and codes not covered by the supplied condition
  documentation declaration; and
- whether coverage is provider-declared complete, bounded partial, or unknown.

Its private pure streaming state machine owns one exact stream key and emits
typed effects for subscribe, recovery, accepted batches, unsubscribe and final
status. It enforces generation-scoped callbacks, event/byte/queue/session and
operation/cleanup budgets, bounded reconnect and overlap recovery, stale/late
completion suppression, idempotent stop, and confirmed versus unconfirmed
cleanup without performing an effect itself.

The core deliberately has no quote, bid/offer, order-book, aggressor inference,
volume-profile, signal, recommendation, streaming, or execution surface. A
provider completeness declaration remains a declaration, not authentication.
The private `finance_execution` tape model may consume a validated packet to
produce explicit compatible fill/non-fill branches; it cannot convert the tape
into a broker receipt or actual-fill claim.
The T6 `stock_tape` Pi shell and all live adapters remain unwired while the live
three-track capability blocker is open.

Run its focused deterministic suite with:

```sh
bun run test:unit -- finance_tape
```

The 20 deterministic tests cover the packet laws and streaming transitions.
