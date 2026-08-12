# finance_monitoring

Pure provider-neutral monitoring contracts for Tier 3. The source projection
validates and pages exact content-bound event receipts without collapsing
corrections, retractions, duplicates, equal-time events, original language,
track identity, source failures, entitlement, licence, coverage, or date
semantics. The durable alert module owns versioned monitor definitions,
mechanical predicate states, cooldown/deduplication facts, append-only event
replay, correction lineage, privacy, notification authorization and delivery
attempt receipts.

Alert journals use immutable event/idempotency indexes and reverse internal
storage so bounded replay is not quadratic. Replay revalidates the same event
kind, definition lineage, active definition, disable, complete evaluation
shape, and notification-authorization laws as live append; a matching
self-supplied hash cannot admit an incomplete event. Evaluation builds one
exact decoded observation index per call, applies the configured content-hash
window within and across batches, and authorizes only exact decoded match IDs
rather than payload substrings.

The package never polls, schedules, chooses a source, interprets materiality,
infers urgency or causality, selects a notification destination, or takes a
portfolio/trading action.
