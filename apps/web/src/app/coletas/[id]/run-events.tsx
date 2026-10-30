"use client";

import {
  EntityReference,
  entityLabel,
  formatInstant,
  mediumLabel,
  ReadFeedback,
  useRead,
} from "../../comunicacoes/_components/consultation";
import type { CollectionEvent } from "../types";
import styles from "../../comunicacoes/consultation.module.css";

export function RunEvents({ runId }: { runId: string }) {
  const { state, reload } = useRead<{ events: CollectionEvent[] }>(
    `/api/collection-runs/${encodeURIComponent(runId)}/events`,
  );

  return (
    <section className={styles.section} aria-labelledby="run-events">
      <h2 id="run-events">Marcos do Escrevente</h2>
      <p className="notice">
        Os marcos de início e término são imutáveis e não podem ser editados ou
        excluídos. Ausência de término não permite inferir falha. O Escrevente
        não apresenta erros técnicos nem conteúdo de comunicações.
      </p>
      {state.status !== "ready" ? (
        <ReadFeedback
          state={state}
          retry={reload}
          label="os marcos do Escrevente"
          ownerOnly
        />
      ) : state.data.events.length === 0 ? (
        <p className="panel" role="status">
          Nenhum marco registrado para esta execução. Não há início, término ou
          sucesso a presumir.
        </p>
      ) : (
        <ol className={styles.list} aria-label="Marcos em ordem de registro">
          {state.data.events.map((event) => (
            <li className={styles.item} key={event.id}>
              <div className={styles.header}>
                <h3>
                  {event.event_type === "started"
                    ? "Início do processamento"
                    : event.event_type === "completed"
                      ? "Término bem-sucedido confirmado"
                      : event.event_type}
                </h3>
                <time dateTime={event.recorded_at}>
                  {formatInstant(event.recorded_at)} (Brasília)
                </time>
              </div>
              <p>
                {entityLabel(event.entity_type)} · {event.court} ·{" "}
                {event.source} · {mediumLabel(event.medium)}
              </p>
              <dl className={styles.metadata}>
                <div>
                  <dt>Monitoramento</dt>
                  <dd>
                    <EntityReference
                      type={event.entity_type}
                      id={event.entity_id}
                    />
                  </dd>
                </div>
                <div>
                  <dt>Trabalho</dt>
                  <dd>
                    <code className={styles.identifier}>{event.job_id}</code>
                  </dd>
                </div>
                <div>
                  <dt>Identificador do marco</dt>
                  <dd>
                    <code className={styles.identifier}>{event.id}</code>
                  </dd>
                </div>
              </dl>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}
