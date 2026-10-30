"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useState,
  type ReactNode,
} from "react";
import { api, ApiError, setDisplayedSession, withSessionLock } from "@/lib/api";

export type Membership = {
  id: string;
  tenant_id: string;
  role: "owner" | "member";
  expires_at: string | null;
};
export type Session = {
  authenticated: boolean;
  onboarded: boolean;
  csrf_token?: string;
  membership_id?: string | null;
  tenant_id?: string | null;
  role?: "owner" | "member" | null;
  selection_required?: boolean;
  memberships?: Membership[];
};

type SessionContextValue = {
  session: Session | null;
  loading: boolean;
  error: string | null;
  pendingInvitation: boolean;
  invitationMismatch: boolean;
  invitationFingerprint: string | null;
  discardInvitation: () => Promise<void>;
  refresh: () => Promise<Session>;
  logout: () => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | null>(null);
const invitationFingerprintKey = "advocacia:invitation-fingerprint";
let fragmentCapture: Promise<void> | undefined;

async function invitationRequest(
  method = "GET",
  body?: unknown,
): Promise<{ pending?: boolean; fingerprint?: string }> {
  let response: Response;
  try {
    response = await fetch("/convite/preservar", {
      method,
      body: body === undefined ? undefined : JSON.stringify(body),
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin",
      cache: "no-store",
      redirect: "error",
    });
  } catch {
    throw new Error(
      "Não foi possível preservar o convite. Abra novamente o link recebido quando sua conexão estiver disponível.",
    );
  }
  if (!response.ok)
    throw new Error(
      "Não foi possível preservar o convite. Abra novamente o link recebido ou solicite um novo convite ao titular.",
    );
  return response.status === 204 ? {} : response.json();
}

function captureInvitation(): Promise<void> {
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  if (!fragment.has("token")) return fragmentCapture ?? Promise.resolve();
  // Erase the sensitive fragment before any navigation. No storage, URL query,
  // React state, diagnostic output or third-party request ever receives it.
  window.history.replaceState(
    window.history.state,
    "",
    `${window.location.pathname}${window.location.search}`,
  );
  const token = fragment.get("token");
  fragmentCapture = withSessionLock(async () => {
    const result = await invitationRequest("POST", { token });
    if (!result.fingerprint || !/^[0-9a-f]{64}$/.test(result.fingerprint))
      throw new Error("Não foi possível preservar o convite nesta aba.");
    // A fingerprint is not the bearer token and cannot redeem the invitation.
    sessionStorage.setItem(invitationFingerprintKey, result.fingerprint);
  });
  return fragmentCapture;
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pendingInvitation, setPendingInvitation] = useState(false);
  const [invitationMismatch, setInvitationMismatch] = useState(false);
  const [invitationFingerprint, setInvitationFingerprint] = useState<
    string | null
  >(null);

  useLayoutEffect(() => {
    setDisplayedSession(session);
    return () => setDisplayedSession(null);
  }, [session]);

  const refresh = useCallback(
    async () =>
      withSessionLock(async () => {
        try {
          const current = await api<Session>("/api/session");
          const invitation = await invitationRequest();
          setSession(current);
          const localFingerprint = sessionStorage.getItem(
            invitationFingerprintKey,
          );
          const pending =
            invitation.pending === true && localFingerprint !== null;
          if (!invitation.pending && localFingerprint)
            sessionStorage.removeItem(invitationFingerprintKey);
          setPendingInvitation(pending);
          setInvitationFingerprint(pending ? localFingerprint : null);
          setInvitationMismatch(
            pending && localFingerprint !== invitation.fingerprint,
          );
          setError(null);
          return current;
        } catch (reason) {
          setError(
            reason instanceof Error
              ? reason.message
              : "Não foi possível consultar sua sessão.",
          );
          throw reason;
        } finally {
          setLoading(false);
        }
      }),
    [],
  );

  useEffect(() => {
    void captureInvitation()
      .then(refresh)
      .catch((reason: unknown) => {
        setError(
          reason instanceof Error
            ? reason.message
            : "Não foi possível abrir o convite.",
        );
        setLoading(false);
      });
    const invalidate = () =>
      setSession({ authenticated: false, onboarded: false });
    const revalidate = () => {
      void refresh().catch(() => undefined);
    };
    window.addEventListener("advocacia:unauthorized", invalidate);
    window.addEventListener("advocacia:context-changed", revalidate);
    window.addEventListener("focus", revalidate);
    return () => {
      window.removeEventListener("advocacia:unauthorized", invalidate);
      window.removeEventListener("advocacia:context-changed", revalidate);
      window.removeEventListener("focus", revalidate);
    };
  }, [refresh]);

  const discardInvitation = useCallback(async () => {
    await withSessionLock(async () => {
      const local = sessionStorage.getItem(invitationFingerprintKey);
      const current = await invitationRequest();
      if (local && current.pending && current.fingerprint === local)
        await invitationRequest("DELETE");
      sessionStorage.removeItem(invitationFingerprintKey);
    });
    await refresh();
  }, [refresh]);

  const logout = useCallback(async () => {
    try {
      await api<void>("/api/session", { method: "DELETE" });
    } catch (reason) {
      // An already-revoked server session is signed out; never pretend a failed
      // network request revoked an otherwise-live session.
      if (!(reason instanceof ApiError) || reason.status !== 401) throw reason;
    }
    setSession({ authenticated: false, onboarded: false });
    setError(null);
  }, []);

  return (
    <SessionContext.Provider
      value={{
        session,
        loading,
        error,
        pendingInvitation,
        invitationMismatch,
        invitationFingerprint,
        discardInvitation,
        refresh,
        logout,
      }}
    >
      {children}
    </SessionContext.Provider>
  );
}

export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("SessionProvider is required");
  return value;
}

export function destination(
  session: Session,
  pendingInvitation = false,
): string {
  if (pendingInvitation) return "/convite";
  if (!session.authenticated) return "/login";
  if (session.selection_required) return "/vinculos";
  return session.onboarded ? "/dashboard" : "/onboarding";
}
