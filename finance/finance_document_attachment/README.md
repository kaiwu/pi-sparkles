# finance_document_attachment

Experimental pure acceptance policy for market-document attachments. An effect
shell performs a bounded download, redirect observation, cancellation, hashing,
and media/page inspection, then submits immutable metadata to this package.

The policy enforces an exact media allowlist, byte and page ceilings, redirect
budget, optional cross-host redirect rejection, cancellation, and required
SHA-256 identity. Archives and OCR are explicitly unsupported and fail closed;
they are never silently unpacked or delegated. Accepted metadata can construct a
`finance_market_documents.Attachment` while retaining the proven content hash.

This package does not perform network, filesystem, archive, PDF, or OCR effects.
Provider adapters must still use `finance_http` for bounded transport and host/
method policy.
