# finance_research_calculation

Pure exact-decimal calculation core for T2 research plugins. Versioned,
content-bound requests retain every source lexeme, unit, currency, period,
filing/tag context, provenance receipt, caller assumption, rounding rule, and
expression. Supported named mechanics are ratio, difference, percent change,
mean, net margin, enterprise-to-equity-per-share, and FX-explicit cross-listing
premium/discount. Plugin descriptors restrict which operations are exposed.

Zero denominators, duplicate/missing operands, invalid receipts, incoherent
contexts, wrong track/MIC, unsupported operations, and invalid decimal lexemes
fail closed. The core produces no threshold, base case, quality/valuation
label, recommendation, or investment decision.
