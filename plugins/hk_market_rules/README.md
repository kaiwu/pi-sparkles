# hk_market_rules

Track-isolated Pi tool `hk_trading_rules` for the HKEX minimum-spread phases in
force from 2026-08-03. Its approved slice is deliberately narrow: an
independently proven applicable HKD equity with nominal price from 0.50
inclusive to 50.00 exclusive.

Hong Kong board lots are issuer-specific. The caller must provide both the
positive board-lot value and an auditable HKEX/issuer reference; the tool
preserves them as caller-supplied and unverified. It never substitutes 100 or
another universal quantity. ETPs, debt, options, structured products, non-HKD
counters, VCM/CAS, settlement, short selling, and listing-specific eligibility
remain outside this reviewed profile. Source redistribution rights are unknown.
