import { describe, expect, test } from "bun:test";
import { resolve } from "node:path";

const built = resolve(
  import.meta.dir,
  "../../finance/finance_notification_scripted/build/dev/javascript/finance_notification_scripted/finance_notification_scripted_ffi.mjs",
);

describe("scripted notification capability", () => {
  test("returns deterministic delivery, rate-limit, and cancellation receipts", async () => {
    const { deliver } = await import(`${built}?t=${Date.now()}`);
    const signal = new AbortController().signal;
    const first = await deliver("scripted_local", "opaque-1", 1, "delivered", signal);
    const repeated = await deliver("scripted_local", "opaque-1", 1, "delivered", signal);
    expect(first).toEqual(repeated);
    expect(first.status).toBe("delivered");
    expect(first.receipt).toHaveLength(64);
    expect((await deliver("scripted_local", "opaque-1", 2, "rate_limited", signal)).status).toBe("rate_limited");
    const controller = new AbortController();
    controller.abort();
    expect(await deliver("scripted_local", "opaque-1", 1, "delivered", controller.signal)).toEqual({ status: "cancelled" });
  });
});
