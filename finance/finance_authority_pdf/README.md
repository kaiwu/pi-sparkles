# finance_authority_pdf

Experimental narrow composition between raw authority evidence, real-parser PDF
inspection, and attachment metadata. It consumes one bounded binary response
for both `finance_authority_snapshot/artifact` and `finance_pdf`, preventing a
page count from being paired with another response's bytes or evidence hash.

The receipt retains the raw artifact plus page count and PDF parser/version.
It can construct `finance_document_attachment.Metadata` with proven media,
bytes, hash, page count, and zero redirects. OCR remains an explicit caller
decision because structural page inspection does not prove a usable text layer.

This separate package keeps text-only authority adapters independent of PDF.js.
