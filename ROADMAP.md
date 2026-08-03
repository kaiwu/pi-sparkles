# Finance plugin roadmap

This roadmap sketches a family of small Gleam packages that can turn Pi into a
finance research agent, initially focused on public equities. Each plugin is an
independent Gleam project, can be distributed as source through Hex, and must be
built into a Pi-loadable JavaScript artifact with Gleam and Bun.

The catalog is intentionally broad. It is a menu and dependency map, not a
promise to build every package at once.

Every plugin listed here is currently a **draft**. Later, we will implement the
drafts one at a time. Each implementation gets its own `plugins/<name>/`
directory and is an independent Gleam project. Its local `README.md` becomes the
detailed design document; this roadmap retains only the proposal, priority,
dependencies, and delivery status.

## Proposal lifecycle

Use these states when work begins:

```text
Draft -> Selected -> Designing -> Implementing -> Experimental -> Stable
                                   |                    |
                                   +----> Paused <------+
```

- **Draft** means only the proposal in this file exists.
- **Selected** means it is next in the implementation sequence.
- **Designing** starts by creating `plugins/<name>/README.md`, not code.
- **Implementing** means its independent Gleam project and tests exist.
- **Experimental** means it builds, loads in Pi, and can be distributed as Hex
  source, but its API/provider behavior may still change.
- **Stable** requires documented compatibility, release, migration, and
  operational policies.

Each plugin README should cover:

1. user stories and explicit non-goals;
2. commands, tools, flags, events, and custom session data;
3. public Gleam modules and types;
4. provider endpoints, authentication, entitlements, licence, cache, pacing,
   retry, and outage behavior;
5. schemas, decoding rules, units, timestamps, adjustment and freshness policy;
6. permissions, secrets, trust boundary, and non-interactive behavior;
7. lifecycle behavior across reload, new/resume/fork, compaction, and shutdown;
8. pure, FFI, artifact, Pi integration, and provider-contract tests;
9. tested Pi/binding/provider versions and known limitations;
10. Hex source contents and the exact source-to-Pi build instructions.

Creating a plugin directory therefore means its proposal has graduated from
this catalog. Empty placeholder directories are not useful and should not be
created ahead of implementation.

## Product direction

The first useful finance agent should answer questions such as:

- What is this security, where does it trade, and how fresh is the quote?
- What changed in the latest 10-K, 10-Q, or 8-K?
- How are revenue, margins, cash flow, leverage, and dilution changing?
- Which upcoming earnings, dividends, splits, and macro releases matter?
- How does a company compare with peers under explicit valuation assumptions?
- What risks and concentrations exist in a portfolio?
- Can this research be reproduced from cited source data?

It should not begin with autonomous live trading. Read-only research, provenance,
portfolio analytics, and paper execution give us the highest usefulness with a
much smaller failure cost.

## Rules for every finance plugin

Finance tools need a stricter contract than ordinary convenience plugins:

- Every observation carries its source, `as_of` time, retrieval time, timezone,
  currency/unit, and delayed/real-time status.
- Prices say whether they are raw or adjusted and identify the session
  (pre-market, regular, after-hours, or closed).
- Missing, stale, estimated, restated, and revised data are explicit states, not
  silently converted to zero.
- Decimal financial values stay as strings or exact decimal representations at
  the FFI boundary; binary floats are reserved for derived analytics where the
  precision policy is stated.
- Corporate actions and symbol changes are first-class. A ticker alone is not a
  permanent security identifier.
- Every analytical result records its inputs and assumptions. The agent must not
  invent a quote, filing fact, consensus estimate, or citation.
- Provider limits, entitlements, and redistribution terms are respected. Cache
  policy is provider-specific.
- Credentials come from environment/configuration and are never appended to Pi
  sessions, logs, tool details, or error messages.
- Read-only is the default. Paper and live execution are separate plugins and
  capabilities.
- Output is research tooling, not a guarantee, fiduciary service, or substitute
  for professional advice.

## Shared packages before plugins

These are reusable Hex libraries rather than Pi extensions. Building them first
prevents every plugin from inventing incompatible finance types.

| Package | Purpose | First types/capabilities |
| --- | --- | --- |
| `finance_core` | Canonical domain model | `Instrument`, `Listing`, `Money`, `Decimal`, `Currency`, `Exchange`, `Timeframe`, `Observation(a)`, freshness and adjustment metadata |
| `finance_series` | Time-series operations | dated observations, alignment, resampling, returns, drawdown, rolling windows, missing-value policy |
| `finance_calendar` | Trading-time rules | sessions, holidays, early closes, timezone-safe date ranges; provider data remains pluggable |
| `finance_provenance` | Reproducible evidence | source URLs/identifiers, retrieved/as-of timestamps, licence tags, input fingerprints, assumption records |
| `finance_http` | Provider-safe transport | retry/backoff, rate-limit headers, bounded concurrency, cache hooks, user-agent policy, redacted errors |
| `finance_table` | Agent-friendly output | compact Markdown/CSV/JSON tables, units, significant digits, missing-value markers, truncation summaries |
| `finance_math` | Deterministic analytics | descriptive statistics, covariance, beta, CAGR, IRR/XIRR, volatility, VaR helpers, numerical error types |
| `finance_testkit` | Provider fixtures | frozen clocks, cassette responses, market calendars, split/dividend fixtures, decoder conformance tests |

