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
