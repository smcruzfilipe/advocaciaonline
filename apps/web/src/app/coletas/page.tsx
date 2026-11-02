"use client";

import { AlertBanner, Btn, EmptyState, PageShell } from "@/components/ui";
import {
  formatCalendarDate,
  ReadFeedback,
  useRead,
} from "../comunicacoes/_components/consultation";
import { planningState } from "./types";
import type { RunList } from "./types";
import styles from "../comunicacoes/consultation.module.css";

export default function CollectionRunsPage() {
  const { state, reload } = useRead<RunList>("/api/collection-runs");

  return (
    <PageShell maxWidth="max-w-5xl">
      <header className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Histórico de coleta
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Execuções e trabalhos. Consulta exclusiva do advogado titular.
          </p>
        </div>
        <Btn
          variant="secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar histórico"}
        </Btn>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback
          state={state}
          retry={reload}
          label="o histórico de coleta"
          ownerOnly
        />
      ) : (
        <>
          <AlertBanner variant="info">
            O planejamento e o processamento são estados separados. Um plano
            concluído não confirma sucesso da coleta; um trabalho concluído não
            informa a quantidade de publicações. Os registros são somente
            leitura.
          </AlertBanner>
          {state.data.runs.length === 0 ? (
            <div className="mt-6 border border-border">
              <EmptyState
                icon="history"
                title="Nenhuma execução disponível"
                description="O servidor não retornou execuções para este vínculo. Não há conclusão de coleta nem resultado vazio a inferir."
              />
            </div>
          ) : (
            <div
              className={`${styles.tableRegion} mt-6`}
              role="region"
              aria-label="Execuções de coleta"
              tabIndex={0}
            >
              <table>
                <caption>Execuções visíveis no contexto atual.</caption>
                <thead>
                  <tr>
                    <th scope="col">Data</th>
                    <th scope="col">Slot</th>
                    <th scope="col">Planejamento</th>
                  </tr>
                </thead>
                <tbody>
                  {state.data.runs.map((run) => {
                    const status = planningState(run.status);
                    return (
                      <tr key={run.id}>
                        <td>
                          <time dateTime={run.collection_date}>
                            {formatCalendarDate(run.collection_date)}
                          </time>
                        </td>
                        <td>{run.slot}ª execução</td>
                        <td>
                          <strong>{status.label}</strong>
                          <p className="text-xs text-muted-foreground">
                            {status.description}
                          </p>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </PageShell>
  );
}
