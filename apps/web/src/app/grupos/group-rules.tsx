"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { ErrorNotice } from "../equipe/admin-ui";
import RuleForm from "./rule-form";
import {
  operationLabel,
  type AuthorizationGroup,
  type CatalogOperation,
  type Court,
  type GroupRule,
} from "./types";
import { Badge } from "@/components/ui";

export default function GroupRules({
  group,
  operations,
  operationsError,
  courts,
  courtsError,
  disabled,
  onChanged,
  onReloadCatalogs,
  onBusyChange,
}: {
  group: AuthorizationGroup;
  operations: CatalogOperation[] | null;
  operationsError: unknown;
  courts: Court[] | null;
  courtsError: unknown;
  disabled: boolean;
  onChanged: (group: AuthorizationGroup) => void;
  onReloadCatalogs: () => void;
  onBusyChange: (busy: boolean) => void;
}) {
  const [editing, setEditing] = useState<string | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [message, setMessage] = useState("");
  const [removing, setRemoving] = useState<string | null>(null);

  function saved(result: AuthorizationGroup) {
    onChanged(result);
    setEditing(null);
    setError(null);
    setMessage(
      "Regra salva. A política atualizada já é aplicada pelo servidor aos membros associados.",
    );
  }

  async function remove(rule: GroupRule) {
    if (
      !window.confirm(
        `Excluir a regra “${operationLabel(rule.operation)} — ${rule.effect === "allow" ? "Permitir" : "Negar"} — ${rule.court ?? "escopo geral"}”? A mudança afeta imediatamente os membros do grupo. Remover uma negação pode liberar acessos concedidos por outras regras.`,
      )
    )
      return;
    setRemoving(rule.id);
    onBusyChange(true);
    setError(null);
    setMessage("");
    try {
      const result = await api<AuthorizationGroup>(
        `/api/authorization/groups/${encodeURIComponent(group.id)}/rules/${encodeURIComponent(rule.id)}`,
        { method: "DELETE" },
      );
      onChanged(result);
      if (editing === rule.id) setEditing(null);
      setMessage(
        "Regra excluída. As demais regras e associações foram preservadas.",
      );
    } catch (caught) {
      setError(caught);
    } finally {
      setRemoving(null);
      onBusyChange(false);
    }
  }

  return (
    <section
      className="border border-border mb-6 p-5 flex flex-col gap-4 text-sm"
      aria-labelledby="rules-heading"
      aria-busy={removing !== null}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2
          id="rules-heading"
          className="text-base font-semibold font-headings"
        >
          Regras de autorização
        </h2>
        <button
          className="border border-border px-3 py-1.5 text-sm disabled:opacity-50"
          type="button"
          disabled={disabled}
          onClick={onReloadCatalogs}
        >
          Atualizar catálogos
        </button>
      </div>
      {message && (
        <p
          className="border border-success bg-success-bg p-3 text-sm"
          role="status"
        >
          {message}
        </p>
      )}
      {error != null && <ErrorNotice error={error} />}
      {operationsError != null && (
        <ErrorNotice error={operationsError} onRetry={onReloadCatalogs} />
      )}
      {courtsError != null && (
        <div className="border border-border bg-input p-3 flex flex-col gap-3">
          <p>
            Regras de escopo geral continuam disponíveis. Para escolher um
            tribunal específico, é necessário carregar o catálogo real.
          </p>
          <ErrorNotice error={courtsError} onRetry={onReloadCatalogs} />
        </div>
      )}
      {group.rules.length === 0 ? (
        <p>
          Este grupo ainda não tem regras. Uma pessoa com grupos só recebe
          operações com concessão aplicável; o padrão de leitura sem grupos não
          se soma.
        </p>
      ) : (
        <ul className="border border-border flex flex-col">
          {group.rules.map((rule, index) => (
            <li
              className={`border-b border-border last:border-b-0 px-5 py-3 flex flex-col gap-3 ${index % 2 ? "bg-table-row-alt" : "bg-background"}`}
              key={rule.id}
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-col gap-1">
                  <h3 className="text-sm font-medium">
                    {operationLabel(rule.operation)}
                  </h3>
                  <div className="flex items-center gap-3 text-xs text-muted-foreground">
                    <Badge
                      label={rule.effect === "allow" ? "Permitida" : "Negada"}
                      variant={rule.effect === "allow" ? "active" : "error"}
                    />
                    {rule.court ??
                      (operations?.find(
                        (entry) => entry.operation === rule.operation,
                      )?.scope === "court" ||
                      rule.operation === "consultar_comunicacoes"
                        ? "Todos os tribunais"
                        : "Ambiente do advogado")}
                  </div>
                  <code className="text-xs text-muted-foreground break-all">
                    {rule.operation}
                  </code>
                </div>
                <div className="flex flex-wrap gap-2">
                  <button
                    className="border border-border px-3 py-1.5 text-sm disabled:opacity-50"
                    type="button"
                    disabled={disabled || operations === null}
                    onClick={() => {
                      setEditing(rule.id);
                      setMessage("");
                    }}
                  >
                    Editar regra
                  </button>
                  <button
                    className="border border-border px-3 py-1.5 text-sm disabled:opacity-50"
                    type="button"
                    disabled={disabled}
                    onClick={() => {
                      void remove(rule);
                    }}
                  >
                    {removing === rule.id ? "Excluindo…" : "Excluir regra"}
                  </button>
                </div>
              </div>
              {editing === rule.id && operations && (
                <div className="border border-border bg-input p-4">
                  <RuleForm
                    key={rule.id}
                    groupId={group.id}
                    rule={rule}
                    operations={operations}
                    courts={courts}
                    courtsError={courtsError}
                    disabled={disabled}
                    onSaved={saved}
                    onCancel={() => setEditing(null)}
                    onBusyChange={onBusyChange}
                  />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      <h3 className="text-sm font-medium">Adicionar regra</h3>
      {operations === null ? (
        <p className="text-xs text-muted-foreground">
          O catálogo de operações precisa estar disponível para criar ou editar
          regras.
        </p>
      ) : (
        <RuleForm
          groupId={group.id}
          operations={operations}
          courts={courts}
          courtsError={courtsError}
          disabled={disabled}
          onSaved={saved}
          onBusyChange={onBusyChange}
        />
      )}
    </section>
  );
}
