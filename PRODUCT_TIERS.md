# Product-tier delivery standard

This repository delivers complete products for professional roles, not a
sequence of individually promoted plugin exercises. The only delivery,
verification, and promotion unit is a product tier.

The exact, machine-checked ownership of all 135 R1 proposals is
[`tiers.json`](tiers.json). Each proposal belongs to exactly one tier; later
tiers inherit earlier ProductUseful tiers through typed receipts and installed
Pi tools, never plugin-to-plugin source imports.

## Product tiers

| Tier | Product and user | Proposals | Current inventory | ProductUseful outcome |
| --- | --- | ---: | ---: | --- |
| **T1 — ProductUseful** | Swing trader | 45 | 45 packages, 0 not implemented | Exact CN daily acquisition → screen → inspect → technicals → plan → simulate → journal/review; bounded HK/US tools remain separately scoped |
| **T2** | Long-term equity investor | 45 | 8 packages, 37 not implemented | Primary filings/disclosures → normalized company facts → comparison/valuation/quality/governance → cited report and thesis review |
| **T3** | Portfolio manager and monitor | 11 | 3 packages, 8 not implemented | Durable portfolio import/reconciliation → risk/scenarios/attribution/rebalance/tax lots → monitors/alerts and auditable resume |
| **T4** | Quant researcher | 7 | 3 packages, 4 not implemented | Point-in-time universe/data → explicit features/events → trial ledger/backtest/comparison → complete reproduction |
| **T5** | Macro and multi-asset researcher | 16 | 1 package, 15 not implemented | Exact instrument/source legs → reviewed calculations → time-aligned, separately labelled cross-asset research |
| **T6** | Day trader and execution operator | 11 | 2 packages, 9 not implemented | Authenticated live quote/depth/tape → bounded day workflow → account/paper/compliance → explicitly authorized and reconciled live effects |

“Current inventory” means code exists. It is not a completion percentage and
does not credit narrow Experimental slices as finished product behavior.

## Tiers and tracks do not form a matrix

There are six product deliveries, not `6 × 3 = 18`. `cn`, `hk`, and `us` remain
exact observation/source scopes; they are not product variants and do not cause
the role journey or expensive acceptance suite to be copied three times.

| Tier | Single acceptance profile |
| --- | --- |
| T1 swing | One CN anchor journey; exact HK/US acquisition tools retain their own bounded contracts without duplicate swing journeys |
| T2 investor | One US/SEC anchor journey; CN/HK market-owned tools receive focused contract coverage, not two more investor journeys |
| T3 portfolio | One mixed imported portfolio with separately labelled CN/HK/US legs |
| T4 quant | One US point-in-time dataset/replay journey; provider-neutral manifests preserve other track labels |
| T5 multi-asset | Global/cross-market legs; it is not an equity-track product |
| T6 day/execution | One US live/broker journey plus the specific CN tape-adapter contract required by Session 41; no HK/CN journey duplication |

Shared domain types, calculations, receipts, Pi shells, and acceptance logic are
implemented once. Track-owned adapters or rule modules exist only when market
law, identity, calendar, source, entitlement, or correction semantics genuinely
differ. They are already counted once among the 135 proposals and owned by one
tier.

A tier may therefore be ProductUseful for its declared anchor profile while
other end-to-end track journeys are explicitly unsupported or `track_partial`.
That is a complete scoped product, not a half-product. We never imply that an
anchor journey proves another track, and adding a new anchor track would be a
separate future scope decision—not an automatic matrix expansion.

### Provider adapters and credentials

Provider breadth is not a product or acceptance matrix. Shared canonical ports,
schemas and conformance laws are implemented once; concrete adapters are added
for the useful providers whose contracts can be proved. Every shipped adapter
declares its exact environment variables or injected capability, source scope,
entitlement, pacing, limits and unsupported claims. Provider selection is
explicit, and adapters never silently borrow credentials, cross tracks or fall
back to another source.

Credentials are never product files, fixtures, defaults or persisted plugin
state. Ordinary tests use rights-safe response fixtures and scripted
transports. An opt-in live compatibility run may temporarily read caller-owned
credentials from the environment to prove the adapter against the subscribed
service; it must redact them and retain only non-secret evidence. Missing
credentials or alternative-provider breadth is not a blocker. A provider blocks
work only when no testable provider/import path can establish a required
contract, as with authentic T6 real-time stream behavior.

For T1, Eastmoney is the working CN adapter and Tushare Pro is the second
mainstream adapter/conformance proof. The Tushare token is an environment-only
runtime and opt-in-test dependency. Later adapters reuse the same provider port
without reopening T1 or changing the plugin-facing contract.

Each adapter receives focused conformance and decoder coverage. The tier's
expensive role journey uses only its declared anchor adapter, so supporting
additional providers does not duplicate the entire product acceptance suite.

