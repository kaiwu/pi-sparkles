# finance_evidence

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_evidence` is the pure compatibility gate between canonical
`finance_core.Observation(a)`, `finance_provenance.Evidence`, and one explicit
`finance_track` context per market leg. It centralizes rules that must behave
the same in the `cn`, `hk`, and `us` tracks without flattening their identities.

The first slice validates observation and evidence time ordering, source and
optional evidence-ID agreement, availability, known/equal units, declared
quality/restatement policy, exact or independent as-of policy, and explicit
redistribution intent. Same-track composition is the default. A mixed-track
calculation must select `ExplicitCrossTrack`, contain at least two tracks, and
retains every original context and evidence record in the validated value.

`InternalAnalysis` does not claim redistribution rights. A
`RedistributableOutput` fails closed for internal-only, no-redistribution, or
unknown rights. This is a deterministic evidence check, not legal advice or an
authorization to trade.

The package performs no Pi, Promise, FFI, clock, network, storage, or provider
work. Provider adapters remain responsible for constructing truthful canonical
observations and evidence. Track-specific plugins may add stricter market laws
after this common gate; they must not weaken it silently.
