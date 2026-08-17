# Inline OHLCV chart design

## Scope and invariants

`chart_ohlcv` is a view over exact, caller-supplied, completed-daily OHLCV
evidence. It does not fetch data, select a provider, infer missing sessions,
calculate indicators, aggregate bars, rank securities, or make a trading
decision. The existing Gleam decoder and pure domain validation remain the
controlling contract for both hosts. Exact decimal strings, receipts, market
identity, source context, omissions, and the structured fallback remain in the
tool result; host renderers may convert decimal strings to finite JavaScript
numbers only for screen coordinates.

The two renderers are deliberately host-exclusive:

- Pi renders an ASCII chart in the normal inline tool-result component.
- DeepSeek Harness (DSH) renders an interactive browser chart in the normal
  `chart_ohlcv` tool-result card.

Neither host creates an overlay, image block, attachment, data URL, temporary
file, download, or out-of-band chart. The finance-track DSH overlay is a
separate navigation surface and is not used by charts.

## Shared result contract

Successful validation returns ordinary text content and
`pi-sparkles/finance-chart-result` structured details. The details retain all
validated bars and supplied annotations, even when a renderer shows only a
suffix. The result also declares a renderer-neutral presentation policy:

- presentation kind: `responsive_ohlcv_view`;
- time order: ascending input order;
- initial range anchor: latest bar;
- span rule: available plot width divided by a fixed host slot width;
- no downsampling, interpolation, bar aggregation, or inferred gaps;
- explicitly supplied gap records are the only gap annotations;
- exact structured details are controlling, not screen coordinates.

The text content is the durable LLM and accessibility fallback. It includes a
summary plus the bounded `finance_table` rendering; truncating that table never
truncates `details.bars`.

## Pi terminal renderer

Pi registers a custom `renderResult` component through the shared Gleam
binding. Pi calls the component's `render(width)` method with the current tool
result width and rerenders it when terminal layout changes. The renderer never
reads ambient `stdout.columns`, so split panes and nested layouts receive the
correct width.

For a usable chart, the component reserves a price-axis gutter and assigns two
terminal columns per bar. The visible capacity is:

```text
max(1, floor((width - axis_gutter) / 2))
```

The initial visible range is the latest contiguous suffix with that capacity.
A wider component therefore shows a monotonic superset extending earlier in
time. It never changes the interval or synthesizes observations. The header
always reports the exact visible start/end dates, `shown/total`, and the count
of earlier hidden bars.

The compact chart uses an ASCII-only legend and cells so it survives plain
terminals: `|` wick, `#` up body, `=` down body, `-` flat body, `B`/`S` trade
markers, `!` supplied gaps, and `#` volume. Price and volume coordinates are
display projections only. If the available width cannot safely hold an axis
and a bar, the component emits a one-line summary instead. Expanded mode adds
the exact text/table fallback below the responsive chart. Every emitted line is
clipped to the width Pi supplied.

Cancellation is checked before validation. Rendering itself is synchronous and
bounded by the validated limits (240 bars, four indicators, 240 trades, and
240 gaps).

## DSH browser renderer

The stateless Pi shell remains eligible for DSH's global compatibility lane,
but DSH does not invoke or emulate Pi's TUI renderer. The DSH tool bridge
recognizes the exact chart-result schema and uses DSH's native
`output.presentationMeta` hook to persist a JSON-safe chart projection in the
settled `tool/result` event. Other tools are unchanged. Pi-only image blocks are
not produced and are not translated to DSH attachments.

The browser package registers a keyed `tool.call.toolview` contribution for
`chart_ohlcv`. This replaces only the generic row for that tool and renders
inside the transcript at the result's normal position. The card reads only the
current result block's persisted `meta`; it does not use process-global or
session-global chart state.

The card observes its own plot container with `ResizeObserver`. Its automatic
capacity is:

```text
max(1, floor((container_width - price_scale_gutter) / 9))
```

and it selects the latest contiguous suffix. Width growth reveals earlier bars
and width shrinkage hides earlier bars. The exact range disclosure follows the
same rule as Pi. Pointer/keyboard pan or zoom may temporarily override the
automatic range; a Reset control reapplies the proportional latest-suffix
range. A renderer failure leaves the exact textual tool output available.

The browser view uses semantic HTML/SVG owned by the DSH client entrypoint. It
shows candlesticks, volume, supplied price overlays/lower-panel points, trade
markers, and explicit gap annotations. Tool-result metadata is byte-bounded,
schema checked, and contains no credentials beyond the already-approved
structured result fields.

## Lifecycle, packaging, and compatibility

The Pi aggregate contains only the terminal renderer. The DSH package contains
the DSH adapter metadata hook and browser client entrypoint and declares the
exact `@deepseek-ai/dsh-client-ui-tool` peer/injection used for the keyed slot.
Chart delivery does not change `tiers.json` or imply DSH maturity from Pi tier
status. Any material DSH client change requires the independent DSH focused
tests, installed runtime smoke, and visual browser QA before the DSH release
gate can return to ProductUseful.

The structured schema is versioned. A client must reject an unknown schema or
non-finite projection input and allow the normal textual result to render.
Forward-compatible additions may add annotation kinds; changing exact evidence
semantics, span anchoring, or truncation behavior requires a schema-version
change.

## Verification matrix

Pure Gleam tests prove validation, exact-value retention, market isolation,
chronology, gaps, omissions, and deterministic structured results. Pi binding
tests prove no image output, custom component registration, width-bounded ASCII,
monotonic visible capacity, latest-suffix anchoring, expanded fallback, and
cancellation. DSH tests prove presentation metadata is added only for the exact
chart schema, keyed slot registration, inline card rendering, proportional
resize behavior, malformed-metadata fallback, and client discovery/package
locking. Installed DSH verification executes a representative chart call and
checks that its settled result event exposes the expected metadata.