Provider adapters should also be ordinary packages when possible—for example,
`finance_sec`, `finance_fred`, `finance_openfigi`, and
`finance_market_alpaca`. Pi plugins then compose those libraries and expose
agent tools. This makes the data client reusable outside Pi and keeps its test
surface independent of the extension runtime.

## Plugin proposals

Priorities mean:

- **P0**: foundation for the first useful equity research agent;
- **P1**: high-value research and portfolio capabilities;
- **P2**: breadth, specialized analysis, or licensed-data integrations;
- **P3**: execution or operationally sensitive capability.

### Foundation and trust

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_finance_setup` | P0 | Checks provider keys, connectivity, entitlements, currency/timezone defaults, and installed companion plugins without revealing secrets. | `/finance-setup`, `finance_capabilities`, `finance_provider_health` |
| `pi_finance_guardrails` | P0 | Shared freshness, provenance, disclaimer, and action policy. Rejects answers that mix incompatible currencies, periods, or adjustment bases. | `/finance-policy`, `finance_validate_evidence`, `finance_check_freshness` |
| `pi_finance_symbols` | P0 | Resolves company names, tickers, FIGIs, CIKs, MICs, share classes, and historical symbols; returns ambiguity instead of guessing. | `/symbol`, `security_search`, `security_resolve`, `security_identifiers` |
| `pi_finance_calendar` | P0 | Answers exchange session/holiday questions and normalizes market timestamps. | `/market-hours`, `market_session`, `market_days`, `next_market_open` |
| `pi_finance_sources` | P0 | Shows the provenance ledger for the current research session and exports a reproducibility manifest. | `/sources`, `/evidence-export`, `finance_sources`, `finance_replay_manifest` |
| `pi_finance_cache` | P1 | User-controlled local cache inspection, expiry, offline replay, and provider usage accounting. | `/finance-cache`, `cache_status`, `cache_expire`, `provider_usage` |
| `pi_finance_data_quality` | P1 | Cross-checks duplicate/stale data, split discontinuities, missing periods, unit changes, and provider disagreement. | `data_quality_check`, `quote_crosscheck`, `series_anomalies` |

### Equity market data

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_stock_quote` | P0 | Current/delayed quote snapshots with bid/ask, last trade, session, source, and freshness. Backend chosen explicitly. | `/quote`, `stock_quote`, `stock_quotes` |
| `pi_stock_history` | P0 | Daily/intraday OHLCV with raw/adjusted controls and corporate-action metadata. | `/chart-data`, `stock_bars`, `stock_returns`, `stock_performance` |
| `pi_stock_market_snapshot` | P1 | Index/sector/industry breadth, leaders, laggards, gaps, volume, and volatility snapshots. | `/market`, `market_snapshot`, `market_breadth`, `market_movers` |
| `pi_stock_screener` | P1 | Reproducible universe filters combining price, liquidity, fundamentals, growth, valuation, and technical fields. | `/screen`, `stock_screen`, `screen_explain`, `screen_save` |
| `pi_stock_corporate_actions` | P1 | Splits, dividends, symbol changes, mergers, spinoffs, and delistings, with adjustment impact. | `/actions`, `corporate_actions`, `dividend_history`, `split_history` |
| `pi_stock_earnings_calendar` | P1 | Upcoming/recent earnings dates, confirmation status, fiscal period, time-of-day, and estimate provenance. | `/earnings`, `earnings_calendar`, `earnings_event` |
| `pi_stock_market_calendar` | P1 | Equity-specific auctions, halts, short sessions, and pre/post-market context beyond the generic calendar. | `stock_session_status`, `trading_halts`, `market_schedule` |
| `pi_stock_order_book` | P2 | Entitlement-aware top-of-book or depth snapshots, with an explicit warning that snapshots are not executable prices. | `/book`, `stock_top_of_book`, `stock_depth` |
| `pi_stock_tape` | P2 | Recent trades, sale conditions, volume profile, and intraday microstructure summaries. | `/tape`, `stock_trades`, `volume_profile`, `trade_conditions` |

Market-data plugins should expose a provider name in both the tool result and
tool name or configuration. Plausible adapters include Alpaca, Polygon/Massive,
Nasdaq Data Link, and a local licensed feed. Free/delayed and paid/real-time
coverage must never be described as equivalent.

### China stock-market track

