"use client";

import Link from "next/link";
import Image from "next/image";
import headerLogo from "@/assets/header.svg";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { api } from "@/lib/api";
import { destination, useSession } from "./session-provider";
import { AlertBanner, Btn, Icon } from "./ui";

const accessPaths: Record<string, true> = {
  "/": true,
  "/login": true,
  "/verify-email": true,
  "/reset-password": true,
  "/primeiro-acesso": true,
  "/onboarding": true,
  "/vinculos": true,
  "/convite": true,
};
const navigation = [
  { href: "/dashboard", label: "Painel" },
  { href: "/comunicacoes", label: "Comunicações" },
  { href: "/monitoramentos", label: "Monitoramentos" },
  { href: "/equipe", label: "Equipe e grupos", owner: true },
  { href: "/coletas", label: "Execuções de Monitoramento", owner: true },
];

export function ApplicationShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, loading, error, pendingInvitation, refresh, logout } =
    useSession();
  const [signingOut, setSigningOut] = useState(false);
  const [logoutError, setLogoutError] = useState<string | null>(null);
  const accessPage = accessPaths[pathname] === true;
  const administrativePage =
    pathname === "/admin" || pathname.startsWith("/admin/");
  const administrator =
    session?.authenticated && session.platform_admin === true;
  const ready =
    session?.authenticated &&
    (administrativePage
      ? administrator
      : session.onboarded && !session.selection_required && !pendingInvitation);

  const profileKey =
    !administrativePage &&
    session?.authenticated &&
    session.onboarded &&
    session.role === "owner"
      ? `${session.tenant_id}:${session.membership_id}:${session.csrf_token}`
      : null;
  const [profileName, setProfileName] = useState<{
    key: string;
    name: string | null;
  } | null>(null);
  useEffect(() => {
    if (!profileKey) return;
    let current = true;
    api<{ tenant_id: string; profile: { full_name: string } }>(
      "/api/onboarding",
    )
      .then((result) => {
        if (!current) return;
        const name =
          result.tenant_id === session?.tenant_id &&
          typeof result.profile?.full_name === "string"
            ? result.profile.full_name.trim()
            : "";
        setProfileName({ key: profileKey, name: name || null });
      })
      .catch(() => {
        if (current) setProfileName({ key: profileKey, name: null });
      });
    return () => {
      current = false;
    };
  }, [profileKey, session?.tenant_id]);

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

  const accountLabel = profileKey
    ? profileName?.key === profileKey
      ? (profileName.name ?? "Nome indisponível")
      : "Carregando nome…"
    : administrativePage && administrator
      ? "Administradora da plataforma"
      : session?.role === "member"
        ? "Membro da equipe"
        : "Conta autenticada";
  const identity = session?.authenticated ? (
    <div className="flex min-w-0 flex-wrap items-center gap-2">
      <span className="max-w-xs break-words text-sm text-error">
        {accountLabel}
      </span>
      {accessPage &&
        session?.can_create_tenant === true &&
        pathname !== "/onboarding" && (
          <Link href="/onboarding" className="text-xs text-accent underline">
            Concluir meu cadastro
          </Link>
        )}
      <button
        type="button"
        className="text-xs text-muted-foreground underline ml-1 disabled:opacity-40"
        disabled={signingOut}
        onClick={() => void signOut()}
      >
        {signingOut ? "saindo…" : "sair"}
      </button>
    </div>
  ) : null;
  const brand = (
    <Link
      href={
        administrativePage && administrator
          ? "/admin"
          : ready
            ? "/dashboard"
            : "/"
      }
      className="inline-flex shrink-0 items-center"
    >
      <Image
        src={headerLogo}
        alt="Vértice Tecnologia — Central de Processos"
        className="h-10 w-auto object-contain"
        unoptimized
        priority
      />
    </Link>
  );
  const navigationLinks = (
    administrativePage
      ? [
          { href: "/admin", label: "Administração", owner: false },
          ...(session?.can_create_tenant === true
            ? [
                {
                  href: "/onboarding",
                  label: "Concluir meu cadastro",
                  owner: false,
                },
              ]
            : []),
          ...(session?.onboarded
            ? [
                {
                  href: "/dashboard",
                  label: "Ambiente profissional",
                  owner: false,
                },
              ]
            : []),
        ]
      : [
          ...navigation,
          ...(session?.can_create_tenant === true
            ? [
                {
                  href: "/onboarding",
                  label: "Concluir meu cadastro",
                  owner: false,
                },
              ]
            : []),
          ...(administrator
            ? [{ href: "/admin", label: "Administração", owner: false }]
            : []),
        ]
  )
    .filter((item) => !item.owner || session?.role === "owner")
    .map((item) => {
      const active =
        pathname === item.href ||
        pathname.startsWith(`${item.href}/`) ||
        (item.href === "/equipe" && pathname.startsWith("/grupos"));
      return (
        <Link
          key={item.href}
          href={item.href}
          aria-current={active ? "page" : undefined}
          onClick={(event) => {
            const menu = event.currentTarget.closest("details");
            menu?.removeAttribute("open");
            menu?.querySelector("summary")?.focus();
          }}
          className={`flex-shrink-0 px-4 py-2 md:py-3 text-sm font-medium border-b-2 transition-none ${active ? "border-foreground text-foreground" : "border-transparent text-muted-foreground"}`}
        >
          {item.label}
        </Link>
      );
    });
  const messages = (
    <>
      {logoutError && <AlertBanner variant="error">{logoutError}</AlertBanner>}
      {error && (
        <AlertBanner variant="error">
          <p>Não foi possível revalidar sua sessão: {error}</p>
          <button
            type="button"
            className="underline mt-2"
            onClick={() => void refresh().catch(() => undefined)}
          >
            Revalidar sessão
          </button>
        </AlertBanner>
      )}
    </>
  );

  if (accessPage || !ready) {
    return (
      <div className="bg-background min-h-screen font-body">
        <header className="border-b border-border px-4 md:px-8 py-4 flex items-center justify-between gap-3 flex-wrap">
          {brand}
          {identity}
        </header>
        {error && pathname === "/login" && (
          <div className="max-w-sm mx-auto px-4 mt-6">
            <AlertBanner variant="error">{error}</AlertBanner>
            <Btn onClick={() => void refresh().catch(() => undefined)}>
              Revalidar sessão
            </Btn>
          </div>
        )}
        <main id="conteudo" tabIndex={-1}>
          {logoutError && (
            <div className="max-w-xl mx-auto px-4 mt-6">
              <AlertBanner variant="error">{logoutError}</AlertBanner>
            </div>
          )}
          {error && pathname !== "/reset-password" && pathname !== "/login" ? (
            <section className="max-w-sm mx-auto px-4 py-20 flex flex-col gap-6">
              <h1 className="text-2xl font-semibold font-headings">
                Não foi possível abrir sua sessão
              </h1>
              <AlertBanner variant="error">{error}</AlertBanner>
              <Btn onClick={() => void refresh().catch(() => undefined)}>
                Tentar novamente
              </Btn>
              <p className="text-sm text-muted-foreground">
                Se você recebeu um convite, pode abrir novamente o link enviado
                por e-mail.
              </p>
            </section>
          ) : accessPage ? (
            <div
              key={
                pathname === "/reset-password" ||
                pathname === "/login" ||
                pathname === "/primeiro-acesso"
                  ? pathname
                  : (session?.csrf_token ?? "anonymous")
              }
            >
              {children}
            </div>
          ) : (
            <p
              className="max-w-5xl mx-auto px-8 py-8 text-sm text-muted-foreground"
              role="status"
              aria-busy="true"
            >
              {loading
                ? "Consultando sua sessão…"
                : "Redirecionando para seu acesso…"}
            </p>
          )}
        </main>
      </div>
    );
  }

  return (
    <div className="bg-background min-h-screen font-body">
      <header className="bg-background border-b border-border w-full font-body">
        <div className="hidden md:flex items-center justify-between px-8 py-3 border-b border-border gap-4">
          {brand}
          <div className="flex items-center gap-4">
            {!administrativePage && (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Icon i="building-2" size={14} />
                <span
                  className="max-w-48 truncate"
                  title={`Ambiente: ${session.tenant_id}`}
                >
                  Ambiente: {session.tenant_id}
                </span>
                <Link
                  href="/vinculos"
                  className="text-accent underline text-xs ml-1"
                >
                  trocar
                </Link>
              </div>
            )}
            {identity}
          </div>
        </div>
        <div className="flex md:hidden items-center justify-between flex-wrap px-4 py-3 gap-3">
          {brand}
          <details
            key={pathname}
            className="relative ml-auto"
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                event.currentTarget.removeAttribute("open");
                event.currentTarget.querySelector("summary")?.focus();
              }
            }}
          >
            <summary
              aria-label="Menu de navegação"
              className="flex cursor-pointer list-none items-center p-2 text-foreground"
            >
              <Icon i="menu" size={24} />
            </summary>
            <nav
              aria-label="Navegação móvel"
              className="absolute right-0 top-full z-30 flex w-56 flex-col border border-border bg-background py-2"
            >
              {navigationLinks}
            </nav>
          </details>
          <details className="relative ml-auto min-w-0 max-w-full">
            <summary
              aria-label="Menu da conta"
              className="list-none break-words text-sm text-error cursor-pointer"
            >
              {accountLabel}
            </summary>
            <div className="absolute right-0 z-20 w-56 border border-border bg-background p-4 flex flex-col gap-3 text-sm">
              <span className="text-error">{accountLabel}</span>
              {!administrativePage && (
                <Link href="/vinculos" className="text-accent underline">
                  Trocar vínculo
                </Link>
              )}
              <button
                type="button"
                className="text-muted-foreground underline text-left"
                disabled={signingOut}
                onClick={() => void signOut()}
              >
                {signingOut ? "Saindo…" : "Sair"}
              </button>
            </div>
          </details>
        </div>
        <nav
          aria-label="Navegação principal"
          className="hidden items-center overflow-x-auto md:flex md:px-8"
        >
          {navigationLinks}
        </nav>
      </header>
      <main id="conteudo" tabIndex={-1}>
        {(logoutError || error) && (
          <div className="w-full max-w-5xl mx-auto px-4 md:px-8 pt-6 flex flex-col gap-3">
            {messages}
          </div>
        )}
        <div key={session.membership_id}>{children}</div>
      </main>
    </div>
  );
}
