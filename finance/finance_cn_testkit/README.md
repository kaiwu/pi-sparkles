# finance_cn_testkit

Experimental seed-stable, synthetic-only mainland-China scenarios for adapter
and plugin contract tests. The package composes the real CN identity, calendar,
rules, document, and accounting constructors; it does not contain authoritative
exchange data or grant permission to label its values as market facts.

The catalogue covers SSE Main Board, STAR, ChiNext special-treatment,
suspension, B-share listing currency, corrected Chinese reports, exact large
numeric lexemes, `万元`/`万股`, and split trading sessions. Provider adapters
should add separately licensed source fixtures and schema-drift cases.
