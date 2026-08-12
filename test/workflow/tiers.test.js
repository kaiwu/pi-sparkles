import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  catalogProposals,
  readTierManifest,
  tierById,
  tierSummary,
  validateTierManifest,
  verificationBlockers,
} from "../../scripts/tiers.js";
import { ROOT } from "../../scripts/modules.js";

describe("tier delivery workflow", () => {
  test("maps every catalog proposal and implementation package exactly once", () => {
    const manifest = readTierManifest();
    expect(validateTierManifest(manifest)).toEqual([]);
    expect(catalogProposals()).toHaveLength(135);
    expect(manifest.tiers).toHaveLength(6);
    expect(manifest.tiers.flatMap((tier) => tier.proposals)).toHaveLength(135);
    expect(new Set(manifest.tiers.map((tier) => tier.acceptance_lane)).size).toBe(
      6,
    );
    expect(tierSummary(manifest).map((tier) => tier.proposals)).toEqual([
      45, 45, 11, 7, 16, 11,
    ]);
    expect(tierSummary(manifest).map((tier) => tier.open_blockers)).toEqual([
      0, 0, 0, 0, 0, 1,
    ]);
  });

  test("freezes ProductUseful tiers through Tier 5 and activates Tier 6", () => {
    const manifest = readTierManifest();
    const tier = tierById(manifest, "T1");
    const dependency = tierById(manifest, "T2");
    const portfolio = tierById(manifest, "T3");
    const quant = tierById(manifest, "T4");
    const multiAsset = tierById(manifest, "T5");
    const active = tierById(manifest, "T6");
    expect(manifest.active_tier).toBe("T6");
    expect(tier.status).toBe("product_useful");
    expect(dependency.status).toBe("product_useful");
    expect(portfolio.status).toBe("product_useful");
    expect(quant.status).toBe("product_useful");
    expect(multiAsset.status).toBe("product_useful");
    expect(active.status).toBe("blocker_resolution");
    expect(
      verificationBlockers(manifest, tier).some((message) =>
        message.includes("blocker is open"),
      ),
    ).toBeFalse();
    expect(verificationBlockers(manifest, tier)).toContain(
      "T1 status must be verifying, found product_useful",
    );
    expect(
      verificationBlockers(manifest, tier).some((message) =>
        message.includes("implementation is missing"),
      ),
    ).toBeFalse();
    expect(
      verificationBlockers(manifest, dependency).some((message) =>
        message.includes("implementation is missing"),
      ),
    ).toBeFalse();
    expect(verificationBlockers(manifest, dependency)).toContain(
      "T2 status must be verifying, found product_useful",
    );
    expect(verificationBlockers(manifest, portfolio)).toContain(
      "T3 status must be verifying, found product_useful",
    );
    expect(verificationBlockers(manifest, quant)).toContain(
      "T4 status must be verifying, found product_useful",
    );
    expect(verificationBlockers(manifest, multiAsset)).toContain(
      "T5 status must be verifying, found product_useful",
    );
    expect(
      verificationBlockers(manifest, multiAsset).some((message) =>
        message.includes("blocker is open"),
      ),
    ).toBeFalse();
    expect(
      verificationBlockers(manifest, active).some((message) =>
        message.includes("blocker is open: T6-INTRADAY-PROVIDERS"),
      ),
    ).toBeTrue();
    expect(verificationBlockers(manifest, active)).toContain(
      "T6 status must be verifying, found blocker_resolution",
    );
    expect(
      verificationBlockers(manifest, active).some((message) =>
        message.includes("dependency T1 must be product_useful"),
      ),
    ).toBeFalse();
  });

  test("anchors Tier 6 in CN and forbids plugin order mutation", () => {
    const tier = tierById(readTierManifest(), "T6");
    expect(tier.track_profile).toContain("One CN live-session");
    expect(tier.track_profile).toContain(
      "US live market-data and broker-network adapters are on hold",
    );
    expect(tier.product_outcome).toContain(
      "No Pi plugin can place, route, cancel, replace",
    );
    expect(tier.acceptance_lane).toBe("test/tiers/t6_cn_day_trader_review");

    const readiness = readFileSync(join(ROOT, "PRODUCT_READINESS.md"), "utf8");
    expect(readiness).toContain("## Non-executing broker boundary");
    expect(readiness).toContain("never place, submit, route, cancel, replace");

    const scopedDesigns = [
      "R1.md",
      "plugins/cn_broker_paper/README.md",
      "plugins/broker_paper_alpaca/README.md",
      "plugins/broker_paper_ibkr/README.md",
      "plugins/broker_live/README.md",
    ].map((path) => readFileSync(join(ROOT, path), "utf8"));
    for (const legacyTool of [
      "cn_paper_order_submit",
      "paper_order_submit",
      "paper_order_cancel",
      "ibkr_paper_order_submit",
      "live_order_submit",
      "live_order_cancel",
    ]) {
      expect(
        scopedDesigns.some((design) => design.includes(legacyTool)),
        legacyTool,
      ).toBeFalse();
    }
  });

  test("rejects duplicate proposal ownership", () => {
    const manifest = structuredClone(readTierManifest());
    manifest.tiers[1].proposals.push(manifest.tiers[0].proposals[0]);
    expect(
      validateTierManifest(manifest).some((message) =>
        message.includes("proposal appears in more than one tier"),
      ),
    ).toBeTrue();
  });
});
