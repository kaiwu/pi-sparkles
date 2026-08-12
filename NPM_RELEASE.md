# All-in-one npm release

The npm package has one stable identity: `pi-sparkles-all-in-one`. Its selected
aggregate target is recorded separately in `package.json`, `release-lock.json`,
and `aggregate-lock.json`.

## Build and inspect

T5 is the default. Select T6 explicitly when that inventory is wanted:

```sh
bun run npm:pack -- T5
bun run npm:pack -- T6
```

Outputs are written below `dist/npm/t5/` or `dist/npm/t6/`:

- `package/` is the exact unpacked npm package;
- `pi-sparkles-all-in-one-<version>.tgz` is the npm tarball;
- `npm-pack.json` records npm's integrity, sizes, and file inventory; and
- `RELEASE_SHA256SUMS` locks the tarball and pack record.

Use existing aggregate artifacts without rebuilding every plugin:

```sh
bun run aggregate:build -- T5 --no-build
bun run npm:pack -- T5 --no-build
bun run npm:pack -- T5 --verify-only
```

Before a release, exercise npm's publication validation and confirm that the
exact name/version does not already exist:

```sh
bun run npm:pack -- T5 --no-build --publish-dry-run --check-registry
```

The current T5 selection passes the publish gate. The current T6 selection is
still useful as a local npm-format preview, but remains `private: true` and the
publish dry-run gate rejects it. When T6 has no omissions, partials, or blockers
and the ledger marks it ProductUseful, the same T6 command becomes releasable.

## Local consumer verification

Test the packed artifact in a clean temporary project before publication:

```sh
npm install ./dist/npm/t5/pi-sparkles-all-in-one-0.1.0.tgz
pi --no-extensions \
  --extension ./node_modules/pi-sparkles-all-in-one/index.js \
  --list-models
```

The package pins `pdfjs-dist` because the CN PDF path resolves its CMap assets
at runtime. Pi host code is not bundled. There are no npm lifecycle scripts,
and packaging never reads credential values.

## Version and publish procedure

An npm name/version is immutable. Before preparing another release:

1. update the root `package.json` version using Semantic Versioning;
2. update `CHANGELOG.md`;
3. commit, create the matching `v<version>` tag, and rebuild from that tag;
4. run the repository tests plus the npm dry-run and registry checks; and
5. publish the exact content-locked tarball, never the repository root.

The first registry publication must be performed by an authenticated maintainer
because a trusted-publisher relationship cannot be attached until the package
exists. The explicit command is:

```sh
npm publish ./dist/npm/t5/pi-sparkles-all-in-one-0.1.0.tgz --access public
```

Publishing changes external state and is never performed by builds, tests, or
packaging commands. After the first publication, configure the npm package's
trusted publisher for `.github/workflows/npm-publish.yml`, then prefer that
manual, tag-bound OIDC workflow over a long-lived automation token. Configure a
protected GitHub `npm` environment if review approval is required.

After publication, verify the registry artifact and install through Pi:

```sh
npm view pi-sparkles-all-in-one@0.1.0 \
  name version dist.integrity repository --json
pi install npm:pi-sparkles-all-in-one@0.1.0
```
