# finance_quote

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_quote` models an exact provider-reported best bid and ask without
claiming consolidated-market coverage. Prices and sizes retain both the source
JSON lexeme and a normalized decimal. Exchange codes, condition codes, tape,
currency, provider timestamp, and the provider's unverified size unit remain
visible.

The package constructs a canonical `finance_core.Observation(Quote)`, rejects
negative prices and sizes, unsafe text, provider mismatch, and retrieval times
before the quote timestamp. It deliberately retains locked or crossed source
quotes: interpreting those states requires market and condition context that a
generic value constructor does not possess.

This package has no Pi, HTTP, provider, clock, storage, or entitlement logic.
