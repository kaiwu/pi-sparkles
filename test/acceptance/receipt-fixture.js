import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import {
  ACCEPTANCE_FIXTURE_MODULE,
  buildAcceptanceFixture,
} from "../../scripts/build-acceptance-fixture.js";
import {
  loadBundledMarketReceipts,
  verifyBundledMarketCopy,
  verifyBundledUniverseCopy,
} from "./provider-market-fixture.js";

export async function loadReceiptFixture({ build = false } = {}) {
  if (build) buildAcceptanceFixture();
  const module = await import(
    `${pathToFileURL(ACCEPTANCE_FIXTURE_MODULE).href}?fixture=${Date.now()}-${Math.random()}`
  );
  const markets = await loadBundledMarketReceipts();
  const fixture = JSON.parse(
    module.fixture_json_with_market_hashes(
      markets.cn.canonicalContentHash,
      markets.hk.canonicalContentHash,
      markets.us.canonicalContentHash,
    ),
  );
  if (fixture.schema !== "pi-sparkles/swing-acceptance-receipts") {
    throw new Error(`Unexpected acceptance receipt schema: ${fixture.schema}`);
  }
  for (const [track, receipts] of Object.entries(fixture.tracks)) {
    receipts.market = markets[track];
    verifyBundledMarketCopy(track, receipts.market);
    for (const name of [
      "indicator",
      "risk",
      "rule",
      "execution",
      "sectorRegime",
      "catalyst",
      "taskTime",
      "universeCandidate",
    ]) {
      verifyReceiptCopy(name, receipts[name]);
    }
    if (track === "us") {
      Object.assign(receipts.universeCandidate, markets.usUniverse);
      verifyBundledUniverseCopy(
        receipts.universeCandidate,
        receipts.universeCandidate,
      );
    }
  }
  return fixture;
}

function verifyReceiptCopy(name, receipt) {
  let payload = receipt.payload;
  if (receipt.integrity === "envelope_payload_sha256") {
    const envelope = JSON.parse(receipt.payload);
    if (envelope.canonical_content_hash !== receipt.canonicalContentHash) {
      throw new Error(`${name} envelope hash does not match copied handle`);
    }
    payload = JSON.stringify(envelope.payload);
  }
  const actual = createHash("sha256").update(payload).digest("hex");
  if (actual !== receipt.canonicalContentHash) {
    throw new Error(`${name} copied receipt failed content-hash verification`);
  }
}
