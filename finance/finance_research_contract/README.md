# finance_research_contract

Pure versioned import contract for T2 research evidence. A packet binds one
exact role contract, track, listing/issuer/share-class subject, source document,
rights, retrieval/publication times, typed information-state fields, correction
lineage, omissions, and exact source bytes. Inspection is stable-paged and
drill-down is by record ID. The core rejects a wrong contract/track/MIC,
unsupported record kind, duplicate IDs/fields, malformed information states,
impossible correction references, oversized collections, or a mismatched
SHA-256 digest.

This package performs no I/O and imports no Pi package. `finance_local_import`
is the bounded effect adapter; market-owned plugins provide exact descriptors.
