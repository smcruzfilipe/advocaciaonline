"use client";

import Link from "next/link";
import { useState } from "react";
import { api, ApiError } from "@/lib/api";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { destination, useSession } from "@/components/session-provider";

export default function InvitationPage() {
  const {
    session,
    loading,
    pendingInvitation,
    invitationMismatch,
    invitationFingerprint,
    discardInvitation,
    refresh,
    logout,
  } = useSession();
  const [working, setWorking] = useState<
    "accept" | "discard" | "account" | null
  >(null);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function accept() {
    if (working || invitationMismatch || !invitationFingerprint) return;
    setWorking("accept");
    setError(null);
    try {
      await api("/convite/aceitar", {
        method: "POST",
        body: {},
        invitationFingerprint,
      });
      setMessage("Convite aceito. Abrindo o ambiente da equipe…");
      navigateAfterIdentityChange("/dashboard");
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível aceitar o convite.",
      );
      if (
        reason instanceof ApiError &&
        reason.code === "invitation_context_changed"
      )
        void refresh().catch(() => undefined);
      setWorking(null);
    }
  }

  async function discard() {
    if (working) return;
    setWorking("discard");
    setError(null);
    try {
      await discardInvitation();
      setMessage(
        "Convite descartado nesta aba. O link recebido por e-mail não foi revogado.",
      );
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível descartar o convite.",
      );
    } finally {
      setWorking(null);
    }
  }

  async function changeAccount() {
    if (working) return;
    setWorking("account");
    setError(null);
    try {
      await logout();
      navigateAfterIdentityChange("/auth/google");
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível sair da conta atual.",
      );
      setWorking(null);
    }
  }

  return (
    <section
      className="page access-wide stack"
      aria-busy={loading || Boolean(working)}
    >
      <header className="stack">
        <span className="eyebrow">Acesso de equipe</span>
        <h1>Convite para a equipe</h1>
        <p className="muted">
          O acesso só será concedido após o aceite com a conta Google do e-mail
          convidado.
        </p>
      </header>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {message && (
        <p className="notice" role="status">
          {message}
        </p>
      )}
      {loading ? (
        <p role="status">Consultando o convite e sua sessão…</p>
      ) : !pendingInvitation ? (
        <div className="panel stack">
          <h2>Nenhum convite aberto</h2>
          <p>
            Abra o link recebido por e-mail. Se você já o abriu há mais de dez
            minutos, abra-o novamente: a cópia temporária deste navegador é
            apagada automaticamente.
          </p>
          <p>
            O link pode ter vencido, sido utilizado ou revogado. Nesses casos,
            solicite um novo convite ao titular.
          </p>
          <Link
            className="button-secondary"
            href={session ? destination(session) : "/login"}
          >
            {session?.authenticated
              ? "Continuar para meu acesso"
              : "Ir para o login"}
          </Link>
        </div>
      ) : invitationMismatch ? (
        <div className="panel stack" role="alert">
          <h2>O convite aberto nesta aba mudou</h2>
          <p>
            Outro convite foi aberto em outra aba. Para não aceitar o ambiente
            errado, abra novamente o link original nesta aba.
          </p>
          <button
            className="button-secondary"
            type="button"
            disabled={Boolean(working)}
            onClick={() => void discard()}
          >
            Ignorar convite nesta aba
          </button>
        </div>
      ) : (
        <div className="panel stack">
          <h2>
            {session?.authenticated
              ? "Confirme o aceite"
              : "Entre para aceitar o convite"}
          </h2>
          <p>
            O convite permanece protegido neste navegador por até dez minutos e
            não é incluído na URL de login.
          </p>
          {session?.authenticated ? (
            <>
              <p>
                Confirme que você entrou com o e-mail que recebeu o convite. O
                servidor verificará a conta, o prazo e a disponibilidade da
                credencial.
              </p>
              <div className="row">
                <button
                  className="button"
                  type="button"
                  disabled={Boolean(working)}
                  onClick={() => void accept()}
                >
                  {working === "accept"
                    ? "Aceitando…"
                    : "Aceitar convite e entrar na equipe"}
                </button>
                <button
                  className="button-secondary"
                  type="button"
                  disabled={Boolean(working)}
                  onClick={() => void changeAccount()}
                >
                  {working === "account"
                    ? "Saindo da conta atual…"
                    : "Entrar com outra conta Google"}
                </button>
              </div>
            </>
          ) : (
            <a className="button" href="/auth/google">
              Continuar com o Google
            </a>
          )}
          <button
            className="button-secondary"
            type="button"
            disabled={Boolean(working)}
            onClick={() => void discard()}
          >
            {working === "discard"
              ? "Descartando…"
              : "Descartar convite neste navegador"}
          </button>
        </div>
      )}
      <p className="muted small">
        Aceitar o convite não reinicia a validade da credencial de equipe.
        Vencimento e revogação são aplicados pelo servidor em cada operação.
      </p>
    </section>
  );
}
