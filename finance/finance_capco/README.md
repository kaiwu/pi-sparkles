# finance_capco

Experimental, bounded adapter for the China Association for Public Companies
(CAPCO) listed-company industry-classification results.

The first slice selects exactly the official `2025-H2` stock-code-sorted PDF,
published on 2026-04-03 under the CAPCO Listed Company Industry Statistical
Classification Guideline effective 2023-05-01 and referring to GB/T 4754-2017.
The reviewed PDF is pinned to its exact byte length and SHA-256. An upstream
replacement fails closed until its source contract is reviewed again.

The adapter uses `finance_http` for one bounded binary GET, captures the raw PDF
as CN official-source evidence, and uses PDF.js only to return bounded text
items and coordinates. CAPCO table semantics remain pure Gleam logic. The parser
selects one exact six-digit stock-code row and returns only the published
`门类`, `大类`, and manufacturing-only `次类`; it never invents `中类`.

The source publishes a half-year result label and publication date, not
per-company membership effective dates. Consumers must keep taxonomy effective
date, result period, publication date, and retrieval time distinct. Stock-code
prefixes do not prove a MIC or instrument identifier.

CAPCO's legal statement restricts copying and reuse. Captures are read-only
internal-analysis evidence with attribution and `NoRedistribution`. Tests use
synthetic text items and synthetic PDFs; the official PDF is not copied into
the repository and tests never perform live requests.

Official references:

- Guideline: <https://www.capco.org.cn/xhdt/tzgg/202305/20230521/j_2023052117544500016846630061707656.html>
- 2025-H2 result: <https://www.capco.org.cn/xhgg/hyfl/hyfljg/202604/20260403/j_2026040315001700017751997384265508.html>
- Legal statement: <https://www.capco.org.cn/flsm/index.html>

