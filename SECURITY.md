# Security policy

Pi extensions execute with the user's permissions. Before enabling provider
paths, review the package's `CONFIGURATION.md`, the relevant plugin contract,
data rights, entitlement limits, and source provenance.

The all-in-one plugin never places, submits, routes, cancels, replaces, or
otherwise mutates paper or live broker orders. Credentials remain caller-owned
runtime inputs. They must not be committed, bundled, logged, copied into
receipts, or persisted by packaging tools.

Report suspected vulnerabilities privately to the repository owner rather
than opening a public issue containing exploit details, credentials, account
data, or unpublished market data. Revoke any credential that may have been
exposed before sending a redacted report.

Only supported, content-locked npm releases should be used. Verify the npm
registry integrity and the included `SHA256SUMS`; do not install an unpacked
directory or tarball whose inventory differs from `release-lock.json`.
