# pi_sparkles_stock_tape

Status: **Experimental implementation — owned by T6** · explicit external-provider packet review · no bundled provider

`stock_tape` validates one exact bounded `cn`, `hk`, or `us` transaction-tape
packet. It retains provider order, exact unsigned sequence lexemes, gaps,
duplicates, resets, correction/cancel lineage, exchange/provider/retrieval
clocks, condition coverage, entitlement, licence, paging, and content receipts.
Track/MIC scope is exact: CN permits XSHG/XSHE/XBSE, HK permits XHKG, and US
permits XNYS/XNAS. No successful leg supplies another.

The named provider is an explicit caller-owned runtime dependency. The package
ships no OpenD, provider SDK, credential, adapter, transport, quote, bid/offer,
order-book, signal, or broker mutation surface. Provider-declared completeness
and matching hashes are retained facts, not provider or exchange authentication.

Focused checks:

```sh
bun run test:unit -- stock_tape
bun run build -- stock_tape
bun test test/binding/stock_tape.test.js
```