China is a first-class target, not a localization layer over US equities. The
shared finance types should be global from the start, while China-specific
plugins own the exchange rules, disclosures, identifiers, units, language, and
provider contracts for Shanghai, Shenzhen, Beijing, and—where stated—Hong Kong.

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_cn_stock_symbols` | P0 | Resolves Chinese names, short names, six-digit codes, exchange/MIC, board, A/B/H relationships, CDRs, share classes, and historical names without guessing from code alone. | `/cn-symbol`, `cn_security_search`, `cn_security_resolve`, `cn_security_identifiers` |
| `pi_cn_market_calendar` | P0 | Shanghai/Shenzhen/Beijing sessions, holidays, exceptional closures, auctions, midday breaks, and settlement-date calculations by security type. | `/cn-hours`, `cn_market_session`, `cn_market_days`, `cn_settlement_date` |
| `pi_cn_stock_rules` | P0 | Date-effective trading status, board/security-specific price limits, ST/delisting-risk status, lot rules, suspensions, and order constraints. | `/cn-rules`, `cn_trading_rules`, `cn_price_limit`, `cn_order_constraints` |
| `pi_cn_stock_quote` | P0 | Entitlement-labelled A/B-share and Beijing quotes with CNY/USD denomination, session, limit prices, suspension, and freshness. | `/cn-quote`, `cn_stock_quote`, `cn_stock_quotes` |
| `pi_cn_stock_history` | P0 | Daily/intraday OHLCV and turnover with suspension gaps, corporate actions, and explicit raw/forward/backward-adjustment formulas. | `/cn-history`, `cn_stock_bars`, `cn_stock_returns`, `cn_adjustment_factors` |
| `pi_cn_stock_announcements` | P0 | Searches and retrieves original exchange/CNInfo announcements, periodic reports, ad-hoc disclosures, and attachments with Chinese titles preserved. | `/cn-announcements`, `cn_announcements`, `cn_announcement`, `cn_announcement_search` |
| `pi_cn_stock_financials` | P0 | Normalizes Chinese financial statements while retaining original line labels, accounting standard, units, consolidated/parent scope, restatements, report type, and audit status. | `/cn-financials`, `cn_company_financials`, `cn_financial_line`, `cn_financial_trends` |
| `pi_cn_stock_research_report` | P0 | Orchestrates China sources into a bilingual-capable, cited company brief that separates primary disclosures from vendor-derived metrics. | `/cn-research`, `cn_company_brief`, `cn_compare_companies` |
| `pi_cn_market_snapshot` | P1 | Shanghai/Shenzhen/Beijing index, board, breadth, turnover, limit-up/down, suspension, and liquidity summaries. | `/cn-market`, `cn_market_snapshot`, `cn_market_breadth`, `cn_market_movers` |
| `pi_cn_stock_screener` | P1 | A-share/Beijing filters for board, ST state, liquidity, market cap, financials, valuation, growth, dividends, and trading constraints. | `/cn-screen`, `cn_stock_screen`, `cn_screen_explain` |
| `pi_cn_stock_corporate_actions` | P1 | Cash/stock dividends, bonus issues, capitalization, rights issues, splits, mergers, symbol changes, and ex-right/ex-dividend records. | `/cn-actions`, `cn_corporate_actions`, `cn_dividend_history`, `cn_ex_rights` |
| `pi_cn_stock_earnings` | P1 | Reporting calendar, preliminary results, performance forecasts, express reports, periodic reports, and revision history as distinct event types. | `/cn-earnings`, `cn_reporting_calendar`, `cn_performance_forecasts`, `cn_results_history` |
| `pi_cn_stock_share_structure` | P1 | Total/tradable/restricted shares, A/B/H classes, state/legal-person holdings where disclosed, and dated changes to denominators. | `cn_share_structure`, `cn_share_capital_changes` |
| `pi_cn_stock_shareholders` | P1 | Top shareholders, top tradable holders, shareholder count, beneficial-owner context, and quarter-over-quarter changes with disclosure lag. | `/cn-holders`, `cn_top_shareholders`, `cn_holder_changes`, `cn_shareholder_count` |
| `pi_cn_stock_restricted_shares` | P1 | Upcoming and historical restricted-share unlocks, eligible quantities, holders, source announcements, and float-impact estimates. | `/cn-unlocks`, `cn_restricted_unlocks`, `cn_unlock_impact` |
| `pi_cn_stock_pledges` | P1 | Disclosed share pledges, freezes, controlling-shareholder exposure, releases, and concentration warnings. | `/cn-pledges`, `cn_share_pledges`, `cn_pledge_changes` |
| `pi_cn_stock_insiders` | P1 | Director/supervisor/senior-management and major-holder increases, reductions, plans, completions, and short-swing context from disclosures. | `/cn-insiders`, `cn_holder_trades`, `cn_reduction_plans` |
| `pi_cn_stock_public_info` | P1 | Exchange public trading information such as unusual-movement reasons and 龙虎榜, preserving the published seat/institution labels. | `/cn-public-info`, `cn_dragon_tiger`, `cn_abnormal_trading` |
| `pi_cn_stock_margin` | P1 | 融资融券 eligibility, balances, purchases/sales, changes, and market aggregates with unit-aware output. | `/cn-margin`, `cn_margin_eligibility`, `cn_margin_balance`, `cn_margin_changes` |
| `pi_cn_stock_block_trades` | P1 | 大宗交易 records with price, discount/premium, volume, amount, and published buyer/seller branch labels. | `/cn-blocks`, `cn_block_trades`, `cn_block_trade_summary` |
| `pi_cn_stock_connect` | P1 | Shanghai/Shenzhen-Hong Kong Stock Connect eligibility, buy-only/sell-only state, effective dates, calendars, quotas where published, and cross-list mappings. | `/stock-connect`, `connect_eligibility`, `connect_changes`, `connect_calendar` |
| `pi_cn_stock_indices` | P1 | CSI/SSE/SZSE/BSE index identity, methodology links, constituents, weights, rebalances, and index performance. | `/cn-index`, `cn_index_profile`, `cn_index_constituents`, `cn_index_changes` |
| `pi_cn_stock_sector_concept` | P1 | Explicitly sourced CSRC/exchange/vendor industry and concept classifications; never treats competing taxonomies as interchangeable. | `/cn-sector`, `cn_industry_classification`, `cn_sector_members`, `cn_concept_members` |
| `pi_cn_stock_valuation` | P1 | China-aware peer multiples and DCF inputs with share-class currency, cross-listed securities, non-tradable/restricted shares, and source dates exposed. | `/cn-value`, `cn_trading_comps`, `cn_valuation`, `cn_valuation_sensitivity` |
| `pi_cn_stock_filing_diff` | P1 | Chinese section/table-aware comparison of periodic and ad-hoc disclosures, including corrected/restated documents and changed risk factors. | `/cn-filing-diff`, `cn_filing_diff`, `cn_disclosure_changes` |
| `pi_cn_stock_watch` | P1 | Watches announcements, forecasts, unlocks, pledges, suspensions, rule status, and Stock Connect eligibility for named lists. | `/cn-watch`, `cn_watch_add`, `cn_watch_snapshot`, `cn_watch_poll` |
| `pi_cn_regulatory` | P1 | Searches CSRC and exchange rules, inquiries, disciplinary actions, supervision letters, and enforcement releases with effective dates. | `/cn-regulation`, `cn_rule_search`, `cn_company_regulatory_events`, `cn_enforcement_search` |
| `pi_cn_ipo` | P2 | IPO pipeline, prospectuses, inquiry responses, registration status, offer calendar, listing result, lockups, and sponsor/accountant/law-firm identity. | `/cn-ipo`, `cn_ipo_pipeline`, `cn_ipo_company`, `cn_ipo_calendar` |
| `pi_cn_convertible_bonds` | P2 | Exchange-listed convertibles, conversion terms, price triggers, redemption/put clauses, dilution, parity, premium, and announcements. | `/cn-convertible`, `cn_convertible_terms`, `cn_convertible_valuation`, `cn_convertible_events` |
| `pi_cn_funds_etf` | P2 | Listed funds/ETFs, NAV/IOPV context, holdings where licensed, creations/redemptions, distributions, and tracking diagnostics. | `/cn-fund`, `cn_fund_profile`, `cn_etf_holdings`, `cn_tracking_difference` |
| `pi_cn_mutual_funds` | P2 | Public-fund profiles, managers, portfolios, periodic reports, fees, benchmarks, and performance with survivorship warnings. | `/cn-mutual-fund`, `cn_fund_search`, `cn_fund_portfolio`, `cn_fund_performance` |
| `pi_cn_macro` | P1 | NBS/PBOC/SAFE and other official macro series with original release, frequency, units, revisions, and publication calendar. | `/cn-macro`, `cn_macro_search`, `cn_macro_series`, `cn_macro_calendar` |
| `pi_cn_policy_monitor` | P2 | A dated, sourced monitor for monetary, securities, industrial, trade, and company-relevant policy documents; translation is always labelled. | `/cn-policy`, `cn_policy_search`, `cn_policy_timeline`, `cn_policy_watch` |
| `pi_hk_stock` | P2 | HKEX-listed security identity, HKD market data, disclosures, corporate actions, board lots, sessions, and A/H relationships. | `/hk-stock`, `hk_stock_quote`, `hk_announcements`, `ah_compare` |
| `pi_cn_broker_readonly` | P3 | A broker-specific, read-only view of Chinese accounts, positions, orders, cash, settlement, and entitlements. | `/cn-broker`, `cn_broker_positions`, `cn_broker_orders`, `cn_broker_cash` |
| `pi_cn_broker_paper` | P3 | Provider-specific simulation that enforces China instrument/session/lot/limit rules and clearly states simulation limitations. | `/cn-paper-trade`, `cn_paper_order_draft`, `cn_paper_order_submit` |

China-specific correctness requirements:

- Security identity includes venue and board. The bare code `000001`, a company
  name, or an English translation is never accepted as globally unambiguous.
- Original Chinese document titles, text excerpts, units, and source links are
  retained. Machine or model translations are optional derived content and are
  labelled as translations; the original controls when they differ.
- All exchange times are handled in `Asia/Shanghai`; Hong Kong uses its own
  venue calendar. Midday breaks and exceptional sessions are represented rather
  than flattened into a US-style continuous session.
- Price-limit, lot, eligibility, suspension, and settlement behavior is resolved
  from the security, board, status, and effective date. No plugin hardcodes a
  universal “10% A-share rule.”
- Financial decoders preserve `元`, `万元`, `亿元`, shares, `万股`, and percentage
  scales, and distinguish consolidated from parent-company statements.
- Adjusted history always returns the corporate-action inputs and algorithm.
  Labels such as 前复权 and 后复权 are not treated as provider-independent unless
  their formulas and base date match.
- Preliminary earnings, performance forecasts, express reports, audited annual
  reports, and later corrections are different evidence classes.
- Exchange pages may be public without granting an undocumented bulk API or
  redistribution right. Prefer documented products, official downloads, or a
  licensed vendor; do not make reverse-engineered scraping the default adapter.

Generic plugins such as portfolio risk, thesis tracking, event studies, and
backtesting should support China instruments once these adapters exist. They do
not need duplicate `pi_cn_*` versions unless local rules materially change their
public contract.

### Filings, fundamentals, and company intelligence

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_sec_edgar` | P0 | Company identity, filing history, filing retrieval, and links to primary SEC documents. | `/filings`, `sec_company`, `sec_filings`, `sec_filing`, `sec_search_filing` |
| `pi_sec_xbrl` | P0 | Typed company facts and frames from SEC XBRL, retaining taxonomy, units, period, accession, form, and filed date. | `/facts`, `sec_company_facts`, `sec_concept`, `sec_compare_fact` |
| `pi_stock_fundamentals` | P0 | Normalized income statement, balance sheet, cash flow, per-share, and segment series derived with traceable mappings. | `/fundamentals`, `company_financials`, `fundamental_trends`, `segment_history` |
| `pi_filing_diff` | P1 | Section-aware comparison of successive filings, highlighting changed risks, accounting policy, guidance, and exhibits. | `/filing-diff`, `filing_diff`, `filing_changes` |
| `pi_filing_monitor` | P1 | Watches configured companies/forms and injects a sourced summary when new filings arrive. | `/filing-watch`, `filing_watch_add`, `filing_watch_list`, `filing_watch_poll` |
| `pi_sec_insiders` | P1 | Form 3/4/5 transactions with role, ownership type, transaction code, price, and post-transaction holdings. | `/insiders`, `insider_transactions`, `insider_summary` |
| `pi_sec_ownership` | P1 | 13F, 13D/G, and institutional ownership changes with reporting-lag warnings. | `/ownership`, `institutional_holdings`, `ownership_changes` |
| `pi_company_profile` | P1 | Business description, exchanges, securities, fiscal calendar, industry classification, and primary-source links. | `/company`, `company_profile`, `company_entities` |
| `pi_earnings_release` | P1 | Retrieves and compares company earnings releases and filed exhibits; avoids treating marketing metrics as GAAP facts. | `/release`, `earnings_release`, `earnings_release_diff` |
| `pi_earnings_transcript` | P2 | Licensed transcript search, speaker-aware excerpts, topic extraction, and quarter-over-quarter comparison. | `/transcript`, `transcript_search`, `transcript_compare` |
| `pi_company_guidance` | P2 | Tracks explicit management guidance ranges, units, horizon, source passage, and revisions. | `/guidance`, `company_guidance`, `guidance_history` |
| `pi_consensus_estimates` | P2 | Licensed analyst estimates, revisions, dispersion, and surprise history with vendor attribution. | `/estimates`, `consensus_estimates`, `estimate_revisions`, `earnings_surprises` |

