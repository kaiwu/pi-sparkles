# pi-sparkles

Read-only finance evidence tools for the [Pi](https://pi.dev) coding agent.
Gleam packages compile to JavaScript and ship as one Pi extension.

**0.1.5** is the ProductUseful T1–T6 all-in-one package. It registers 135
ledger plugins behind one entrypoint. No plugin can place, route, cancel,
replace, or otherwise mutate a paper or live order.

```sh
pi install npm:@pi-sparkles/pi-sparkles@0.1.5
export AGENT_CONTACT="ops@example.com"
pi --finance-track=cn
```

Then run `/finance-setup` and `/finance-track` before any fetch. A missing
adapter is allowed and never triggers fallback.

| | |
| --- | --- |
| Release | [`@pi-sparkles/pi-sparkles@0.1.5`](NPM_RELEASE.md) |
| Tiers | T1–T6 ProductUseful · 0 open blockers · [tiers.json](tiers.json) |
| Inventory | 135 ledger plugins · 142 Gleam plugin packages · 77 finance libraries |
| Tracks | closed `cn` / `hk` / `us` |
| Tested with | Pi `0.83.0` (`305c014dc`) · Gleam `1.18.0` · Bun `1.3.14` |

The seven packages excluded from the aggregate (`hello`, `lifecycle`,
`safety_gate`, `cn_setup`, `hk_setup`, `cn_fundamentals`, `hk_fundamentals`)
are development extras, not extra products.

Package-level Experimental labels are inventory. ProductUseful applies only to
a whole role tier. Tiers are not a 6×3 track matrix. See
[PRODUCT_TIERS.md](PRODUCT_TIERS.md).

## Docs

| Doc | Use it for |
| --- | --- |
| [PRODUCT_TIERS.md](PRODUCT_TIERS.md), [tiers.json](tiers.json) | six role products, blockers, promotion |
| [PRODUCT_READINESS.md](PRODUCT_READINESS.md) | input paths, compact/drill-down contract, non-executing broker boundary |
| [CHANGELOG.md](CHANGELOG.md), [NPM_RELEASE.md](NPM_RELEASE.md) | published npm identity and release gate (Pi and DSH lines) |
| [dsh/README.md](dsh/README.md) | DeepSeek Harness all-in-one plugin builder + adapter |
| [FUNCTIONAL_DESIGN.md](FUNCTIONAL_DESIGN.md) | functional core / effect shell |
| [TRACK_GUIDE.md](TRACK_GUIDE.md) | adding another closed market track |
| [SECURITY.md](SECURITY.md) | trusted-local-code model |
| [FUTU.md](FUTU.md) | external OpenD runbook; OpenD is never a deliverable |
| [plugins/README.md](plugins/README.md) | 135-proposal index |
| [pi_gleam/README.md](pi_gleam/README.md) | binding authoring |
| [ROADMAP.md](ROADMAP.md) | historical family design, not the release ledger |

## Develop

Requirements: Gleam, Bun, and either a hydrated Pi checkout or an installed
`pi`.

```sh
bun run tier:audit
bun run aggregate:build
pi --no-extensions -e ./dist/aggregate/t6 --list-models
bun run test:aggregate:pi
```

`test:aggregate:pi` loads the cumulative T1–T6 entrypoint once. Per-plugin and
earlier-tier Pi-load targets are not part of verification. It uses
`PI_SOURCE_DIR` when that checkout has its dependencies, defaults to
`/home/kaiwu/Documents/github/pi-mono` in this workspace, and falls back to the
installed Pi.

Focused diagnostics stay cheap; promotion is always a whole tier:

```sh
bun run build -- hello
bun run test:unit -- safety_gate
bun run tier:checkpoint -- T1
bun run test:acceptance -- swing
```

Opt-in live lanes are excluded from `bun run test`:

```sh
bun run test:live:tutor
AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec
```

Packaging: `bun run tier:package -- T1`, `bun run aggregate:build` (T6 means
T1–T6; pass `T5` only to reproduce the prior boundary), `bun run npm:pack`,
`bun run npm:release:verify`. Details in [NPM_RELEASE.md](NPM_RELEASE.md) and
[PRODUCT_TIERS.md](PRODUCT_TIERS.md).

Hex still distributes Gleam **source**, not a loadable Pi plugin, and is not
the user-facing product. `pi_gleam` is an unpublished `0.1.0` binding.

## Runtime environment

Set variables in the environment that launches Pi. This repository does not
load `.env` files. Restart Pi after changes.

| Variable | Kind | Used by |
| --- | --- | --- |
| `AGENT_CONTACT` | non-secret operator identity | every CN/HK/US adapter and the statusline |
| `TUSHARE_TOKEN` | credential | CN symbol discovery and Tushare-backed event tools |
| `ALPACA_API_KEY_ID`, `ALPACA_API_SECRET_KEY` | credential / secret | US quote, OHLCV, universe, corporate actions, news |
| `OPENFIGI_API_KEY` | optional secret | `finance_symbols` (anonymous access otherwise) |
| `TWELVE_DATA_API_KEY` | credential | `company_profile` |
| `FRED_API_KEY` | credential | `macro_fred` |

`AGENT_CONTACT` identifies the caller and grants no provider or market
authority. A known exact CN code can use Eastmoney history without Tushare.
Eastmoney, CNINFO, HKEX, and SEC reuse `AGENT_CONTACT` only. T6 reviews
caller-supplied capability packets and receipts; it does not read broker
credentials.

```sh
export AGENT_CONTACT="ops@example.com"
export TUSHARE_TOKEN="<secret-manager:tushare>"            # optional
export OPENFIGI_API_KEY="<secret-manager:openfigi>"        # optional
export ALPACA_API_KEY_ID="<secret-manager:alpaca-key-id>"
export ALPACA_API_SECRET_KEY="<secret-manager:alpaca-secret>"
export TWELVE_DATA_API_KEY="<secret-manager:twelve-data>"
export FRED_API_KEY="<secret-manager:fred>"
pi --finance-track=cn
```

Generated `CONFIGURATION.md` lists names only. Per-plugin contracts live in
each plugin README.

## Layout

```text
pi-sparkles/
├── pi_gleam/          Gleam binding for Pi's extension API
├── finance/           77 reusable non-Pi libraries (no Pi imports)
├── plugins/           142 Gleam plugin packages; 135 are the T1–T6 ledger
├── dsh/               DeepSeek Harness adapter + bundle (parallel npm line)
├── scripts/           Bun task drivers
├── test/              binding, architecture, artifact, acceptance, workflow
├── tiers.json         exclusive proposal ownership and promotion state
└── dist/              generated, gitignored Pi and DSH artifacts
```

The root is not a Gleam package. Every `finance/` and `plugins/` package owns
a `gleam.toml`, README, source, and tests. Root tasks discover packages by
`gleam.toml`. All 135 ledger proposals are implemented; there is no
README-only remainder.

Architecture rules: [FUNCTIONAL_DESIGN.md](FUNCTIONAL_DESIGN.md). Plugin
index: [plugins/README.md](plugins/README.md). Binding surface:
[pi_gleam/README.md](pi_gleam/README.md).

## Tasks

| Command | Purpose |
| --- | --- |
| `bun run tier:audit` | exhaustive six-tier ownership and blocker counts |
| `bun run tier:show -- T1` | one tier's outcome, profile, blockers, proposals |
| `bun run tier:checkpoint -- T1` | format, build, and focused-test the touched set |
| `bun run tier:verify -- T1` | one expensive promotion matrix for a complete tier |
| `bun run tier:package -- T1` | content-lock one ProductUseful Pi package |
| `bun run tier:install -- T1` | verify and `pi install` (user scope default) |
| `bun run aggregate:build -- [T5\|T6]` | one Pi entrypoint; T6 is T1–T6 |
| `bun run npm:pack -- [T5\|T6]` | all-in-one npm tarball, no publish |
| `bun run dsh:bundle -- [T5\|T6]` | all-in-one DeepSeek Harness plugin (dist/dsh/dsh-sparkles) |
| `bun run dsh:verify` | schema bridge vs the real dsh-tools validator |
| `bun run dsh:npm:pack -- [T5\|T6]` | `@dsh-sparkles/dsh-sparkles` npm tarball, no publish |
| `bun run check` | format and warnings-as-errors for every package |
| `bun run build [-- name]` | diagnostic plugin bundle |
| `bun run test:unit [-- name]` | Gleam tests |
| `bun run test:architecture` | functional-core / effect-shell import rules |
| `bun run test:ffi` | JavaScript binding contracts |
| `bun run test:artifacts` | generated extension modules |
| `bun run test:acceptance [-- swing]` | deterministic CN/HK/US journeys |
| `bun run test:aggregate:pi` | load T1–T6 once in Pi |
| `bun run test:live:tutor` | opt-in LLM journey |
| `bun run test:live:sec` | opt-in live SEC compatibility |
| `bun run test:workflow` | tier manifest and promotion laws |
| `bun run test` | full diagnostic matrix |
| `bun run clean` | remove generated output |

`PI_SPARKLES_TEST_JOBS=1..16` bounds unit-test workers (default 4). Publishing
is never part of `build` or `test`.

## Still open

The finance product is shipped. Remaining work is Hex **source** publication
and further typed `pi_gleam` coverage — not missing role tiers.

- Hex name, consumer builder, and `hex:check` / `hex:publish` are unbuilt.
- `pi_gleam` typed wrappers still grow only when a plugin needs them; `pi/raw`
  covers the rest.
- Later calendars, official CN/HK filing-linked accounting depth, production
  entitlements, and redistribution stay explicitly unknown.

Unknown facts stay unknown. Providers, SDKs, gateways, credentials, login
state, and live certification stay caller-owned.
