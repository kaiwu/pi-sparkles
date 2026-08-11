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
      41, 49, 11, 7, 16, 11,
    ]);
  });

  test("keeps blocker resolution ahead of Tier 1 implementation", () => {
    const manifest = readTierManifest();
    const tier = tierById(manifest, "T1");
    expect(manifest.active_tier).toBe("T1");
    expect(tier.status).toBe("blocker_resolution");
    expect(verificationBlockers(manifest, tier)).toContain(
      "T1 status must be verifying, found blocker_resolution",
    );
    expect(
      verificationBlockers(manifest, tier).some((message) =>
        message.includes("T1-DAILY-PROVIDERS"),
      ),
    ).toBeTrue();
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
