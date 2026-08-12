# Plugin implementation and design index

The catalog currently contains 135 exact `pi_*` proposals:

- 62 have an implementation package (`gleam.toml`, source, tests, and README);
- 73 are **Designing** and contain only `plugins/<name>/README.md`.

README-only directories are reviewed specifications, not runnable plugins.
Root tasks discover packages by `gleam.toml`, so these designs do not increase
implementation breadth. The implementation queue remains controlled by the
[product-tier standard](../PRODUCT_TIERS.md), [R2](../R2.md), and
[`tiers.json`](../tiers.json). The complete T1 swing product is ProductUseful;
no individual plugin is selected next.

Every design inherits the [professional product-readiness standard](../PRODUCT_READINESS.md)
and follows the functional-core/effect-shell boundary in
[FUNCTIONAL_DESIGN.md](../FUNCTIONAL_DESIGN.md). Its linked domain and product
sessions are normative. Provider agreements, licences, entitlements, source
authority and coverage, security/legal review, and explicit human authorization
remain separate even when domain and architecture contracts are complete.

## Professional product audit — Sessions 40–46

QA22–QA28 asked the tutor to audit every design for real professional
usefulness, Pi implementability, operational safety, cross-plugin composition,
and end-to-end acceptance. The corrected verdict is: **zero unresolved
non-external questions** inside the reviewed scope.

| Evidence | Applies to | Controlling result |
| --- | --- | --- |
| [Session 40](../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md) | All 81 designs and repository maturity | Architecture-ready audit, implementation checklist, professional Definition of Done |
| [Session 41](../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md) | 30 market/source/identity/rule/disclosure/cache/tape/HK designs | Concrete professional tasks, provider-path requirements, tape depth, compact/drill-down and failures |
| [Session 42](../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md) | 31 research/portfolio/monitoring/company-intelligence designs | Exact workflows, receipt chains, durable artifacts, executable assumptions and acceptance |
| [Session 43](../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md) | 12 fund/rates/fixed-income/options/commodity/COT/crypto/macro/FX/global designs | Instrument semantics, calculations, source paths and cross-asset laws |
| [Session 44](../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md) | 7 `track_partial` broker/simulation/receipt/compliance packages plus 1 README-only CN broker design, amended 2026-08-12 | Current code is offline/import-only validation and pure evaluation; read-only network observation, named simulation, provider conformance, private import, and richer compliance remain explicit backlog; order mutation is forbidden |
| [Session 45](../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md) | Whole product | Uniform Pi contract, capability/data-flow DAG, lifecycle, five persona journeys and acceptance |
| [Session 46](../../trading-course/sessions/46_product_readiness_corrections_20260811.md) | Sessions 40, 44 and 45 | Correct chronology, maturity/input-path semantics, DAG meaning and ambiguous live-submission handling |

Session 41 governs the 30 source/market designs below, Session 42 the 31
research/portfolio designs, Session 43 the 12 multi-asset designs, and Session
44 the 8 broker designs. Sessions 40, 45, and 46 apply to all 81. Every
individual README cites its family session directly.

## Tutor-specified designs — Sessions 24–39

| Session | Individual design READMEs |
| --- | --- |
| [24](../../trading-course/sessions/24_cg_portfolio_full_review_contract_20260811.md) | [portfolio_scenarios](portfolio_scenarios/README.md), [portfolio_attribution](portfolio_attribution/README.md), [portfolio_rebalance](portfolio_rebalance/README.md), [tax_lots](tax_lots/README.md) |
| [25](../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md) | [broker_readonly_alpaca](broker_readonly_alpaca/README.md), [broker_readonly_ibkr](broker_readonly_ibkr/README.md), [cn_broker_readonly](cn_broker_readonly/README.md), [broker_paper_alpaca](broker_paper_alpaca/README.md), [broker_paper_ibkr](broker_paper_ibkr/README.md), [cn_broker_paper](cn_broker_paper/README.md), [broker_live](broker_live/README.md), [trade_compliance](trade_compliance/README.md) |
| [26](../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md) | [stock_peers](stock_peers/README.md), [stock_comps](stock_comps/README.md), [stock_valuation](stock_valuation/README.md), [industry_research](industry_research/README.md), [cn_stock_valuation](cn_stock_valuation/README.md), [cn_stock_research_report](cn_stock_research_report/README.md) |
| [27](../../trading-course/sessions/27_quality_growth_thesis_evidence_contract_20260811.md) | [stock_quality](stock_quality/README.md), [stock_growth](stock_growth/README.md), [stock_thesis](stock_thesis/README.md) |
| [28](../../trading-course/sessions/28_quant_event_study_factor_contract_20260811.md) | [stock_event_study](stock_event_study/README.md), [stock_factor_lab](stock_factor_lab/README.md) |
| [29](../../trading-course/sessions/29_monitoring_catalyst_alert_contract_20260811.md) | [finance_catalysts](finance_catalysts/README.md), [finance_alerts](finance_alerts/README.md), [filing_monitor](filing_monitor/README.md), [cn_stock_watch](cn_stock_watch/README.md), [cn_policy_monitor](cn_policy_monitor/README.md) |
| [30](../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md) | [filing_diff](filing_diff/README.md), [cn_stock_filing_diff](cn_stock_filing_diff/README.md), [earnings_release](earnings_release/README.md), [earnings_transcript](earnings_transcript/README.md), [company_guidance](company_guidance/README.md), [consensus_estimates](consensus_estimates/README.md), [company_governance](company_governance/README.md), [cn_stock_earnings](cn_stock_earnings/README.md) |
| [31](../../trading-course/sessions/31_sentiment_market_claim_verification_contract_20260811.md) | [finance_sentiment](finance_sentiment/README.md), [finance_rumor_check](finance_rumor_check/README.md) |
| [32](../../trading-course/sessions/32_cn_ipo_information_contract_20260811.md) | [cn_ipo](cn_ipo/README.md) |
| [33](../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md) | [hk_stock_corporate_actions](hk_stock_corporate_actions/README.md), [hk_stock_board_lot](hk_stock_board_lot/README.md), [hk_stock_shareholders](hk_stock_shareholders/README.md), [hk_stock_connect](hk_stock_connect/README.md), [hk_stock_ah_comparison](hk_stock_ah_comparison/README.md) |
| [34](../../trading-course/sessions/34_fund_etf_mutual_fund_contract_20260811.md) | [cn_funds_etf](cn_funds_etf/README.md), [cn_mutual_funds](cn_mutual_funds/README.md) |
| [35](../../trading-course/sessions/35_rates_fixed_income_convertible_contract_20260811.md) | [rates_treasury](rates_treasury/README.md), [fixed_income](fixed_income/README.md), [cn_convertible_bonds](cn_convertible_bonds/README.md) |
| [36](../../trading-course/sessions/36_options_information_calculation_contract_20260811.md) | [options](options/README.md) |
| [37](../../trading-course/sessions/37_commodity_futures_cot_contract_20260811.md) | [commodities](commodities/README.md), [cftc_cot](cftc_cot/README.md) |
| [38](../../trading-course/sessions/38_crypto_market_information_contract_20260811.md) | [crypto_market](crypto_market/README.md) |
| [39](../../trading-course/sessions/39_macro_fx_global_market_composition_contract_20260811.md) | [macro_dashboard](macro_dashboard/README.md), [fx_ecb](fx_ecb/README.md), [global_markets](global_markets/README.md) |