SEC data is the preferred first fundamentals source because it is primary and
its submissions/company-facts APIs require no API key. Normalization remains
hard: company extensions, restatements, units, fiscal calendars, and duplicate
contexts must remain visible rather than being papered over.

### Research and valuation

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_stock_peers` | P1 | Builds an explainable peer set by industry, business mix, size, geography, and user constraints. | `/peers`, `peer_candidates`, `peer_compare` |
| `pi_stock_comps` | P1 | Comparable-company tables with consistent dates, currencies, enterprise values, and denominator definitions. | `/comps`, `trading_comps`, `comps_explain` |
| `pi_stock_valuation` | P1 | Transparent DCF, dividend, residual-income, and multiples models with editable assumptions and sensitivity grids. | `/value`, `dcf`, `valuation_multiples`, `valuation_sensitivity` |
| `pi_stock_quality` | P1 | Profitability, accruals, leverage, dilution, cash conversion, and accounting-quality diagnostics. | `/quality`, `quality_scorecard`, `accounting_flags` |
| `pi_stock_growth` | P1 | Historical growth decomposition, cyclicality, base effects, and scenario ranges. | `/growth`, `growth_analysis`, `growth_scenarios` |
| `pi_stock_technicals` | P1 | Deterministic indicators and regime summaries without unsupported predictive language. | `/technicals`, `technical_indicators`, `support_resistance`, `trend_regime` |
| `pi_stock_event_study` | P2 | Abnormal-return studies around earnings, filings, guidance, splits, or user-supplied events. | `/event-study`, `event_study`, `event_window_returns` |
| `pi_stock_factor_lab` | P2 | Cross-sectional value, quality, momentum, size, low-volatility, and custom factors with neutralization controls. | `/factors`, `factor_exposure`, `factor_rank`, `factor_test` |
| `pi_stock_thesis` | P1 | Stores bull/base/bear theses as structured claims, evidence, disconfirming signals, and review dates. | `/thesis`, `thesis_create`, `thesis_update`, `thesis_audit` |
| `pi_stock_research_report` | P0 | Orchestrates other read-only tools into a cited company brief, earnings preview/review, or comparison report. | `/research`, `/earnings-preview`, `company_brief`, `compare_companies` |

The report plugin should orchestrate; it should not own a second copy of every
data client. If a required capability is absent, it should state that gap in the
report rather than substitute unsourced model knowledge.

### News and event intelligence

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_finance_news` | P1 | Provider-backed company/market news search with timestamps, canonical URLs, deduplication, and licence-aware excerpts. | `/news`, `finance_news`, `news_search`, `news_cluster` |
| `pi_finance_catalysts` | P1 | A sourced timeline joining earnings, filings, guidance, macro releases, dividends, and user events. | `/catalysts`, `catalyst_calendar`, `company_timeline` |
| `pi_finance_alerts` | P1 | Poll-based alerts for price, volume, filings, fundamentals, news, and thesis conditions; lifecycle-safe cleanup on reload. | `/alerts`, `alert_add`, `alert_list`, `alert_remove`, `alert_poll` |
| `pi_finance_sentiment` | P2 | Transparent text classification over licensed/user-supplied documents, with samples and uncertainty—not a magic score. | `/sentiment`, `document_sentiment`, `sentiment_compare` |
| `pi_finance_rumor_check` | P2 | Cross-checks a market claim against filings, issuer releases, regulator sources, and licensed news. | `/verify-market-claim`, `market_claim_check` |

