import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { createServer } from "node:http";
import { once } from "node:events";
import {
  forwardedHeaders,
  invitationCookie,
  invitationFingerprint,
  invitationToken,
  isApiPath,
  matchesInvitation,
  publicOrigin,
  railsFetch,
  responseHeaders,
  safeGoogleRedirect,
  sameOrigin,
  sessionDestination,
  trustedClientIp,
  uiRedirect,
} from "./transport.ts";

const previousOrigin = process.env.APP_ORIGIN;
const previousRailsOrigin = process.env.RAILS_API_ORIGIN;
const previousIngressSecret = process.env.AUTH_INGRESS_SECRET;
afterEach(() => {
  if (previousOrigin === undefined) delete process.env.APP_ORIGIN;
  else process.env.APP_ORIGIN = previousOrigin;
  if (previousRailsOrigin === undefined) delete process.env.RAILS_API_ORIGIN;
  else process.env.RAILS_API_ORIGIN = previousRailsOrigin;
  if (previousIngressSecret === undefined)
    delete process.env.AUTH_INGRESS_SECRET;
  else process.env.AUTH_INGRESS_SECRET = previousIngressSecret;
});

test("public origin requires HTTPS and rejects credentials or non-origin components", () => {
  for (const value of [
    "http://app.test",
    "https://user@app.test",
    "https://app.test/path",
    "https://app.test?next=x",
    "https://app.test#token=x",
  ]) {
    process.env.APP_ORIGIN = value;
    assert.throws(publicOrigin);
  }
  process.env.APP_ORIGIN = "https://app.test/";
  assert.equal(publicOrigin().origin, "https://app.test");
});

test("proxy only accepts existing API resource paths", () => {
  for (const path of [
    "/api/session",
    "/api/session/membership",
    "/api/monitorings/parties/abc",
    "/api/team/credentials/abc/renewal",
    "/api/authorization/groups/abc/memberships/def",
    "/api/collection-runs/abc/execution",
  ])
    assert.equal(isApiPath(path), true, path);
  for (const path of [
    "https://attacker.test/api/session",
    "//attacker.test",
    "/api/../auth/google",
    "/api/arbitrary",
    "/api/session/extra",
    "/api/team/credentials/a%2fb",
  ])
    assert.equal(isApiPath(path), false, path);
});

test("upstream host comes from configuration and actual Origin is never invented", () => {
  process.env.APP_ORIGIN = "https://app.test";
  const request = new Request("http://internal.test/api/session", {
    headers: {
      Host: "attacker.test",
      Origin: "https://attacker.test",
      Cookie:
        "__Host-advocacia_session=session; __Host-advocacia_invitation=private-invitation",
      "X-CSRF-Token": "csrf",
    },
  });
  const headers = forwardedHeaders(request);
  assert.equal(headers.get("host"), "app.test");
  assert.equal(headers.get("x-forwarded-host"), "app.test");
  assert.equal(headers.get("x-forwarded-proto"), "https");
  assert.equal(headers.get("origin"), "https://attacker.test");
  assert.equal(headers.get("x-csrf-token"), "csrf");
  assert.equal(headers.get("cookie"), "__Host-advocacia_session=session");
  assert.equal(
    forwardedHeaders(new Request("http://internal.test")).has("origin"),
    false,
  );
});

test("all Set-Cookie headers and private caching policy survive response adaptation", () => {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json",
  });
  headers.append(
    "set-cookie",
    "__Host-advocacia_oidc=; Path=/; Secure; HttpOnly; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
  );
  headers.append(
    "set-cookie",
    "__Host-advocacia_session=secret; Path=/; Secure; HttpOnly; SameSite=Lax",
  );
  const forwarded = responseHeaders(new Response("{}", { headers }));
  assert.equal(forwarded.getSetCookie().length, 2);
  assert.equal(forwarded.get("cache-control"), "no-store");
  assert.equal(forwarded.get("referrer-policy"), "no-referrer");
});

