"use client";

import Link from "next/link";
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
    <div className="page stack">
      <header className={styles.header}>
        <div>
          <h1>Histórico de coleta</h1>
          <p className="muted">
            Execuções, trabalhos e marcos do Escrevente. Consulta exclusiva do
            advogado titular.
          </p>
        </div>
        <button
          className="button-secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar histórico"}
        </button>
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
          <p className="notice">
            O planejamento e o processamento são estados separados. Um plano
            concluído não confirma sucesso da coleta; um trabalho concluído não
            informa a quantidade de publicações. Os registros são somente
            leitura.
          </p>
          {state.data.runs.length === 0 ? (
            <section className="panel stack" role="status">
              <h2>Nenhuma execução disponível</h2>
              <p>
                O servidor não retornou execuções para este vínculo. Não há
                conclusão de coleta nem resultado vazio a inferir.
              </p>
            </section>
          ) : (
            <div
              className={styles.tableRegion}
              role="region"
              aria-label="Execuções de coleta"
              tabIndex={0}
            >
              <table>
                <caption>
                  Execuções visíveis no contexto atual. Datas no fuso
                  America/Sao_Paulo.
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Data</th>
                    <th scope="col">Slot</th>
                    <th scope="col">Planejamento</th>
                    <th scope="col">Consulta</th>
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
                          <p className="muted">{status.description}</p>
                        </td>
                        <td>
                          <Link
                            href={`/coletas/${encodeURIComponent(run.id)}`}
                            prefetch={false}
                          >
                            Ver trabalhos e marcos
                            <span className={styles.visuallyHidden}>
                              {" "}
                              de {formatCalendarDate(run.collection_date)}, slot{" "}
                              {run.slot}
                            </span>
                          </Link>
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
    </div>
  );
}
