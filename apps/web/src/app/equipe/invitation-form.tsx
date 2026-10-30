"use client";

import { useState, type FormEvent } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import type { AuthorizationGroup } from "../grupos/types";
import { ErrorNotice, isDeliveryError } from "./admin-ui";
import ValidityFields, {
  validityValue,
  type ValidityChoice,
} from "./validity-fields";
import type { TeamCredential } from "./types";
import styles from "./admin.module.css";

export default function InvitationForm({
  groups,
  groupsError,
  disabled,
  onChanged,
  onBusyChange,
}: {
  groups: AuthorizationGroup[] | null;
  groupsError: unknown;
  disabled: boolean;
  onChanged: () => Promise<void>;
  onBusyChange: (busy: boolean) => void;
}) {
  const [email, setEmail] = useState("");
  const [choice, setChoice] = useState<ValidityChoice>("");
  const [days, setDays] = useState("");
  const [groupIds, setGroupIds] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [message, setMessage] = useState("");
  const [recorded, setRecorded] = useState(false);
  const missingGroups = groups
    ? groupIds.filter((id) => !groups.some((group) => group.id === id))
    : [];

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setMessage("");
    setBusy(true);
    onBusyChange(true);
    try {
      const validity = validityValue(choice, days);
      if (
        !groups ||
        groupIds.some((id) => !groups.some((group) => group.id === id))
      ) {
        throw new Error(
          "Atualize os grupos disponíveis antes de enviar o convite. As seleções foram preservadas.",
        );
      }
      await api<{ credential: TeamCredential }>("/api/team/credentials", {
        method: "POST",
        body: {
          email: email.trim(),
          validity_days: validity,
          group_ids: groupIds,
        },
      });
      setRecorded(true);
      setMessage(
        "Credencial criada e envio do convite confirmado. O destinatário deve aceitar com a conta Google do e-mail convidado.",
      );
      await onChanged();
    } catch (caught) {
      setError(caught);
      if (isDeliveryError(caught)) {
        setRecorded(true);
        await onChanged();
      }
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  function newInvitation() {
    setEmail("");
    setChoice("");
    setDays("");
    setGroupIds([]);
    setError(null);
    setMessage("");
    setRecorded(false);
  }

  return (
    <section className="panel stack" aria-labelledby="invite-heading">
      <h2 id="invite-heading">Convidar para a equipe</h2>
      <p>
        O e-mail recebe um link de aceite. A validade da credencial começa ao
        confirmar a criação, mesmo quando a entrega do e-mail falha.
      </p>
      {message && (
        <div className="notice" role="status">
          {message}
        </div>
      )}
      {error != null && <ErrorNotice error={error} id="invite-error" />}
      {recorded && (
        <div className="notice stack">
          <p>
            A credencial já está registrada.{" "}
            <a href="#credentials">Consulte a lista de credenciais</a>; não crie
            outra para repetir o envio. Use “Reemitir convite” na credencial
            pendente. A reemissão invalida o link anterior e não reinicia a
            validade.
          </p>
          <div>
            <button
              type="button"
              className="button-secondary"
              disabled={busy || disabled}
              onClick={newInvitation}
            >
              Convidar outra pessoa
            </button>
          </div>
        </div>
      )}
      <form
        onSubmit={submit}
        className={styles.form}
        aria-busy={busy}
        aria-describedby={error != null ? "invite-error" : undefined}
      >
        <fieldset className="stack" disabled={busy || recorded || disabled}>
          <div className="field">
            <label htmlFor="invite-email">
              E-mail do convidado (obrigatório)
            </label>
            <input
              id="invite-email"
              type="email"
              autoComplete="email"
              maxLength={254}
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              aria-describedby="invite-email-help"
            />
            <p className="muted" id="invite-email-help">
              Informe apenas o endereço de e-mail, sem nome de exibição.
            </p>
          </div>
          <ValidityFields
            id="invite"
            choice={choice}
            days={days}
            onChoice={setChoice}
            onDays={setDays}
          />
          <fieldset className="stack" aria-describedby="invite-groups-help">
            <legend>Grupos (opcional)</legend>
            <p className="muted" id="invite-groups-help">
              Sem grupos, a equipe recebe leituras padrão de monitoramentos,
              comunicações e dashboard, sem escrita automática.
            </p>
            {groupsError != null && (
              <ErrorNotice
                error={groupsError}
                onRetry={() => {
                  void onChanged();
                }}
              />
            )}
            {groups === null ? (
              <p className="muted">
                A seleção de grupos ainda não está disponível.
              </p>
            ) : groups.length === 0 ? (
              <p>
                Nenhum grupo criado.{" "}
                <Link href="/grupos">Gerenciar grupos</Link>.
              </p>
            ) : (
              <div className={styles.checks}>
                {groups.map((group) => (
                  <label key={group.id} className={styles.choice}>
                    <input
                      type="checkbox"
                      checked={groupIds.includes(group.id)}
                      onChange={(event) =>
                        setGroupIds((current) =>
                          event.target.checked
                            ? [...current, group.id]
                            : current.filter((id) => id !== group.id),
                        )
                      }
                    />
                    {group.name}
                  </label>
                ))}
              </div>
            )}
            {missingGroups.length > 0 && (
              <div className="notice stack">
                <p>
                  Alguns grupos selecionados não estão mais disponíveis.
                  Desmarque-os para continuar; as demais entradas foram
                  preservadas.
                </p>
                {missingGroups.map((id) => (
                  <label key={id} className={styles.choice}>
                    <input
                      type="checkbox"
                      checked
                      onChange={() =>
                        setGroupIds((current) =>
                          current.filter((value) => value !== id),
                        )
                      }
                    />
                    Grupo indisponível: {id}
                  </label>
                ))}
              </div>
            )}
          </fieldset>
          <div>
            <button className="button" type="submit" disabled={groups === null}>
              {busy
                ? "Criando credencial e enviando…"
                : "Criar credencial e enviar convite"}
            </button>
          </div>
        </fieldset>
      </form>
    </section>
  );
}
