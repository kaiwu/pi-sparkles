# finance_hkex

Experimental read-only adapter for exact, already-known PDF documents on
[HKEXnews](https://www.hkexnews.hk/). A typed reference proves Gregorian date,
13-digit identifier shape, and identifier/date-prefix coherence before it can
construct the `listedco/listconews/sehk` path. The shared runtime allowlists one
exact origin/path and applies bounded retry, cancellation-aware pacing,
concurrency, and queueing.

The adapter retains the original bytes as base64, hashes those bytes with
SHA-256, requires a PDF signature, and records HK-track, `NoRedistribution`
evidence attributed directly to HKEXnews. `capture_inspected` additionally
binds a bounded real-parser page count to the same artifact hash. It does not
perform document search, parse filing semantics, inspect the text layer, or
infer issuer identity.

Normal tests use constructed responses and never make live requests.
