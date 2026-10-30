import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import { api, ApiError, setDisplayedSession } from "./api.ts";

const originalFetch = globalThis.fetch;
const originalNavigator = Object.getOwnPropertyDescriptor(
  globalThis,
  "navigator",
);

beforeEach(() => {
  let queue = Promise.resolve();
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      locks: {
        request(_name, _options, operation) {
          const result = queue.then(operation);
          queue = result.catch(() => undefined);
          return result;
        },
      },
    },
  });
  setDisplayedSession({
    authenticated: true,
    csrf_token: "csrf-a",
    membership_id: "a",
  });
});

afterEach(() => {
  globalThis.fetch = originalFetch;
  setDisplayedSession(null);
  if (originalNavigator)
    Object.defineProperty(globalThis, "navigator", originalNavigator);
  else delete globalThis.navigator;
});

test("a rotated session cannot receive a write prepared for the previous account", async () => {
  let token = "csrf-a";
  let writes = 0;
  globalThis.fetch = async (path) => {
    if (path === "/api/session")
      return Response.json({
        authenticated: true,
        csrf_token: token,
        membership_id: "a",
      });
    writes += 1;
    return Response.json({ ok: true });
  };
  await api("/api/onboarding", { method: "POST", body: {} });
  token = "csrf-b";
  await assert.rejects(
    api("/api/onboarding", { method: "POST", body: {} }),
    (error) =>
      error instanceof ApiError && error.code === "session_context_changed",
  );
  assert.equal(writes, 1);
});

test("a membership switch in another tab cannot redirect a queued write to that tenant", async () => {
  let membership = "a";
  let writes = 0;
  const started = Promise.withResolvers();
  const release = Promise.withResolvers();
  globalThis.fetch = async (path, options) => {
    if (path === "/api/session" && options.method === "GET")
      return Response.json({
        authenticated: true,
        csrf_token: "csrf-a",
        membership_id: membership,
      });
    if (path === "/api/session/membership") {
      started.resolve();
      await release.promise;
      membership = "b";
      return Response.json({ membership_id: "b" });
    }
    writes += 1;
    return Response.json({ ok: true });
  };
  const switching = api("/api/session/membership", {
    method: "PATCH",
    body: { membership_id: "b" },
  });
  await started.promise;
  const staleWrite = api("/api/monitorings/parties", {
    method: "POST",
    body: { name: "Parte" },
  });
  release.resolve();
  await switching;
  await assert.rejects(
    staleWrite,
    (error) =>
      error instanceof ApiError && error.code === "session_context_changed",
  );
  assert.equal(writes, 0);
});

test("a read cannot display another membership's data under the previous context", async () => {
  let requestedData = false;
  globalThis.fetch = async (path) => {
    if (path === "/api/session")
      return Response.json({
        authenticated: true,
        csrf_token: "csrf-a",
        membership_id: "b",
      });
    requestedData = true;
    return Response.json({ private: "tenant b" });
  };
  await assert.rejects(
    api("/api/communications"),
    (error) =>
      error instanceof ApiError && error.code === "session_context_changed",
  );
  assert.equal(requestedData, false);
});

test("a session rotating during a read cannot return data from the new account", async () => {
  let token = "csrf-a";
  globalThis.fetch = async (path) => {
    if (path === "/api/session")
      return Response.json({
        authenticated: true,
        csrf_token: token,
        membership_id: "a",
      });
    token = "csrf-b";
    return Response.json({ private: "new account" });
  };
  await assert.rejects(
    api("/api/communications"),
    (error) =>
      error instanceof ApiError && error.code === "session_context_changed",
  );
});

test("logout accepts the backend's empty 204 response", async () => {
  globalThis.fetch = async (_path, options) =>
    options.method === "GET"
      ? Response.json({
          authenticated: true,
          csrf_token: "csrf-a",
          membership_id: "a",
        })
      : new Response(null, { status: 204 });
  assert.equal(await api("/api/session", { method: "DELETE" }), undefined);
});

test("expired authentication never sends a mutation without CSRF", async () => {
  let count = 0;
  globalThis.fetch = async () => {
    count += 1;
    return Response.json({ authenticated: false });
  };
  await assert.rejects(
    api("/api/onboarding", { method: "POST", body: {} }),
    (error) => error instanceof ApiError && error.status === 401,
  );
  assert.equal(count, 1);
});

test("network failures never return fake empty results or expose private details", async () => {
  globalThis.fetch = async () => {
    throw new TypeError("private network details");
  };
  await assert.rejects(
    api("/api/dashboard"),
    (error) =>
      error instanceof ApiError &&
      error.status === 0 &&
      error.code === "network_error" &&
      !error.message.includes("private"),
  );
});

test("external URLs are rejected before requesting credentials", async () => {
  let count = 0;
  globalThis.fetch = async () => {
    count += 1;
    return Response.json({});
  };
  await assert.rejects(
    api("https://attacker.test/api/session"),
    (error) => error instanceof ApiError,
  );
  assert.equal(count, 0);
});

test("writes fail closed when cross-tab locking is unavailable", async () => {
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {},
  });
  let count = 0;
  globalThis.fetch = async () => {
    count += 1;
    return Response.json({});
  };
  await assert.rejects(
    api("/api/onboarding", { method: "POST", body: {} }),
    (error) =>
      error instanceof ApiError && error.code === "browser_not_supported",
  );
  assert.equal(count, 0);
});
