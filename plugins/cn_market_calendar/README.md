# cn_market_calendar

Experimental Pi plugin for the isolated `cn` track. It registers
`cn_market_calendar`, which classifies one exact 2026 date for an explicitly
selected SSE, SZSE, or BSE venue.

The plugin composes `finance_cn_calendar` over the provider-neutral
`finance_market_calendar` and `finance_calendar` engines. The venue remains
explicit; no code-prefix inference or HK/US calendar substitution is allowed.
Results expose the exact exchange source URL, dataset version and coverage,
sessions, timezone, entitlement, licence state, and every limitation.

The source-reviewed dataset covers calendar year 2026 only. It models the
published equity auction/continuous sessions and planned holiday closures. A
later exceptional-closure notice may supersede it. Settlement, Stock Connect,
security-specific suspensions, and redistribution permission are outside this
contract. Dates outside coverage fail closed instead of using a weekday guess.

Sources:

- SSE: <https://www.sse.com.cn/disclosure/dealinstruc/closed/>
- SZSE: <https://investor.szse.cn/disclosure/notice/general/t20251222_618087.html>
- BSE: <https://www.bse.cn/important_news/200027428.html>

Build and test with the repository task runner:

```sh
bun run test:unit -- cn_market_calendar
bun run build -- cn_market_calendar
```
