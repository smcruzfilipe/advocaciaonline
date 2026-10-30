import assert from "node:assert/strict";
import test from "node:test";
import { readInvitationBody } from "./invitation-body.ts";

test("an oversized invitation body is rejected", async () => {
  const request = new Request("https://app.test/convite/preservar", {
    method: "POST",
    body: "x".repeat(1025),
  });
  await assert.rejects(readInvitationBody(request));
});

test("an unfinished invitation body cannot hold the handler indefinitely", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const request = new Request("https://app.test/convite/preservar", {
    method: "POST",
    body: new ReadableStream({ start() {} }),
    duplex: "half",
  });
  const pending = readInvitationBody(request);
  t.mock.timers.tick(5001);
  await assert.rejects(pending);
});
