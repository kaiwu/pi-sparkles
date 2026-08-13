# pi_sparkles_stock_earnings_calendar

Experimental read-only HK source slice exposing one `earnings_calendar` tool.
It accepts only exact `hk` / `XHKG`, caller-selected `main` or `gem`, one exact
five-digit security code, and an inclusive Gregorian range. There is no track,
venue, board, provider, or identity fallback.

The tool retrieves the corresponding official HKEX Board Meeting Notifications
page through `finance_hkex`. It returns issuer-announced board-meeting start
dates whose raw purpose contains one of the visible results markers `RESULTS`,
`INT RES`, `FIN RES`, or `QUARTER RES`. Every matching-code row rejected by
that mechanical rule remains in `excludedSourceRows` with its raw purpose and
period. The original printed code is retained alongside its additive normalized
five-digit form.

This is deliberately not an earnings-release timestamp API. HKEX says the
consolidated page may not be exhaustive, is for reference only, and shows only
the start date for meetings lasting more than one day. Therefore no-match never
proves absence, `publicationTimestamp` is always null, and callers are directed
to issuer announcements for the controlling record. The plugin calculates only
the earliest retained date in the requested range; the LLM owns interpretation
and next action.

Set the shared non-secret `AGENT_CONTACT` operator identity.
The outbound product label is fixed as
`pi-sparkles-stock-earnings-calendar/0.1`. The request is HTTPS-only,
host/path allowlisted, limited to 2 MB and 30 seconds, one request per second,
one in flight, retry-bounded, cancellation-aware, and captured as
no-redistribution local-analysis evidence before the fixture-tested parser runs.
Normal tests never make a live request.

Status: **Experimental**.

Verification on 2026-08-08: 18 `finance_hkex` tests, 7 plugin-domain tests,
5 bundled boundary scenarios, artifact export, architecture checks,
installed-Pi smoke, and full `bun run test` passed.
