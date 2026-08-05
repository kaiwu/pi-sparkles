# finance_cninfo

Experimental read-only adapter for exact, already-known PDF documents in the
[CNINFO official disclosure repository](https://www.cninfo.com.cn/). A typed
reference constructs only the static `finalpage/YYYY-MM-DD/identifier.PDF`
path; the shared runtime allowlists that one exact origin/path and applies
bounded retry, cancellation-aware pacing, concurrency, and queueing.

The adapter retains the original bytes as base64, hashes those bytes with
SHA-256, requires a PDF signature, and records CN-track, `NoRedistribution`
evidence attributed to CNINFO as the repository. It does not search CNINFO,
parse filing semantics, inspect the text layer, or infer that the filing was
issued by SSE, SZSE, or BSE. `capture_inspected` additionally binds a bounded
real-parser page count to the same artifact hash. Venue attribution requires
separate official discovery metadata or decoded document identity evidence; a
caller-provided hint is not proof.

Normal tests use constructed responses and never make live requests.
