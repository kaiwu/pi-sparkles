# finance_pdf

Experimental bounded PDF structure and page-count inspector. It accepts only an
already-bounded `finance_http.BinaryResponse`, never a URL. It decodes the
base64 canonically, checks byte length, recomputes SHA-256, then uses the pinned
`pdfjs-dist@6.2.108` parser to walk every declared page. It returns only page
count, byte length, parser name, and parser version.

Policies require finite byte, page, and time limits. Cancellation or timeout
destroys the PDF.js loading task. Inspection disables URL/range fetching,
auto-fetch, rendering-oriented fonts/images/GPU/XFA/WASM facilities, and uses
strict `stopAtErrors`. Encrypted, malformed, oversized, over-page-budget, and
unreadable-page documents fail with body-free typed errors.

PDF.js is maintained by Mozilla and distributed under Apache-2.0. This package
does not render pages, extract text, run OCR, execute document actions, accept
passwords, or claim that successful structural inspection proves semantic
filing identity.

The repository root pins `pdfjs-dist` in `package.json`/`bun.lock`. Hex
distribution contains the Gleam and FFI source, so downstream JavaScript/Bun
builders must install that exact dependency before compiling this Experimental
package; it is not loaded by text-only authority adapters.