test("OAuth redirects are restricted to the backend Google authorization endpoint", () => {
  assert.equal(
    safeGoogleRedirect(
      "https://accounts.google.com/o/oauth2/v2/auth?state=bound",
    ),
    true,
  );
  for (const value of [
    "https://attacker.test",
    "//accounts.google.com/o/oauth2/v2/auth",
    "https://accounts.google.com.attacker.test/o/oauth2/v2/auth",
    "https://user@accounts.google.com/o/oauth2/v2/auth",
    "https://accounts.google.com/other",
  ])
    assert.equal(safeGoogleRedirect(value), false);
});

test("callback chooses fixed UI destinations and invitation wins over onboarding", () => {
  assert.equal(
    sessionDestination({ authenticated: true, onboarded: false }, true),
    "/convite",
  );
  assert.equal(
    sessionDestination({ authenticated: true, selection_required: true }),
    "/vinculos",
  );
  assert.equal(
    sessionDestination({ authenticated: true, onboarded: false }),
    "/onboarding",
  );
  assert.equal(
    sessionDestination({
      authenticated: true,
      onboarded: true,
      next: "https://attacker.test",
    }),
    "/dashboard",
  );
  assert.equal(sessionDestination({ authenticated: false }), "/login");
});

test("invitation cookie is an opaque backend token with no arbitrary cookie content", () => {
  assert.equal(invitationToken("a".repeat(43)), "a".repeat(43));
  for (const value of [undefined, "", "a".repeat(42), "x; Path=/", "../secret"])
    assert.equal(invitationToken(value), null);
});

test("a confirmation is bound to the invitation opened in that tab", () => {
  const first = "a".repeat(43);
  const second = "b".repeat(43);
  const fingerprint = invitationFingerprint(first);
  assert.equal(matchesInvitation(first, fingerprint), true);
  assert.equal(matchesInvitation(second, fingerprint), false);
  assert.equal(matchesInvitation(first, null), false);
});

test("invitation handoff requires the actual configured browser origin", () => {
  process.env.APP_ORIGIN = "https://app.test";
  assert.equal(
    sameOrigin(
      new Request("https://app.test/convite/preservar", {
        headers: {
          Origin: "https://app.test",
          "Sec-Fetch-Site": "same-origin",
        },
      }),
    ),
    true,
  );
  for (const headers of [
    {},
    { Origin: "https://attacker.test" },
    { Origin: "https://app.test", "Sec-Fetch-Site": "cross-site" },
  ]) {
    assert.equal(
      sameOrigin(
        new Request("https://app.test/convite/preservar", { headers }),
      ),
      false,
    );
  }
});

test("invitation persistence has secure host-only short-lived HttpOnly semantics and deletion", () => {
  const cookie = invitationCookie("a".repeat(43));
  assert.match(cookie, /^__Host-advocacia_invitation=/);
  for (const attribute of [
    "Path=/",
    "HttpOnly",
    "Secure",
    "SameSite=Lax",
    "Max-Age=600",
  ])
    assert.ok(cookie.includes(attribute), attribute);
  assert.equal(/domain=/i.test(cookie), false);
  assert.match(invitationCookie(null), /Max-Age=0/);
});

test("only the authenticated ingress can supply an individual login address", () => {
  process.env.AUTH_INGRESS_SECRET = "s".repeat(43);
  const request = (secret, ip) =>
    new Request("https://app.test/auth/google", {
      headers: {
        "x-advocacia-ingress-secret": secret,
        "x-advocacia-client-ip": ip,
      },
    });
  assert.equal(
    trustedClientIp(request("s".repeat(43), "198.51.100.24")),
    "198.51.100.24",
  );
  assert.equal(trustedClientIp(request("wrong", "198.51.100.24")), null);
  assert.equal(
    trustedClientIp(request("s".repeat(43), "198.51.100.24, 203.0.113.4")),
    null,
  );
  delete process.env.AUTH_INGRESS_SECRET;
  assert.equal(trustedClientIp(request("s".repeat(43), "198.51.100.24")), null);
});

