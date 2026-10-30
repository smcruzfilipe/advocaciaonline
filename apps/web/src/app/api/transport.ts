import { createHash, timingSafeEqual } from "node:crypto";
import { isIP } from "node:net";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { Readable, Transform } from "node:stream";
import type { ReadableStream as NodeReadableStream } from "node:stream/web";

export const INVITATION_COOKIE = "__Host-advocacia_invitation";
export const INVITATION_LIFETIME = 600;
export const MAX_REQUEST_BODY_BYTES = 1024 * 1024;

export class RequestBodyTooLarge extends Error {
  constructor() {
    super("Request body exceeds the web proxy limit");
    this.name = "RequestBodyTooLarge";
  }
}

function configuredOrigin(name: string, protocols: string[]): URL {
  const value = process.env[name];
  if (!value) throw new Error("Missing server origin configuration");
  const url = new URL(value);
  if (
    !protocols.includes(url.protocol) ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname !== "/"
  ) {
    throw new Error("Invalid server origin configuration");
  }
  return url;
}

export function publicOrigin(): URL {
  return configuredOrigin("APP_ORIGIN", ["https:"]);
}

export function isApiPath(path: string): boolean {
  return /^\/api\/(?:session(?:\/membership)?|onboarding|courts|dashboard|communications(?:\/[A-Za-z0-9_-]+)?|monitorings\/(?:lawyer|(?:parties|processes)(?:\/[A-Za-z0-9_-]+)?)|team\/(?:invitations\/accept|credentials(?:\/[A-Za-z0-9_-]+(?:\/(?:renewal|invitation))?)?)|authorization\/(?:catalog|groups(?:\/[A-Za-z0-9_-]+(?:\/rules(?:\/[A-Za-z0-9_-]+)?|\/memberships\/[A-Za-z0-9_-]+)?)?)|collection-runs(?:\/[A-Za-z0-9_-]+\/(?:jobs|events|execution))?)$/.test(
    path,
  );
}

export function privateHeaders(): Headers {
  return new Headers({
    "Cache-Control": "no-store",
    Pragma: "no-cache",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
  });
}

export function failure(
  code: string,
  message: string,
  status: number,
): Response {
  return Response.json(
    { error: { code, message } },
    { status, headers: privateHeaders() },
  );
}

export function sameOrigin(request: Request): boolean {
  return (
    request.headers.get("origin") === publicOrigin().origin &&
    request.headers.get("sec-fetch-site") !== "cross-site"
  );
}

