"use client";

import Link from "next/link";
import { AlertBanner, Btn, EmptyState, PageShell } from "@/components/ui";
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
    <PageShell maxWidth="max-w-5xl">
      <nav className="mb-6 text-sm" aria-label="Caminho da coleta">
        <Link
          className="text-accent underline"
          href="/coletas"
          prefetch={false}
        >
          Voltar para histórico de coleta
        </Link>
      </nav>
      <header className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Execução de coleta
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Plano, estado operacional e registros imutáveis do fluxo.
          </p>
        </div>
        <Btn
          variant="secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar execução"}
        </Btn>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback
          state={state}
          retry={reload}
          label="a execução de coleta"
          ownerOnly
        />
      ) : !run ? (
        <div className="border border-border">
          <EmptyState
            icon="file-x"
            title="Execução não encontrada"
            description="Esta execução não está disponível para o vínculo atual. Nenhuma informação adicional pode ser exibida."
          />
        </div>
      ) : (
        <div className="flex flex-col gap-6">
          <section
            className="flex flex-col gap-4 border border-border p-5"
            aria-labelledby="run-metadata"
          >
            <h2 id="run-metadata" className="text-sm font-medium">
              Planejamento
            </h2>
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
            <AlertBanner variant="info">
              {planningState(run.status).description}
            </AlertBanner>
          </section>
          <RunJobs runId={run.id} />
          <RunEvents runId={run.id} />
        </div>
      )}
    </PageShell>
  );
}
