"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import type { AuthorizationGroup } from "../grupos/types";
import { ErrorNotice, isDeliveryError } from "./admin-ui";
import {
  credentialState,
  formatInstant,
  validityLabel,
  type TeamCredential,
} from "./types";
import ValidityFields, {
  validityValue,
  type ValidityChoice,
} from "./validity-fields";
import styles from "./admin.module.css";

type Action = "renewal" | "revoke" | "invitation";

export default function CredentialItem({
  credential,
  groups,
  disabled,
  onUpdated,
  onReload,
  onBusyChange,
}: {
  credential: TeamCredential;
  groups: AuthorizationGroup[] | null;
  disabled: boolean;
  onUpdated: (credential: TeamCredential) => void;
  onReload: () => Promise<void>;
  onBusyChange: (busy: boolean) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [choice, setChoice] = useState<ValidityChoice>(
    credential.validity_days === null ? "unlimited" : "days",
  );
  const [days, setDays] = useState(credential.validity_days?.toString() ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [message, setMessage] = useState("");
  const state = credentialState(credential);
  const revoked = credential.revoked_at !== null;
  const canReissue =
    !revoked && !credential.accepted_at && state !== "Expirada";
  const memberGroups = groups?.filter((group) =>
    group.membership_ids.includes(credential.id),
  );

  async function saveValidity(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    onBusyChange(true);
    setError(null);
    setMessage("");
    try {
      const result = await api<{ credential: TeamCredential }>(
        `/api/team/credentials/${encodeURIComponent(credential.id)}`,
        {
          method: "PATCH",
          body: { validity_days: validityValue(choice, days) },
        },
      );
      onUpdated(result.credential);
      setEditing(false);
      setMessage(
        "Escolha de validade salva. O vencimento vigente não mudou; a nova escolha será aplicada somente ao renovar.",
      );
    } catch (caught) {
      setError(caught);
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  async function perform(action: Action) {
    const confirmations: Record<Action, string> = {
      renewal: `Renovar a credencial de ${credential.invited_email}? Um novo período começa agora, com a escolha salva: ${validityLabel(credential.validity_days)}. O prazo anterior não é somado e o convite anterior não é prorrogado.`,
      revoke: `Revogar a credencial de ${credential.invited_email}? O acesso será interrompido imediatamente, inclusive em sessões abertas. Esta credencial não poderá ser reativada; será necessário criar outra.`,
      invitation: `Reemitir o convite de ${credential.invited_email}? O link anterior será invalidado. A validade da credencial não será reiniciada.`,
    };
    if (!window.confirm(confirmations[action])) return;
    setBusy(true);
    onBusyChange(true);
    setError(null);
    setMessage("");
    try {
      const suffix = action === "revoke" ? "" : `/${action}`;
      const result = await api<{ credential: TeamCredential }>(
        `/api/team/credentials/${encodeURIComponent(credential.id)}${suffix}`,
        {
          method: action === "revoke" ? "DELETE" : "POST",
        },
      );
      onUpdated(result.credential);
      setMessage(
        action === "revoke"
          ? "Credencial revogada. O acesso foi interrompido."
          : action === "invitation"
            ? "Convite reemitido; envio confirmado. O link anterior foi invalidado."
            : "Credencial renovada a partir de agora. Se o aceite estiver pendente, reemita o convite separadamente; renovar não prorroga o link anterior.",
      );
    } catch (caught) {
      setError(caught);
      if (isDeliveryError(caught)) await onReload();
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  function openValidity() {
    setChoice(credential.validity_days === null ? "unlimited" : "days");
    setDays(credential.validity_days?.toString() ?? "");
    setEditing(true);
    setError(null);
    setMessage("");
  }

  return (
    <li className={`${styles.item} stack`} aria-busy={busy}>
      <div className={styles.header}>
        <h3>{credential.invited_email}</h3>
        <span className={styles.status}>{state}</span>
      </div>
      <dl className={styles.meta}>
        <div>
          <dt>Período vigente iniciado em</dt>
          <dd>{formatInstant(credential.credential_started_at)}</dd>
        </div>
        <div>
          <dt>Vencimento vigente</dt>
          <dd>
            {credential.expires_at
              ? formatInstant(credential.expires_at)
              : "Sem expiração"}
          </dd>
        </div>
        <div>
          <dt>Escolha para a próxima renovação</dt>
          <dd>{validityLabel(credential.validity_days)}</dd>
        </div>
        <div>
          <dt>Aceite do convite</dt>
          <dd>
            {credential.accepted_at
              ? formatInstant(credential.accepted_at)
              : "Pendente"}
          </dd>
        </div>
        {credential.revoked_at && (
          <div>
            <dt>Revogada em</dt>
            <dd>{formatInstant(credential.revoked_at)}</dd>
          </div>
        )}
        <div>
          <dt>Grupos</dt>
          <dd>
            {memberGroups === undefined
              ? "Não foi possível consultar os grupos."
              : memberGroups.length === 0
                ? "Sem grupos"
                : memberGroups.map((group, index) => (
                    <span key={group.id}>
                      {index > 0 && ", "}
                      <Link href={`/grupos/${group.id}`}>{group.name}</Link>
                    </span>
                  ))}
          </dd>
        </div>
      </dl>
      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}
      {error != null && (
        <ErrorNotice error={error} id={`credential-${credential.id}-error`} />
      )}
      {revoked ? (
        <p className="muted">
          A renovação não reativa credenciais revogadas. Para restabelecer o
          acesso, crie uma nova credencial no formulário de convite.
        </p>
      ) : (
        <>
          <div className="row">
            <button
              className="button-secondary"
              type="button"
              disabled={busy || disabled}
              onClick={openValidity}
            >
              Alterar validade
            </button>
            <button
              className="button-secondary"
              type="button"
              disabled={busy || disabled}
              onClick={() => {
                void perform("renewal");
              }}
            >
              Renovar credencial
            </button>
            {canReissue && (
              <button
                className="button-secondary"
                type="button"
                disabled={busy || disabled}
                onClick={() => {
                  void perform("invitation");
                }}
              >
                Reemitir convite
              </button>
            )}
            <button
              className="button-secondary"
              type="button"
              disabled={busy || disabled}
              onClick={() => {
                void perform("revoke");
              }}
            >
              Revogar credencial
            </button>
          </div>
          {!credential.accepted_at && state === "Expirada" && (
            <p className="muted">
              Renove a credencial expirada antes de reemitir o convite.
            </p>
          )}
        </>
      )}
      {busy && <p role="status">Processando solicitação…</p>}
      {editing && !revoked && (
        <form
          className={`${styles.form} ${styles.confirm}`}
          onSubmit={saveValidity}
          aria-describedby={
            error != null ? `credential-${credential.id}-error` : undefined
          }
        >
          <h4>Alterar escolha de validade</h4>
          <p>
            Salvar não muda o vencimento atual. A alteração só passa a valer
            mediante renovação explícita.
          </p>
          <ValidityFields
            id={`validity-${credential.id}`}
            choice={choice}
            days={days}
            onChoice={setChoice}
            onDays={setDays}
            disabled={busy || disabled}
          />
          <div className="row">
            <button
              className="button"
              type="submit"
              disabled={busy || disabled}
            >
              Salvar escolha
            </button>
            <button
              className="button-secondary"
              type="button"
              disabled={busy || disabled}
              onClick={() => setEditing(false)}
            >
              Cancelar alteração
            </button>
          </div>
        </form>
      )}
    </li>
  );
}
