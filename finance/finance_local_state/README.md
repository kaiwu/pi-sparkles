# finance_local_state

`finance_local_state` is a generic user-owned local persistence capability for
durable finance workflows. It reads one explicit regular UTF-8 file under a
caller budget and atomically replaces it only when the current bytes still
match the caller's replayed bytes. A sibling lock file serializes writers and a
same-directory temporary file is fsynced before rename.

The adapter rejects symbolic links, non-files, invalid UTF-8, stale concurrent
writes, cancellation, and oversized state. It does not choose paths, create
directories, interpret finance data, retain credentials, log content, retry,
compact, or delete journals.
