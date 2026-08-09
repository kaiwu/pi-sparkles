import { afterEach, describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import {
  mkdtempSync,
  readdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const artifact = resolve(import.meta.dir, "../../dist/portfolio/index.js");
const directories = [];

afterEach(() => {
  for (const directory of directories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

async function harness() {
  const tools = new Map();
  const api = {
    registerTool(definition) {
      tools.set(definition.name, definition);
    },
  };
  const module = await import(`${artifact}?portfolio=${Date.now()}-${Math.random()}`);
  await module.default(api);
  return tools;
}

function directory() {
  const value = mkdtempSync(join(tmpdir(), "pi-sparkles-portfolio-"));
  directories.push(value);
  return value;
}

function execute(tool, value, signal = new AbortController().signal) {
  return tool.execute("portfolio-call", value, signal, undefined, {
    hasUI: false,
    ui: {},
  });
}

function importInput(path, overrides = {}) {
  return {
    path,
    format: "json",
    delimiter: "comma",
    decimalConvention: "plain_dot",
    maximumBytes: 1_000_000,
    maximumRows: 100,
    maximumColumns: 100,
    maximumFieldBytes: 4096,
    maximumJsonDepth: 10,
    maximumJsonElements: 10_000,
    reconciliationTolerance: "0.01",
    accountVisibility: "redacted",
    ...overrides,
  };
}

function document(overrides = {}) {
  return JSON.stringify({
    snapshot: {
      snapshot_id: "snap-001",
      source_kind: "ImportedFile",
      account_id: "private-account-123",
      base_currency: "USD",
      source_as_of: "2026-08-08T20:00:00Z",
      entitlement: "caller_private_local_use",
      source_declared_total: "1250.00",
      source_total_currency: "USD",
      ...overrides.snapshot,
    },
    positions: overrides.positions ?? [
      {
        position_id: "P1",
        track: "us",
        listing_id: "listing-1",
        mic: "XNAS",
        source_symbol: "AAPL",
        security_name: "Apple Inc.",
        security_type: "CommonStock",
        direction: "Long",
        quantity: "10",
        quantity_unit: "shares",
        avg_cost: "100",
        cost_basis_total: "1000",
        current_mark: "125.00",
        mark_time: "2026-08-08T20:00:00Z",
        market_value: "1250.00",
        position_currency: "USD",
        unrealized_pnl: "250.00",
        source_row_id: "row-1",
        tax_id: "must-never-leave",
      },
    ],
  });
}

describe("portfolio import and inspection boundary", () => {
  test("registers only the three Session 21 read-only tools", async () => {
    const tools = await harness();
    expect([...tools.keys()]).toEqual([
      "portfolio_import",
      "portfolio_summary",
      "portfolio_positions",
    ]);
  });

  test("imports exact JSON, redacts privacy, and supports session-local drill-down", async () => {
    const root = directory();
    const path = join(root, "broker-export.json");
    const source = document();
    writeFileSync(path, source);
    const tools = await harness();

    const imported = await execute(
      tools.get("portfolio_import"),
      importInput(path),
    );
    expect(imported.details).toMatchObject({
      operation: "portfolio_import",
      snapshotId: "snap-001",
      sourceKind: "ImportedFile",
      baseCurrency: "USD",
      accountId: {
        state: "redacted",
        reason: "account_visibility_not_review_visible",
      },
      sourceFile: {
        path: "redacted",
        name: "redacted",
        byteLength: Buffer.byteLength(source),
        hashedByteLength: Buffer.byteLength(source),
        hashScope: "complete_file",
        contentSha256: createHash("sha256").update(source).digest("hex"),
        authentication: "unauthenticated_import",
      },
      counts: {
        totalSourceRows: 1,
        retainedRows: 1,
        unsupported: 0,
        identityUnresolved: 0,
      },
      reconciliation: {
        state: "calculated",
        sourceDeclaredTotal: "1250",
        calculatedTotal: "1250",
        delta: "0",
        withinTolerance: true,
        correctnessVerdict: null,
      },
      storage: {
        kind: "bounded_session_local_memory",
        durable: false,
        survivesReload: false,
      },
      decisionOwner: "llm_user",
      pluginDecisionFields: [],
    });

    const summary = await execute(tools.get("portfolio_summary"), {
      snapshotId: "snap-001",
    });
    expect(summary.details.sourceFile.contentSha256).toBe(
      imported.details.sourceFile.contentSha256,
    );

    const positions = await execute(tools.get("portfolio_positions"), {
      snapshotId: "snap-001",
      cursor: 0,
      limit: 10,
      track: "us",
      identityResolved: true,
    });
    expect(positions.details).toMatchObject({
      matchedCount: 1,
      returnedCount: 1,
      nextCursor: null,
      positions: [
        {
          positionId: { state: "known", value: "P1" },
          track: { state: "known", value: "us" },
          calculatedMarketValue: {
            state: "calculated",
            value: "1250",
            formula: "quantity * current_mark",
            currency: "USD",
          },
          marketValueReconciliation: {
            state: "calculated",
            delta: "0",
            correctnessVerdict: null,
          },
          unrealizedPnlReconciliation: {
            state: "calculated",
            delta: "0",
            correctnessVerdict: null,
          },
          extraColumns: { tax_id: { state: "redacted" } },
        },
      ],
    });
    const serialized = JSON.stringify([imported.details, positions.details]);
    expect(serialized).not.toContain(path);
    expect(serialized).not.toContain("private-account-123");
    expect(serialized).not.toContain("must-never-leave");
    expect(readdirSync(root)).toEqual(["broker-export.json"]);
  });

  test("retains complete CSV records when the byte budget truncates the file", async () => {
    const root = directory();
    const path = join(root, "positions.csv");
    const header =
      "snapshot_id,source_kind,base_currency,source_as_of,entitlement,position_id,track,listing_id,source_symbol,security_type,direction,quantity,quantity_unit,current_mark,mark_time,market_value,position_currency,source_row_id,note\n";
    const first =
      'snap-csv,ImportedFile,USD,Unknown(source),caller_private,P1,us,L1,AAPL,CommonStock,Long,10,shares,5,2026-08-08T00:00:00Z,50,USD,row-1,"exact, note"\n';
    const second =
      "snap-csv,ImportedFile,USD,Unknown(source),caller_private,P2,us,L2,MSFT,CommonStock,Long,2,shares,10,2026-08-08T00:00:00Z,20,USD,row-2,second\n";
    const source = header + first + second;
    writeFileSync(path, source);
    const maximumBytes = Buffer.byteLength(header + first) + 8;
    const tools = await harness();

    const imported = await execute(
      tools.get("portfolio_import"),
      importInput(path, { format: "csv", maximumBytes }),
    );
    expect(imported.details).toMatchObject({
      snapshotId: "snap-csv",
      counts: { retainedRows: 1 },
      truncation: {
        state: "truncated_by_byte_budget",
        totalFileBytes: Buffer.byteLength(source),
        nextSourceIndex: 3,
      },
      sourceFile: {
        byteLength: Buffer.byteLength(source),
        hashScope: "retained_utf8_prefix",
      },
    });
    const positions = await execute(tools.get("portfolio_positions"), {
      snapshotId: "snap-csv",
      cursor: 0,
      limit: 10,
    });
    expect(positions.details.returnedCount).toBe(1);
    expect(positions.details.positions[0].extraColumns.note).toBe("exact, note");
  });

  test("same ID is idempotent for exact bytes and rejects changed content", async () => {
    const root = directory();
    const path = join(root, "snapshot.json");
    writeFileSync(path, document());
    const tools = await harness();
    const first = await execute(tools.get("portfolio_import"), importInput(path));
    const second = await execute(tools.get("portfolio_import"), importInput(path));
    expect(second.details.sourceFile.contentSha256).toBe(
      first.details.sourceFile.contentSha256,
    );

    writeFileSync(
      path,
      document({ snapshot: { environment: "changed-content" } }),
    );
    await expect(
      execute(tools.get("portfolio_import"), importInput(path)),
    ).rejects.toThrow("snapshot ID already names different content");
  });

  test("session-local snapshots do not survive a new extension instance", async () => {
    const root = directory();
    const path = join(root, "snapshot.json");
    writeFileSync(path, document());
    const first = await harness();
    await execute(first.get("portfolio_import"), importInput(path));

    const second = await harness();
    await expect(
      execute(second.get("portfolio_summary"), { snapshotId: "snap-001" }),
    ).rejects.toThrow("not found in this session");
  });

  test("fails strict UTF-8 and symbolic links without exposing paths", async () => {
    const root = directory();
    const invalidPath = join(root, "invalid.json");
    writeFileSync(invalidPath, Buffer.from([0xff, 0xfe, 0xfd]));
    const tools = await harness();
    await expect(
      execute(tools.get("portfolio_import"), importInput(invalidPath)),
    ).rejects.toThrow("strict UTF-8");

    const realPath = join(root, "real.json");
    const linkPath = join(root, "link.json");
    writeFileSync(realPath, document());
    symlinkSync(realPath, linkPath);
    try {
      await execute(tools.get("portfolio_import"), importInput(linkPath));
      throw new Error("expected symlink rejection");
    } catch (error) {
      expect(String(error)).toContain("symbolic_link_not_supported");
      expect(String(error)).not.toContain(linkPath);
      expect(String(error)).not.toContain(realPath);
    }
  });

  test("honors cancellation before filesystem work", async () => {
    const root = directory();
    const path = join(root, "snapshot.json");
    writeFileSync(path, document());
    const tools = await harness();
    const controller = new AbortController();
    controller.abort();
    await expect(
      execute(tools.get("portfolio_import"), importInput(path), controller.signal),
    ).rejects.toThrow("cancelled");
  });
});
