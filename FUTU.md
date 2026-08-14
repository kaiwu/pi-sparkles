# Futu OpenD runbook for T6

This document lets a later development session resume the Futu investigation
without rediscovering the local setup or weakening the T6 delivery rules. It is
an operational note only. [`tiers.json`](tiers.json),
[`PRODUCT_TIERS.md`](PRODUCT_TIERS.md), and the blocker record in
[`R3.md`](R3.md#t6-intraday-provider-blocker--active-2026-08-13) remain
normative.

## Current state — 2026-08-14

- T6 remains in `blocker_resolution` because `T6-INTRADAY-PROVIDERS` is open.
- Futu OpenD `10.10.7008` for Ubuntu 18.04 was inspected and exercised on this
  x86-64 Arch Linux host. Its bundled libraries resolve against the host, the
  command-line process starts, and it listens on `127.0.0.1:11111`.
- The local development launcher is `/usr/local/bin/futu-opend`; the external
  installation is `/opt/futu-opend/10.10.7008`. Neither path is a repository
  input or distribution asset.
- A caller-owned Futu account authenticated successfully. OpenD reported normal
  Shanghai LV1, Shenzhen LV1, Hong Kong securities LV2 and US securities LV2
  quote permissions and a subscription quota of 100. No XBSE/BSE permission
  was established, so XBSE remains unsupported until separately proved.
- Authentication happened after CN/HK market hours. A later XSHG continuous-
  session baseline and an XHKG continuous-session baseline passed on
  2026-08-14, followed by an independent XSHE baseline. Separate US XNAS and XNYS baselines were completed during the
  regular session on 2026-08-13 Eastern time. Their bounded conclusions are
  recorded below. None exercised reconnect or captured raw provider rows.
- The official JavaScript SDK `futu-api@10.10.7008` is pinned only as a root
  development dependency. Bun imports it directly. Its transitive
  `protobufjs` postinstall remains blocked because the quote client works
  without running lifecycle scripts. Neither the SDK nor its dependencies are
  tier runtime assets.
- `scripts/futu-us-ticker-probe.js` is a private, opt-in Bun blocker probe. It
  is inert without `--live`, imports no Python package, invokes only
  `GetSubInfo` and `Sub`, and cannot enter normal tests, tier gates, packages,
  installation, or plugin load.
- `scripts/futu-cn-ticker-probe.js` reuses that guarded quote lifecycle for
  separate XSHG and XSHE runs. It accepts only the repository-reviewed ordinary
  A-share anchors, maps them to Futu markets `21` and `22`, omits US-only
  session fields, requires the official `Asia/Shanghai` continuous-auction
  window with enough time left for cleanup, and permits only one venue per
  reviewed run.
- `scripts/futu-hk-ticker-probe.js` applies the same lifecycle to the sole
  repository-reviewed XHKG ordinary-share anchor. It fixes Futu market `1`,
  omits US-only session fields, and permits only HKEX continuous trading with
  enough time left for exact release before lunch or closing auction.
- `scripts/futu-us-rights-probe.js` is a separate one-request Bun entitlement
  probe. It invokes only global protocol 1005 with field flag 4, reads only
  `usQotRight`, and emits no identity/account field or provider text. It
  consumes no subscription unit.
- The operator selected OpenD's remember-login option. That vendor-owned local
  state is outside the product. Future sessions must not inspect, print, copy,
  package, commit, or convert it into plugin configuration.

The host/account facts above prove only that the gateway and three entitlements
are plausible inputs. The bounded live baselines recorded below are blocker
evidence, but their explicit unknowns do not resolve the blocker or constitute
ProductUseful evidence.

## Futu-first multi-track decision — 2026-08-13

Use Futu as the first explicitly selected real-time transaction-ticker/tape provider for
each user-visible track that its caller-owned entitlement and focused
conformance exercise can prove. This is one provider implementation reused
behind canonical ports, not one undifferentiated cross-market feed:

- `cn`: initially XSHG and XSHE A-share LV1; XBSE remains unsupported or
  `track_partial` until separately entitled and proved;
- `hk`: required first XHKG securities LV2 leg, based on the account-reported
  entitlement; exact product, trade/ticker schema, rights, sequence, clocks,
  conditions, corrections, reconnect, and venue coverage still require their
  own exercise; and
- `us`: required first XNYS and XNAS securities LV2 leg, based on the account-reported
  entitlement; exact feed, exchange coverage, SIP/proprietary status, rights,
  sequence, clocks, conditions, corrections, session coverage, and reconnect
  behavior still require their own exercise.

The account-reported entitlement is permission to probe, not provider
conformance evidence. A successful `cn` exercise must not authenticate `hk` or
`us`, and a successful open-market smoke on one track must not be copied into
another track's receipt. Each adapter configuration declares one exact track,
feed, venue set, entitlement, and unsupported surface. Provider selection is
explicit and there is no cross-track fallback.

This is Futu-first, not Futu-locked architecture. Domain types, canonical
provider ports, fixtures, and conformance laws remain provider-neutral so a
later licensed adapter can be added without redesign. Futu is used only for
the capabilities it actually exposes and proves; it does not replace official
exchange calendars and rules, SEC/HKEX/CN disclosure authorities, identity
evidence, or other capability-specific sources.

T6 now declares one composed role acceptance lane with mandatory `cn`, `hk`,
and `us` live transaction-tape legs. It is not three cloned products: shared
workflow laws and transitions are exercised once, while each track's Futu
feed, identity, rights, sequence, conditions, clocks and recovery are proved
independently. `T6-INTRADAY-PROVIDERS` remains open until all three live legs
meet the recorded exit contract.

T6 provider acquisition never requests a stock quote, bid, offer, or order
book. The Futu OAuth scope name `quote:read` is the provider's umbrella name for
read-only market-data APIs and is required for its transaction-ticker endpoint;
it does not broaden the T6 product surface. The existing provider-neutral
`stock_order_book` proposal accepts and validates caller-supplied observations
only and performs no live acquisition.

## Non-negotiable boundary

OpenD is temporary external development infrastructure. It must never be:

- copied into this repository, a tier package, aggregate, npm tarball, fixture,
  cache, test artifact, or Pi extension;
- downloaded, installed, started, updated, or authenticated by a shipped
  plugin;
- made a required peer, lifecycle script, implicit fallback, or default
  provider;
- given to the model as raw logs, account output, remembered-login state, or
  credential material; or
- used through a trade context, trade unlock, account-mutation call, or order
  placement, routing, cancellation, replacement, or submission API.

The JavaScript development probe may connect only to the caller-started
localhost WebSocket bridge on `127.0.0.1:33333`; that external bridge may
forward only to the caller-started quote gateway on `127.0.0.1:11111`. A
future shipped Futu adapter, if retained, must accept an explicit
caller-provided capability, fail closed when it is absent, and allow the
package to load without OpenD or credentials.

OpenD can establish provider-side trade connections even when its paper engine
is disabled. That does not grant this project authority to construct a Futu
trade context. The probe and adapter must import and invoke quote-only APIs.

## Provider-safety gate

Futu access is a scarce caller-owned entitlement. Protecting it takes priority
over completing a probe. Official documentation currently says this account
class has 100 real-time subscription units, each security/subtype pair consumes
one unit, subscriptions cannot be explicitly released until at least one minute
after subscription, closing a connection before that point delays automatic
release until the minute has elapsed, and quotas are shared across OpenD
connections. API-specific request limits remain controlling even when they are
higher than the repository budgets below.

Every live probe must satisfy all of these rules:

- Read Futu's current official authority, subscription, ticker and relevant
  interface-limit pages immediately before the run. If documentation, account
  quota or entitlement differs from this record, stop and update the plan.
- Run one track, one instrument and one `TICKER` subtype at a time. The initial
  probe may consume at most one subscription unit—1% of the observed quota.
  Do not add `QUOTE`, order book, broker queue, candlesticks, options or another
  symbol merely for convenience.
- Before subscribing, query all-connection subscription status. Stop if the
  status cannot be read, the intended symbol/subtype is already held by an
  unidentified connection, remaining quota is below 90, or another probe
  connection is active. Never unsubscribe another caller-owned connection.
- Make one subscribe request, keep it active for at least 65 seconds, and use
  pushed callbacks. Do not poll snapshots or ticker-history endpoints while a
  callback can prove the behavior.
- Make no automatic retry after authentication, entitlement, quota,
  rate-limit, pacing, server-busy, malformed-response or provider-warning
  outcomes. Redact and classify the first failure, unsubscribe when allowed,
  close cleanly and stop the run. A human must review before another attempt.
- Do not run CN, HK and US probes concurrently or immediately chain them.
  Complete cleanup, verify that the probe's subscription unit is released, and
  review the evidence before scheduling another track.
- Reconnect/gap work starts only after a clean baseline run. It gets a separate
  human-reviewed run budget and at most one reconnect. Never create reconnect
  loops, quote-right contention, rapid resubscription, or repeated authority
  grabs. Keep `auto_hold_quote_right=0`.
- On normal completion, wait until unsubscribe is permitted, explicitly
  unsubscribe the exact probe symbol/subtype, close the quote context, query
  all-connection status from the remaining controlled context when possible,
  and verify release. If release is delayed, wait without resubscribing; do not
  consume another unit to diagnose it.
- Do not call historical-candlestick endpoints: their separate seven-day quota
  is unnecessary for T6 live conformance. Never use a trading endpoint, unlock
  trade, or submit an order to increase account activity or quota.

The probe implementation must enforce these limits as code-level hard stops,
not operator suggestions. Provider limits are ceilings, never throughput
targets. No live Futu call belongs in ordinary tests, tier checkpoints,
verification, packaging, installation or plugin load.

## Starting and stopping the local gateway

Before starting OpenD, check whether the port already belongs to a running
instance:

```sh
ss -ltnp '( sport = :11111 )'
```

If the listener is the expected caller-owned `FutuOpenD`, reuse it. Do not
start a second instance. If a stale OpenD owns the port, inspect its exact PID,
terminate that verified PID gracefully, confirm that the port is free, and
then restart. Never kill an unidentified process merely because it owns the
preferred port.

Start OpenD in a dedicated terminal:

```sh
/usr/local/bin/futu-opend
```

The expected safe OpenD startup facts are:

- paper trading disabled;
- API listener `127.0.0.1:11111`;
- WebSocket and Telnet listeners absent; and
- normal Shanghai LV1 and Shenzhen LV1 quote permissions after login.

Keep the terminal open for the probe. In another terminal, confirm the exact
listener again with `ss`. The official JavaScript SDK needs OpenD's separately
bundled WebSocket bridge. Resolve the one exact OpenD PID read-only and start
the bridge in its own foreground terminal:

```sh
pgrep -ax FutuOpenD
/opt/futu-opend/10.10.7008/FTWebSocket \
  -h 0 \
  -i <EXACT_FUTU_OPEND_PID> \
  -p 33333 \
  -d 127.0.0.1 \
  -o 11111 \
  -a 127.0.0.1
ss -ltnp '( sport = :11111 or sport = :33333 )'
```

Both listeners must be bound to `127.0.0.1`. Do not pass `-l no`: this bundled
bridge parses its log-level argument as an integer. The bridge is external
development infrastructure just like OpenD; never copy or start it from the
repository or ship it. Do not pass an account or password on the command line,
add either value to environment files, or search for local credential files.

The dry run is offline and only prints the fixed request plan and hard limits:

```sh
bun scripts/futu-us-ticker-probe.js
bun scripts/futu-cn-ticker-probe.js
```

After reviewing the exact market date, one caller-selected ordinary security,
its authoritative XNYS or XNAS identity, both localhost listeners, and current
Futu limits, run exactly one US baseline:

```sh
FUTU_PROBE_SYMBOL=US.<CALLER_SELECTED_SYMBOL> \
FUTU_PROBE_MIC=XNYS \
FUTU_PROBE_EXPECTED_US_DATE=YYYY-MM-DD \
FUTU_PROBE_SESSION=regular \
FUTU_LIVE_CONFIRM=I_ACCEPT_ONE_FUTU_US_TICKER_SUBSCRIPTION \
bun run probe:live:futu:us
```

Use `FUTU_PROBE_MIC=XNAS` only for a separately reviewed XNAS listing. The
probe fixes the host and port to localhost, requests regular trading hours
by default, disables automatic reconnect, suppresses SDK/provider text, and
prints only repository-safe aggregates. It has no credential variables.

For a separately reviewed pre/post-market exercise, set
`FUTU_PROBE_SESSION=extended`. The probe then requires Eastern time to be
04:05–09:25 or 16:05–19:55, sends Futu session enum `ETH` (`2`) with
`extendedTime=true`, and labels the result as an extended subscription scope.
It refuses to use that mode during regular hours or overnight.

For CN, first verify the reviewed market date against both exchanges' official
calendar. The accepted development anchors already exist in repository
identity tests; they are probe inputs, not recommendations or product defaults.
Run one venue, verify exact release, stop the bridge, and review the safe
evidence before starting the other venue:

```sh
FUTU_PROBE_SYMBOL=SH.600519 \
FUTU_PROBE_MIC=XSHG \
FUTU_PROBE_EXPECTED_CN_DATE=YYYY-MM-DD \
FUTU_LIVE_CONFIRM=I_ACCEPT_ONE_FUTU_CN_TICKER_SUBSCRIPTION \
bun run probe:live:futu:cn
```

The separately reviewed XSHE run uses `SZ.000001` and `FUTU_PROBE_MIC=XSHE`.
The script refuses all other identities and any start time outside
09:30–11:28 or 13:00–14:55 `Asia/Shanghai`. The exchanges' current 2026 rules
define continuous auction as 09:30–11:30 and 13:00–14:57; the narrower end
bounds leave enough time for the 70-second capture and exact unsubscribe before
lunch or closing auction. The probe may start at the 09:30 continuous-session
boundary and never subscribes during opening or closing auction. No `session`
or `extendedTime` field is sent for CN.

For the separately reviewed HK leg, verify HKEX's official full/half-day
calendar and use:

```sh
FUTU_PROBE_SYMBOL=HK.00700 \
FUTU_PROBE_MIC=XHKG \
FUTU_PROBE_EXPECTED_HK_DATE=YYYY-MM-DD \
FUTU_LIVE_CONFIRM=I_ACCEPT_ONE_FUTU_HK_TICKER_SUBSCRIPTION \
bun run probe:live:futu:hk
```

The HK wrapper accepts a start only in 09:30–11:58 or 13:00–15:58
`Asia/Hong_Kong`, leaving the same cleanup margin inside HKEX continuous
trading. It does not include the extended-morning session for ordinary shares
or the closing auction.

Stop the foreground WebSocket bridge with `Ctrl-C` after the probe and verify
port 33333 is closed. Stop OpenD with `Ctrl-C` when the development session is
done and verify port 11111 is closed. Do not leave either process unattended
merely to make a later session more convenient.

## What work is allowed now

While T6 is in `blocker_resolution`, work is limited to resolving and recording
the live-provider blocker. A small opt-in probe, a disposable external SDK
environment, redaction checks, and repository-safe derived evidence are within
that scope. The probe must never run from `bun run test`, tier verification,
packaging, installation, or plugin initialization.

Do not create or expose `pi_stock_tape`, `pi_cn_broker_readonly`, or another
incomplete public surface yet. The controlling
[`stock_tape` contract](plugins/stock_tape/README.md) begins implementation only
after T6 enters `building`. Existing offline T6 packages remain the
ledger-declared `track_partial` inventory; their simulations do not establish
Futu behavior.

## When to run the live blocker probe

Run three separate probes on reviewed open market days using the exact
track-owned calendar and timezone:

- `cn`: actively trading ordinary A-share listings with exact XSHG and XSHE
  identities in `Asia/Shanghai`; do not claim XBSE coverage;
- `hk`: an actively trading ordinary security with exact XHKG identity in
  `Asia/Hong_Kong`; and
- `us`: actively trading ordinary securities with exact XNYS and XNAS
  identities in `America/New_York`, preserving regular/extended-session scope
  and the selected Futu feed.

At least one capture per track must occur during that market's continuous
trading session, not only after hours or against a snapshot. Useful bounded
windows include an auction/session transition where the selected market and
feed expose it, but one window never proves a complete session. Symbols are
caller-selected probe inputs, not recommendations or product defaults. Do not
silently substitute a venue, feed, security type, or track.

The first exercise is deliberately small:

- exactly one caller-selected instrument and only its `TICKER` subtype, using
  one subscription unit and one controlled quote connection;
- at most 20 elapsed minutes per track exercise;
- at most 25,000 accepted events and 64 MiB of decoded event material;
- a bounded consumer queue with an induced slow-consumer interval; and
- unconditional unsubscribe, context close, cancellation, and process cleanup.

The baseline run performs no intentional disconnect. A later separately
approved reconnect run may perform exactly one disconnect/reconnect only after
the baseline has demonstrated clean subscribe, ≥65-second lifetime,
unsubscribe, quota release and shutdown.

## CN XSHG baseline — passed 2026-08-14 China time

The first CN Bun/JavaScript run used one repository-established ordinary XSHG
A-share at the 09:30 continuous-auction boundary. Its composite probe SHA-256
was `32bc0816974e5c51c9b241d18c58b35d0e1dacb2df6a07345e4948f078e68c61`,
covering both the CN wrapper and shared quote lifecycle. The symbol and all raw
market fields were discarded.

- Exact quota moved from 0 used / 100 remaining / no pairs to 1 / 99 / one
  owned Futu market-21 `TICKER` pair for 70,018.010 ms, then exact unsubscribe
  restored 0 / 100 / no pairs with release verified.
- Five quote-only requests received and processed 24 events in 24 pushes (5,808
  estimated bytes). Queue high-water was 1/512 during the induced slow-consumer
  interval, with zero drops, retries, reconnects, warnings, identity mismatch,
  malformed push, budget stop, unexpected disconnect, or callback after close.
- All 24 sequence lexemes were distinct in received order with zero duplicate
  or decrease. Twenty-three positive deltas exceeded one and the largest was
  17,179,870,384, disproving contiguity for this window without proving a
  provider sequence domain, monotonicity contract, reset, or gap recovery.
- Direction counts were `{1:10, 2:10, 3:4}`; every ticker type was vendor
  `0`/unknown; type-sign was opaque `32:24`; push source was realtime `1:23`
  and cache `3:1`. Every event-time string had millisecond resolution.
- Local receipt minus event time was 248–1,910 ms (mean 574.625 ms), OpenD
  receive minus event time was 245.783–1,903.577 ms (mean 573.283 ms), and
  local dispatch minus OpenD receive was 0.196–6.423 ms (mean 1.342 ms).
  Clock-path uncertainty remains unestablished, so these are offsets, not
  exchange-latency claims.

This proves one bounded Futu Mainland LV1 XSHG live-observation path, not XBSE,
XSHE, complete transaction coverage, exchange-authenticated identity, replay,
or correction/cancel/bust lineage. Licence, retention, redistribution, exact
feed composition, reset, and complete recovery remain unknown. Do not repeat
this baseline merely to collect more events.

## CN XSHE baseline — passed 2026-08-14 China time

After XSHG and XHKG were each released, stopped, and reviewed, the unchanged CN
probe exercised one separate repository-established ordinary XSHE A-share.

- Quota moved 0 / 100 / no pairs to 1 / 99 / one Futu market-22 `TICKER` pair
  for 70,008.623 ms, then exact unsubscribe restored 0 / 100 / no pairs.
- Five quote-only requests processed 25 events in 25 pushes (5,950 estimated
  bytes). Queue high-water was 1/512 with no drops, retries, reconnects,
  warnings, wrong-identity/malformed pushes, budget stop, unexpected disconnect,
  or callback after close.
- All 25 sequence lexemes were distinct with zero duplicate/decrease; 24
  positive deltas exceeded one and the largest was 12,886,233,188. Direction
  was `{1:7, 2:18}`; ticker type was vendor `0:25`/unknown; opaque type-sign was
  `{32:25}`; push source was realtime `1:24`, cache `3:1`.
- Event-time strings had only second resolution. Local receipt minus event time
  was 191–2,485 ms (mean 322.040 ms), OpenD receive minus event time was
  190.831–2,480.001 ms (mean 320.884 ms), and local dispatch minus OpenD
  receive was 0.150–4.999 ms (mean 1.156 ms). These are offsets, not latency.

Together the XSHG and XSHE runs prove separate bounded Futu Mainland LV1
observation paths for the declared first CN scope. They do not prove XBSE,
complete tape, sequence reset/recovery, exchange identity, redistribution
rights, or correction/cancel/bust lineage, so the CN limitations and whole T6
blocker remain open.

## HK XHKG baseline — passed 2026-08-14 Hong Kong time

One repository-established ordinary XHKG Main Board share was exercised in a
separate run after XSHG release and review. Composite probe SHA-256 was
`114d04fae76b31516b52605738ab6322db9fed33af1261c02303381656be44fb`.

- Quota moved 0 / 100 / no pairs to 1 / 99 / one Futu market-1 `TICKER` pair
  for 70,013.397 ms, then returned to 0 / 100 / no pairs with release verified.
- Five quote-only requests processed 490 events in 290 pushes (118,572
  estimated bytes). Queue high-water was 14/512, with zero drops, retries,
  reconnects, warnings, malformed/wrong-identity pushes, budget stops,
  unexpected disconnects, or callbacks after close.
- All 490 sequence lexemes were distinct with zero duplicate/decrease; 70
  positive deltas exceeded one and the largest was 8,589,934,593. Contiguity,
  domain, reset, and recovery are not established.
- Direction counts were `{1:267, 2:128, 3:95}`; ticker types were regular sale
  `1:401`, same-broker regular `4:47`, same-broker non-regular `5:36`, and odd
  lot `6:6`; opaque type-sign was `{32:401, 68:6, 88:36, 89:47}`; push source
  was realtime `1:489`, cache `3:1`.
- Event time had millisecond resolution for 488 events and second resolution
  for two. Local receipt minus event time was 35–444 ms (mean 119.359 ms),
  OpenD receive minus event time was 34.302–442.750 ms (mean 118.423 ms), and
  local dispatch minus OpenD receive was -0.286–6.713 ms (mean 0.937 ms).
  These remain clock offsets, not exchange-latency evidence.

This proves one bounded account-reported HK securities LV2 XHKG observation
path. Exact LV2 feed composition, licence/retention/redistribution, exchange-
authenticated identity, transaction completeness, reset/recovery, replay, and
correction/cancel/bust lineage remain unknown or unavailable.

## US XNAS baseline — passed 2026-08-13 Eastern time

The first Bun/JavaScript baseline used one ordinary, repository-established
XNAS development identity during the regular session. The symbol and every raw
price, size, turnover, timestamp and sequence lexeme were discarded. The probe
implementation SHA-256 was
`e3a8935226881a1a31b45e9b19ac819b1ce812dc04f7aa0d98461f16af9af9c3`.

- The preflight observed 0 used, 100 remaining and no active subscription
  pairs. The exact one-symbol `TICKER` subscription observed 1 used and 99
  remaining, remained active for 70,000.680 ms, and exact unsubscribe returned
  the status to 0 used, 100 remaining and no active pairs.
- Five quote-only requests were made: all-connection status, subscribe,
  post-subscribe status, exact unsubscribe and release status. There were no
  trade, history or snapshot calls, retries, reconnects, unexpected
  disconnects, provider warnings, identity mismatches, malformed pushes,
  signals or callbacks after close.
- The window received 646 pushes containing 973 decoded and processed events,
  estimated at 235,462 decoded bytes. The deliberately slow consumer produced
  queue high-water 27 of 512 with zero dropped or coalesced events. No event,
  byte or elapsed budget was reached.
- All 973 sequence lexemes were distinct in the window, with zero duplicates
  and zero decreases in received order. There were 71 positive deltas greater
  than one and the largest was 4,294,967,293. This disproves contiguity for the
  observed stream; it does not establish monotonicity, scope, reset rules,
  exchange authority, or gap recoverability.
- Direction enum counts were `1:133`, `2:157`, `3:683`; ticker-type counts were
  `1:183`, `6:772`, `23:1`, `24:17`; raw type-sign counts were `32:183`,
  `55:1`, `73:772`, `87:17`; and push-source counts were realtime `1:972` and
  cache `3:1`. The cached event was observed despite `isFirstPush=false`; its
  cause is unknown and it must not be relabelled realtime.
- Event time had millisecond text resolution for 972 events and second
  resolution for one. Local wall receipt minus event time ranged 130–222 ms
  with mean 156.680 ms; OpenD receive minus event time ranged 129.387–215.203
  ms with mean 155.618 ms; local dispatch minus OpenD receive ranged
  -0.287–9.888 ms with mean 1.062 ms. The host reported NTP synchronized after
  the run, but synchronization uncertainty and the provider/exchange clock path
  were not established, so none of these offsets is an exchange-latency claim.
- The callback schema supplied no correction, cancel, bust, provider-reference,
  reset or replay lineage. The baseline intentionally performed no reconnect.
  Futu's documentation says a reconnect can supplement up to 50 recent ticker
  events and marks them by push type, but recovery completeness and a usable
  replay watermark remain unproved.

This is evidence for one caller-declared XNAS identity on Futu's US market
surface, not proof that the ticker protocol authenticates its MIC or that the
account-reported LV2 label is SIP/proprietary/exchange-complete. The XNYS
baseline below is separate evidence rather than an inference from this run.

Futu's quotation definitions label direction `1` active buy, `2` active sell
and `3` neutral. These are vendor classifications and must not be promoted to
exchange aggressor-side facts. The observed ticker types map to `1` regular
sale, `6` odd-lot trade, `23` contingent trade and `24` average-price trade.
The protobuf `typeSign` integers observed in the runs are not documented by the
public field catalogue; they remain opaque exact lexemes. Notably, the
post-market run below contained only ticker types `1` and `6`, not Futu's Form
T (`21`) or extended-hours/out-of-sequence (`22`) values, so subscription scope
and event timestamps—not an assumed condition code—are the session evidence.

## US XNYS baseline — passed 2026-08-13 Eastern time

After the XNAS subscription was released and its evidence reviewed, the same
unchanged probe exercised one ordinary, repository-established XNYS development
identity in a separate regular-session run. It used the same implementation
SHA-256 and retained the same aggregate-only evidence surface.

- Subscription status again changed from 0 used / 100 remaining / no active
  pairs to exactly 1 / 99 / one owned pair, remained active for 70,011.963 ms,
  and returned to 0 / 100 / no pairs after exact unsubscribe.
- Five quote-only requests produced 89 pushes containing 102 decoded and
  processed events (24,680 estimated decoded bytes). Queue high-water was
  4/512 during the same slow-consumer exercise, with zero drops, coalescing,
  retries, reconnects, warnings, malformed or wrong-identity pushes,
  unexpected disconnects, budget stops, or callbacks after close.
- All 102 sequence lexemes were distinct with zero duplicates or decreases;
  49 positive deltas exceeded one and the largest was 30,064,771,071. This
  independently disproves contiguity for the XNYS window without proving a
  provider sequence domain or monotonicity contract.
- Direction counts were `1:6`, `2:6`, `3:90`; ticker-type counts were `1:8`,
  `6:94`; type-sign counts were `32:8`, `73:94`; and push-source counts were
  realtime `1:101`, cache `3:1`. The one cache-labelled event again appeared
  with `isFirstPush=false`, so initial/cached delivery needs a typed state and
  cannot be flattened into realtime.
- Event time had millisecond text resolution for 101 events and second
  resolution for one. Local wall receipt minus event time ranged 130–203 ms
  (mean 145.588 ms), OpenD receive minus event time ranged 129.485–198.437 ms
  (mean 144.516 ms), and local dispatch minus OpenD receive ranged
  0.047–4.563 ms (mean 1.073 ms). These remain unsynchronized-path offsets,
  not exchange-latency evidence.

Both required US venue labels now have successful bounded live baselines, but
Futu still exposed only its generic US market code and therefore authenticated
neither MIC. Futu's v10.10 rights page publicly describes US securities
coverage for NYSE, NYSE-American and Nasdaq listed equities/ETFs and a
promotional free LV3 bundle of Nasdaq Basic, Nasdaq TotalView and NYSE
ArcaBook. This OpenD session reported US LV2 instead, so the account's exact
feed composition and price were not authenticated against that advertised
bundle; licence/retention/redistribution scope is also unstated. Correction/
cancel/bust lineage is absent from the observed schema, and reset, reconnect
supplementation, replay and gap recovery remain unexercised. The US blocker leg
and the whole T6 blocker remain open.

## All-track API quote-right baseline — passed 2026-08-14 China time

A later allowlisted Bun `GetUserInfo` query used global protocol `1005`, field
flag `4`, and requested only the four current track-owned quote-right fields.
It returned Futu API enum `2` (`Level1`) for `shQotRight` and `szQotRight`, and
enum `3` (`Level2`) for `hkQotRight` and `usQotRight`. This independently binds
the exercised XSHG and XSHE paths to Mainland Level 1, the XHKG path to Hong
Kong Level 2, and the generic US market path to US Level 2 at the Futu API
permission layer.

The probe made one read-only request, consumed no subscription unit, invoked no
subscription, trade, history, retry, or reconnect operation, and retained no
identity, account, deprecated aggregate-CN-right, quota, provider-text, or raw
market field. The temporary WebSocket bridge was stopped immediately afterward;
the caller-owned OpenD process remained running.

These enums authenticate permission level only. They do not establish feed
composition, transaction completeness, exchange/MIC identity, price, licence,
retention, redistribution, sequence/reset/replay semantics, or correction/
cancel/bust lineage. In particular, the US exercises must not inherit the
public page's separately advertised promotional Level 3 bundle. The blocker
therefore remains open.

## US XNAS extended-hours baseline — passed 2026-08-13 Eastern time

An updated probe with SHA-256
`dc66a4ea0f77742b86710109de78c33058996527b22c9bbbf145da33bbdefd01`
performed one separate post-market XNAS exercise using Futu session `ETH` (`2`)
and `extendedTime=true`. It ran after the regular baselines had been released
and reviewed.

- Quota moved from 0 used / 100 remaining / no pairs to exactly 1 / 99 / one
  owned ticker pair for 70,006.048 ms, then returned to 0 / 100 / no pairs
  after exact unsubscribe.
- Five quote-only requests received 18 pushes containing 25 decoded and
  processed events (6,050 estimated bytes). Queue high-water was 3/512 during
  the slow-consumer interval, with zero drops, coalescing, retry, reconnect,
  warning, malformed/wrong-identity push, unexpected disconnect, budget stop,
  or callback after closure.
- All 25 sequence lexemes were distinct with zero duplicates or decreases;
  11 positive deltas exceeded one and the largest was 68,719,476,736. This
  again disproves contiguity for the window but proves no sequence domain.
- Direction counts were `1:19`, `2:3`, `3:3`; ticker-type counts were `1:5`,
  `6:20`; type-sign counts were `32:5`, `73:20`; and push-source counts were
  realtime `1:24`, cache `3:1`. All event-time strings had millisecond
  resolution. Local receipt minus event time was 135–464 ms (mean 167.160 ms),
  OpenD receive minus event time was 133.383–458.685 ms (mean 165.926 ms), and
  local dispatch minus OpenD receive was 0.148–5.315 ms (mean 1.234 ms). These
  are unsynchronized-path offsets, not latency claims.
- No provider-disconnect supplement (`PushDataType=2`) appeared. The probe now
  explicitly treats only that enum as potential evidence of Futu-server
  recovery; cycling the JavaScript WebSocket would test a different layer and
  must not be presented as provider reconnect evidence.

This proves a bounded Futu `ETH` post-market ticker path for one
caller-declared XNAS identity. It does not prove pre-market or overnight
behavior, venue authentication, complete transaction coverage, replay, or
correction lineage.

## US capability decision after the baselines

Do not repeat the US regular or post-market baselines merely to obtain more
events. They already establish the bounded development facts needed from those
windows:

- **available:** caller-owned Futu API Level 2; generic US ticker subscription;
  separately caller-declared XNAS and XNYS regular-session identities; one XNAS
  post-market `ETH` path; pushed event, direction, ticker-type, push-source,
  event/OpenD/local receipt clocks; quota accounting; bounded slow-consumer,
  cancellation, exact unsubscribe and shutdown behavior;
- **unavailable in the documented ticker schema:** correction, cancel and bust
  fields; a correction reference identifier; complete replay; and a replay
  watermark; and
- **unknown/unproved:** provider-authenticated MIC, exact Level 2 feed
  composition and transaction completeness, sequence domain/reset rule,
  complete gap detection/recovery, pre-market/overnight behavior, and
  licence/retention/redistribution terms.

Cycling the JavaScript WebSocket is not a valid next experiment. It tests the
script-to-OpenD bridge, while Futu documents `PushDataType=2` for an
OpenD-to-Futu-server interruption. Do not intentionally disturb OpenD's
provider connection without a separately reviewed, bounded method that cannot
create reconnect loops or quote-right contention. A passive spontaneous
supplement may be recorded if it occurs during a future necessary probe, but a
capped supplement still cannot prove complete replay.

On the OpenD evidence alone, Futu is suitable for the T6 US bounded live-
observation adapter but is not sufficient evidence for the stronger tape,
recovery, and lineage claims in the blocker exit. The direct Futu Web API path
below is the next Futu-first candidate. Keep Futu explicitly selected for the
surfaces it proves; do not silently substitute or combine feeds.

## Direct Futu Web API candidate — reviewed 2026-08-14

Futu now documents a gateway-free REST and WebSocket API using OAuth 2.1 with
PKCE. Its quote WebSocket endpoint is
`wss://webapi-quote.futunn.com/ws`; this could be a caller-selected runtime
adapter without placing OpenD, its bridge, login state, or binaries in the
product. The existing phone/password OpenD login does not itself grant an OAuth
token. Caller browser consent with quote-only scope is a new prerequisite and
must not be derived from the remembered OpenD password. The caller must verify
that Futu's consent page grants exactly `quote:read`; any account, trade, or
write scope aborts the probe.

The private one-shot authorization lane is:

```sh
FUTU_WEBAPI_CONFIRM=I_ACCEPT_ONE_FUTU_QUOTE_ONLY_OAUTH_FLOW \
  bun run probe:live:futu:webapi:oauth
```

It follows Futu's documented public-client registration and PKCE flow. The
registration advertises the documented authorization-code and refresh-token
grant types, but the lane never retains or uses the returned refresh token or
registration access token. It emits no access token, accepts only a returned
`Bearer` token whose complete scope is `quote:read`, and writes only that
short-lived access token, scope, and expiry to fixed mode-0600 file
`/tmp/pi-sparkles-futu-webapi-quote-token.json`. The file must be removed after
the bounded direct-API probes or expiry. This development lane is excluded from
product code, package contents, tier gates, and normal tests.

The direct REST ticker contract is materially stronger than the legacy OpenD
schema in several narrow respects:

- it calls `sequence` a monotonically increasing `int64` usable for
  deduplication and incremental fetch;
- it returns an exact `period_type` and an exchange `trade_type` lexeme, with
  the US catalogue explicitly including `U` for cancel; and
- it supports HK, US, SH, SZ, and BJ identifiers, so all three product tracks
  are addressable through one Futu transport without erasing track ownership.

Recovery remains bounded rather than complete. The REST ticker call returns
only the latest requested observations, defaults to 500, caps `num` at 750,
and does not accept a time range. Futu's direct WebSocket guidance requires a
client to reconnect, authenticate, and resubscribe; old subscription state is
not restored. It recommends the REST latest-state/ticker query after a
disconnect and explicitly warns not to use push ordering as historical
backfill. A T6 adapter could therefore recover only when the latest-750 window
overlaps its last accepted sequence; otherwise it must emit an unrecoverable
gap and fail closed. This is useful exact behavior, not complete replay.

This route is not yet exercised for the caller and does not close the blocker.
Before it can do so, a quote-only OAuth authorization and separate bounded
CN/HK/US conformance exercise must prove the actual entitlement/feed response,
sequence scope and reset behavior, recovery overlap/failure states, trade-type
semantics, clocks, cancellation, backpressure, and shutdown. Futu must also
provide or identify applicable retention and redistribution terms. No OAuth
token, refresh token, client registration credential, or raw response may enter
the repository, generated package, logs, or model context.

Official direct-API references:
[getting started and OAuth](https://open.futunn.com/api/overview/getting-started),
[REST real-time ticker](https://open.futunn.com/api/quote/realtime/rt-ticker),
[quote WebSocket overview](https://open.futunn.com/api/quote/push/overview),
[quote push data format](https://open.futunn.com/api/quote/push/data-format), and
[quote push quota](https://open.futunn.com/api/quote/push/rate-limit).

### Direct OAuth and ticker exercises — 2026-08-14

The one-shot public-client PKCE lane completed after the caller deselected the
default trade-read permission. The accepted token response contained exactly
`quote:read`, type `Bearer`, and a 7,200-second lifetime. The lane retained no
refresh token, client registration access token, account scope, trade scope,
write scope, account field, password, or provider login state. It placed the
short-lived access token only in the fixed mode-0600 `/tmp` file, never emitted
it, and deleted the file after the bounded probes.

The direct REST probe used only
`GET /api/v1.0/quote/{reviewed-symbol}/rt-ticker?num=10`, one request per
reviewed leg, a ten-second timeout, a 256-KiB response ceiling, no redirect, and
no retry. It explicitly forbids stock-quote, bid/offer, order-book, K-line,
trade, and account endpoints and preserves numeric sequence fields as exact
int64 lexemes before JSON decoding.

The HK/XHKG request passed: one 1,146-ms response returned ten current
transaction-ticker events in 2,040 bytes. All ten sequences were exact and
distinct; the latest-first response had nine decreases, no duplicate, and
maximum absolute delta 8,589,934,593. All event timestamps were
millisecond-resolved; local completion minus event time ranged 660–7,195 ms and
is an unsynchronized clock offset, not a latency claim. Aggregate direction was
BUY 9 / SELL 1, session was NORMAL 10, all ticker types were non-unknown, and
all exchange trade-type lexemes were blank. No symbol, raw sequence, raw time,
price, size, turnover, name, provider text, token, or account field was retained.

The separate CN/XSHG and CN/XSHE REST requests each stopped after one call with
provider `ret_code=-9`; the XSHE structured error classified it as a permission
denial. HK success proves the endpoint, OAuth token, and decoder were valid, so
the two Mainland results are not a global authentication failure. No XSHG
retry occurred, no CN request followed the second denial, and the direct Futu
account cannot currently satisfy the shippable CN leg.

The ticker-only direct WebSocket lane then exercised HK/XHKG with one connection
at `wss://webapi-quote.futunn.com/ws`, one OAuth auth frame, one `ticker`
subscription, no other data-type field, and no reconnect or retry. Futu pushed
a `TICKER` message after the subscription request but before returning the
documented subscription acknowledgement. The first client version failed
closed on that observed ordering and disconnected. After a conservative cleanup
interval and a focused state-machine correction, one reviewed retry again did
not receive the documented subscribe acknowledgement within eight seconds; it
sent the exact ticker-only unsubscribe, received no documented unsubscribe
acknowledgement within eight seconds, and closed. No further WebSocket attempt
is allowed on this evidence.

The direct route therefore proves a useful, gateway-free HK REST transaction-
ticker surface and stronger bounded REST recovery semantics. It does not close
T6: direct Mainland access is permission-denied, the current WebSocket cannot
prove subscription/unsubscribe lifecycle conformance, and the direct US live
leg has not been exercised. OpenD remains development-only and cannot fill any
of those runtime gaps.

These are initial safety ceilings, not claims that the resulting window is
complete. Tighten them if the actual event rate requires it; do not silently
raise them while a probe is running.

## What the probe must establish

Record repository-safe conclusions for every item below. Unknown and
unavailable are valid results; invented or inferred provider semantics are not.

1. **Provider and rights** — exact OpenD and SDK versions plus the independently
   selected Futu CN LV1, HK LV2 or US LV2 feed; exact venue/session coverage,
   subscription quota, entitlement, price, licence, retention and
   redistribution limitations.
2. **Identity** — exact requested symbol, `cn`/`hk`/`us` track, MIC,
   listing/board/share-class scope and provider code. A successful subscription
   must not authenticate an otherwise unproved listing assertion.
3. **Sequence** — exact raw sequence lexeme and observed scope across symbol,
   connection, subscription, reconnect, and trading day. Measure duplicates,
   reversals, discontinuities, and first/last values, but do not call the value
   contiguous or monotonic unless Futu documents and the probe demonstrates
   that contract.
4. **Reconnect and recovery** — events immediately before disconnect and after
   resubscription, whether a reset/watermark/replay indicator exists, whether a
   gap can be classified, and whether missing events can actually be recovered.
   A fresh stream is not replay proof.
5. **Backpressure** — queue high-water mark, dropped/coalesced events, provider
   or SDK warnings, cancellation latency, stale completion handling, and the
   fail-closed outcome when a budget is reached.
6. **Event semantics** — exact observed and documented transaction type,
   direction, condition, venue, push-source, and unknown enum lexemes. Never
   infer aggressor side from price movement or an undocumented flag.
7. **Lineage** — original, correction, cancel, and bust availability plus exact
   reference identifiers for the selected track/feed. If it exposes none,
   record an explicit unavailable result and narrow that track's Futu claim.
   Resolving the external blocker does not waive a stronger lineage requirement
   at tier verification; a stronger licensed provider may still be necessary.
8. **Clocks** — exchange/event time, provider/OpenD time if supplied, local
   receipt wall clock, and local monotonic receipt time. Record resolution,
   timezone, synchronization method, observed offsets, and every missing clock.
   Do not describe local receipt latency as exchange latency.
9. **Shutdown** — bounded unsubscribe, quote-context close, gateway behavior,
   no callbacks after closure, no retained credential data, and no trading API
   invocation.

## Evidence that may enter the repository

Raw Futu rows, account identifiers, connection endpoints other than localhost,
credentials, remembered-login files, provider logs, and redistributable market
content stay outside the repository and model context.

The blocker record may retain only non-secret, non-market-content evidence such
as:

- versions and a hash of the probe implementation;
- run date, bounded window, MICs, instrument count, and event count without
  account identifiers;
- enum/schema inventory derived from official documentation;
- sequence/gap/duplicate/reset aggregates without prices, sizes, symbols, or
  raw rows;
- clock-resolution and offset summaries without market content;
- cancellation, reconnect, queue, byte, event, and elapsed-time measurements;
- entitlement/licence conclusions and explicit unknown/unavailable facts; and
- hashes of ephemeral inputs only when hashing them does not disclose or claim
  redistribution authority.

Provider-controlled error strings must be classified and redacted before they
become evidence. A digest proves content identity only; it is not a provider
signature, exchange authority, origin authentication, or redistribution grant.

## Exact gate for starting full T6 development

After successful `cn`, `hk`, and `us` market-hours exercises, compare each
track's derived evidence with all five exit requirements in
[`R3.md`](R3.md#t6-intraday-provider-blocker--active-2026-08-13). Full T6
development starts only when every requirement is independently answered for
all three legs and the result is recorded there without secrets:

- provider/feed, venue coverage, entitlement, price, and rights;
- authentic sequence and reset/rebuild behavior plus observed gap, reconnect,
  and backpressure behavior;
- correction/cancel/bust lineage or an explicit unavailable state that narrows
  the claim;
- exchange/provider/receipt clocks and their limitations; and
- exact event types/conditions plus bounded cancellation and shutdown.

Then, and only then, update `T6-INTRADAY-PROVIDERS` to `resolved`, add its exact
resolution record, and move the whole tier from `blocker_resolution` to
`building` in `tiers.json`. Validate the ledger transition with:

```sh
bun run tier:audit
bun run tier:show -- T6
```

Do not run `bun run tier:verify -- T6` at that point. Verification is allowed
only after all eleven T6 proposals and the complete
`test/tiers/t6_day_trader_review` role journey exist.

## Development sequence after the gate

Once T6 is `building`, implement the entire tier dependency cone atomically,
not one plugin as an independent milestone:

1. pure tape identity, event, exact-lexeme, ordering, duplicate, sequence,
   gap/reset, clock, and correction-lineage laws;
2. deterministic simulators and transition tests for normal, gap, reconnect,
   slow-consumer, correction, cancellation, shutdown, and failure paths;
3. canonical bounded streaming capabilities and quote-only Futu configurations
   for `cn`, `hk`, and `us`, with shared transport mechanics but track-owned
   fixture decoding, explicit feed selection, pacing, cancellation, redaction,
   rights and receipt handling;
4. `stock_tape`, order-book, workbench, track-owned read-only/import, local
   simulation, compliance, handoff, and external-receipt consumers through
   typed Pi-visible receipts rather than plugin source imports; and
5. the single composed role acceptance lane with mandatory `cn`, `hk`, and `us`
   legs, including per-track failure and recovery without duplicating shared
   workflow laws.

Keep every touched package coherent and buildable and use:

```sh
bun run tier:checkpoint -- T6
```

as the atomic working-set check. Focused package tests remain inner-loop
diagnostics and never change maturity. Massive, Alpaca, IBKR, direct exchange
feeds and other providers remain explicit optional breadth; none may silently
substitute for a missing required Futu track leg.
