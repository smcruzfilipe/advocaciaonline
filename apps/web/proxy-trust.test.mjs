import test from "node:test";
import assert from "node:assert/strict";
import { trustedProxyHeaders } from "./proxy-trust.mjs";

test("only the configured proxy can provide the client address", () => {
  const secret = "s".repeat(64);
  const headers = { "x-forwarded-for": "203.0.113.99, 198.51.100.24", "x-advocacia-client-ip": "203.0.113.99", "x-advocacia-ingress-secret": "forged" };
  assert.deepEqual(trustedProxyHeaders("::ffff:10.0.1.7", headers, "10.0.1.7", secret), { "x-advocacia-client-ip": "198.51.100.24", "x-advocacia-ingress-secret": secret });
  assert.equal(trustedProxyHeaders("10.0.1.8", headers, "10.0.1.7", secret), null);
  assert.equal(trustedProxyHeaders("10.0.1.7", { "x-forwarded-for": "203.0.113.99, invalid" }, "10.0.1.7", secret), null);
  assert.equal(trustedProxyHeaders("10.0.1.7", {}, "10.0.1.7", secret), null);
  assert.equal(trustedProxyHeaders("10.0.1.7", headers, "10.0.1.7", "short"), null);
});