These sessions originally answered 52 proposal rows. Session 33 retired one
broad HK umbrella and replaced it with five exact designs, so 56 current rows
are represented above.

## Already-governed thin designs — Sessions 11–22

| Family | Individual design READMEs |
| --- | --- |
| CN quote/history/disclosures/accounting | [cn_stock_quote](cn_stock_quote/README.md), [cn_stock_history](cn_stock_history/README.md), [cn_stock_announcements](cn_stock_announcements/README.md), [cn_stock_financials](cn_stock_financials/README.md) |
| CN identity/rules/corporate/index/macro | [cn_stock_symbols](cn_stock_symbols/README.md), [cn_stock_rules](cn_stock_rules/README.md), [cn_stock_corporate_actions](cn_stock_corporate_actions/README.md), [cn_stock_indices](cn_stock_indices/README.md), [cn_macro](cn_macro/README.md), [cn_regulatory](cn_regulatory/README.md) |
| CN ownership and market publications | [cn_stock_share_structure](cn_stock_share_structure/README.md), [cn_stock_shareholders](cn_stock_shareholders/README.md), [cn_stock_restricted_shares](cn_stock_restricted_shares/README.md), [cn_stock_pledges](cn_stock_pledges/README.md), [cn_stock_insiders](cn_stock_insiders/README.md), [cn_stock_public_info](cn_stock_public_info/README.md), [cn_stock_margin](cn_stock_margin/README.md), [cn_stock_block_trades](cn_stock_block_trades/README.md), [cn_stock_connect](cn_stock_connect/README.md) |
| SEC and infrastructure | [sec_ownership](sec_ownership/README.md), [sec_insiders](sec_insiders/README.md), [finance_cache](finance_cache/README.md) |
| Existing shared-shell projections | [cn_stock_screener](cn_stock_screener/README.md), [cn_market_snapshot](cn_market_snapshot/README.md) |
| T6 day/execution inventory | README-only: [stock_tape](stock_tape/README.md), [cn_broker_readonly](cn_broker_readonly/README.md). Implemented `track_partial`: [cn_broker_paper](cn_broker_paper/README.md), [broker_readonly_alpaca](broker_readonly_alpaca/README.md), [broker_readonly_ibkr](broker_readonly_ibkr/README.md), [broker_paper_alpaca](broker_paper_alpaca/README.md), [broker_paper_ibkr](broker_paper_ibkr/README.md), [broker_live](broker_live/README.md), [trade_compliance](trade_compliance/README.md) |

## Tier-only implementation and promotion rule

A design normally becomes code only as part of its owning tier after every tier
blocker is resolved. T6's seven explicit offline/import-only exceptions are
listed as `track_partial` in `tiers.json`; they neither resolve its feed blocker
nor permit verification. Cross-package work is expected, but every touched
package remains compilable and focused-test green at atomic checkpoints;
incomplete public tools or placeholder behavior are forbidden.

No README-only design or implemented package is individually promoted. The
full build/binding/artifact/Pi/persona matrix runs once through
`bun run tier:verify -- Tn`, after every proposal and handoff required by the
role product is implemented. Only the complete tier becomes ProductUseful.
Existing Experimental slices are inventory to integrate or replace, not
delivery milestones.
