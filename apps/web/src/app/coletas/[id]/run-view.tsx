"use client";

import Link from "next/link";
import {
  formatCalendarDate,
  ReadFeedback,
  useRead,
} from "../../comunicacoes/_components/consultation";
import { planningState } from "../types";
import type { RunList } from "../types";
import { RunJobs } from "./run-jobs";
import { RunEvents } from "./run-events";
import styles from "../../comunicacoes/consultation.module.css";

export function CollectionRunView({ id }: { id: string }) {
  const { state, reload } = useRead<RunList>("/api/collection-runs");
  const run =
    state.status === "ready"
      ? state.data.runs.find(
          (item) => item.id.toLowerCase() === id.toLowerCase(),
        )
      : undefined;

  return (
    <div className="page stack">
      <nav aria-label="Caminho da coleta">
        <Link href="/coletas" prefetch={false}>
          Voltar para histórico de coleta
        </Link>
      </nav>
      <header className={styles.header}>
        <div>
          <h1>Execução de coleta</h1>
          <p className="muted">
            Plano, estado operacional e registros imutáveis do fluxo.
          </p>
        </div>
        <button
          className="button-secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar execução"}
        </button>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback
          state={state}
          retry={reload}
          label="a execução de coleta"
          ownerOnly
        />
      ) : !run ? (
        <section className="panel stack" role="alert">
          <h2>Execução não encontrada</h2>
          <p>
            Esta execução não está disponível para o vínculo atual. Nenhuma
            informação adicional pode ser exibida.
          </p>
        </section>
      ) : (
        <>
          <section className="panel stack" aria-labelledby="run-metadata">
            <h2 id="run-metadata">Planejamento</h2>
            <dl className={styles.metadata}>
              <div>
                <dt>Data da execução (America/Sao_Paulo)</dt>
                <dd>
                  <time dateTime={run.collection_date}>
                    {formatCalendarDate(run.collection_date)}
                  </time>
                </dd>
              </div>
              <div>
                <dt>Slot diário</dt>
                <dd>{run.slot}ª execução</dd>
              </div>
              <div>
                <dt>Situação do plano</dt>
                <dd>{planningState(run.status).label}</dd>
              </div>
              <div>
                <dt>Identificador da execução</dt>
                <dd>
                  <code className={styles.identifier}>{run.id}</code>
                </dd>
              </div>
            </dl>
            <p className="notice">{planningState(run.status).description}</p>
          </section>
          <RunJobs runId={run.id} />
          <RunEvents runId={run.id} />
        </>
      )}
    </div>
  );
}
