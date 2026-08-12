# finance_notification_scripted

Deterministic notification effect used to prove Tier 3 authorization,
idempotency, bounded-attempt, cancellation, rate-limit, failure and delivery
handling without production credentials. The caller supplies an opaque
destination reference and an explicit scripted outcome. The adapter emits only
a content-bound attempt receipt; it performs no network I/O and stores nothing.
