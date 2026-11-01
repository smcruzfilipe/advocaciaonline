"use client";

import { useState } from "react";
import { api } from "@/lib/api";
import { asError, monitoringConfig } from "./monitoring";
import type { MonitoringKind, MonitoringWriteResult } from "./monitoring";
import { RequestError } from "./request-error";
import { Btn } from "@/components/ui";

export function StatusActions({
  kind,
  recordId,
  active,
  locked,
  onSaved,
  onBusyChange,
}: {
  kind: MonitoringKind;
  recordId: string;
  active?: boolean;
  locked: boolean;
  onSaved: (result: MonitoringWriteResult, active: boolean) => void;
  onBusyChange: (busy: boolean) => void;
}) {
  const [confirmation, setConfirmation] = useState<boolean>();
  const [pending, setPending] = useState<boolean>();
  const [error, setError] = useState<Error>();
  const disabled = locked || pending !== undefined;

  async function changeStatus(target: boolean) {
    if (disabled) return;
    setError(undefined);
    setPending(target);
    onBusyChange(true);
    try {
      const result = await api<MonitoringWriteResult>(
        `${monitoringConfig[kind].apiPath}/${encodeURIComponent(recordId)}`,
        {
          method: "PATCH",
          body: { active: target },
        },
      );
      setConfirmation(undefined);
      onSaved(result, target);
    } catch (reason: unknown) {
      setError(asError(reason));
    } finally {
      setPending(undefined);
      onBusyChange(false);
    }
  }

  return (
    <section
      className="mt-5 border-t border-border pt-5 flex flex-col gap-3 text-sm"
      aria-busy={pending !== undefined}
      aria-labelledby="monitoring-status-title"
    >
      <h2
        id="monitoring-status-title"
        className="text-sm font-semibold text-foreground"
      >
        Situação do monitoramento
      </h2>
      <p>
        Desativar interrompe novas coletas deste alvo. O cadastro, as
        comunicações já coletadas e o histórico são preservados.
      </p>
      {active === undefined && (
        <p className="text-xs text-muted-foreground">
          A situação atual não está disponível. Cada ação será autorizada
          separadamente pelo servidor, sem consultar dados protegidos.
        </p>
      )}
      {confirmation === undefined ? (
        <div className="flex flex-wrap items-center gap-3">
          {active !== false && (
            <button
              type="button"
              className="text-sm text-error underline disabled:opacity-40"
              disabled={disabled}
              onClick={() => {
                setError(undefined);
                setConfirmation(false);
              }}
            >
              Desativar monitoramento
            </button>
          )}
          {active !== true && (
            <Btn
              type="button"
              variant="secondary"
              disabled={disabled}
              onClick={() => {
                setError(undefined);
                setConfirmation(true);
              }}
            >
              Reativar monitoramento
            </Btn>
          )}
        </div>
      ) : (
        <div className="border border-warning bg-warning-bg p-4 flex flex-col gap-3">
          <strong>
            {confirmation
              ? "Reativar este monitoramento?"
              : "Desativar este monitoramento?"}
          </strong>
          <p>
            {confirmation
              ? "O alvo volta a participar de novas coletas conforme o filtro de tribunais salvo. Não será feita uma busca histórica."
              : "Este alvo deixa de participar de novas coletas. As comunicações existentes não serão excluídas."}
          </p>
          <div className="flex flex-wrap items-center gap-3">
            <Btn
              type="button"
              variant={confirmation ? "primary" : "danger"}
              disabled={disabled}
              onClick={() => changeStatus(confirmation)}
            >
              {pending !== undefined
                ? "Salvando situação…"
                : confirmation
                  ? "Confirmar reativação"
                  : "Confirmar desativação"}
            </Btn>
            <Btn
              type="button"
              variant="secondary"
              disabled={disabled}
              onClick={() => {
                setConfirmation(undefined);
                setError(undefined);
              }}
            >
              Cancelar
            </Btn>
          </div>
        </div>
      )}
      {error && (
        <RequestError
          error={error}
          title="Não foi possível alterar a situação"
        />
      )}
    </section>
  );
}