### Macro, rates, and other asset classes

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_macro_fred` | P0 | FRED/ALFRED series search, observations, transformations, release dates, and historical vintages. | `/fred`, `fred_search`, `fred_series`, `fred_vintage`, `macro_release_calendar` |
| `pi_macro_dashboard` | P1 | Configurable growth/inflation/labor/liquidity/credit dashboards composed from provenance-rich series. | `/macro`, `macro_dashboard`, `macro_compare` |
| `pi_rates_treasury` | P1 | Treasury yields, auctions, debt, and curve analytics from official or clearly licensed sources. | `/rates`, `treasury_curve`, `yield_spread`, `auction_calendar` |
| `pi_fx_ecb` | P1 | ECB reference exchange rates and SDMX series with explicit base, quote, and fixing conventions. | `/fx`, `fx_rate`, `fx_history`, `fx_convert` |
| `pi_fixed_income` | P2 | Bond lookup, cash flows, yield/duration/convexity, spread analysis, and entitlement-aware TRACE data. | `/bond`, `bond_cashflows`, `bond_analytics`, `bond_trades` |
| `pi_options` | P2 | Chains, contract identity, Greeks, implied volatility, payoff diagrams, and scenario surfaces. | `/options`, `option_chain`, `option_greeks`, `option_payoff`, `iv_surface` |
| `pi_cftc_cot` | P2 | CFTC Commitments of Traders positioning, changes, percentiles, and report-lag context. | `/cot`, `cot_positions`, `cot_changes`, `cot_extremes` |
| `pi_commodities` | P2 | Futures curves, roll/term structure, contract calendars, and commodity-specific units. | `/commodity`, `futures_curve`, `curve_spread`, `roll_yield` |
| `pi_crypto_market` | P2 | Spot crypto products, candles, order books, funding context, and venue identity. | `/crypto`, `crypto_quote`, `crypto_bars`, `crypto_book` |
| `pi_global_markets` | P2 | Country/index/ETF and cross-market dashboard with trading calendars, currencies, and local-vs-ADR identity. | `/global-markets`, `global_snapshot`, `cross_market_compare` |

### Portfolio, risk, and workflow

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_portfolio` | P1 | Imports and validates positions from CSV/JSON or read-only broker APIs; calculates value, P&L, weights, and exposures. | `/portfolio`, `portfolio_import`, `portfolio_summary`, `portfolio_positions` |
| `pi_portfolio_risk` | P1 | Concentration, volatility, beta, correlation, VaR/CVaR, liquidity, currency, and drawdown diagnostics with method labels. | `/risk`, `portfolio_risk`, `risk_contributors`, `correlation_matrix` |
| `pi_portfolio_scenarios` | P1 | User-defined and historical shocks across securities, factors, rates, FX, volatility, and correlations. | `/scenario`, `portfolio_scenario`, `stress_test` |
| `pi_portfolio_attribution` | P2 | Return attribution by position, sector, factor, currency, and period with cash-flow-aware calculations. | `/attribution`, `performance_attribution`, `portfolio_returns` |
| `pi_portfolio_rebalance` | P2 | Generates tax/fee/liquidity-aware rebalance proposals but never submits them. | `/rebalance`, `rebalance_plan`, `rebalance_validate` |
| `pi_tax_lots` | P2 | Lot-level gains, holding periods, harvest candidates, and jurisdiction-labelled estimates. | `/lots`, `tax_lots`, `realized_gains`, `harvest_candidates` |
| `pi_trade_journal` | P1 | Records decisions, assumptions, orders, fills, screenshots/links, and post-trade reviews in portable local data. | `/journal`, `journal_entry`, `journal_search`, `trade_review` |
| `pi_watchlist` | P0 | Persistent named watchlists with notes, thesis links, tags, and compact snapshots. | `/watch`, `watchlist_add`, `watchlist_remove`, `watchlist_snapshot` |
| `pi_backtest` | P2 | Reproducible bar-based strategy tests with transaction costs, survivorship/look-ahead warnings, and exported run manifests. | `/backtest`, `backtest_run`, `backtest_compare`, `backtest_audit` |

