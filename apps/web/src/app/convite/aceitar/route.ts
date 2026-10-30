import type { NextRequest } from "next/server";
import {
  INVITATION_COOKIE,
  failure,
  invitationCookie,
  invitationToken,
  matchesInvitation,
  railsFetch,
  relay,
  sameOrigin,
} from "../../api/transport";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function POST(request: NextRequest): Promise<Response> {
  try {
    if (!sameOrigin(request))
      return failure(
        "invalid_origin",
        "Aceite o convite nesta aplicação.",
        403,
      );
    const token = invitationToken(
      request.cookies.get(INVITATION_COOKIE)?.value,
    );
    if (!token)
      return failure(
        "invitation_missing",
        "Abra novamente o link de convite recebido por e-mail.",
        422,
      );
    if (
      !matchesInvitation(token, request.headers.get("x-invitation-fingerprint"))
    )
      return failure(
        "invitation_context_changed",
        "O convite aberto nesta aba mudou. Abra novamente o link original.",
        409,
      );
    // The original browser Origin and CSRF header are verified by Rails. There is
    // no server-side CSRF bypass and the invitation never returns to JavaScript.
    const upstream = await railsFetch(request, "/api/team/invitations/accept", {
      method: "POST",
      body: JSON.stringify({ token }),
    });
    const response = relay(upstream);
    if (upstream.ok)
      response.headers.append("Set-Cookie", invitationCookie(null));
    return response;
  } catch {
    return failure(
      "backend_unavailable",
      "Não foi possível aceitar o convite. Tente novamente.",
      503,
    );
  }
}
