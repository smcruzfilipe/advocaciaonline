"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { useSession } from "@/components/session-provider";
import { AlertBanner, Btn } from "@/components/ui";
import { api, ApiError } from "@/lib/api";

type Invitation = {
  id: string;
  email: string;
  created_at: string;
  expires_at: string;
};

type InvitationLink = { id: string; link: string; expires_at: string };
type Notice = { variant: "success" | "error" | "info"; text: string };

function formatDate(value: string) {
  return new Date(value).toLocaleString("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  });
}

function mutationError(
  reason: unknown,
  action: "criação" | "reemissão" | "envio",
) {
  if (
    !(reason instanceof ApiError) ||
    reason.status === 0 ||
    reason.status === 408 ||
    reason.status >= 500 ||
    reason.code === "invalid_response"
  ) {
    return action === "envio"
      ? "Não foi possível confirmar o resultado do envio. A mensagem pode ter sido aceita pelo servidor SMTP; isso não confirma a entrega. Você pode copiar o link ou reenviar explicitamente."
      : `Não foi possível confirmar o resultado da ${action}. Atualize a lista e confira o convite antes de tentar novamente.`;
  }
  return reason.message;
}

export function PlatformAdminInvitations() {
  const {
    session,
    loading: sessionLoading,
    error: sessionError,
  } = useSession();
  if (sessionLoading)
    return (
      <p className="mx-auto max-w-5xl px-4 py-8" role="status">
        Validando sessão...
      </p>
    );
  if (!session?.authenticated || session.platform_admin !== true)
    return (
      <p className="mx-auto max-w-5xl px-4 py-8" role="alert">
        {sessionError ?? "Sua sessão não permite administrar convites."}
      </p>
    );
  return <AdminInvitations key={session.csrf_token} />;
}

function AdminInvitations() {
  const [invitations, setInvitations] = useState<Invitation[] | null>(null);
  const [email, setEmail] = useState("");
  const [link, setLink] = useState<InvitationLink | null>(null);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [busy, setBusy] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const working = useRef(false);

  useEffect(() => {
    let active = true;
    api<{ invitations: Invitation[] }>("/api/admin/invitations")
      .then((result) => {
        if (active) setInvitations(result.invitations);
      })
      .catch((reason: unknown) => {
        if (active) {
          setNotice({
            variant: "error",
            text:
              reason instanceof Error
                ? reason.message
                : "Não foi possível consultar os convites.",
          });
        }
      })
      .finally(() => {
        if (active) setInitialLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  async function refreshList() {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const result = await api<{ invitations: Invitation[] }>(
        "/api/admin/invitations",
      );
      setInvitations(result.invitations);
      setLink((current) =>
        current &&
        result.invitations.some(
          (item) =>
            item.id === current.id && item.expires_at === current.expires_at,
        )
          ? current
          : null,
      );
    } catch (reason) {
      setNotice({
        variant: "error",
        text:
          reason instanceof Error
            ? reason.message
            : "Não foi possível consultar os convites.",
      });
    } finally {
      working.current = false;
      setBusy(false);
    }
  }

  async function createInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const created = await api<Invitation>("/api/admin/invitations", {
        method: "POST",
        body: { email },
      });
      setInvitations((current) => [created, ...(current ?? [])]);
      setEmail("");
      setNotice({
        variant: "success",
        text: "Convite criado. Escolha copiar o link ou enviar por e-mail.",
      });
    } catch (reason) {
      setNotice({ variant: "error", text: mutationError(reason, "criação") });
    } finally {
      working.current = false;
      setBusy(false);
    }
  }

  async function copyLink(invitation: Invitation) {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setNotice(null);
    setLink(null);
    try {
      const result = await api<{ link: string; expires_at: string }>(
        `/api/admin/invitations/${encodeURIComponent(invitation.id)}/link`,
      );
      setLink({ id: invitation.id, ...result });
      try {
        await navigator.clipboard.writeText(result.link);
        setNotice({
          variant: "success",
          text: "Link copiado. Compartilhe-o manualmente com a pessoa convidada.",
        });
      } catch {
        setNotice({
          variant: "error",
          text: "Não foi possível copiar para a área de transferência. Selecione e copie o link exibido abaixo.",
        });
      }
    } catch (reason) {
      setNotice({
        variant: "error",
        text:
          reason instanceof Error
            ? reason.message
            : "Não foi possível recuperar o link.",
      });
    } finally {
      working.current = false;
      setBusy(false);
    }
  }

  async function sendEmail(invitation: Invitation) {
    if (working.current) return;
    working.current = true;
    setBusy(true);
    setNotice(null);
    try {
      const result = await api<{ accepted: true; message: string }>(
        `/api/admin/invitations/${encodeURIComponent(invitation.id)}/email`,
        { method: "POST", body: {} },
      );
      setNotice({ variant: "info", text: result.message });
    } catch (reason) {
      setNotice({ variant: "error", text: mutationError(reason, "envio") });
    } finally {
      working.current = false;
      setBusy(false);
    }
  }

  async function reissue(invitation: Invitation) {
    if (
      working.current ||
      !window.confirm(
        `Reemitir o convite para ${invitation.email}? O link anterior será invalidado e um novo prazo será iniciado.`,
      )
    )
      return;
    working.current = true;
    setBusy(true);
    setNotice(null);
    setLink(null);
    try {
      const replacement = await api<Invitation>(
        `/api/admin/invitations/${encodeURIComponent(invitation.id)}/reissue`,
        { method: "POST", body: {} },
      );
      setInvitations((current) =>
        (current ?? []).map((item) =>
          item.id === invitation.id ? replacement : item,
        ),
      );
      setNotice({
        variant: "success",
        text: "Convite reemitido. O link anterior foi invalidado; copie ou envie o novo link.",
      });
    } catch (reason) {
      setNotice({ variant: "error", text: mutationError(reason, "reemissão") });
    } finally {
      working.current = false;
      setBusy(false);
    }
  }

  return (
    <section className="mx-auto flex max-w-5xl flex-col gap-6 px-4 py-8 md:px-8">
      <header className="flex flex-col gap-2">
        <Link
          href="/admin"
          className="self-start text-sm text-accent underline"
        >
          Voltar à administração
        </Link>
        <h1 className="font-headings text-2xl font-semibold">
          Convites de primeiro acesso
        </h1>
        <p className="text-sm text-muted-foreground">
          Crie um convite e escolha como compartilhar o link. Copiar ou reenviar
          não altera o prazo de validade.
        </p>
      </header>

      {notice && (
        <AlertBanner variant={notice.variant}>{notice.text}</AlertBanner>
      )}

      <form
        onSubmit={createInvitation}
        className="flex flex-col gap-4 border border-border p-4"
        aria-busy={busy}
      >
        <h2 className="font-headings text-lg font-semibold">Criar convite</h2>
        <label htmlFor="invitation-email" className="text-sm font-medium">
          E-mail do advogado
        </label>
        <input
          id="invitation-email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          className="min-w-0 w-full border border-border bg-background px-3 py-2 text-sm"
        />
        <Btn
          type="submit"
          disabled={busy || invitations === null}
          className="self-start"
        >
          Criar convite
        </Btn>
      </form>

      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="font-headings text-lg font-semibold">
            Convites ativos
          </h2>
          <Btn
            variant="secondary"
            onClick={refreshList}
            disabled={busy || initialLoading}
          >
            Atualizar lista
          </Btn>
        </div>
        {invitations === null ? (
          <p role="status" className="text-sm">
            {notice?.variant === "error"
              ? "Não foi possível carregar a lista. Use Atualizar lista para tentar novamente."
              : "Carregando convites..."}
          </p>
        ) : invitations.length === 0 ? (
          <p className="text-sm text-muted-foreground">Nenhum convite ativo.</p>
        ) : (
          <ul className="flex flex-col gap-3">
            {invitations.map((invitation) => (
              <li
                key={invitation.id}
                className="flex min-w-0 flex-col gap-3 border border-border p-4"
              >
                <div className="min-w-0 text-sm">
                  <h3 className="break-all font-semibold">
                    {invitation.email}
                  </h3>
                  <p className="mt-1 text-muted-foreground">
                    Criado em {formatDate(invitation.created_at)}
                  </p>
                  <p className="text-muted-foreground">
                    Válido até {formatDate(invitation.expires_at)}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  <Btn
                    variant="secondary"
                    disabled={busy}
                    onClick={() => copyLink(invitation)}
                    aria-label={`Copiar link para ${invitation.email}`}
                  >
                    Copiar link
                  </Btn>
                  <Btn
                    variant="secondary"
                    disabled={busy}
                    onClick={() => sendEmail(invitation)}
                    aria-label={`Enviar convite por e-mail para ${invitation.email}`}
                  >
                    Enviar por e-mail
                  </Btn>
                  <Btn
                    variant="secondary"
                    disabled={busy}
                    onClick={() => reissue(invitation)}
                    aria-label={`Reemitir convite para ${invitation.email}`}
                  >
                    Reemitir
                  </Btn>
                </div>
                {link?.id === invitation.id && (
                  <div className="flex min-w-0 flex-col gap-1">
                    <label
                      htmlFor={`link-${invitation.id}`}
                      className="text-sm font-medium"
                    >
                      Link para compartilhamento manual
                    </label>
                    <input
                      id={`link-${invitation.id}`}
                      readOnly
                      value={link.link}
                      onFocus={(event) => event.currentTarget.select()}
                      className="min-w-0 w-full border border-border bg-background px-3 py-2 text-sm"
                    />
                    <p className="text-xs text-muted-foreground">
                      Válido até {formatDate(link.expires_at)}. Compartilhe
                      apenas com a pessoa convidada.
                    </p>
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
