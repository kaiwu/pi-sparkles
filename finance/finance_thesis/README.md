# finance_thesis

Pure append-only event and replay model for caller-authored stock theses. Every
version is a full immutable snapshot with exact listing identity, horizon,
claims, evidence relations/states, author attribution, privacy, parent event,
idempotency key, and canonical content hash. Replay rejects forks, version
gaps, identity changes, invalid withdrawals, duplicate IDs, and hash changes.

The package compares version mechanics only. It never validates claims, scores
evidence, infers confidence, or decides whether a thesis is healthy.
