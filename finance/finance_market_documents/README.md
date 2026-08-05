# finance_market_documents

Experimental provider-neutral disclosure identity, lineage, attachments, and
strict schema-v1 JSON. The wire codec preserves track/MIC issuer identity,
Unicode originals, period, source, and evidence, and rejects unknown versions
or invalid track/listing combinations.

Experimental track-scoped identity for disclosures and related documents. It
preserves exact Unicode titles and optional original text, language, issuer,
publication time, reporting period, source, and evidence identity.

Corrections, replacements, supplements, translations, and parallel-language
publications retain both document identities. Attachments retain media type,
declared byte length, content hash, and evidence identity. This domain model
does not fetch attachments; bounded retrieval and archive/OCR policy belong to
a separate effect boundary.
