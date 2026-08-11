# finance_local_import

`finance_local_import` is the single bounded local-file capability used by the
T2 research evidence adapters. It reads one caller-selected regular UTF-8 file
under an explicit byte limit, rejects symlinks and non-files, observes
cancellation before and after I/O, and returns typed missing/truncated/failure
states. It never searches directories, follows links, writes, watches, caches,
or authenticates the file's origin.

The adapter contains no finance interpretation. Callers must content-bind the
returned exact bytes and decode them through a versioned domain contract.
