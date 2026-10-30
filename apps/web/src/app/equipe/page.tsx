"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import type { AuthorizationGroup } from "../grupos/types";
import { ErrorNotice } from "./admin-ui";
import type { TeamCredential } from "./types";
import CredentialItem from "./credential-item";
import InvitationForm from "./invitation-form";
import styles from "./admin.module.css";

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
    <div className="page stack">
      <header className={styles.header}>
        <div className="stack">
          <h1>Equipe e credenciais</h1>
          <p className="muted">
            Convites, validade e acesso da equipe. Administração exclusiva do
            advogado titular.
          </p>
        </div>
        <div className="row">
          <Link className="button-secondary" href="/grupos">
            Grupos e permissões
          </Link>
          <button
            className="button-secondary"
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
        <p className="notice">
          A atualização da lista falhou. Os dados abaixo são da última consulta
          concluída; as entradas do formulário foram preservadas.
        </p>
      )}
      {credentials !== null && (
        <>
          <section
            className="panel stack"
            id="credentials"
            aria-labelledby="credentials-heading"
            aria-busy={loading}
          >
            <h2 id="credentials-heading">Credenciais da equipe</h2>
            <p className="muted">
              Datas em UTC. A escolha de validade e o vencimento vigente são
              apresentados separadamente.
            </p>
            {groupsError != null && (
              <div className="notice">
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
              <ul className={styles.list}>
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
          <aside className="notice stack" aria-label="Política de validade">
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
    </div>
  );
}
