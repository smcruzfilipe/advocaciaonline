"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import type { AuthorizationGroup } from "../grupos/types";
import { ErrorNotice } from "./admin-ui";
import type { TeamCredential } from "./types";
import CredentialItem from "./credential-item";
import InvitationForm from "./invitation-form";
import { PageShell, SectionHeader } from "@/components/ui";

export default function TeamPage() {
  const [credentials, setCredentials] = useState<TeamCredential[] | null>(null);
  const [groups, setGroups] = useState<AuthorizationGroup[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [groupsError, setGroupsError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [mutating, setMutating] = useState(false);

  const load = useCallback(
    () =>
      Promise.allSettled([
        api<{ credentials: TeamCredential[] }>("/api/team/credentials"),
        api<{ groups: AuthorizationGroup[] }>("/api/authorization/groups"),
      ]).then(([credentialResult, groupResult]) => {
        setError(null);
        if (credentialResult.status === "fulfilled") {
          setCredentials(credentialResult.value.credentials);
        } else {
          setError(credentialResult.reason);
          if (
            credentialResult.reason instanceof ApiError &&
            [401, 403].includes(credentialResult.reason.status)
          )
            setCredentials(null);
        }
        if (groupResult.status === "fulfilled") {
          setGroups(groupResult.value.groups);
          setGroupsError(null);
        } else {
          setGroups(null);
          setGroupsError(groupResult.reason);
          if (
            groupResult.reason instanceof ApiError &&
            [401, 403].includes(groupResult.reason.status)
          ) {
            setCredentials(null);
            setError(groupResult.reason);
          }
        }
        setLoading(false);
      }),
    [],
  );

  useEffect(() => {
    void load();
  }, [load]);

  function reload() {
    setLoading(true);
    return load();
  }

  function updated(credential: TeamCredential) {
    setCredentials(
      (current) =>
        current?.map((row) => (row.id === credential.id ? credential : row)) ??
        null,
    );
  }

  return (
    <PageShell maxWidth="max-w-4xl">
      <header className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Equipe e credenciais
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Convites, validade e acesso da equipe. Administração exclusiva do
            advogado titular.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            className="border border-border px-3 py-2 text-sm bg-background text-foreground"
            href="/grupos"
          >
            Grupos e permissões
          </Link>
          <button
            className="border border-border px-3 py-2 text-sm bg-background text-foreground disabled:opacity-50"
            type="button"
            disabled={loading || mutating}
            onClick={() => {
              void reload();
            }}
          >
            Atualizar lista
          </button>
        </div>
      </header>
      {loading && <p role="status">Carregando credenciais e grupos…</p>}
      {error != null && (
        <ErrorNotice
          error={error}
          onRetry={
            !loading && !mutating
              ? () => {
                  void reload();
                }
              : undefined
          }
        />
      )}
      {error != null && credentials !== null && (
        <p className="border border-border bg-input p-4 text-xs text-muted-foreground">
          A atualização da lista falhou. Os dados abaixo são da última consulta
          concluída; as entradas do formulário foram preservadas.
        </p>
      )}
      {credentials !== null && (
        <>
          <section
            className="mb-10 flex flex-col gap-4"
            id="credentials"
            aria-label="Membros da equipe"
            aria-busy={loading}
          >
            <SectionHeader
              title="Membros da equipe"
              subtitle="Credenciais ativas, pendentes, expiradas e revogadas."
            />
            {groupsError != null && (
              <div className="border border-border bg-input p-4 flex flex-col gap-3 text-sm">
                <p>
                  As credenciais foram carregadas, mas seus grupos não estão
                  disponíveis.
                </p>
                <ErrorNotice
                  error={groupsError}
                  onRetry={
                    !loading && !mutating
                      ? () => {
                          void reload();
                        }
                      : undefined
                  }
                />
              </div>
            )}
            {credentials.length === 0 ? (
              <p>
                Nenhuma credencial de equipe criada. Convide a primeira pessoa
                abaixo.
              </p>
            ) : (
              <ul className="border border-border flex flex-col">
                {credentials.map((credential) => (
                  <CredentialItem
                    key={credential.id}
                    credential={credential}
                    groups={groups}
                    disabled={loading || mutating}
                    onUpdated={updated}
                    onReload={reload}
                    onBusyChange={setMutating}
                  />
                ))}
              </ul>
            )}
          </section>
          <InvitationForm
            groups={groups}
            groupsError={groupsError}
            disabled={loading || mutating}
            onChanged={reload}
            onBusyChange={setMutating}
          />
          <aside
            className="border border-border bg-input p-4 flex flex-col gap-2 text-xs text-muted-foreground leading-relaxed"
            aria-label="Política de validade"
          >
            <p>
              Alterar a escolha de validade não muda o vencimento já efetivo.
              Renovar inicia um novo período a partir da renovação; não soma
              dias ao prazo anterior.
            </p>
            <p>
              Revogar interrompe imediatamente o acesso, inclusive em sessões
              abertas. Uma credencial revogada não pode ser renovada; para
              restabelecer o acesso, crie outra.
            </p>
            <p>
              O link de convite é válido por até 24 horas, limitado pelo
              vencimento da credencial. Reemitir invalida o link anterior sem
              renovar a credencial. A lista não informa a situação de entrega de
              convites anteriores.
            </p>
          </aside>
        </>
      )}
    </PageShell>
  );
}