### Execution—deliberately last

| Proposed plugin | Priority | What it gives Pi | Candidate commands/tools |
| --- | --- | --- | --- |
| `pi_broker_readonly_alpaca` | P2 | Read-only accounts, positions, orders, activities, and entitlements from Alpaca. | `/broker`, `broker_accounts`, `broker_positions`, `broker_orders` |
| `pi_broker_readonly_ibkr` | P2 | Read-only IBKR portfolio/account/contract access with session and pacing visibility. | `/ibkr`, `ibkr_accounts`, `ibkr_positions`, `ibkr_contract_search` |
| `pi_broker_paper_alpaca` | P3 | Explicit paper order drafts, validation, submission, cancel/replace, and fill monitoring. | `/paper-trade`, `paper_order_draft`, `paper_order_submit`, `paper_order_cancel` |
| `pi_broker_paper_ibkr` | P3 | The same paper-first workflow for an IBKR simulated account. | `/paper-ibkr`, `ibkr_paper_order_draft`, `ibkr_paper_order_submit` |
| `pi_broker_live` | P3 | Optional live adapter only after a security review and prolonged paper use. No generic auto-trading mode. | `/live-order`, `live_order_draft`, `live_order_submit`, `live_order_cancel` |
| `pi_trade_compliance` | P3 | Account/user policy: symbols, asset classes, max quantity/notional, trading window, order types, daily loss, and immutable decision logs. | `/trade-policy`, `trade_policy_check`, `trade_audit` |

