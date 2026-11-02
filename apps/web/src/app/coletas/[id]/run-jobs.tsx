"use client";

import { Badge } from "@/components/ui";
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
      <h2 id="run-jobs" className="text-sm font-medium">
        Trabalhos da execução
      </h2>
      <p className="text-sm text-muted-foreground">
        O estado operacional vem da coleta, não da presença ou ausência de
        marcos. As contagens abaixo refletem somente resultados persistidos.
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
              <p
                className="border border-border bg-input p-5 text-sm"
                role="status"
              >
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
              <h3 className="text-sm font-medium">
                {entityLabel(job.entity_type)} · {job.court}
              </h3>
              <Badge
                label={
                  operational
                    ? executionState(operational.state)
                    : "Estado operacional indisponível"
                }
                variant={operational?.state === "failed" ? "error" : "muted"}
              />
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
            {job.source === "STF" && (
              <div className="mt-3 text-sm">
                {operational?.source_path === "andamentos" ? (
                  <>
                    <dl className={styles.metadata}>
                      <div>
                        <dt>Processos elegíveis</dt>
                        <dd>
                          {operational.eligible_process_count ??
                            "Não disponível"}
                        </dd>
                      </div>
                      <div>
                        <dt>Andamentos encontrados</dt>
                        <dd>{operational.matched_count ?? "Não disponível"}</dd>
                      </div>
                      <div>
                        <dt>Identidades pendentes</dt>
                        <dd>
                          {operational.pending_identity_count ??
                            "Não disponível"}
                        </dd>
                      </div>
                    </dl>
                    {operational.state === "succeeded" &&
                      operational.eligible_process_count === 0 && (
                        <p>Nenhum processo elegível encontrado.</p>
                      )}
                    {operational.state === "succeeded" &&
                      operational.eligible_process_count != null &&
                      operational.eligible_process_count > 0 &&
                      operational.matched_count === 0 && (
                        <p>Nenhum andamento encontrado para o dia.</p>
                      )}
                  </>
                ) : (
                  <p>Resultado de andamentos não disponível.</p>
                )}
              </div>
            )}
            <details className={styles.disclosure}>
              <summary>Critérios fixados no planejamento</summary>
              <p className="text-xs text-muted-foreground">
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
