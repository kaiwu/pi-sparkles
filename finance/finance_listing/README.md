# finance_listing

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_listing` supplies the small provider-neutral identity pieces shared by
the `cn`, `hk`, and `us` tracks: a listing key is a canonical instrument ID plus
symbol, MIC, and explicit track; effective intervals are inclusive; historical
aliases and listing relationships retain optional evidence IDs.

The package deliberately does not define boards, code formats, currencies,
share classes, or A/B/H/CDR relationship laws. Those belong to market packages.
A relationship kind is therefore accepted only as a validated stable identifier
and must be constructed through a market-owned wrapper before user-facing use.

There is no provider lookup and no first-candidate selection. Provider adapters
build these values from reviewed source data, while market identity packages
apply their own venue and relationship invariants.