test("public host reaches the backend host authorization over a real connection", async () => {
  const server = createServer((request, response) => {
    const authorized =
      request.headers.host === "app.test" &&
      (request.url !== "/auth/google" ||
        request.headers["x-forwarded-for"] === "198.51.100.24");
    response.writeHead(authorized ? 200 : 403);
    response.end();
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    process.env.APP_ORIGIN = "https://app.test";
    process.env.RAILS_API_ORIGIN = `http://127.0.0.1:${server.address().port}`;
    const response = await railsFetch(
      new Request("https://app.test/api/session"),
      "/api/session",
    );
    assert.equal(response.status, 200);
    const authResponse = await railsFetch(
      new Request("https://app.test/auth/google"),
      "/auth/google",
      { clientIp: "198.51.100.24" },
    );
    assert.equal(authResponse.status, 200);
  } finally {
    server.close();
    await once(server, "close");
  }
});

test("the backend can reject a streamed request without waiting for the entire body", async () => {
  const server = createServer((request, response) => {
    request.once("data", () => response.writeHead(413).end());
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  let bodyController;
  const body = new ReadableStream({
    start(controller) {
      bodyController = controller;
      controller.enqueue(new TextEncoder().encode("{"));
    },
  });
  const abort = new AbortController();
  const deadline = Promise.withResolvers();
  const timer = setTimeout(
    () => deadline.reject(new Error("The proxy buffered the entire body")),
    1000,
  );
  try {
    process.env.APP_ORIGIN = "https://app.test";
    process.env.RAILS_API_ORIGIN = `http://127.0.0.1:${server.address().port}`;
    const input = new Request("https://app.test/api/session", {
      method: "POST",
      body,
      duplex: "half",
      signal: abort.signal,
    });
    const result = railsFetch(input, "/api/session");
    result.catch(() => undefined);
    const response = await Promise.race([result, deadline.promise]);
    assert.equal(response.status, 413);
  } finally {
    clearTimeout(timer);
    abort.abort();
    try {
      bodyController.close();
    } catch {}
    server.closeAllConnections();
    server.close();
    await once(server, "close");
  }
});

test("an oversized streamed mutation is rejected before reaching the backend in full", async () => {
  let received = 0;
  const server = createServer((request) => {
    request.on("data", (chunk) => {
      received += chunk.length;
    });
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const timeout = Promise.withResolvers();
  const timer = setTimeout(
    () => timeout.reject(new Error("Request was not bounded")),
    500,
  );
  try {
    process.env.APP_ORIGIN = "https://app.test";
    process.env.RAILS_API_ORIGIN = `http://127.0.0.1:${server.address().port}`;
    const body = new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array(1024 * 1024 + 1));
        controller.close();
      },
    });
    const input = new Request("https://app.test/api/session", {
      method: "POST",
      body,
      duplex: "half",
    });
    const result = railsFetch(input, "/api/session");
    result.catch(() => undefined);
    await assert.rejects(
      Promise.race([result, timeout.promise]),
      (error) => error.name === "RequestBodyTooLarge",
    );
    assert.ok(received < 1024 * 1024 + 1);
  } finally {
    clearTimeout(timer);
    server.closeAllConnections();
    server.close();
    await once(server, "close");
  }
});

test("callback adaptation retains all cookies and never includes provider parameters in its redirect", () => {
  process.env.APP_ORIGIN = "https://app.test";
  const headers = new Headers();
  headers.append(
    "set-cookie",
    "__Host-advocacia_oidc=; Path=/; Secure; HttpOnly; Max-Age=0",
  );
  headers.append(
    "set-cookie",
    "__Host-advocacia_session=opaque; Path=/; Secure; HttpOnly",
  );
  const result = uiRedirect("/convite", new Response(null, { headers }));
  assert.equal(result.status, 303);
  assert.equal(result.headers.get("location"), "https://app.test/convite");
  assert.equal(result.headers.getSetCookie().length, 2);
  assert.equal(result.headers.get("cache-control"), "no-store");
});
