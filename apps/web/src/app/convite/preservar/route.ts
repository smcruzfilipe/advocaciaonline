import type { NextRequest } from "next/server";
import {
  INVITATION_COOKIE,
  failure,
  invitationCookie,
  invitationFingerprint,
  invitationToken,
  privateHeaders,
  sameOrigin,
} from "../../api/transport";
import { readInvitationBody } from "./invitation-body";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest): Promise<Response> {
  if (request.headers.get("sec-fetch-site") === "cross-site")
    return failure("invalid_origin", "Abra o convite nesta aplicação.", 403);
  const token = invitationToken(request.cookies.get(INVITATION_COOKIE)?.value);
  return Response.json(
    token
      ? { pending: true, fingerprint: invitationFingerprint(token) }
      : { pending: false },
    { headers: privateHeaders() },
  );
}

export async function POST(request: Request): Promise<Response> {
  try {
    if (!sameOrigin(request))
      return failure("invalid_origin", "Abra o convite nesta aplicação.", 403);
    if (
      request.headers.get("content-type")?.split(";")[0] !== "application/json"
    )
      return failure("invalid_content_type", "Envie o convite em JSON.", 415);
    const input = await readInvitationBody(request);
    const token = invitationToken(
      input && typeof input === "object" && "token" in input
        ? input.token
        : null,
    );
    if (!token)
      return failure(
        "invalid_invitation",
        "Este link de convite não é válido. Solicite um novo convite ao titular.",
        422,
      );
    const headers = privateHeaders();
    headers.append("Set-Cookie", invitationCookie(token));
    return Response.json(
      { pending: true, fingerprint: invitationFingerprint(token) },
      { headers },
    );
  } catch {
    return failure(
      "invalid_invitation",
      "Não foi possível preservar este convite. Abra novamente o link recebido.",
      422,
    );
  }
}

export async function DELETE(request: Request): Promise<Response> {
  try {
    if (!sameOrigin(request))
      return failure("invalid_origin", "Abra o convite nesta aplicação.", 403);
    const headers = privateHeaders();
    headers.append("Set-Cookie", invitationCookie(null));
    return new Response(null, { status: 204, headers });
  } catch {
    return failure(
      "backend_unavailable",
      "A configuração de acesso está indisponível.",
      503,
    );
  }
}
