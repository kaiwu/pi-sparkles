# finance_hk_identity

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_hk_identity` is the isolated Hong Kong listing identity layer. Each
listing requires a canonical instrument ID, an exact five-digit code (including
leading zeroes), HKEX MIC `XHKG`, explicit Main Board/GEM board, share class,
currency, and status. The package never left-pads a user code or imports
mainland board, currency, or venue defaults.

Resolution preserves ambiguity through `finance_core.identifier.Resolution`.
Historical names reuse the same evidence-backed, effective-dated alias type as
the mainland package. A/H relationships are composed explicitly by
`finance_cn_identity` over independent `cn` and `hk` listing keys.

No HKEX security master, board-lot rules, provider client, or redistribution
claim is bundled. Tests contain synthetic values only; production coverage
waits for approved source and fixture rights.
