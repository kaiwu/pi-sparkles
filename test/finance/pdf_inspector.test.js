import { createHash } from "node:crypto";
import { expect, test } from "bun:test";
import * as time from "../../finance/finance_pdf/build/dev/javascript/finance_core/finance_core/time.mjs";
import * as binaryResponse from "../../finance/finance_pdf/build/dev/javascript/finance_http/finance_http/binary_response.mjs";
import * as response from "../../finance/finance_pdf/build/dev/javascript/finance_http/finance_http/response.mjs";
import * as transport from "../../finance/finance_pdf/build/dev/javascript/finance_http/finance_http/transport.mjs";
import * as inspector from "../../finance/finance_pdf/build/dev/javascript/finance_pdf/finance_pdf/inspector.mjs";
import { Error, Ok, toList } from "../../finance/finance_pdf/build/dev/javascript/finance_pdf/gleam.mjs";
import { minimalPdf } from "./pdf_fixture.js";

function unwrap(result) {
  if (result instanceof Ok) return result[0];
  throw new globalThis.Error(`Expected Ok, received ${result.constructor.name}`);
}

function duration(milliseconds) {
  return unwrap(time.duration(milliseconds));
}

function inspectionPolicy({ maximumBytes = 1_000_000, maximumPages = 10 } = {}) {
  return unwrap(inspector.policy(maximumBytes, maximumPages, duration(5_000)));
}

function pdfResponse(bytes, sha256 = createHash("sha256").update(bytes).digest("hex")) {
  return unwrap(
    binaryResponse.new$(
      200,
      toList([response.Header$Header("content-type", "application/pdf")]),
      bytes.toString("base64"),
      bytes.byteLength,
      sha256,
      bytes.subarray(0, 16).toString("hex"),
      duration(1),
    ),
  );
}

test("PDF inspector walks every page and reports its pinned parser", async () => {
  const result = await inspector.inspect(
    inspectionPolicy(),
    pdfResponse(minimalPdf(2)),
    transport.new_cancellation(),
  );

  expect(result).toBeInstanceOf(Ok);
  expect(inspector.page_count(result[0])).toBe(2);
  expect(inspector.parser(result[0])).toBe("pdfjs-dist");
  expect(inspector.parser_version(result[0])).toBe("6.2.108");
});

test("PDF inspector fails closed on page budget, malformed data, and cancellation", async () => {
  const overBudget = await inspector.inspect(
    inspectionPolicy({ maximumPages: 1 }),
    pdfResponse(minimalPdf(2)),
    transport.new_cancellation(),
  );
  expect(overBudget).toBeInstanceOf(Error);
  expect(overBudget[0]).toBeInstanceOf(inspector.TooManyPages);
  expect(overBudget[0].received).toBe(2);

  const malformedBytes = Buffer.from("%PDF-not-a-document", "ascii");
  const malformed = await inspector.inspect(
    inspectionPolicy(),
    pdfResponse(malformedBytes),
    transport.new_cancellation(),
  );
  expect(malformed).toBeInstanceOf(Error);
  expect(malformed[0]).toBe(inspector.InspectionError$InvalidPdf$const);

  const forgedHash = await inspector.inspect(
    inspectionPolicy(),
    pdfResponse(minimalPdf(1), "a".repeat(64)),
    transport.new_cancellation(),
  );
  expect(forgedHash).toBeInstanceOf(Error);
  expect(forgedHash[0]).toBe(
    inspector.InspectionError$ContentHashMismatch$const,
  );

  const cancellation = transport.new_cancellation();
  transport.cancel(cancellation);
  const cancelled = await inspector.inspect(
    inspectionPolicy(),
    pdfResponse(minimalPdf(1)),
    cancellation,
  );
  expect(cancelled).toBeInstanceOf(Error);
  expect(cancelled[0]).toBe(inspector.InspectionError$Cancelled$const);
});
