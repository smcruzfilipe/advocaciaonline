"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
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
import { AlertBanner, Badge, Btn, Icon } from "@/components/ui";

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
  const [open, setOpen] = useState(false);
  const [confirmRevoke, setConfirmRevoke] = useState(false);
  const dialogRef = useRef<HTMLDialogElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const dialog = dialogRef.current;
    const trigger = triggerRef.current;
    if (!open || !dialog) return;
    dialog.showModal();
    return () => {
      dialog.close();
      trigger?.focus();
    };
  }, [open]);
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
    if (action !== "revoke" && !window.confirm(confirmations[action])) return;
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
      setConfirmRevoke(false);
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
    setError(null);
    setMessage("");
  }

  const variant =
    state === "Ativa"
      ? "active"
      : state === "Expirada"
        ? "warning"
        : revoked
          ? "error"
          : "info";
  const expiry = credential.expires_at
    ? formatInstant(credential.expires_at)
    : "Sem expiração";

  return (
    <li
      className="border-b border-border last:border-b-0 px-5 py-3.5 flex flex-wrap items-center justify-between gap-4 font-body"
      aria-busy={busy}
    >
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-sm font-medium text-foreground break-all">
          {credential.invited_email}
        </span>
        <div className="flex gap-1 flex-wrap mt-1">
          {memberGroups === undefined ? (
            <span className="text-xs text-muted-foreground">
              Grupos indisponíveis
            </span>
          ) : memberGroups.length === 0 ? (
            <span className="text-xs text-muted-foreground">Sem grupos</span>
          ) : (
            memberGroups.map((group) => (
              <Link
                key={group.id}
                href={`/grupos/${group.id}`}
                className="bg-secondary text-secondary-foreground px-1.5 py-0.5 text-xs border border-border"
              >
                {group.name}
              </Link>
            ))
          )}
        </div>
      </div>
      <div className="flex items-center gap-3 flex-wrap">
        <Badge label={state} variant={variant} />
        <span className="text-xs text-muted-foreground">{expiry}</span>
        <button
          ref={triggerRef}
          type="button"
          className="text-xs text-accent underline disabled:opacity-50"
          disabled={disabled || busy}
          onClick={() => {
            openValidity();
            setOpen(true);
            setConfirmRevoke(false);
          }}
        >
          gerenciar
        </button>
      </div>
      {open && (
        <dialog
          ref={dialogRef}
          aria-labelledby={`credential-title-${credential.id}`}
          onCancel={(event) => {
            event.preventDefault();
            setOpen(false);
          }}
          onClick={(event) => {
            if (event.target === event.currentTarget) setOpen(false);
          }}
          className="fixed inset-0 m-auto max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] max-w-md overflow-y-auto bg-background text-foreground border border-border p-0 backdrop:bg-black/50"
        >
          <div className="border-b border-border px-5 py-4 flex items-center justify-between">
            <h2
              id={`credential-title-${credential.id}`}
              className="text-base font-semibold font-headings"
            >
              Gerenciar credencial
            </h2>
            <button
              autoFocus
              type="button"
              aria-label="Fechar gerenciar credencial"
              className="text-muted-foreground p-1"
              onClick={() => setOpen(false)}
            >
              <Icon i="x" size={18} />
            </button>
          </div>
          <div className="px-5 py-5 flex flex-col gap-4">
            <div className="flex items-start justify-between gap-3">
              <p className="text-sm font-medium break-all">
                {credential.invited_email}
              </p>
              <Badge label={state} variant={variant} />
            </div>
            <dl className="border-t border-border pt-4 grid gap-3 text-sm">
              <div>
                <dt className="text-xs text-muted-foreground uppercase tracking-wide">
                  Validade atual
                </dt>
                <dd>{expiry}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted-foreground">
                  Período vigente iniciado em
                </dt>
                <dd>{formatInstant(credential.credential_started_at)}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted-foreground">
                  Escolha para a próxima renovação
                </dt>
                <dd>{validityLabel(credential.validity_days)}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted-foreground">
                  Aceite do convite
                </dt>
                <dd>
                  {credential.accepted_at
                    ? formatInstant(credential.accepted_at)
                    : "Pendente"}
                </dd>
              </div>
              {credential.revoked_at && (
                <div>
                  <dt className="text-xs text-muted-foreground">Revogada em</dt>
                  <dd>{formatInstant(credential.revoked_at)}</dd>
                </div>
              )}
            </dl>
            {message && <AlertBanner variant="success">{message}</AlertBanner>}
            {error != null && (
              <ErrorNotice
                error={error}
                id={`credential-${credential.id}-error`}
              />
            )}
            {!revoked && (
              <>
                <form
                  onSubmit={saveValidity}
                  className="flex flex-col gap-3"
                  aria-describedby={
                    error != null
                      ? `credential-${credential.id}-error`
                      : undefined
                  }
                >
                  <p className="text-xs text-muted-foreground">
                    A alteração passa a valer na próxima renovação — a
                    credencial vigente não é interrompida.
                  </p>
                  <ValidityFields
                    compact
                    id={`validity-${credential.id}`}
                    choice={choice}
                    days={days}
                    onChoice={setChoice}
                    onDays={setDays}
                    disabled={busy || disabled}
                  />
                  <div className="flex gap-2 flex-wrap">
                    <Btn type="submit" disabled={busy || disabled}>
                      Salvar escolha
                    </Btn>
                    <Btn
                      type="button"
                      variant="secondary"
                      disabled={busy}
                      onClick={openValidity}
                    >
                      Cancelar alteração
                    </Btn>
                  </div>
                </form>
                <div className="border-t border-border pt-4 flex flex-col gap-2">
                  <Btn
                    type="button"
                    variant="secondary"
                    icon="refresh-cw"
                    disabled={busy || disabled}
                    onClick={() => {
                      void perform("renewal");
                    }}
                  >
                    Renovar credencial
                  </Btn>
                  {canReissue && (
                    <Btn
                      type="button"
                      variant="secondary"
                      icon="send"
                      disabled={busy || disabled}
                      onClick={() => {
                        void perform("invitation");
                      }}
                    >
                      Reemitir convite
                    </Btn>
                  )}
                  <button
                    type="button"
                    className="text-sm text-error underline text-left mt-1 disabled:opacity-50"
                    disabled={busy || disabled}
                    onClick={() => setConfirmRevoke(true)}
                  >
                    Revogar credencial
                  </button>
                </div>
                {!credential.accepted_at && state === "Expirada" && (
                  <p className="text-xs text-muted-foreground">
                    Renove a credencial expirada antes de reemitir o convite.
                  </p>
                )}
              </>
            )}
            <AlertBanner variant="warning">
              Uma credencial revogada não é reativada por renovação. Para
              restabelecer o acesso, crie uma nova credencial no formulário de
              convite.
            </AlertBanner>
            {confirmRevoke && !revoked && (
              <div className="border border-error bg-error-bg p-4 flex flex-col gap-3">
                <h3 className="text-sm font-medium text-error">
                  Confirmar revogação
                </h3>
                <p className="text-sm break-words">
                  {credential.invited_email} perderá o acesso imediatamente,
                  inclusive em sessões abertas. Esta ação não pode ser desfeita.
                </p>
                <div className="flex gap-2 flex-wrap">
                  <Btn
                    type="button"
                    variant="secondary"
                    size="sm"
                    disabled={busy}
                    onClick={() => setConfirmRevoke(false)}
                  >
                    Cancelar
                  </Btn>
                  <Btn
                    type="button"
                    variant="danger"
                    size="sm"
                    disabled={busy || disabled}
                    onClick={() => {
                      void perform("revoke");
                    }}
                  >
                    Revogar agora
                  </Btn>
                </div>
              </div>
            )}
            {busy && (
              <p role="status" className="text-xs text-muted-foreground">
                Processando solicitação…
              </p>
            )}
          </div>
        </dialog>
      )}
    </li>
  );
}
