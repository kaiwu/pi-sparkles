# hk_market_calendar

Experimental Pi plugin for the isolated `hk` track. It registers
`hk_market_calendar`, which classifies one exact 2026 date using Stock Exchange
of Hong Kong circular CT/075/25.

The plugin composes `finance_hk_calendar` over the provider-neutral
`finance_market_calendar` and `finance_calendar` engines. Results expose the
exact HKEX source URL, dataset version and coverage, full-day/half-day state,
sessions, timezone, entitlement, licence state, and every limitation. No CN or
US calendar can satisfy the tool.

The source-reviewed dataset covers calendar year 2026 only. It preserves the
three published half-days and every published full closure. It intentionally
does not classify the extended-morning market or the random closing-auction
window as continuously open. A later exceptional-closure notice may supersede
the planned schedule. Settlement, Stock Connect, derivatives, typhoon/severe
weather state, and redistribution permission are outside this contract. Dates
outside coverage fail closed instead of using a weekday guess.

Source: <https://www.hkex.com.hk/-/media/HKEX-Market/Services/Circulars-and-Notices/Participant-and-Members-Circulars/SEHK/2025/ce_SEHK_CT_075_2025.pdf>

Build and test with the repository task runner:

```sh
bun run test:unit -- hk_market_calendar
bun run build -- hk_market_calendar
```
