# finance_table

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_table` renders compact, deterministic finance tables for agent text,
files, and structured tool details. It makes units, missing values, precision,
ordering, and truncation visible. It is a pure library with no Pi, terminal,
filesystem, provider, or network dependency.

The implemented slice includes typed columns/cells, exact decimal and money
cells, explicit missing reasons, duplicate/width/kind/safe-integer validation,
stable alignment, escaping, captions/notes, deterministic Markdown and CSV,
versioned semantic JSON, and immutable row truncation with omission counts.
The foundation also includes unit/currency validation, evidence annotations,
compound row/column/cell/text budgets with structured omission summaries, and
an explicitly named spreadsheet-safe CSV policy. Rich locale formatting and
grouped headers remain optional presentation extensions.

## User stories

- A plugin renders the same typed table as Markdown, CSV, and JSON without
  losing decimal precision or changing row order.
- A reader can see currency/unit, as-of/freshness context, missing markers, and
  truncation rather than infer them from prose.
- A tool can cap rows/columns/cells predictably and describe omitted material
  without inventing an export path.
- Invalid column/cell combinations fail before a misleading table reaches the
  model or user.

## Non-goals

- No terminal UI widgets, charts, spreadsheets, file writes, localization
  engine, SQL/dataframe operations, or statistical calculations.
- No implicit joins, sorting, aggregation, currency conversion, or unit
  conversion.
- No fetching observations and no ownership of provenance manifests.
- No ANSI color or width measurement based on a specific terminal.

## Module surface

| Module | Responsibility |
| --- | --- |
| `finance_table/table` | columns, rows, captions, notes, validation, and stable ordering |
| `finance_table/render` | semantic cell-to-text conversion, including visible annotations |
| `finance_table/markdown` | escaped compact Markdown rendering |
| `finance_table/csv` | RFC 4180-compatible data export with documented newline/encoding policy |
| `finance_table/json` | typed JSON value and canonical string encoding |

## Functional design

Tables, formats, budgets, and omissions are immutable values. Validation,
column projection, row mapping, sorting by an explicit comparator, truncation,
and every renderer are pure functions. Rendering the same table with the same
policy is byte-deterministic and never reads locale, terminal width, time, or
environment implicitly.

The API should expose composable transformations such as mapping a column,
filtering rows, adding annotations, and applying a budget while retaining
validation. Transformations must preserve row keys and table metadata by
construction. Renderer tests include laws: validation is idempotent, canonical
JSON round-trips semantic cells, truncation never increases size, and applying
an already-satisfied budget is an identity operation.

## Data model

A `Column` has stable key, display heading, declared `ColumnKind`, optional
unit/currency, alignment, and format policy. A `Row` has an optional stable key
and exactly one cell for every column. A `Table` has caption, ordered columns,
ordered rows, notes, and optional table-level as-of/source summary.

`Cell` variants preserve semantic values. Decimal and money cells contain
`finance_core` exact decimals; they never become `Float` during rendering.
Missing values use reasons such as unavailable, not applicable, suppressed,
not reported, and parse failure. Estimated, revised, stale, and delayed are
annotations, not special punctuation with undocumented meaning.

Construction or explicit `validate` returns a typed error for duplicate keys,
row-width mismatch, cell/kind mismatch, invalid precision, incompatible units,
or impossible budgets. Renderers return `Result` and never silently stringify a
mismatched cell.

## Formatting policy

- Decimal precision is explicit per column. Half-even is the default rounding
  inherited from `finance_core`; a renderer cannot introduce another default.
- Percent cells state whether the stored decimal is a ratio (`0.125`) or percent
  points (`12.5`). The format policy performs only the declared scale display.
- Money defaults to an ISO code such as `USD 12.34`. Locale-specific symbols
  are opt-in and must disambiguate collisions such as `$`.
- Negative style, positive sign, thousands separators, date/time representation,
  timezone display, and missing marker are explicit policies.
- Markdown alignment is deterministic and independent of terminal width.
  Unicode display-width heuristics are deferred unless separately tested.

## Renderer contracts

### Markdown

Markdown escapes pipes, backslashes, newlines, and control characters. Notes
appear below the table in stable order. The renderer may use compact or expanded
mode, but neither can drop units, freshness, or truncation metadata.

### CSV

CSV contains raw display values plus optional metadata columns selected by the
caller. Quoting follows one documented dialect: comma separator, double-quote
escaping, UTF-8, and CRLF or LF chosen explicitly. Spreadsheet formula
injection is mitigated by an opt-in safe-text policy; data-preserving and
spreadsheet-safe exports are named distinctly.

### JSON

`to_json` returns a Gleam JSON value preserving semantic kind, exact decimal
strings, units, annotations, and missing reasons. `encode_json` produces a
canonical string. JSON is not derived from already formatted Markdown cells.

## Truncation

A `Budget` can cap rows, columns, total cells, and per-cell characters. The
result contains the rendered table plus a structured `Omission` count and
reason. Stable head/tail or priority-column selection must be explicitly chosen;
the default is stable prefix rows and required columns.

A truncation note says what was omitted. It mentions a full-data artifact only
if the caller supplies a logical artifact label or path after separately
writing it. This pure library never claims that it saved a file.

## Provenance boundary

Tables may include compact source/evidence IDs and as-of/freshness annotations
from `finance_core`. They do not build or validate a
`finance_provenance.Manifest`; the calling plugin links table roots to evidence.
Renderer metadata must preserve those IDs unchanged.

## Error and security policy

Errors identify table/row/column keys and a typed reason. They must not echo an
entire untrusted cell or arbitrary source metadata. Text cells are escaped per
target format, NUL/control characters are rejected or replaced by explicit
policy, and configurable character/row limits prevent accidental prompt or
artifact amplification.

## Test design

- Golden Markdown, CSV, and canonical JSON outputs for mixed semantic cells.
- Exact large-decimal, negative-zero normalization, half-even rounding, money,
  percent-ratio, Unicode, multiline, delimiter, quote, and formula fixtures.
- Validation tests for every column/cell mismatch and duplicate/width error.
- Missing, stale, delayed, revised, and estimated annotation preservation
  across all formats.
- Deterministic row/column/cell truncation with accurate omission counts and no
  fabricated artifact path.
- Round-trip JSON decoder tests and cross-renderer semantic equivalence tests.
- Composition tests proving successive projections/annotations preserve stable
  keys, ordering, provenance IDs, and validation errors.

## Distribution and compatibility

The package depends on `finance_core` and Gleam standard libraries only. It has
no FFI planned for 0.1. Hex contains source and documentation, not generated
tables. Canonical JSON includes a schema version; Markdown appearance may gain
new optional modes but default escaping and semantic preservation are
compatibility commitments.

## Acceptance criteria

- A table containing exact decimals, money, missing values, and annotations
  renders deterministically in all three formats.
- Cell/kind and unit mismatches return errors.
- Currency code display is unambiguous by default.
- Truncation is bounded, deterministic, and fully disclosed.
- JSON retains semantic values rather than formatted strings alone.
- Formatting, warnings-as-errors build, unit tests, and Hex tarball audit pass.

## Post-foundation decisions

- Whether row keys are required for 0.1 or optional until interactive diffing.
- Whether tables support grouped/multi-row headers before a real plugin needs
  them.
