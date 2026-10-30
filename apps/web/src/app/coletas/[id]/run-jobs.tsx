"use client";

import {
  EntityReference,
  entityLabel,
  mediumLabel,
  ReadFeedback,
  useRead,
} from "../../comunicacoes/_components/consultation";
import { executionState } from "../types";
import type { CollectionJob, ExecutionJob } from "../types";
import styles from "../../comunicacoes/consultation.module.css";

export function RunJobs({ runId }: { runId: string }) {
  const path = `/api/collection-runs/${encodeURIComponent(runId)}`;
  const plan = useRead<{ jobs: CollectionJob[] }>(`${path}/jobs`);
  const execution = useRead<{ jobs: ExecutionJob[] }>(`${path}/execution`);
  const reload = () => {
    plan.reload();
    execution.reload();
  };
  const pendingState =
    plan.state.status !== "ready"
      ? plan.state
      : execution.state.status !== "ready"
        ? execution.state
        : undefined;

  return (
    <section className={styles.section} aria-labelledby="run-jobs">
      <h2 id="run-jobs">Trabalhos da execução</h2>
      <p className="muted">
        O estado operacional vem da coleta, não da presença ou ausência de
        marcos. Ele não informa contagens de publicações nem resultado parcial
        por tribunal.
      </p>
      {pendingState ? (
        <ReadFeedback
          state={pendingState}
          retry={reload}
          label="os trabalhos e seus estados"
          ownerOnly
        />
      ) : (
        plan.state.status === "ready" &&
        execution.state.status === "ready" && (
          <>
            {plan.state.data.jobs.length === 0 ? (
              <p className="panel" role="status">
                Nenhum trabalho retornado para esta execução. Isso não constitui
                sucesso de coleta com zero publicações.
              </p>
            ) : (
              <JobList
                jobs={plan.state.data.jobs}
                execution={execution.state.data.jobs}
              />
            )}
          </>
        )
      )}
    </section>
  );
}

function JobList({
  jobs,
  execution,
}: {
  jobs: CollectionJob[];
  execution: ExecutionJob[];
}) {
  const states = new Map(execution.map((job) => [job.job_id, job]));

  return (
    <ul className={styles.list}>
      {jobs.map((job) => {
        const operational = states.get(job.id);
        return (
          <li className={styles.item} key={job.id}>
            <div className={styles.header}>
              <h3>
                {entityLabel(job.entity_type)} · {job.court}
              </h3>
              <span className={styles.badge}>
                {operational
                  ? executionState(operational.state)
                  : "Estado operacional indisponível"}
              </span>
            </div>
            <dl className={styles.metadata}>
              <div>
                <dt>Monitoramento</dt>
                <dd>
                  <EntityReference type={job.entity_type} id={job.entity_id} />
                </dd>
              </div>
              <div>
                <dt>Tribunal</dt>
                <dd>{job.court}</dd>
              </div>
              <div>
                <dt>Fonte</dt>
                <dd>{job.source}</dd>
              </div>
              <div>
                <dt>Meio</dt>
                <dd>{mediumLabel(job.medium)}</dd>
              </div>
              <div>
                <dt>Situação registrada no plano</dt>
                <dd>
                  {job.status === "pending"
                    ? "Pendente no plano — não é o estado operacional"
                    : job.status}
                </dd>
              </div>
              <div>
                <dt>Identificador do trabalho</dt>
                <dd>
                  <code className={styles.identifier}>{job.id}</code>
                </dd>
              </div>
            </dl>
            <details className={styles.disclosure}>
              <summary>Critérios fixados no planejamento</summary>
              <p className="muted">
                Os critérios refletem o momento do planejamento, mesmo se o
                monitoramento foi alterado depois.
              </p>
              <pre className={styles.sourceJson}>
                {JSON.stringify(job.criteria, null, 2)}
              </pre>
            </details>
          </li>
        );
      })}
    </ul>
  );
}
