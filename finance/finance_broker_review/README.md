# finance_broker_review

Pure validation, deduplication, conflict detection, and content-receipt logic
for non-executing broker-related plugins. The package accepts only bounded
caller-supplied facts and lifecycle observations. It has no transport, broker
session, credential, market-depth, or order-mutation capability.

Every successful projection is explicitly `track_partial`. A provider-specific
plugin must add its unavailable capabilities, and the core rejects a projection
that tries to report an empty missing-capability set.

The semantic receipt binds the supplied projection. A caller-provided source
hash is retained only as a reference: without source bytes the core explicitly
reports that it did not verify that hash or authenticate provider origin.

The core caps facts, events, and the complete canonical semantic payload in
encoded bytes; rejects control characters, credential-shaped names/values,
unsafe integer times, cross-track MICs, and every market-depth field; and keeps
input order distinct from event chronology. Results expose
`lastInputStatusLexeme`, an explicit nondecreasing or nonmonotonic time-order
fact, the greatest occurred-at time, and every distinct status tied at that
time. They never invent one “latest” status from list order.
