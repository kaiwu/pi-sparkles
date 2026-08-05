# finance_hk_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_hk_calendar` binds caller-supplied HKEX session data to the `hk`
track, `XHKG`, `Asia/Hong_Kong`, an explicit source/licence/version, and bounded
coverage. It shares the generic calendar engine and dataset wrapper with the
mainland package while retaining a separate user and domain contract.

The Monday–Friday helper is only a base template. No HKEX holidays, typhoon or
extreme-weather arrangements, half days, or exceptional notices are bundled or
inferred. Outside coverage is unknown and returns an error. Synthetic tests
exercise multiple sessions and the midday gap without claiming provider data.
