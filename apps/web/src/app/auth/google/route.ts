import {
  failure,
  privateHeaders,
  railsFetch,
  responseHeaders,
  safeGoogleRedirect,
  trustedClientIp,
  uiRedirect,
} from "../../api/transport";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: Request): Promise<Response> {
  try {
    if (request.headers.get("sec-fetch-site") === "cross-site") {
      return failure("invalid_origin", "Inicie o login nesta aplicação.", 403);
    }
    const clientIp = trustedClientIp(request);
    if (!clientIp)
      return failure(
        "trusted_ingress_required",
        "A entrada de autenticação não está configurada com segurança.",
        503,
      );
    const upstream = await railsFetch(request, "/auth/google", { clientIp });
    const location = upstream.headers.get("location");
    if (
      upstream.status >= 300 &&
      upstream.status < 400 &&
      location &&
      safeGoogleRedirect(location)
    ) {
      const headers = responseHeaders(upstream);
      headers.delete("content-type");
      headers.set("Location", location);
      return new Response(null, { status: 302, headers });
    }
    return uiRedirect(
      upstream.status === 429
        ? "/login?erro=rate_limited"
        : "/login?erro=google_login_failed",
      upstream,
    );
  } catch {
    // Do not include upstream URLs, OAuth state or provider errors in this response.
    try {
      return uiRedirect("/login?erro=backend_unavailable");
    } catch {
      return Response.json(
        {
          error: {
            code: "backend_unavailable",
            message: "A configuração de acesso está indisponível.",
          },
        },
        { status: 503, headers: privateHeaders() },
      );
    }
  }
}
