# pi_sparkles_crypto_market

Tier 5 ProductUseful, stateless Pi shell over the pure `finance_multi_asset`
contract. It registers `crypto_market_inspect` and accepts one bounded caller-owned,
versioned JSON packet plus its expected SHA-256 digest.

The first slice validates exact asset/network/token/contract/venue identity, quote/trades/24-7 candle/order book/derivative context, venue state and lifecycle events. Every result retains exact source,
time, entitlement, licence, correction and receipt context. The input digest
binds the imported bytes and the result receipt, but is not a provider
signature, authority proof or origin authentication.

The shell owns only bounded UTF-8 import, cancellation and Pi presentation.
Domain decoding, validation and calculations remain pure Gleam. There is no
ambient credential, network fallback, storage or cross-plugin source import.

Crypto is not a fourth equity track. No fiat equivalence, safety, arbitrage, liquidity, value or trading judgment.

Focused package builds are inner-loop diagnostics only. Product usefulness is
decided once by the complete T5 multi-asset researcher acceptance lane.
