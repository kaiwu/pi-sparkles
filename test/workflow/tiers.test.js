import { describe, expect, test } from "bun:test";
import {
  catalogProposals,
  readTierManifest,
  tierById,
  tierSummary,
  validateTierManifest,
  verificationBlockers,
} from "../../scripts/tiers.js";

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

  test("freezes ProductUseful dependencies and activates Tier 4", () => {
    const manifest = readTierManifest();
    const tier = tierById(manifest, "T1");
    const dependency = tierById(manifest, "T2");
    const portfolio = tierById(manifest, "T3");
    const active = tierById(manifest, "T4");
    expect(manifest.active_tier).toBe("T4");
    expect(tier.status).toBe("product_useful");
    expect(dependency.status).toBe("product_useful");
    expect(portfolio.status).toBe("product_useful");
    expect(active.status).toBe("product_useful");
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
    expect(verificationBlockers(manifest, active)).toContain(
      "T4 status must be verifying, found product_useful",
    );
    expect(
      verificationBlockers(manifest, active).some((message) =>
        message.includes("implementation is missing"),
      ),
    ).toBeFalse();
    expect(
      verificationBlockers(manifest, active).some((message) =>
        message.includes("blocker is open"),
      ),
    ).toBeFalse();
    expect(
      verificationBlockers(manifest, active).some((message) =>
        message.includes("dependency T1 must be product_useful"),
      ),
    ).toBeFalse();
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
