# finance_hk_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_hk_calendar` binds caller-supplied HKEX session data to the `hk`
track, `XHKG`, `Asia/Hong_Kong`, an explicit source/licence/version, and bounded
coverage. It shares the generic calendar engine and dataset wrapper with the
mainland package while retaining a separate user and domain contract.

The Monday–Friday helper remains available for injected datasets. The package
also supplies a source-reviewed `official_2026` securities-market dataset from
HKEX circular CT/075/25. It preserves every published full closure and the
three published half-days, with exact source/version/coverage and unknown-
redistribution metadata.

Outside 2026 is unknown and returns an error. The broad equity calendar omits
extended-morning eligibility and the random closing-auction window rather than
claiming they are continuously open. Settlement, Stock Connect, derivatives,
security-specific suspension, typhoon/severe-weather state, and later
exceptional notices remain separate contracts. Tests cover source identity,
full closures, half days, the midday gap, and coverage edges.
