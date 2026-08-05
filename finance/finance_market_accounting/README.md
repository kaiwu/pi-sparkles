# finance_market_accounting

Experimental lossless reported facts, executable mappings, and strict
schema-v1 JSON. Numeric source tokens and scale multipliers are encoded as JSON
strings, so binary floating-point coercion cannot silently change a filing.

Experimental lossless domain types for market-reported accounting facts.
Numeric source tokens remain exact strings until `normalized_numeric` applies a
validated reported-scale multiplier through `finance_core` decimal arithmetic.

Facts retain listing, source document, original line code/label, reported unit
and scale, normalized unit, accounting standard, consolidated/parent scope,
exact period, report class, audit/restatement state, and evidence identity.

Mappings are executable data: normalized name, accepted line codes, unit kind,
period kind, and method are visible. Resolution requires one exact listing,
period, and scope, and preserves duplicates as `Ambiguous`; it has no hidden
line-code or restatement precedence.
