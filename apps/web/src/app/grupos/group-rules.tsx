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
import styles from "../equipe/admin.module.css";

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
      className="panel stack"
      aria-labelledby="rules-heading"
      aria-busy={removing !== null}
    >
      <div className={styles.header}>
        <h2 id="rules-heading">Regras de autorização</h2>
        <button
          className="button-secondary"
          type="button"
          disabled={disabled}
          onClick={onReloadCatalogs}
        >
          Atualizar catálogos
        </button>
      </div>
      {message && (
        <p className="notice" role="status">
          {message}
        </p>
      )}
      {error != null && <ErrorNotice error={error} />}
      {operationsError != null && (
        <ErrorNotice error={operationsError} onRetry={onReloadCatalogs} />
      )}
      {courtsError != null && (
        <div className="notice stack">
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
        <ul className={styles.list}>
          {group.rules.map((rule) => (
            <li className={`${styles.item} stack`} key={rule.id}>
              <div className={styles.header}>
                <div className="stack">
                  <h3>{operationLabel(rule.operation)}</h3>
                  <p>
                    <strong>
                      {rule.effect === "allow" ? "Permitir" : "Negar"}
                    </strong>{" "}
                    ·{" "}
                    {rule.court ??
                      (operations?.find(
                        (entry) => entry.operation === rule.operation,
                      )?.scope === "court" ||
                      rule.operation === "consultar_comunicacoes"
                        ? "Todos os tribunais"
                        : "Ambiente do advogado")}
                  </p>
                  <code className={styles.code}>{rule.operation}</code>
                </div>
                <div className="row">
                  <button
                    className="button-secondary"
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
                    className="button-secondary"
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
                <div className={styles.confirm}>
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
      <h3>Adicionar regra</h3>
      {operations === null ? (
        <p className="muted">
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
      {operations && (
        <details>
          <summary>Operações do catálogo ({operations.length})</summary>
          <ul>
            {operations.map((entry) => (
              <li key={entry.operation}>
                <strong>{operationLabel(entry.operation)}</strong> ·{" "}
                {entry.scope === "court"
                  ? "escopo de tribunal"
                  : "escopo do ambiente"}
                <br />
                <code className={styles.code}>{entry.operation}</code>
              </li>
            ))}
          </ul>
          <p className="muted">
            Somente as operações retornadas pelo servidor estão disponíveis para
            regras. A administração de equipe e grupos não é delegável.
          </p>
        </details>
      )}
    </section>
  );
}
