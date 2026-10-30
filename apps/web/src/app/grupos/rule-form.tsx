"use client";

import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import { ErrorNotice } from "../equipe/admin-ui";
import { prepareRuleInput } from "./rule-input";
import {
  operationLabel,
  type AuthorizationGroup,
  type CatalogOperation,
  type Court,
  type GroupRule,
} from "./types";
import styles from "../equipe/admin.module.css";

export default function RuleForm({
  groupId,
  rule,
  operations,
  courts,
  courtsError,
  disabled,
  onSaved,
  onCancel,
  onBusyChange,
}: {
  groupId: string;
  rule?: GroupRule;
  operations: CatalogOperation[];
  courts: Court[] | null;
  courtsError: unknown;
  disabled: boolean;
  onSaved: (group: AuthorizationGroup) => void;
  onCancel?: () => void;
  onBusyChange: (busy: boolean) => void;
}) {
  const [operation, setOperation] = useState(rule?.operation ?? "");
  const [effect, setEffect] = useState<string>(rule?.effect ?? "");
  const [courtScope, setCourtScope] = useState(
    rule?.court ? "specific" : "all",
  );
  const [court, setCourt] = useState(rule?.court ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const selectedOperation = operations.find(
    (entry) => entry.operation === operation,
  );
  const courtOperation = selectedOperation?.scope === "court";
  const prefix = rule ? `rule-${rule.id}` : "new-rule";

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    onBusyChange(true);
    setError(null);
    try {
      const body = prepareRuleInput({
        rule,
        operation,
        effect,
        selectedOperation,
        courtScope,
        court,
        courts,
      });
      const result = await api<AuthorizationGroup>(
        `/api/authorization/groups/${encodeURIComponent(groupId)}/rules${rule ? `/${encodeURIComponent(rule.id)}` : ""}`,
        { method: rule ? "PATCH" : "POST", body },
      );
      if (!rule) {
        setOperation("");
        setEffect("");
        setCourtScope("all");
        setCourt("");
      }
      onSaved(result);
    } catch (caught) {
      setError(caught);
    } finally {
      setBusy(false);
      onBusyChange(false);
    }
  }

  return (
    <form
      className="stack"
      onSubmit={submit}
      aria-busy={busy}
      aria-describedby={error != null ? `${prefix}-error` : undefined}
    >
      {error != null && <ErrorNotice error={error} id={`${prefix}-error`} />}
      <fieldset className="stack" disabled={busy || disabled}>
        <div className={styles.ruleFields}>
          <div className="field">
            <label htmlFor={`${prefix}-operation`}>
              Operação (obrigatória)
            </label>
            <select
              id={`${prefix}-operation`}
              required
              value={operation}
              onChange={(event) => {
                setOperation(event.target.value);
                setCourtScope("all");
                setCourt("");
              }}
            >
              <option value="">Selecione a operação</option>
              {operations.map((entry) => (
                <option key={entry.operation} value={entry.operation}>
                  {operationLabel(entry.operation)}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label htmlFor={`${prefix}-effect`}>Efeito (obrigatório)</label>
            <select
              id={`${prefix}-effect`}
              required
              value={effect}
              onChange={(event) => setEffect(event.target.value)}
            >
              <option value="">Selecione o efeito</option>
              <option value="allow">Permitir</option>
              <option value="deny">Negar</option>
            </select>
          </div>
        </div>
        {courtOperation ? (
          <fieldset className="stack" aria-describedby={`${prefix}-scope-help`}>
            <legend>Escopo de tribunal</legend>
            <label className={styles.choice}>
              <input
                type="radio"
                name={`${prefix}-scope`}
                checked={courtScope === "all"}
                onChange={() => setCourtScope("all")}
              />
              Todos os tribunais (escopo geral)
            </label>
            <label className={styles.choice}>
              <input
                type="radio"
                name={`${prefix}-scope`}
                checked={courtScope === "specific"}
                onChange={() => setCourtScope("specific")}
              />
              Um tribunal específico
            </label>
            <p id={`${prefix}-scope-help`} className="muted">
              A regra de comunicações pode abranger todos os tribunais ou apenas
              o tribunal escolhido.
            </p>
            {courtScope === "specific" && (
              <div className="field">
                <label htmlFor={`${prefix}-court`}>
                  Tribunal (obrigatório neste escopo)
                </label>
                {courtsError != null && <ErrorNotice error={courtsError} />}
                {courts === null ? (
                  <p className="muted">
                    O catálogo de tribunais ainda não está disponível. Você pode
                    manter o tribunal já salvo ou atualizar o catálogo para
                    escolher outro.
                  </p>
                ) : (
                  <>
                    <select
                      id={`${prefix}-court`}
                      required
                      value={court}
                      onChange={(event) => setCourt(event.target.value)}
                    >
                      <option value="">Selecione o tribunal</option>
                      {court &&
                        !courts.some((entry) => entry.code === court) && (
                          <option value={court}>
                            {court} — tribunal já salvo, indisponível no
                            catálogo atual
                          </option>
                        )}
                      {courts.map((entry) => (
                        <option
                          key={entry.code}
                          value={entry.code}
                          disabled={
                            !/^[A-Za-z][A-Za-z0-9]{1,31}$/.test(entry.code)
                          }
                        >
                          {entry.code} — {entry.name}
                          {!/^[A-Za-z][A-Za-z0-9]{1,31}$/.test(entry.code)
                            ? " (não aceito em regras)"
                            : ""}
                        </option>
                      ))}
                    </select>
                    {courts.length === 0 && (
                      <p className="muted">
                        O catálogo foi consultado e não contém tribunais.
                      </p>
                    )}
                  </>
                )}
              </div>
            )}
          </fieldset>
        ) : (
          selectedOperation && (
            <p className="muted">
              Escopo do ambiente do advogado. Esta operação não aceita restrição
              de tribunal.
            </p>
          )
        )}
        <p className="muted">
          A regra passa a valer para os membros associados assim que for salva.
          Uma negação explícita prevalece sobre concessões aplicáveis ao mesmo
          escopo.
        </p>
        <div className="row">
          <button
            className="button"
            type="submit"
            disabled={
              operations.length === 0 ||
              (courtOperation && courtScope === "specific" && courts === null)
            }
          >
            {busy
              ? "Salvando regra…"
              : rule
                ? "Salvar regra"
                : "Adicionar regra"}
          </button>
          {onCancel && (
            <button
              className="button-secondary"
              type="button"
              onClick={onCancel}
            >
              Cancelar edição
            </button>
          )}
        </div>
      </fieldset>
    </form>
  );
}