## Mandatory tier workflow

Every tier moves through this exact sequence:

```text
Queued
  -> BlockerResolution
  -> Building
  -> Verifying
  -> ProductUseful
```

There is no tier-level Experimental completion and no plugin-level promotion.
Existing Experimental packages are reusable inventory whose behavior must be
completed, integrated, or replaced inside their owning tier.

### 1. Resolve the blocker dossier first

Before new tier implementation begins, every genuine blocker in `tiers.json` must be
changed from `open` to `resolved` with exact evidence recorded in `R3.md` or the
referenced provider/security decision record. A condition is a blocker only
when no testable provider, public source, bounded user-owned import, fixture, or
scripted capability can support implementation. Alternative providers,
production credentials and acceptance work are delivery requirements, not
pre-build stops.

An unresolved provider or operational prerequisite stops the whole tier. We do
not fill the time by producing provider-neutral shells and calling them a
completed slice.

### 2. Build the whole tier inside out

Once blockers are resolved, implement one coherent dependency cone:

1. canonical types, invariants, state transitions, receipts, and shared pure
   finance laws;
2. named provider/import/storage capabilities and their real-byte decoders,
   budgets, cancellation, rights, correction, and failure contracts;
3. thin Pi shells with the uniform compact-response, stable-handle,
   drill-down, available-operation, observability, and privacy contract;
4. receipt handoffs and durable/session lifecycle composition across every
   plugin needed by the role;
5. the ordinary professional journey, its failures, recovery, resume/fork, and
   counterexamples.

Work may cross many plugin and finance-package directories in one change.
Nothing in the tier is promoted merely because one package compiles or its
isolated tests pass.

### Atomic package integrity during tier work

Tier implementation is deliberately cross-package, but the shared worktree may
never be left with a half-wired or broken plugin:

- every touched package must format, compile with warnings as errors, and pass
  its focused deterministic tests at each handoff or commit checkpoint;
- a public tool, command, event, or manifest entry is wired only when its whole
  typed path—decode, capability, domain transition/calculation, effect,
  response, error, cancellation, and test—is coherent;
- unfinished branches remain private compilable modules or explicit tier
  backlog, not public stubs, placeholder success results, `todo`/panic paths,
  silently empty adapters, or misleading README claims;
- coordinated type/receipt changes update every affected producer and consumer
  atomically. Compatibility shims must be real, tested behavior rather than an
  excuse to leave one package broken;
- plugin source-import boundaries remain intact even when a feature crosses
  them: share pure finance packages and compose plugin shells through typed
  Pi-visible receipts/capability injection.

This preserves a continuously buildable repository without turning each
package checkpoint into a delivery or promotion event.

### 3. Test cheaply while building; verify once at tier scope

Focused unit, decoder, transition, and boundary tests remain mandatory as
inner-loop diagnostics. They may be run while editing affected packages, but
they do not update the ledger and are not completion evidence.

`bun run tier:checkpoint -- T1` checks the currently touched code packages as
one atomic working set. Use it before handing off or committing an in-progress
tier change; it does not promote the tier.

The expensive matrix runs exactly once, after the entire tier enters
`verifying`:

```sh
bun run tier:audit
bun run tier:verify -- T1
```

`tier:verify` fails before spending the full-test cost unless:

- the requested tier is the active tier and has status `verifying`;
- every blocker is resolved with recorded evidence;
- every dependency tier is ProductUseful;
- all proposals in the tier have implementation packages; and
- the tier's role-level acceptance lane exists.

It then runs the repository build/unit/architecture/finance/binding/artifact/Pi
matrix once and the tier-specific end-to-end acceptance lane once. We never run
that full promotion matrix after each plugin.

### 4. Promote only the complete role product

A tier becomes ProductUseful only when its entire role journey satisfies
[`PRODUCT_READINESS.md`](PRODUCT_READINESS.md), including named repeatable input
paths, real or contract-faithful provider evidence, compact output and bounded
drill-down, all cross-plugin receipt handoffs, lifecycle/failure recovery, and
applicable human/security gates.

If any plugin, provider path, track leg, failure mode, or handoff required by the
tier remains partial, the tier remains `building` or `verifying`. We report the
exact tier blocker; we do not promote the working subset as an Experimental
product.

## Active ledger decision

T1 is **ProductUseful**. All 45 proposal packages exist; the complete repository
matrix, installed-Pi smoke lane, existing CN/HK/US receipt-and-journal swing
workflow, and dedicated Eastmoney-first CN role lane passed on 2026-08-11.
Tushare credentials remain environment-only adapter inputs and CNINFO remains a
public official-source path. `pi_stock_tape` belongs to T6; authentic real-time
market-data access for T6 is the only open external tier blocker.
