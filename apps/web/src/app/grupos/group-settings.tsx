"use client";

import { useState, type FormEvent } from "react";
import { api, ApiError } from "@/lib/api";
import { ErrorNotice } from "../equipe/admin-ui";
import type { AuthorizationGroup } from "./types";
import styles from "../equipe/admin.module.css";

export default function GroupSettings({
  group,
  disabled,
  onChanged,
  onDeleted,
  onBusyChange,
}: {
  group: AuthorizationGroup;
  disabled: boolean;
  onChanged: (group: AuthorizationGroup) => void;
  onDeleted: () => void;
  onBusyChange: (busy: boolean) => void;
}) {
  const [name, setName] = useState(group.name);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [message, setMessage] = useState("");

  async function rename(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    onBusyChange(true);
    setMessage("");
    try {
      if (!name.trim()) throw new Error("Informe um nome de grupo válido.");
      const result = await api<AuthorizationGroup>(
        `/api/authorization/groups/${encodeURIComponent(group.id)}`,
        { method: "PATCH", body: { name } },
      );
      onChanged(result);
      setName(result.name);
      setMessage("Nome do grupo atualizado.");
    } catch (caught) {
      setError(caught);
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  async function remove() {
    if (
      !window.confirm(
        `Excluir o grupo “${group.name}”, suas ${group.rules.length} regras e ${group.membership_ids.length} associações? As credenciais não serão revogadas. Quem ficar sem grupos voltará às leituras padrão de monitoramentos, comunicações e dashboard. Esta ação não pode ser desfeita.`,
      )
    )
      return;
    setBusy(true);
    onBusyChange(true);
    setError(null);
    setMessage("");
    try {
      await api<void>(
        `/api/authorization/groups/${encodeURIComponent(group.id)}`,
        { method: "DELETE" },
      );
      onDeleted();
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
      aria-labelledby="settings-heading"
      aria-busy={busy}
    >
      <h2 id="settings-heading">Nome e exclusão do grupo</h2>
      {error != null && <ErrorNotice error={error} id="group-settings-error" />}
      {message && (
        <p className="notice" role="status">
          {message}
        </p>
      )}
      <form
        className={styles.form}
        onSubmit={rename}
        aria-describedby={error != null ? "group-settings-error" : undefined}
      >
        <div className="field">
          <label htmlFor="rename-group">Nome do grupo (obrigatório)</label>
          <input
            id="rename-group"
            required
            maxLength={120}
            value={name}
            disabled={busy || disabled}
            onChange={(event) => setName(event.target.value)}
            aria-invalid={
              error instanceof ApiError && [409, 422].includes(error.status)
            }
            aria-describedby={
              error != null ? "group-settings-error" : undefined
            }
          />
        </div>
        <div>
          <button className="button" type="submit" disabled={busy || disabled}>
            {busy ? "Processando…" : "Salvar nome"}
          </button>
        </div>
      </form>
      <div className="stack">
        <p className="muted">
          Excluir remove as regras e associações, não as credenciais. A remoção
          do último grupo muda a política de leitura da pessoa.
        </p>
        <div>
          <button
            className="button-secondary"
            type="button"
            disabled={busy || disabled}
            onClick={() => {
              void remove();
            }}
          >
            Excluir grupo
          </button>
        </div>
      </div>
    </section>
  );
}
