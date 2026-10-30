"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { ErrorNotice } from "../equipe/admin-ui";
import { credentialState, type TeamCredential } from "../equipe/types";
import type { AuthorizationGroup } from "./types";
import styles from "../equipe/admin.module.css";

export default function GroupMembers({
  group,
  credentials,
  credentialsError,
  disabled,
  onChanged,
  onReload,
  onBusyChange,
}: {
  group: AuthorizationGroup;
  credentials: TeamCredential[] | null;
  credentialsError: unknown;
  disabled: boolean;
  onChanged: (group: AuthorizationGroup) => void;
  onReload: () => void;
  onBusyChange: (busy: boolean) => void;
}) {
  const [membershipId, setMembershipId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [message, setMessage] = useState("");
  const available = credentials?.filter(
    (credential) =>
      !credential.revoked_at && !group.membership_ids.includes(credential.id),
  );

  async function assign(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const selected = available?.find(
      (credential) => credential.id === membershipId,
    );
    if (!selected) {
      setError(
        new Error(
          "Selecione uma credencial disponível deste ambiente. Atualize a lista caso ela tenha sido alterada.",
        ),
      );
      return;
    }
    if (
      !window.confirm(
        `Associar ${selected.invited_email} ao grupo “${group.name}”? As regras deste grupo passam a participar das decisões de acesso. Se a pessoa estava sem grupos, suas leituras padrão deixam de ser aplicadas; só terá operações com concessão aplicável.`,
      )
    )
      return;
    await mutate(
      selected.id,
      "PUT",
      `Vínculo de ${selected.invited_email} associado ao grupo.`,
    );
  }

  async function remove(id: string) {
    const credential = credentials?.find((row) => row.id === id);
    const label = credential?.invited_email ?? `vínculo ${id}`;
    if (
      !window.confirm(
        `Desassociar ${label} do grupo “${group.name}”? A credencial não será revogada. Se este for o último grupo, voltam a valer as leituras padrão de monitoramentos, comunicações e dashboard, sem escrita automática.`,
      )
    )
      return;
    await mutate(
      id,
      "DELETE",
      "Vínculo desassociado. A credencial não foi revogada.",
    );
  }

  async function mutate(id: string, method: "PUT" | "DELETE", success: string) {
    setBusy(true);
    onBusyChange(true);
    setError(null);
    setMessage("");
    try {
      const result = await api<AuthorizationGroup>(
        `/api/authorization/groups/${encodeURIComponent(group.id)}/memberships/${encodeURIComponent(id)}`,
        { method },
      );
      onChanged(result);
      setMessage(success);
      if (method === "PUT") setMembershipId("");
    } catch (caught) {
      setError(caught);
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  return (
    <section
      className="panel stack"
      aria-labelledby="members-heading"
      aria-busy={busy}
    >
      <div className={styles.header}>
        <h2 id="members-heading">Membros associados</h2>
        <Link className="button-secondary" href="/equipe">
          Gerenciar credenciais
        </Link>
      </div>
      <p className="muted">
        Convites pendentes e credenciais expiradas também podem ter grupos.
        Associação não aceita o convite, não renova e não revoga a credencial.
      </p>
      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}
      {error != null && <ErrorNotice error={error} id="group-member-error" />}
      {credentialsError != null && (
        <ErrorNotice error={credentialsError} onRetry={onReload} />
      )}
      {group.membership_ids.length === 0 ? (
        <p>Nenhum vínculo associado a este grupo.</p>
      ) : (
        <ul className={styles.list}>
          {group.membership_ids.map((id) => {
            const credential = credentials?.find((row) => row.id === id);
            return (
              <li className={`${styles.item} ${styles.header}`} key={id}>
                <div className="stack">
                  <h3>{credential?.invited_email ?? "Vínculo associado"}</h3>
                  <p className="muted">
                    {credential
                      ? credentialState(credential)
                      : "Identificação por e-mail não disponível na lista de credenciais."}
                  </p>
                  <code className={styles.code}>{id}</code>
                </div>
                <button
                  className="button-secondary"
                  type="button"
                  disabled={busy || disabled}
                  onClick={() => {
                    void remove(id);
                  }}
                >
                  Desassociar membro
                </button>
              </li>
            );
          })}
        </ul>
      )}
      <h3>Associar membro</h3>
      {credentials === null ? (
        <p className="muted">
          Carregue as credenciais reais do ambiente para selecionar um membro.
        </p>
      ) : available?.length === 0 ? (
        <p>
          Não há outras credenciais não revogadas disponíveis.{" "}
          <Link href="/equipe">Convidar alguém para a equipe</Link>.
        </p>
      ) : (
        <form
          className={styles.form}
          onSubmit={assign}
          aria-describedby={error != null ? "group-member-error" : undefined}
        >
          <div className="field">
            <label htmlFor="group-member">
              Credencial da equipe (obrigatória)
            </label>
            <select
              id="group-member"
              required
              value={membershipId}
              disabled={busy || disabled}
              onChange={(event) => setMembershipId(event.target.value)}
            >
              <option value="">Selecione uma credencial</option>
              {available?.map((credential) => (
                <option key={credential.id} value={credential.id}>
                  {credential.invited_email} — {credentialState(credential)}
                </option>
              ))}
            </select>
          </div>
          <div>
            <button
              className="button"
              type="submit"
              disabled={busy || disabled}
            >
              {busy ? "Processando associação…" : "Associar ao grupo"}
            </button>
          </div>
        </form>
      )}
      <p className="muted">
        Desassociar o último grupo volta a aplicar as leituras padrão. Para
        interromper todo o acesso, use “Revogar credencial” na página da equipe.
      </p>
    </section>
  );
}
