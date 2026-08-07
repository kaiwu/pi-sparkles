# pi_sparkles_stock_screener

Status: **Experimental — Alpaca US asset-universe acquisition slice** ·
version: `0.1.0` · target: JavaScript/Bun

`stock_screener` currently registers one information-only tool,
`stock_universe`. It fetches Alpaca's US-equity asset-master array using an
explicit caller-selected paper/live environment, status, exchange, and maximum
row budget. It does not yet calculate price, liquidity, fundamental, growth,
valuation, or technical filters; its name records the broader roadmap package,
not a claim that this slice screens or ranks securities.

Every result preserves the exact provider row order, duplicates, asset ID,
class, exchange, symbol, name, status, capability booleans, attributes, request
ID, retrieval time, query URL, exact response hash, and request-plus-response
universe hash. Rows that conflict with the requested provider filter remain
visible. Exceeding the response-byte or row budget fails instead of truncating.

The result always reports `decisionOwner: "llm"` and
`pluginDecisionFields: []`. Provider `status`, `tradable`, `marginable`,
`shortable`, `easy_to_borrow`, and `fractionable` fields are information for the
LLM; none becomes eligibility, qualification, suitability, rank, recommendation,
or an operation choice.

Required environment variables:

- `ALPACA_API_KEY_ID`
- `ALPACA_API_SECRET_KEY`
- `ALPACA_USER_AGENT_CONTACT`

`ALPACA_USER_AGENT_PRODUCT` is optional and defaults to
`pi-sparkles-stock-screener/0.1`.

Provider reference:

- <https://docs.alpaca.markets/us/reference/get-v2-assets-1>

Normal tests use exact fixture bytes and mocked `fetch`; they make no live
provider call. The endpoint supplies no historical as-of parameter, and its
catalogue is not an authoritative listing/security master. This slice does not
persist screens, rank rows, infer MICs, authenticate provider origin from a
content hash, grant redistribution rights, or fall back among environments,
statuses, exchanges, providers, or tracks.

Verification on 2026-08-07 covers two pure plugin tests, two bundled boundary
tests, artifact export, Pi smoke loading, and the three-track swing acceptance
lane. The US acceptance journey invokes this bundled tool over exact scripted
bytes and proves its source and universe hashes match the attached candidate
receipt. The configured tutor LLM then completed 21 calls across three Pi
processes with no plugin decision fields.
