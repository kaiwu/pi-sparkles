# finance_archive

Experimental effect contract for extracting a small, exact allowlist of UTF-8
text entries from an in-memory ZIP artifact. It exists for reviewed structured
authority datasets such as XLSX workbooks; it is not a general attachment,
filesystem, or recursive archive API.

The caller must declare exact entry names plus compressed archive, entry-count,
per-entry uncompressed, and total uncompressed byte budgets. The extractor
rejects multi-disk and ZIP64 archives, unsafe or duplicate names, encryption,
unsupported compression, malformed central/local headers, missing required
entries, invalid UTF-8, length drift, and CRC-32 mismatch. Deflate output is
read incrementally and cancelled once its declared/budgeted bound is exceeded.
No archive entry is written to disk and nested archives are not interpreted.

Cancellation is checked before and after extraction through the shared HTTP
token. The JavaScript FFI performs only ZIP framing, bounded decompression,
UTF-8 decoding, and CRC verification; provider-specific workbook meaning stays
in pure Gleam decoders.

Normal tests use constructed in-memory archives and never fetch a provider.
