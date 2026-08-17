# All-in-one npm release

The npm package has one stable identity: `@pi-sparkles/pi-sparkles`. Its selected
aggregate target is recorded separately in `package.json`, `release-lock.json`,
and `aggregate-lock.json`.

## Build and inspect

T6 is the current ProductUseful release default and always means the cumulative
T1-through-T6 inventory. Select T5 explicitly only to reproduce the prior 0.1.4
release boundary:

```sh
bun run npm:pack
bun run npm:pack -- T5
```

Outputs are written below `dist/npm/t5/` or `dist/npm/t6/`:

- `package/` is the exact unpacked npm package;
- `pi-sparkles-pi-sparkles-<version>.tgz` is the npm tarball;
- `npm-pack.json` records npm's integrity, sizes, and file inventory; and
- `RELEASE_SHA256SUMS` locks the tarball and pack record.

Use existing aggregate artifacts without rebuilding every plugin:

```sh
bun run aggregate:build -- --no-build
bun run npm:pack -- --no-build
bun run npm:pack -- --verify-only
```

Before a release, run the dedicated all-in-one gate. It exercises only the npm
product boundary: focused aggregate/package laws, a fresh T6 build, one exact
tarball, a clean install, one plain-Pi aggregate entrypoint load, npm's publish
dry-run, and exact name/version availability:

```sh
bun run npm:release:verify
```

The repository has no per-plugin Pi-load matrix. Development, promotion, and
release verification load the T6 all-in-one aggregate entrypoint once so all
135 plugin registrations are exercised at the actual distribution boundary.
The loader rejects earlier-tier and per-plugin target overrides.

The T5 selection remains the published 0.1.4 boundary. T6 is ProductUseful with
zero omissions, partials, or blockers and is selected for version 0.1.5.

## Local consumer verification

The `--install-smoke` gate installs the exact tarball into a clean temporary npm
prefix with lifecycle scripts disabled, verifies the installed package and exact
`pdfjs-dist` version, imports its default extension, removes every declared
provider variable from the child environment, and asks plain Pi to load the
entrypoint with `--list-models`. For a manual equivalent:

```sh
npm install ./dist/npm/t6/pi-sparkles-pi-sparkles-0.1.5.tgz
pi --no-extensions \
  --extension ./node_modules/@pi-sparkles/pi-sparkles/index.js \
  --list-models
```

The package pins `pdfjs-dist` because the CN PDF path resolves its CMap assets
at runtime. Pi host code is not bundled and is declared with the Pi-required
`"*"` peer ranges. There are no npm lifecycle scripts, and packaging never
reads credential values.

Futu OpenD, Alpaca, IBKR, their SDKs or gateways, credentials, entitlements,
login state, and live certification are external caller-owned dependencies.
They are not npm dependencies or package assets. T6 accepts only explicitly
selected, bounded capability packets and receipts and provides no order-mutation
surface or silent provider fallback.

## Version and publish procedure

An npm name/version is immutable. Before preparing another release:

1. update the root `package.json` version using Semantic Versioning;
2. update `CHANGELOG.md`;
3. commit, create the matching `v<version>` tag, and rebuild from that tag;
4. run `bun run npm:release:verify`; and
5. publish the exact content-locked tarball, never the repository root.

The first registry publication must be performed by an authenticated maintainer
because a trusted-publisher relationship cannot be attached until the package
exists. The explicit command is:

```sh
npm publish ./dist/npm/t6/pi-sparkles-pi-sparkles-0.1.5.tgz --access public
```

Publishing changes external state and is never performed by builds, tests, or
packaging commands. After the first publication, configure the npm package's
trusted publisher for `.github/workflows/npm-publish.yml`, then prefer that
manual, tag-bound OIDC workflow over a long-lived automation token. Configure a
protected GitHub `npm` environment if review approval is required.

After publication, verify the registry artifact and install through Pi:

```sh
npm view @pi-sparkles/pi-sparkles@0.1.5 \
  name version dist.integrity repository --json
pi install npm:@pi-sparkles/pi-sparkles@0.1.5
```

---

# DeepSeek Harness release — @dsh-sparkles/dsh-sparkles

The DeepSeek Harness distribution is a separate npm identity and release gate.
It reuses compatible T1–T6 functional cores/effect shells, declares
`dsh.bundle.patch`, and is installed with `dsh plugin`:

```sh
bun run dsh:bundle                      # dist/dsh/dsh-sparkles (all-in-one plugin)
bun run dsh:npm:pack                    # content-lock and pack the tarball, never publish
bun run dsh:verify                      # real schema + generated ToolRuntime execution
bun run dsh:npm:preview:verify          # allowed private-preview gate
dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles
```

The packed package has one self-contained server entrypoint registering tools
through `ctx.tools` and finance commands through `ctx.commands`, plus one DSH
browser entrypoint for `shell.overlay`. All 135 ledger components are covered:
131 global-safe Pi shells and four `scoped_pi` counterparts instantiated once
per DSH agent. DSH-only Cordis entries remain in the isolated `dsh/plugins/`
lane. The exact excluded/scoped/extra lists are recorded in `dsh-lock.json` and
the manifest's `dshSparkles` section. It pins the tested agent, tool, command,
system-prompt, session-projection, client-runtime, and UI-layout peers to
`0.1.0-rc.6`, pins `pdfjs-dist` for the CN PDF CMap runtime resolution,
requires Node 22.19+, carries the
`dsh.bundle.patch` manifest and a content lock (`dsh-lock.json` +
`release-lock.json` + inner/outer `SHA256SUMS`), and has no lifecycle scripts
or credential values. The install smoke installs the exact tarball into a clean
npm prefix, imports the entrypoint to verify its Cordis plugin shape, and
composes it in an isolated `DSH_HOME` profile with the real `dsh` CLI.

The DSH manifest is currently `preview`: the four global exclusions now have
implemented per-agent counterparts, but the independent DSH role acceptance
lane has not been declared complete. Therefore T5 and T6 pack only as private
blocked previews; the publish dry-run, registry check, and real publication
gate refuse them. Do not run an npm publish command until
`dsh_release.status` is independently promoted to `product_useful` with its
acceptance evidence. Packaging/verification never publish.

```sh
bun run dsh:npm:release:verify          # intentionally refuses while preview
```
