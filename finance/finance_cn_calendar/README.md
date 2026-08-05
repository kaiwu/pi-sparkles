# finance_cn_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_cn_calendar` binds caller-supplied SSE, SZSE, or BSE calendar data to
the `cn` track, the venue MIC, `Asia/Shanghai`, a source, licence, dataset
version, and inclusive coverage. It composes the generic session engine and the
bounded `finance_market_calendar` wrapper.

The package provides a Monday–Friday base-template helper, not a holiday
calendar. Production constructors must receive reviewed dated closures and
exceptional-session overrides. Queries outside dataset coverage fail and no
weekend-only inference is available through the bounded API.

No exchange fixture is bundled while authoritative source and redistribution
rights remain undecided. Unit tests use synthetic sessions and closures solely
to prove auctions, a midday gap, overrides, venue identity, and coverage-edge
behavior.
