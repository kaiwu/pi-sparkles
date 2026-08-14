# pi_sparkles_broker_readonly_alpaca

Status: **Experimental implementation — owned by T6** · Alpaca is an explicit external dependency

`review_alpaca_activity_import` validates bounded normalized US account,
position, order, fill, capability, entitlement, and lifecycle evidence from an
explicit Alpaca read-only capability or caller-owned export. Provider identity
and read-only authority must be exact; XNYS/XNAS scope, unknowns, conflicts,
status lexemes, chronology, and receipts are preserved.

The package bundles no Alpaca SDK, credential, adapter, or network transport,
does not authenticate Alpaca, and cannot mutate an account or order. Focused Pi
coverage is in `test/binding/broker_readonly.test.js`.
