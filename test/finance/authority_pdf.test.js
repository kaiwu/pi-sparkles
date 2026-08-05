import { createHash } from "node:crypto";
import { expect, test } from "bun:test";
import * as cnTime from "../../finance/finance_cninfo/build/dev/javascript/finance_core/finance_core/time.mjs";
import * as cnBinaryResponse from "../../finance/finance_cninfo/build/dev/javascript/finance_http/finance_http/binary_response.mjs";
import * as cnHttpResponse from "../../finance/finance_cninfo/build/dev/javascript/finance_http/finance_http/response.mjs";
import * as cnTransport from "../../finance/finance_cninfo/build/dev/javascript/finance_http/finance_http/transport.mjs";
import * as cninfo from "../../finance/finance_cninfo/build/dev/javascript/finance_cninfo/finance_cninfo.mjs";
import * as cninfoResponse from "../../finance/finance_cninfo/build/dev/javascript/finance_cninfo/finance_cninfo/response.mjs";
import * as cnPdfArtifact from "../../finance/finance_cninfo/build/dev/javascript/finance_authority_pdf/finance_authority_pdf/capture.mjs";
import * as cnArtifact from "../../finance/finance_cninfo/build/dev/javascript/finance_authority_snapshot/finance_authority_snapshot/artifact.mjs";
import * as cnSource from "../../finance/finance_cninfo/build/dev/javascript/finance_core/finance_core/source.mjs";
import { Ok as CnOk, toList as cnList } from "../../finance/finance_cninfo/build/dev/javascript/finance_cninfo/gleam.mjs";
import * as hkTime from "../../finance/finance_hkex/build/dev/javascript/finance_core/finance_core/time.mjs";
import * as hkBinaryResponse from "../../finance/finance_hkex/build/dev/javascript/finance_http/finance_http/binary_response.mjs";
import * as hkHttpResponse from "../../finance/finance_hkex/build/dev/javascript/finance_http/finance_http/response.mjs";
import * as hkTransport from "../../finance/finance_hkex/build/dev/javascript/finance_http/finance_http/transport.mjs";
import * as hkex from "../../finance/finance_hkex/build/dev/javascript/finance_hkex/finance_hkex.mjs";
import * as hkexResponse from "../../finance/finance_hkex/build/dev/javascript/finance_hkex/finance_hkex/response.mjs";
import * as hkPdfArtifact from "../../finance/finance_hkex/build/dev/javascript/finance_authority_pdf/finance_authority_pdf/capture.mjs";
import * as hkArtifact from "../../finance/finance_hkex/build/dev/javascript/finance_authority_snapshot/finance_authority_snapshot/artifact.mjs";
import * as hkSource from "../../finance/finance_hkex/build/dev/javascript/finance_core/finance_core/source.mjs";
import { Ok as HkOk, toList as hkList } from "../../finance/finance_hkex/build/dev/javascript/finance_hkex/gleam.mjs";
import { minimalPdf } from "./pdf_fixture.js";

function unwrap(result, OkType) {
  if (result instanceof OkType) return result[0];
  throw new globalThis.Error(`Expected Ok, received ${result.constructor.name}`);
}

function responseFor(bytes, modules) {
  return unwrap(
    modules.binary.new$(
      200,
      modules.list([
        modules.response.Header$Header("content-type", "application/pdf"),
      ]),
      bytes.toString("base64"),
      bytes.byteLength,
      createHash("sha256").update(bytes).digest("hex"),
      bytes.subarray(0, 16).toString("hex"),
      unwrap(modules.time.duration(1), modules.Ok),
    ),
    modules.Ok,
  );
}

test("CNINFO and HKEXnews capture bind page counts to the same hashed artifact", async () => {
  const bytes = minimalPdf(3);
  const cnModules = {
    binary: cnBinaryResponse,
    response: cnHttpResponse,
    time: cnTime,
    list: cnList,
    Ok: CnOk,
  };
  const cnDocument = unwrap(
    cninfo.document(2025, 8, 4, "1224386249"),
    CnOk,
  );
  const cnCaptured = await cninfoResponse.capture_inspected(
    cnDocument,
    responseFor(bytes, cnModules),
    unwrap(cnTime.instant(1000), CnOk),
    cnTransport.new_cancellation(),
  );
  expect(cnCaptured).toBeInstanceOf(CnOk);
  expect(cnPdfArtifact.page_count(cnCaptured[0])).toBe(3);
  expect(
    cnSource.provider(cnArtifact.source(cnPdfArtifact.artifact(cnCaptured[0]))),
  ).toBe("CNINFO");

  const hkModules = {
    binary: hkBinaryResponse,
    response: hkHttpResponse,
    time: hkTime,
    list: hkList,
    Ok: HkOk,
  };
  const hkDocument = unwrap(
    hkex.document(2026, 3, 31, "2026033103673"),
    HkOk,
  );
  const hkCaptured = await hkexResponse.capture_inspected(
    hkDocument,
    responseFor(bytes, hkModules),
    unwrap(hkTime.instant(1000), HkOk),
    hkTransport.new_cancellation(),
  );
  expect(hkCaptured).toBeInstanceOf(HkOk);
  expect(hkPdfArtifact.page_count(hkCaptured[0])).toBe(3);
  expect(
    hkSource.provider(hkArtifact.source(hkPdfArtifact.artifact(hkCaptured[0]))),
  ).toBe("HKEXnews");
});
