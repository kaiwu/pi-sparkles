import { createHash } from "node:crypto";

export function sha256_hex(value) {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
