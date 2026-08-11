# finance_text_analysis

Pure transparent text mechanics for T2. `sentiment` applies the fixed,
versioned `finance_lexicon_v1` only to caller-supplied exact token spans and
shows every contributing span. `rumor` compares a structured claim with each
caller-supplied source independently using exact predicate/value/unit and
negation/exclusivity rules.

Neither module decides truth, credibility, materiality, market impact, or a
trading action.
