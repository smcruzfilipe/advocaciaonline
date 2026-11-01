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
import { Btn } from "@/components/ui";

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
        "Credencial criada e envio do convite confirmado. O destinatário deve aceitar com a conta do e-mail convidado.",
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
    <section
      className="mb-6 flex flex-col gap-4"
      aria-labelledby="invite-heading"
    >
      <h2
        id="invite-heading"
        className="text-base font-semibold font-headings text-foreground"
      >
        Enviar convite
      </h2>
      <p className="text-sm text-muted-foreground">
        O e-mail recebe um link de aceite. A validade da credencial começa ao
        confirmar a criação, mesmo quando a entrega do e-mail falha.
      </p>
      {message && (
        <div
          className="border border-success bg-success-bg p-3 text-sm"
          role="status"
        >
          {message}
        </div>
      )}
      {error != null && <ErrorNotice error={error} id="invite-error" />}
      {recorded && (
        <div className="border border-border bg-input p-4 flex flex-col gap-3 text-sm">
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
              className="border border-border bg-background px-3 py-2 text-sm disabled:opacity-50"
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
        className="border border-border p-5 flex flex-col gap-5"
        aria-busy={busy}
        aria-describedby={error != null ? "invite-error" : undefined}
      >
        <fieldset
          className="flex flex-col gap-5"
          disabled={busy || recorded || disabled}
        >
          <div className="flex flex-col gap-1.5 text-sm">
            <label htmlFor="invite-email">
              E-mail do convidado (obrigatório)
            </label>
            <input
              className="border border-border px-3 py-2 text-sm bg-input w-full"
              id="invite-email"
              type="email"
              autoComplete="email"
              maxLength={254}
              required
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              aria-describedby="invite-email-help"
            />
            <p className="text-xs text-muted-foreground" id="invite-email-help">
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
          <fieldset
            className="flex flex-col gap-2 text-sm"
            aria-describedby="invite-groups-help"
          >
            <legend className="font-medium mb-2">Grupos (opcional)</legend>
            <p
              className="text-xs text-muted-foreground"
              id="invite-groups-help"
            >
              Sem grupos, a equipe recebe leituras padrão de monitoramentos,
              comunicações e painel, sem escrita automática.
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
              <p className="text-xs text-muted-foreground">
                A seleção de grupos ainda não está disponível.
              </p>
            ) : groups.length === 0 ? (
              <p>
                Nenhum grupo criado.{" "}
                <Link href="/grupos">Gerenciar grupos</Link>.
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                {groups.map((group) => (
                  <label
                    key={group.id}
                    className="flex items-center gap-3 border border-border px-3 py-2.5"
                  >
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
              <div className="border border-warning bg-warning-bg p-3 flex flex-col gap-2 text-sm">
                <p>
                  Alguns grupos selecionados não estão mais disponíveis.
                  Desmarque-os para continuar; as demais entradas foram
                  preservadas.
                </p>
                {missingGroups.map((id) => (
                  <label key={id} className="flex items-center gap-3">
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
          <div className="flex justify-end">
            <Btn icon="send" type="submit" disabled={groups === null}>
              {busy
                ? "Criando credencial e enviando…"
                : "Criar credencial e enviar convite"}
            </Btn>
          </div>
        </fieldset>
      </form>
    </section>
  );
}
