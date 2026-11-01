"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { useSession } from "@/components/session-provider";
import { AlertBanner, Badge, Btn, Icon } from "@/components/ui";

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
      <section className="mx-auto max-w-lg px-4 py-12 sm:px-0" aria-busy="true">
        <h1 className="mb-1 text-2xl font-semibold">Selecionar vínculo</h1>
        <p className="text-sm text-muted-foreground" role="status">
          Consultando os vínculos disponíveis…
        </p>
      </section>
    );
  const memberships = session.memberships ?? [];
  return (
    <section className="mx-auto flex w-full max-w-lg flex-col gap-6 px-4 py-12 sm:px-0">
      <header>
        <h1 className="mb-1 font-headings text-2xl font-semibold text-foreground">
          Selecionar vínculo
        </h1>
        <p className="text-sm text-muted-foreground">
          Escolha em qual contexto profissional você quer trabalhar agora.
        </p>
      </header>
      {error && <AlertBanner variant="error">{error}</AlertBanner>}
      {memberships.length === 0 ? (
        <div className="flex flex-col gap-4 border border-border p-5 text-sm">
          <h2 className="font-semibold">Nenhum vínculo disponível</h2>
          <p>
            Seu acesso de equipe pode ter vencido ou sido revogado. Peça ao
            titular uma renovação ou um novo convite. O login não restabelece a
            credencial.
          </p>
          <p>
            Se você é advogado e quer criar seu próprio ambiente, cadastre seu
            perfil profissional.
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <Link
              className="bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
              href="/onboarding"
            >
              Cadastrar perfil profissional
            </Link>
            <Link className="text-xs text-accent underline" href="/convite">
              Abrir convite recebido
            </Link>
          </div>
        </div>
      ) : (
        <form
          className="flex flex-col gap-6"
          onSubmit={(event) => void selectMembership(event)}
          aria-busy={saving}
        >
          <fieldset className="min-w-0 border border-border" disabled={saving}>
            <legend className="sr-only">
              Vínculos disponíveis (obrigatório)
            </legend>
            {memberships.map((membership) => (
              <label
                className={`flex cursor-pointer items-center gap-3 border-b border-border px-5 py-4 last:border-b-0 ${selectedId === membership.id ? "bg-secondary" : "bg-background"}`}
                key={membership.id}
              >
                <input
                  type="radio"
                  name="membership"
                  value={membership.id}
                  checked={selectedId === membership.id}
                  onChange={() => setSelected(membership.id)}
                  required
                />
                <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                  <span className="flex flex-wrap items-center gap-2 text-sm font-medium text-foreground">
                    <Icon
                      i={membership.role === "owner" ? "user" : "building-2"}
                      size={15}
                    />
                    {membership.role === "owner"
                      ? "Titular — ambiente próprio"
                      : "Membro da equipe"}
                    {session.membership_id === membership.id && (
                      <Badge label="Atual" variant="active" />
                    )}
                  </span>
                  <span className="ml-5 break-all text-xs text-muted-foreground">
                    Ambiente: {membership.tenant_id}
                  </span>
                  <span className="ml-5 text-xs text-muted-foreground">
                    {expiration(membership.expires_at)}
                  </span>
                </span>
              </label>
            ))}
          </fieldset>
          <div className="flex flex-wrap items-center gap-3">
            <Btn type="submit" disabled={!selectedId || saving}>
              {saving ? "Selecionando…" : "Continuar neste vínculo"}
            </Btn>
            {session.onboarded && (
              <Link className="text-xs text-accent underline" href="/dashboard">
                Voltar ao ambiente atual
              </Link>
            )}
          </div>
        </form>
      )}
      <p className="text-xs text-muted-foreground">
        Cada vínculo mantém seus próprios dados e permissões. Ao trocar de
        vínculo, o servidor valida novamente seu acesso.
      </p>
    </section>
  );
}
