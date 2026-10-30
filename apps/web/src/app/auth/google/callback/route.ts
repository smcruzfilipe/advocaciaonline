import type { NextRequest } from "next/server";
import {
  INVITATION_COOKIE,
  invitationToken,
  privateHeaders,
  railsFetch,
  sessionDestination,
  uiRedirect,
} from "../../../api/transport";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: NextRequest): Promise<Response> {
  let upstream: Response | undefined;
  try {
    // Rails consumes state, browser cookie, code and provider errors itself.
    // Never return those parameters in Location, the HTML body or diagnostics.
    upstream = await railsFetch(
      request,
      `/auth/google/callback${request.nextUrl.search}`,
    );
    if (!upstream.ok)
      return uiRedirect("/login?erro=google_login_failed", upstream);
    const session: unknown = await upstream.json();
    if (
      !session ||
      typeof session !== "object" ||
      !("authenticated" in session) ||
      session.authenticated !== true
    ) {
      return uiRedirect("/login?erro=google_login_failed", upstream);
    }
    const pending =
      invitationToken(request.cookies.get(INVITATION_COOKIE)?.value) !== null;
    const target = sessionDestination(
      {
        authenticated: true,
        onboarded: "onboarded" in session && session.onboarded === true,
        selection_required:
          "selection_required" in session &&
          session.selection_required === true,
      },
      pending,
    );
    return uiRedirect(target, upstream);
  } catch {
    try {
      return uiRedirect("/login?erro=backend_unavailable", upstream);
    } catch {
      return new Response("A configuração de acesso está indisponível.", {
        status: 503,
        headers: privateHeaders(),
      });
    }
  }
}
