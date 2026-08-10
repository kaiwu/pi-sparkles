# finance_data_quality

Experimental provider-neutral Pi plugin for mechanically inspecting one exact
`cn`, `hk`, or `us` observation-compatibility packet.

`data_quality_check` accepts a bounded source catalogue, exact observation
coordinates, and caller/provider-adapter facts. It retains canonical source,
receipt, entitlement, licence, unit, adjustment, time, raw lexeme, unavailable,
and conflicting states. It reports explicit expected-coordinate omissions,
same-source duplicate groups, caller-selected as-of-age freshness, unit and
adjustment incompatibility, and exact cross-provider agreement or disagreement.

The comparison method is deliberately narrow: providers are compared only when
each has one observed exact decimal for the same coordinate and all unit and
adjustment contexts are known and identical. Duplicate, unavailable,
conflicting, unknown-context, and incompatible rows make the comparison
indeterminate rather than being dropped or coerced.

This first slice is network-free and stateless. It does not authenticate source
receipts, verify listing or membership identity, infer missing expected periods,
select or score providers, repair or interpolate data, apply split detection,
declare a source correct, generate a signal, or trade.
