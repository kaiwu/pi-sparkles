# finance_market_calendar

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_market_calendar` wraps the pure `finance_calendar` engine with the
metadata required for market use: exactly one `finance_track` context, a
dataset version, inclusive coverage bounds, source reference, and licence.

Every day and session query checks coverage first. Dates outside the declared
range return `OutsideCoverage`; they never fall back to weekdays. Construction
also proves that the context timezone equals the calendar timezone and that the
source provider is named in the context.

This package contains no exchange dataset and makes no redistribution claim.
CN, HK, and US packages supply reviewed source data and market-specific session
templates while reusing this bounded wrapper.