export function forwardedHeaders(request: Request): Headers {
  const origin = publicOrigin();
  const headers = new Headers({
    Accept: "application/json",
    Host: origin.host,
    "X-Forwarded-Host": origin.host,
    "X-Forwarded-Proto": "https",
  });
  for (const name of [
    "origin",
    "content-type",
    "x-csrf-token",
    "sec-fetch-site",
    "sec-fetch-mode",
    "sec-fetch-dest",
  ]) {
    const value = request.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  // The frontend-only invitation must never be sent as part of Rails' cookie jar.
  const cookies = (request.headers.get("cookie") ?? "")
    .split(";")
    .map((part) => part.trim())
    .filter((part) => /^__Host-advocacia_(?:session|oidc)=/.test(part));
  if (cookies.length) headers.set("cookie", cookies.join("; "));
  return headers;
}

export function trustedClientIp(request: Request): string | null {
  const expected = process.env.AUTH_INGRESS_SECRET;
  const provided = request.headers.get("x-advocacia-ingress-secret");
  const address = request.headers.get("x-advocacia-client-ip");
  if (
    !expected ||
    Buffer.byteLength(expected) < 32 ||
    !provided ||
    !address ||
    !isIP(address)
  )
    return null;
  const expectedDigest = createHash("sha256").update(expected).digest();
  const providedDigest = createHash("sha256").update(provided).digest();
  return timingSafeEqual(expectedDigest, providedDigest) ? address : null;
}

export async function railsFetch(
  request: Request,
  path: string,
  options?: { method?: string; body?: string; clientIp?: string },
): Promise<Response> {
  const upstream = configuredOrigin("RAILS_API_ORIGIN", ["http:", "https:"]);
  const target = new URL(path, upstream);
  if (
    target.origin !== upstream.origin ||
    (!isApiPath(target.pathname) &&
      !["/auth/google", "/auth/google/callback"].includes(target.pathname))
  ) {
    throw new Error("Invalid backend resource");
  }
  const method = options?.method ?? request.method;
  const send = target.protocol === "https:" ? httpsRequest : httpRequest;
  const headers = forwardedHeaders(request);
  if (options?.clientIp) {
    if (target.pathname !== "/auth/google" || !isIP(options.clientIp))
      throw new Error("Invalid client address");
    headers.set("X-Forwarded-For", options.clientIp);
  }
  const { promise, resolve, reject } = Promise.withResolvers<Response>();
  let bodyStream: Readable | undefined;
  let bodyLimit: Transform | undefined;
  const outgoing = send(
    target,
    {
      method,
      headers: Object.fromEntries(headers),
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(20_000)]),
    },
    (incoming) => {
      if (bodyStream && !bodyStream.readableEnded) {
        bodyStream.unpipe(bodyLimit);
        bodyLimit?.unpipe(outgoing);
        bodyLimit?.destroy();
        bodyStream.destroy();
      }
      try {
        const headers = new Headers();
        for (let i = 0; i < incoming.rawHeaders.length; i += 2)
          headers.append(incoming.rawHeaders[i], incoming.rawHeaders[i + 1]);
        const status = incoming.statusCode ?? 502;
        const responseBody = [204, 205, 304].includes(status)
          ? null
          : (Readable.toWeb(incoming, {
              strategy: {
                highWaterMark: 64 * 1024,
                size: (chunk) => (chunk as Uint8Array).byteLength,
              },
            }) as ReadableStream);
        resolve(new Response(responseBody, { status, headers }));
      } catch (error) {
        incoming.destroy();
        reject(error);
      }
    },
  );
  outgoing.on("error", (error) => {
    bodyLimit?.destroy();
    bodyStream?.destroy();
    reject(error);
  });
  if (method === "GET" || method === "HEAD") outgoing.end();
  else if (options?.body !== undefined) outgoing.end(options.body);
  else if (request.body) {
    bodyStream = Readable.fromWeb(request.body as NodeReadableStream);
    let bytes = 0;
    bodyLimit = new Transform({
      transform(chunk: Buffer, _encoding, callback) {
        bytes += chunk.byteLength;
        callback(
          bytes > MAX_REQUEST_BODY_BYTES ? new RequestBodyTooLarge() : null,
          chunk,
        );
      },
    });
    bodyStream.on("error", (error) => outgoing.destroy(error));
    bodyLimit.on("error", (error) => {
      bodyStream?.destroy();
      outgoing.destroy(error);
    });
    bodyStream.pipe(bodyLimit).pipe(outgoing);
  } else outgoing.end();
  return promise;
}

export function responseHeaders(upstream: Response): Headers {
  const headers = privateHeaders();
  for (const name of ["content-type", "retry-after"]) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  // A comma split would corrupt Expires and silently lose one of the OAuth cookies.
  for (const cookie of upstream.headers.getSetCookie())
    headers.append("Set-Cookie", cookie);
  return headers;
}

export function relay(upstream: Response): Response {
  if (upstream.status >= 300 && upstream.status < 400) {
    return failure(
      "unexpected_backend_redirect",
      "O servidor de dados retornou uma resposta inesperada.",
      502,
    );
  }
  return new Response(
    upstream.status === 204 || upstream.status === 205 ? null : upstream.body,
    { status: upstream.status, headers: responseHeaders(upstream) },
  );
}

export function invitationToken(value: unknown): string | null {
  return typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value)
    ? value
    : null;
}

export function invitationFingerprint(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function matchesInvitation(
  token: string,
  fingerprint: string | null,
): boolean {
  if (!fingerprint || !/^[0-9a-f]{64}$/.test(fingerprint)) return false;
  return timingSafeEqual(
    Buffer.from(invitationFingerprint(token), "hex"),
    Buffer.from(fingerprint, "hex"),
  );
}

export function invitationCookie(value: string | null): string {
  return `${INVITATION_COOKIE}=${value ?? ""}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${value ? INVITATION_LIFETIME : 0}`;
}

export function safeGoogleRedirect(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.origin === "https://accounts.google.com" &&
      !url.username &&
      !url.password &&
      url.pathname === "/o/oauth2/v2/auth"
    );
  } catch {
    return false;
  }
}

export function sessionDestination(
  session: {
    authenticated?: boolean;
    selection_required?: boolean;
    onboarded?: boolean;
  },
  pendingInvitation = false,
): string {
  if (!session.authenticated) return "/login";
  if (pendingInvitation) return "/convite";
  if (session.selection_required) return "/vinculos";
  return session.onboarded ? "/dashboard" : "/onboarding";
}

export function uiRedirect(path: string, upstream?: Response): Response {
  const headers = upstream ? responseHeaders(upstream) : privateHeaders();
  headers.delete("content-type");
  headers.set("Location", new URL(path, publicOrigin()).href);
  return new Response(null, { status: 303, headers });
}
