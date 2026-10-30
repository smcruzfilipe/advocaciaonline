"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { useSession } from "@/components/session-provider";

function expiration(value: string | null): string {
  return value === null
    ? "Sem expiração por prazo"
    : `Válido até ${new Date(value).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })} (Brasília)`;
}

export default function MembershipsPage() {
  const router = useRouter();
  const { session, loading, pendingInvitation, refresh } = useSession();
  const [selected, setSelected] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const selectedId = selected || session?.membership_id || "";

  useEffect(() => {
    if (loading || !session) return;
    if (pendingInvitation) router.replace("/convite");
    else if (!session.authenticated) router.replace("/login");
  }, [loading, pendingInvitation, router, session]);

  async function selectMembership(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving || !selectedId) return;
    setSaving(true);
    setError(null);
    try {
      await api("/api/session/membership", {
        method: "PATCH",
        body: { membership_id: selectedId },
      });
      navigateAfterIdentityChange("/dashboard");
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível selecionar este vínculo.",
      );
      setSaving(false);
      void refresh().catch(() => undefined);
    }
  }

  if (loading || !session?.authenticated || pendingInvitation)
    return (
      <section className="page access-page" aria-busy="true">
        <h1>Seus vínculos</h1>
        <p role="status">Consultando os vínculos disponíveis…</p>
      </section>
    );
  const memberships = session.memberships ?? [];
  return (
    <section className="page access-wide stack">
      <header className="stack">
        <span className="eyebrow">Contexto de trabalho</span>
        <h1>Selecione seu vínculo</h1>
        <p className="muted">
          Escolha em qual ambiente deseja trabalhar. Somente os vínculos
          disponíveis para sua conta Google são apresentados.
        </p>
      </header>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {memberships.length === 0 ? (
        <div className="panel stack">
          <h2>Nenhum vínculo disponível</h2>
          <p>
            Seu acesso de equipe pode ter vencido ou sido revogado. Peça ao
            titular uma renovação ou um novo convite. O login Google não
            restabelece a credencial.
          </p>
          <p>
            Se você é advogado e quer criar seu próprio ambiente, cadastre seu
            perfil profissional.
          </p>
          <div className="row">
            <Link className="button" href="/onboarding">
              Cadastrar perfil profissional
            </Link>
            <Link href="/convite">Abrir convite recebido</Link>
          </div>
        </div>
      ) : (
        <form
          className="stack"
          onSubmit={(event) => void selectMembership(event)}
          aria-busy={saving}
        >
          <fieldset className="stack" disabled={saving}>
            <legend>Vínculos disponíveis (obrigatório)</legend>
            {memberships.map((membership) => (
              <label className="membership-option" key={membership.id}>
                <input
                  type="radio"
                  name="membership"
                  value={membership.id}
                  checked={selectedId === membership.id}
                  onChange={() => setSelected(membership.id)}
                  required
                />
                <span className="stack">
                  <strong>
                    {membership.role === "owner"
                      ? "Titular — ambiente próprio"
                      : "Membro da equipe"}
                  </strong>
                  <span className="identifier">
                    Ambiente: {membership.tenant_id}
                  </span>
                  <span className="muted small">
                    {expiration(membership.expires_at)}
                  </span>
                  {session.membership_id === membership.id && (
                    <span className="badge">Vínculo atual</span>
                  )}
                </span>
              </label>
            ))}
          </fieldset>
          <div className="row">
            <button
              type="submit"
              className="button"
              disabled={!selectedId || saving}
            >
              {saving ? "Selecionando…" : "Continuar neste vínculo"}
            </button>
            {session.onboarded && (
              <Link href="/dashboard">Voltar ao ambiente atual</Link>
            )}
          </div>
        </form>
      )}
      <p className="muted small">
        Cada vínculo mantém seus próprios dados e permissões. Ao trocar de
        vínculo, o servidor valida novamente seu acesso.
      </p>
    </section>
  );
}
