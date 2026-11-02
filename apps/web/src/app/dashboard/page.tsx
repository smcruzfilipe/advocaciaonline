"use client";

import Link from "next/link";
import { useSession } from "@/components/session-provider";
import {
  AlertBanner,
  Badge,
  Btn,
  Icon,
  MetricCard,
  PageShell,
} from "@/components/ui";
import {
  formatInstant,
  ReadFeedback,
  useRead,
} from "../comunicacoes/_components/consultation";
import { metricPresentation, statePresentation } from "./presentation.mjs";
import type { MetricValue } from "./presentation.mjs";
import type { DashboardSnapshot } from "./types";

const periods = [
  { key: "today", label: "Hoje" },
  { key: "week", label: "Esta semana" },
  { key: "last_seven_days", label: "Últimos 7 dias" },
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
    <MetricCard
      label={label}
      value={presentation.value}
      period={presentation.note}
      state={
        presentation.value === "*"
          ? "restricted"
          : presentation.value === "—"
            ? "loading"
            : "value"
      }
    />
  );
}

export default function DashboardPage() {
  const { session } = useSession();
  const { state, reload } = useRead<DashboardSnapshot>("/api/dashboard");
  const snapshot = state.status === "ready" ? state.data : undefined;
  const presentation = snapshot ? statePresentation(snapshot.state) : undefined;

  return (
    <PageShell maxWidth="max-w-5xl">
      <div className="flex md:hidden items-center gap-2 text-xs text-muted-foreground border-b border-border pb-3 mb-5">
        <Icon i="building-2" size={13} />
        <span
          className="min-w-0 truncate"
          title={session?.tenant_id ?? undefined}
        >
          Ambiente: {session?.tenant_id}
        </span>
        <Link
          href="/vinculos"
          className="text-accent underline ml-auto shrink-0"
        >
          trocar
        </Link>
      </div>
      <header className="mb-5 flex flex-wrap items-start justify-between gap-3 md:mb-6">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Painel
          </h1>
          {snapshot ? (
            <p className="mt-0.5 text-xs text-muted-foreground md:text-sm">
              Atualizado em{" "}
              <time dateTime={snapshot.as_of}>
                {formatInstant(snapshot.as_of)}
              </time>
            </p>
          ) : (
            <p className="mt-0.5 text-sm text-muted-foreground">
              Comunicações novas persistidas e processos distintos associados.
            </p>
          )}
        </div>
        <Btn
          variant="secondary"
          size="sm"
          icon="refresh-cw"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading" ? "Atualizando…" : "Atualizar painel"}
        </Btn>
      </header>
      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="o painel" />
      ) : (
        snapshot &&
        presentation && (
          <div className="flex flex-col gap-5 md:gap-8">
            {snapshot.warnings.length > 0 && (
              <section
                aria-labelledby="collection-warnings"
                className="flex flex-col gap-2"
              >
                <h2
                  id="collection-warnings"
                  className="mb-1 text-sm font-medium text-foreground"
                >
                  Alertas de coleta
                </h2>
                {snapshot.warnings.map((warning) => (
                  <AlertBanner
                    key={`${warning.court}:${warning.code}`}
                    variant="error"
                  >
                    <strong>{warning.court}</strong> —{" "}
                    {warning.code === "collection_failed"
                      ? "Falha de coleta ainda não recuperada. O aviso não representa zero publicações."
                      : warning.code}{" "}
                    Os números exibidos podem estar incompletos para este
                    tribunal.
                  </AlertBanner>
                ))}
                <p className="text-xs text-muted-foreground">
                  O aviso permanece até sucesso integral em um slot posterior do
                  mesmo dia. Falhas não recuperadas de dias anteriores continuam
                  sinalizadas, sem iniciar coleta retroativa; o histórico da
                  execução é preservado.
                </p>
              </section>
            )}
            <AlertBanner
              variant={
                snapshot.state === "failed"
                  ? "error"
                  : snapshot.state === "partial" || snapshot.state === "masked"
                    ? "warning"
                    : "info"
              }
            >
              <strong>{presentation.label}.</strong> {presentation.description}
            </AlertBanner>
            {periods.map(({ key, label }) => {
              const period = snapshot.periods[key];
              return (
                <section key={key} aria-labelledby={`period-${key}`}>
                  <header className="mb-2 border-b border-border pb-2 md:mb-4">
                    <h2
                      id={`period-${key}`}
                      className="text-xs font-medium uppercase tracking-wide text-foreground md:text-base md:normal-case md:tracking-normal"
                    >
                      {label}
                    </h2>
                    <p className="mt-1 text-xs text-muted-foreground">
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
                  <div className="grid grid-cols-2 gap-3 md:gap-4">
                    <Metric
                      label="Comunicações novas"
                      value={period.communications}
                      masked={snapshot.state === "masked"}
                    />
                    <Metric
                      label="Processos distintos associados"
                      value={period.processes}
                      masked={snapshot.state === "masked"}
                    />
                  </div>
                </section>
              );
            })}
            <section aria-labelledby="court-states">
              <h2
                id="court-states"
                className="mb-3 text-sm font-medium text-foreground"
              >
                Estado por tribunal autorizado
              </h2>
              {snapshot.courts.length === 0 ? (
                <p className="border border-border bg-input p-4 text-sm text-muted-foreground">
                  Não há estado de tribunal disponível neste escopo.
                </p>
              ) : (
                <ul className="divide-y divide-border border border-border">
                  {snapshot.courts.map((court) => (
                    <li
                      key={court.court}
                      className="flex flex-wrap items-center justify-between gap-2 px-5 py-3"
                    >
                      <h3 className="text-sm font-medium">{court.court}</h3>
                      <Badge
                        label={statePresentation(court.state).label}
                        variant={
                          court.state === "failed"
                            ? "error"
                            : court.state === "succeeded"
                              ? "success"
                              : "muted"
                        }
                      />
                    </li>
                  ))}
                </ul>
              )}
            </section>
            <footer className="flex flex-col gap-3 border border-border bg-input p-4 text-sm text-muted-foreground">
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
              <div className="flex flex-wrap gap-4">
                <Link
                  className="text-accent underline"
                  href="/comunicacoes"
                  prefetch={false}
                >
                  Consultar comunicações
                </Link>
                {session?.role === "owner" && (
                  <Link
                    className="text-accent underline"
                    href="/coletas"
                    prefetch={false}
                  >
                    Histórico operacional (somente titular)
                  </Link>
                )}
              </div>
            </footer>
          </div>
        )
      )}
    </PageShell>
  );
}
