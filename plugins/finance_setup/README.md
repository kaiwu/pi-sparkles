# pi_sparkles_finance_setup

Tier coverage: **ProductUseful T1** · package behavior is promoted and verified
only through the complete tier

Pi extension for finance capability discovery and safe configuration
diagnostics. It registers `/finance-setup`,
`finance_capabilities`, and `finance_provider_health`.

## Why this plugin exists

Finance answers fail deceptively when a provider is absent, a default currency
is malformed, or an agent assumes that an installed package implies live data.
This plugin gives every later finance workflow a small preflight contract. It
reports only states it can prove and never prints or returns provider secrets.

The current vertical slice validates currency/timezone defaults, lists the
installed functional foundations, detects companion tools through Pi's active
tool registry, and distinguishes an absent provider adapter from a checked
network connection. It deliberately does **not** call a provider endpoint yet;
connectivity, credentials, and entitlement become `ready` only when a
provider-specific adapter implements a typed health probe.

## Functional design

`capability.gleam` is a pure function:

```text
defaults + active tool names -> immutable capability report
```

It depends on `finance_core` smart constructors for currency and timezone
validation. The root module is the effect shell: it reads Pi flags and active
tool names, passes ordinary values into the core, and renders the result. Equal
inputs produce equal reports, so setup behavior is unit-testable without Pi or
ambient environment variables.

## Interface

- `/finance-setup` uses `--finance-currency` (default `USD`) and
  `--finance-timezone` (default `UTC`).
- `finance_capabilities` accepts optional global reporting `currency` and
  `timezone` overrides. The result labels them as reporting defaults and never
  presents them as the active track's effective currency/timezone.
- `finance_provider_health` accepts a provider name. Eastmoney, Tushare Pro,
  Alpaca, OpenFIGI, and SEC EDGAR have registered adapter-surface contracts;
  unknown providers remain explicitly `unknown`.

Tool results include structured `details` with state names. `available` means a
companion tool is installed; it never implies that credentials, connectivity,
data freshness, or entitlement were verified. Those require a provider-specific
probe.

## Safety and permissions

The plugin performs no network, filesystem, subprocess, storage, or environment
effects. It reads only Pi flags and Pi's active tool-name list. It cannot reveal
secrets because it never reads them. Future provider probes must return
redacted diagnostics and keep configured, authenticated, reachable, entitled,
and fresh as separate states.

## Dependencies and status

Local development uses path dependencies on `../../pi_gleam` and
`../../finance/finance_core`. Replace them with released Hex constraints before
publishing. Tested against Pi `0.83.0`. The installed-capability report is part
of ProductUseful T1; live provider health remains explicitly unproved unless a
provider-specific probe supplies that evidence.
