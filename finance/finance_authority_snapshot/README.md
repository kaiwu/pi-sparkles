# finance_authority_snapshot

Experimental provider-neutral acquisition support for official public text and
binary artifacts. It validates one-track authority policies, exact media/byte
bounds, source kind, and time order, then records the unmodified UTF-8 text or
byte-preserving base64 body as a `finance_provenance.Evidence` record. Binary
captures use the transport's SHA-256 over the original bytes and verify the
declared file signature. Captures are explicitly `NoRedistribution` and
local-analysis-only.

The shared text and binary runtimes own bounded retry, cancellation-aware
pacing, concurrency, queueing, and an origin/path allowlist. Source adapters
supply the exact policy; plugins do not create local HTTP or cache stacks. Unit
tests use constructed responses and injected effects only. This package does
not parse HTML/XML/PDF semantics, infer publication dates, inspect text layers,
or make issuer/venue identity claims from repository paths alone. The separate
`finance_authority_pdf` package binds a `finance_pdf` structural inspection to
the exact same response and evidence hash without making text-only adapters
depend on PDF.js.