Live execution needs a stronger interaction contract than an LLM tool call:

1. The model may create a non-executable order draft.
2. The policy plugin validates account, instrument, side, quantity/notional,
   price type, session, stale quote, and configured limits.
3. Pi displays the exact normalized order and estimated maximum cost in an
   interactive confirmation.
4. The user confirms with a short-lived nonce; ordinary natural-language assent
   is insufficient.
5. Submission uses an idempotency/client-order ID and records the broker request
   ID, response, and policy decision with secrets redacted.
6. The agent separately polls and reports acknowledgement, partial fills,
   rejection, cancellation, and final state. A submitted order is never called
   filled until the broker says so.

Paper trading stays a separate package and endpoint. Alpaca explicitly notes
that its paper environment does not model effects such as market impact,
information leakage, latency slippage, or queue position, so simulated results
must not be presented as live-performance estimates.

## Recommended build sequence

### F0 — trustworthy substrate

Build `finance_core`, `finance_provenance`, `finance_http`, `finance_table`, and
`finance_testkit`, then the `pi_finance_setup`, `pi_finance_guardrails`, and
`pi_finance_symbols` plugins.

Acceptance:

- one canonical observation envelope is used across packages;
- secrets are redacted from tool results and errors;
- identifier ambiguity and stale data are observable test cases;
- OpenFIGI uses v3 rather than the retired v2 API;
- provider HTTP behavior has deterministic fixtures and rate-limit tests.

### F1 — first equity research agent

Build `pi_stock_quote`, `pi_stock_history`, `pi_sec_edgar`, `pi_sec_xbrl`,
`pi_stock_fundamentals`, `pi_watchlist`, and `pi_stock_research_report`.

Acceptance: given a US-listed company, Pi resolves the security, gets a properly
labelled quote/history, finds primary filings, extracts a small audited set of
fundamentals, and produces a cited report. The same run can be reproduced from
an evidence manifest without a model call to fetch facts.

### F2 — monitoring and analysis

Add corporate actions, earnings calendar/releases, filing diff/monitor,
screening, peers/comps, valuation, technicals, news, catalysts, and alerts.

Acceptance: a saved watchlist produces a bounded, sourced morning brief and
alerts survive `/new` and `/fork` correctly while stopping cleanly on reload or
session shutdown.

### F3 — portfolio agent

Add portfolio import, risk, scenarios, attribution, thesis tracking, journal,
and rebalance proposals.

Acceptance: every portfolio result reconciles to imported positions and a dated
price snapshot; risk/valuation outputs expose methods, assumptions, missing
data, and sensitivity rather than a single unexplained score.

### F4 — asset-class breadth

Add FRED/ALFRED macro data, official rate/FX sources, options, fixed income,
CFTC positioning, commodities, crypto, and global markets according to demand.

Acceptance: shared types handle calendars, currencies, units, contract identity,
and different data frequencies without equity-specific shortcuts.

### F5 — paper execution

Add one read-only broker adapter, its paper-only execution companion, and trade
policy/audit plugins. Run paper-only for an extended period with fault injection.

Acceptance: duplicate calls do not duplicate orders; every transition is
reconciled against the broker; UI-less mode cannot submit; stale quotes and
policy violations fail closed; all lifecycle cleanup is idempotent.

### F6 — optional live execution

Only consider a broker-specific live plugin after a separate threat model,
security review, operational runbook, and explicit user decision. A generic
provider-independent live order tool should not be the first design.

### CN0–CN4 — China parallel track

The China track can begin alongside F1 without waiting for US feature breadth:

1. **CN0 identity/rules:** `pi_cn_stock_symbols`, `pi_cn_market_calendar`, and
   `pi_cn_stock_rules`.
2. **CN1 primary research:** announcements, financials, quote/history, and the
   first China company report.
3. **CN2 market structure:** corporate actions, earnings, share structure,
   unlocks, pledges, public information, margin, block trades, and Stock Connect.
4. **CN3 analysis:** China screener, industries/concepts, indices, valuation,
   filing diff, watches, regulatory events, and macro/policy context.
5. **CN4 breadth:** Beijing-specific edge cases, convertibles, funds/ETFs, IPOs,
   Hong Kong/A-H comparison, and only then read-only/paper broker work.

CN1 acceptance: Pi can take an unambiguous Shanghai, Shenzhen, or Beijing
listing, show a source/freshness-labelled quote, retrieve original disclosures,
normalize a small audited set of financial fields without losing Chinese units
or statement scope, and produce a cited report containing the original Chinese
source titles.

## Suggested first sprint

The best vertical slice is narrow enough to finish and broad enough to feel like
a finance agent:

1. `finance_core`: identifiers, exact decimals, dated observations, provenance.
2. `finance_http`: redaction, retry/backoff, rate limits, fixtures.
3. `finance_openfigi` + `pi_finance_symbols`: unambiguous instrument identity.
4. `finance_sec` + `pi_sec_edgar`: company and filing lookup.
5. `pi_sec_xbrl`: a deliberately small fact set—revenue, net income, assets,
   debt, cash, operating cash flow, capex, and diluted shares—with raw facts
   preserved.
