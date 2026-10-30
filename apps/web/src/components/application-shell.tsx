"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { destination, useSession } from "./session-provider";

const accessPaths: Record<string, true> = {
  "/": true,
  "/login": true,
  "/onboarding": true,
  "/vinculos": true,
  "/convite": true,
};
const navigation = [
  { href: "/dashboard", label: "Visão geral" },
  { href: "/comunicacoes", label: "Comunicações" },
  { href: "/monitoramentos", label: "Monitoramentos" },
  { href: "/equipe", label: "Equipe", owner: true },
  { href: "/grupos", label: "Grupos de acesso", owner: true },
  { href: "/coletas", label: "Coletas e Escrevente", owner: true },
];

export function ApplicationShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, loading, error, pendingInvitation, refresh, logout } =
    useSession();
  const [signingOut, setSigningOut] = useState(false);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const accessPage = accessPaths[pathname] === true;
  const ready =
    session?.authenticated &&
    session.onboarded &&
    !session.selection_required &&
    !pendingInvitation;

  useEffect(() => {
    if (!accessPage && !loading && !error && !ready && session)
      router.replace(destination(session, pendingInvitation));
  }, [accessPage, error, loading, pendingInvitation, ready, router, session]);

  async function signOut() {
    setSigningOut(true);
    setLogoutError(null);
    try {
      await logout();
      navigateAfterIdentityChange("/login");
    } catch (reason) {
      setLogoutError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível sair. Tente novamente.",
      );
      setSigningOut(false);
    }
  }

  const identity = session?.authenticated ? (
    <div className="session-summary">
      <span>Conta Google autenticada</span>
      {session.role && (
        <strong>
          {session.role === "owner" ? "Titular" : "Membro da equipe"}
        </strong>
      )}
      <button
        className="button-secondary"
        type="button"
        disabled={signingOut}
        onClick={() => void signOut()}
      >
        {signingOut ? "Saindo…" : "Sair"}
      </button>
    </div>
  ) : null;

  if (accessPage || !ready) {
    return (
      <>
        <header className="access-header">
          <Link className="brand" href="/">
            Advocacia Online
          </Link>
          {identity}
        </header>
        <main id="conteudo" tabIndex={-1}>
          {logoutError && (
            <p className="error page" role="alert">
              {logoutError}
            </p>
          )}
          {error ? (
            <section className="page access-page stack">
              <h1>Não foi possível abrir sua sessão</h1>
              <p className="error" role="alert">
                {error}
              </p>
              <button
                className="button"
                type="button"
                onClick={() => void refresh().catch(() => undefined)}
              >
                Tentar novamente
              </button>
              <p className="muted">
                Se você recebeu um convite, pode abrir novamente o link enviado
                por e-mail.
              </p>
            </section>
          ) : accessPage ? (
            <div key={session?.csrf_token ?? "anonymous"}>{children}</div>
          ) : (
            <div className="page" role="status" aria-busy="true">
              {loading
                ? "Consultando sua sessão…"
                : "Redirecionando para seu acesso…"}
            </div>
          )}
        </main>
      </>
    );
  }

  return (
    <div className="app-layout">
      <header className="app-header">
        <Link className="brand" href="/dashboard">
          Advocacia Online
        </Link>
        {identity}
      </header>
      <aside className="app-sidebar">
        <nav aria-label="Navegação principal">
          <ul>
            {navigation
              .filter((item) => !item.owner || session.role === "owner")
              .map((item) => (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    aria-current={
                      pathname === item.href ||
                      pathname.startsWith(`${item.href}/`)
                        ? "page"
                        : undefined
                    }
                  >
                    {item.label}
                  </Link>
                </li>
              ))}
          </ul>
        </nav>
        <div className="tenant-context stack">
          <span className="eyebrow">Vínculo selecionado</span>
          <strong>
            {session.role === "owner"
              ? "Seu ambiente profissional"
              : "Ambiente da equipe"}
          </strong>
          <span className="muted identifier">
            Identificador: {session.tenant_id}
          </span>
          <Link href="/vinculos">Trocar vínculo</Link>
        </div>
      </aside>
      <main className="app-main" id="conteudo" tabIndex={-1}>
        {logoutError && (
          <p className="error" role="alert">
            {logoutError}
          </p>
        )}
        {error && (
          <div className="error" role="alert">
            <p>Não foi possível revalidar sua sessão: {error}</p>
            <button
              className="button-secondary"
              onClick={() => void refresh().catch(() => undefined)}
            >
              Revalidar sessão
            </button>
          </div>
        )}
        <div key={session.membership_id}>{children}</div>
      </main>
    </div>
  );
}
