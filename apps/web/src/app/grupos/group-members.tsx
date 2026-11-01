"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { ErrorNotice } from "../equipe/admin-ui";
import { credentialState, type TeamCredential } from "../equipe/types";
import type { AuthorizationGroup } from "./types";

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
        `Desassociar ${label} do grupo “${group.name}”? A credencial não será revogada. Se este for o último grupo, voltam a valer as leituras padrão de monitoramentos, comunicações e painel, sem escrita automática.`,
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
      className="border border-border p-5 mb-6 flex flex-col gap-4 text-sm"
      aria-labelledby="members-heading"
      aria-busy={busy}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2
          id="members-heading"
          className="text-base font-semibold font-headings"
        >
          Membros associados
        </h2>
        <Link
          className="border border-border px-3 py-1.5 text-sm"
          href="/equipe"
        >
          Gerenciar credenciais
        </Link>
      </div>
      <p className="text-xs text-muted-foreground">
        Convites pendentes e credenciais expiradas também podem ter grupos.
        Associação não aceita o convite, não renova e não revoga a credencial.
      </p>
      {message && (
        <div
          className="border border-success bg-success-bg p-3 text-sm"
          role="status"
        >
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
        <ul className="border border-border flex flex-col">
          {group.membership_ids.map((id) => {
            const credential = credentials?.find((row) => row.id === id);
            return (
              <li
                className="border-b border-border last:border-b-0 px-5 py-3.5 flex flex-wrap items-center justify-between gap-3"
                key={id}
              >
                <div className="flex flex-col gap-0.5 min-w-0">
                  <h3 className="text-sm font-medium break-all">
                    {credential?.invited_email ?? "Vínculo associado"}
                  </h3>
                  <p className="text-xs text-muted-foreground">
                    {credential
                      ? credentialState(credential)
                      : "Identificação por e-mail não disponível na lista de credenciais."}
                  </p>
                  <code className="text-xs text-muted-foreground break-all">
                    {id}
                  </code>
                </div>
                <button
                  className="border border-border px-3 py-1.5 text-sm disabled:opacity-50"
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
      <h3 className="text-sm font-medium">Associar membro</h3>
      {credentials === null ? (
        <p className="text-xs text-muted-foreground">
          Carregue as credenciais reais do ambiente para selecionar um membro.
        </p>
      ) : available?.length === 0 ? (
        <p>
          Não há outras credenciais não revogadas disponíveis.{" "}
          <Link href="/equipe">Convidar alguém para a equipe</Link>.
        </p>
      ) : (
        <form
          className="flex flex-col gap-4"
          onSubmit={assign}
          aria-describedby={error != null ? "group-member-error" : undefined}
        >
          <div className="flex flex-col gap-1.5 text-sm">
            <label htmlFor="group-member">
              Credencial da equipe (obrigatória)
            </label>
            <select
              className="border border-border bg-input px-3 py-2 text-sm w-full"
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
              className="bg-primary text-primary-foreground px-4 py-2 text-sm disabled:opacity-50"
              type="submit"
              disabled={busy || disabled}
            >
              {busy ? "Processando associação…" : "Associar ao grupo"}
            </button>
          </div>
        </form>
      )}
      <p className="text-xs text-muted-foreground">
        Desassociar o último grupo volta a aplicar as leituras padrão. Para
        interromper todo o acesso, use “Revogar credencial” na página da equipe.
      </p>
    </section>
  );
}
