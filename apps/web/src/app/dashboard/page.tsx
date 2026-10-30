"use client";

import Link from "next/link";
import { useSession } from "@/components/session-provider";
import {
  formatInstant,
  ReadFeedback,
  useRead,
} from "../comunicacoes/_components/consultation";
import { metricPresentation, statePresentation } from "./presentation.mjs";
import type { MetricValue } from "./presentation.mjs";
import type { DashboardSnapshot } from "./types";
import styles from "./dashboard.module.css";
import shared from "../comunicacoes/consultation.module.css";

const periods = [
  { key: "today", label: "Hoje" },
  { key: "week", label: "Semana civil" },
  { key: "last_seven_days", label: "Últimos sete dias de calendário" },
] as const;

function Metric({
  label,
  value,
  masked,
}: {
  label: string;
  value: MetricValue;
  masked: boolean;
}) {
  const presentation = metricPresentation(value, masked);
  return (
    <div className={styles.metric}>
      <dt>{label}</dt>
      <dd>
        <span
          className={styles.value}
          aria-label={presentation.value === "*" ? "Sem permissão" : undefined}
        >
          {presentation.value}
        </span>
        <span className="muted">{presentation.note}</span>
      </dd>
    </div>
  );
}

export default function DashboardPage() {
  const { session } = useSession();
  const { state, reload } = useRead<DashboardSnapshot>("/api/dashboard");
  const snapshot = state.status === "ready" ? state.data : undefined;
  const presentation = snapshot ? statePresentation(snapshot.state) : undefined;

  return (
    <div className="page stack">
      <header className={shared.header}>
        <div>
          <h1>Dashboard</h1>
          <p className="muted">
            Comunicações novas persistidas e processos distintos associados.
          </p>
          {snapshot && (
            <p className="muted">
              Consulta em{" "}
              <time dateTime={snapshot.as_of}>
                {formatInstant(snapshot.as_of)}
              </time>{" "}
              · {snapshot.timezone}
            </p>
          )}
        </div>
        <button
          className="button-secondary"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar dashboard"}
        </button>
      </header>

      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="a dashboard" />
      ) : (
        snapshot &&
        presentation && (
          <>
            <section className="notice stack" aria-labelledby="dashboard-state">
              <h2 id="dashboard-state">{presentation.label}</h2>
              <p>{presentation.description}</p>
            </section>

            {snapshot.warnings.length > 0 && (
              <section
                className="notice stack"
                aria-labelledby="collection-warnings"
              >
                <h2 id="collection-warnings">Avisos persistentes de coleta</h2>
                <ul className={styles.warnings}>
                  {snapshot.warnings.map((warning) => (
                    <li key={`${warning.court}:${warning.code}`}>
                      <strong>{warning.court}</strong> —{" "}
                      {warning.code === "collection_failed"
                        ? "Falha de coleta ainda não recuperada. O aviso não representa zero publicações."
                        : warning.code}
                    </li>
                  ))}
                </ul>
                <p>
                  O aviso permanece até sucesso integral em um slot posterior do
                  mesmo dia. Falhas não recuperadas de dias anteriores continuam
                  sinalizadas, sem iniciar coleta retroativa; o histórico da
                  execução é preservado.
                </p>
              </section>
            )}

            <div className={styles.periods}>
              {periods.map(({ key, label }) => {
                const period = snapshot.periods[key];
                return (
                  <section
                    className={styles.period}
                    key={key}
                    aria-labelledby={`period-${key}`}
                  >
                    <header>
                      <h2 id={`period-${key}`}>{label}</h2>
                      <p className="muted">
                        De{" "}
                        <time dateTime={period.start}>
                          {formatInstant(period.start)}
                        </time>{" "}
                        até{" "}
                        <time dateTime={period.end}>
                          {formatInstant(period.end)}
                        </time>{" "}
                        (fim exclusivo).
                      </p>
                    </header>
                    <dl className={styles.metrics}>
                      <Metric
                        label="Comunicações novas persistidas"
                        value={period.communications}
                        masked={snapshot.state === "masked"}
                      />
                      <Metric
                        label="Processos distintos associados"
                        value={period.processes}
                        masked={snapshot.state === "masked"}
                      />
                    </dl>
                  </section>
                );
              })}
            </div>

            <section className={shared.section} aria-labelledby="court-states">
              <h2 id="court-states">Estado por tribunal autorizado</h2>
              {snapshot.courts.length === 0 ? (
                <p className="panel">
                  Não há estado de tribunal disponível neste escopo.
                </p>
              ) : (
                <ul className={shared.list}>
                  {snapshot.courts.map((court) => (
                    <li className={shared.item} key={court.court}>
                      <div className={shared.header}>
                        <h3>{court.court}</h3>
                        <span className={shared.badge}>
                          {statePresentation(court.state).label}
                        </span>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </section>

            <footer className="panel stack">
              <p>
                As janelas se sobrepõem intencionalmente e usam a primeira
                persistência local, não a data de publicação. A semana começa na
                segunda-feira; os últimos sete dias começam à meia-noite de seis
                dias atrás.
              </p>
              <p>
                Comunicações com identidade pendente ficam fora das duas
                métricas. Processos distintos usam a identidade canônica válida
                fornecida pela fonte.
              </p>
              <div className="row">
                <Link href="/comunicacoes" prefetch={false}>
                  Consultar comunicações
                </Link>
                {session?.role === "owner" && (
                  <Link href="/coletas" prefetch={false}>
                    Histórico operacional (somente titular)
                  </Link>
                )}
              </div>
            </footer>
          </>
        )
      )}
    </div>
  );
}
