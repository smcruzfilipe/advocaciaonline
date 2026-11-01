import {
  failure,
  isApiPath,
  railsFetch,
  relay,
  RequestBodyTooLarge,
  sameOrigin,
  trustedClientIp,
} from "../transport";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type Context = { params: Promise<{ path: string[] }> };

async function forward(request: Request, context: Context): Promise<Response> {
  try {
    const { path } = await context.params;
    const pathname = `/api/${path.map(encodeURIComponent).join("/")}`;
    if (!isApiPath(pathname))
      return failure("not_found", "Recurso não encontrado.", 404);
    const auth = pathname.startsWith("/api/auth/");
    if (auth && (request.method !== "POST" || !sameOrigin(request)))
      return failure("invalid_origin", "Solicitação de acesso inválida.", 403);
    const clientIp = auth ? trustedClientIp(request) : null;
    if (auth && !clientIp)
      return failure(
        "ingress_unavailable",
        "O serviço de acesso está indisponível. Tente novamente em instantes.",
        503,
      );
    const response = relay(
      await railsFetch(
        request,
        `${pathname}${new URL(request.url).search}`,
        clientIp ? { clientIp } : undefined,
      ),
    );
    // A delayed lookup of a revoked session must not erase a newer login cookie.
    // Rails only deletes stale cookies on this GET; logout still forwards its deletion.
    if (pathname === "/api/session" && request.method === "GET")
      response.headers.delete("Set-Cookie");
    return response;
  } catch (error) {
    if (error instanceof RequestBodyTooLarge)
      return failure(
        "request_too_large",
        "Os dados enviados excedem o limite permitido.",
        413,
      );
    const reading = ["GET", "HEAD", "OPTIONS"].includes(request.method);
    return failure(
      "backend_unavailable",
      reading
        ? "Não foi possível conectar ao servidor de dados. Tente novamente."
        : "Não foi possível confirmar o resultado. Atualize a lista e verifique se a operação já foi concluída antes de tentar novamente.",
      503,
    );
  }
}

export const GET = forward;
export const HEAD = forward;
export const POST = forward;
export const PATCH = forward;
export const PUT = forward;
export const DELETE = forward;