6. `pi_stock_quote`: one configurable market-data backend, delayed/real-time
   status always visible.
7. `pi_stock_research_report`: one concise, cited company brief.

This slice exercises commands, typed tools, network cancellation, provider
configuration, structured results, provenance, caching, and report composition.
It also exposes the next binding gaps through real use rather than expanding
`pi_gleam` speculatively.

## Provider notes

Provider choice is configuration and packaging policy, not an invisible
fallback chain.

- [SEC EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
  provide unauthenticated submissions and XBRL JSON, update throughout the day,
  and require compliant automated-access behavior.
- [OpenFIGI v3](https://www.openfigi.com/api/documentation) maps third-party
  identifiers and exposes explicit rate limits. Its v2 API reached sunset in
  July 2026, so new code must target v3.
- [FRED and ALFRED](https://fred.stlouisfed.org/docs/api/fred/series/series_observations.html)
  provide macro observations, transformations, release data, and historical
  vintages. Underlying series can retain third-party usage restrictions.
- [Alpaca market data](https://docs.alpaca.markets/us/docs/about-market-data-api)
  covers historical/real-time equities, options, and crypto over HTTP and
  WebSocket, but access and feed breadth depend on authentication and plan.
- [Alpaca paper trading](https://docs.alpaca.markets/us/v1.4.2/docs/paper-trading)
  is useful for workflow testing but documents important simulation omissions.
- [IBKR Web API](https://ibkrcampus.com/campus/ibkr-api-page/webapi-doc/)
  exposes account, portfolio, market-data, and order workflows with authentication,
  session, subscription, and endpoint pacing constraints.
- [Nasdaq Data Link](https://docs.data.nasdaq.com/docs/getting-started) offers
  free and premium datasets through several APIs; datasets must retain their
  individual entitlement and usage terms.
- [CFTC Commitments of Traders](https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm)
  is available through the CFTC public reporting API and is naturally suited to
  a positioning plugin.
- [ECB Data Portal](https://data.ecb.europa.eu/help/api/data) exposes SDMX data,
  including reference FX series and revision-aware queries.
- [FINRA Query API](https://developer.finra.org/products/query-api) covers
  equity and fixed-income datasets, while data-specific terms and TRACE product
  boundaries need separate review.
- [Coinbase Advanced Trade API](https://docs.cdp.coinbase.com/api-reference/advanced-trade-api/rest-api/introduction)
  provides REST order management and WebSocket market data for a possible
  crypto adapter; trading remains outside the early equity roadmap.
- [Shanghai Stock Exchange data services](https://english.sse.com.cn/markets/dataservice/products/)
  distinguish licensed real-time Level 1/2 products from historical and
  end-of-day data, so public visibility must not be mistaken for redistribution
  permission.
- [Shenzhen Stock Exchange data services](https://www.szse.cn/English/services/dataServices/index.html)
  describe real-time, delayed, end-of-day, corporate, and other information
  products managed by its authorized information company.
- [CNInfo](https://www.cninfo.com.cn/) is operated by an SZSE subsidiary as a
  statutory disclosure platform and aggregates Shanghai, Shenzhen, and Beijing
  company announcements and related public information.
- [Beijing Stock Exchange disclosures](https://www.bse.cn/disclosure/announcement.html)
  provide an official announcement surface that must be covered alongside the
  longer-established Shanghai and Shenzhen venues.
- [HKEX Stock Connect eligibility](https://www.hkex.com.hk/Mutual-Market/Stock-Connect/Eligible-Stocks/View-All-Eligible-Securities?sc_lang=en)
  publishes dated northbound/southbound eligibility and special sell-only lists;
  eligibility must therefore be modelled as time-varying state.
- [CSRC disclosure rules](https://www.csrc.gov.cn/csrc/c106256/c1653948/content.shtml)
  and exchange rules should be retained with effective dates; summaries and
  translations cannot replace the controlling Chinese source.
- [National Bureau of Statistics data](https://data.stats.gov.cn/) is a
  candidate primary source for the China macro plugin, alongside PBOC and SAFE
  releases whose access and reuse terms must be studied per dataset.

Unofficial scraping endpoints should not be the default data substrate. If a
community plugin supports one, it must identify it as unofficial, isolate its
decoder, respect the site's terms, and fail clearly when the surface changes.

## Open decisions

- Which market-data provider should power the first quote/history adapter?
- Is the first audience US equities only, or should the core types require
  US and China equities together? The core types should be multi-market from day
  one either way.
- Where should persistent watchlists, theses, alerts, and evidence manifests
  live: session entries, a user-owned local directory, or a small database?
- Should `finance_core` and provider libraries live in this monorepo alongside
  Pi plugins or in a separate Gleam finance repository?
- Which report is the flagship workflow: company brief, earnings review,
  watchlist morning brief, or portfolio risk review?
- Which licensed China market-data provider can cover Shanghai, Shenzhen, and
  Beijing with documented programmatic access and acceptable redistribution
  terms?

None of these choices changes the safety-first ordering: identity and
provenance, then primary-source research, then analytics and portfolio work,
then paper execution, and live execution only as an explicit later project.
