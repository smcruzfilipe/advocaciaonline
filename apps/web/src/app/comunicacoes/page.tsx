"use client";

import Link from "next/link";
import {
  AlertBanner,
  Badge,
  Btn,
  EmptyState,
  PageShell,
} from "@/components/ui";
import { ReadFeedback, useRead } from "./_components/consultation";
import { IdentityWarning } from "./_components/identity-warning";
import { CourtSymbol } from "./_components/court-symbol";
import { processLabel } from "./detail-presentation.mjs";
import type { CommunicationList } from "./types";

export default function CommunicationsPage() {
  const { state, reload } = useRead<CommunicationList>("/api/communications");
  return (
    <PageShell maxWidth="max-w-4xl">
      <header className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold font-headings text-foreground">
            Comunicações
          </h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Publicações judiciais coletadas para seus monitoramentos. Agrupadas
            por tribunal e limitadas ao seu acesso.
          </p>
        </div>
        <Btn
          variant="secondary"
          size="sm"
          icon="refresh-cw"
          onClick={reload}
          disabled={state.status === "loading"}
        >
          {state.status === "loading"
            ? "Atualizando…"
            : "Atualizar comunicações"}
        </Btn>
      </header>
      {state.status !== "ready" ? (
        <ReadFeedback state={state} retry={reload} label="comunicações" />
      ) : (
        <>
          <AlertBanner variant="info">
            Esta lista reúne o que já foi persistido. A presença ou ausência de
            comunicações não confirma que a coleta foi concluída.{" "}
            <Link className="underline" href="/dashboard" prefetch={false}>
              Consultar estado da coleta
            </Link>
            .
          </AlertBanner>
          <div className="mt-6 flex flex-col gap-8">
            {state.data.courts.length === 0 ? (
              <div className="border border-border">
                <EmptyState
                  icon="mail"
                  title="Nenhuma comunicação disponível"
                  description="Não há comunicações persistidas que seu vínculo possa consultar neste contexto. Isso não significa coleta concluída nem zero publicações na fonte."
                />
              </div>
            ) : (
              state.data.courts.map((group) => (
                <details
                  key={group.court}
                  className="group"
                  aria-label={`Comunicações de ${group.court}`}
                  open
                >
                  <summary className="flex cursor-pointer list-none items-center gap-3 border border-border bg-secondary px-5 py-2.5">
                    <CourtSymbol court={group.court} />
                    <h2 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      {group.court}
                    </h2>
                    <span
                      aria-hidden="true"
                      className="ml-auto text-muted-foreground group-open:rotate-180"
                    >
                      ▾
                    </span>
                  </summary>
                  <ul className="divide-y divide-border border border-t-0 border-border">
                    {group.communications.map((communication) => {
                      const process = processLabel(
                        {
                          numeroprocessocommascara:
                            communication.process_number_masked,
                        },
                        communication.process_number,
                      );
                      const organ =
                        communication.organ_name?.trim() ||
                        "Órgão não fornecido pela fonte";
                      return (
                        <li
                          key={communication.id}
                          className="flex flex-col gap-1.5 px-4 py-4 md:px-5"
                        >
                          <div className="flex flex-col justify-between gap-3 md:flex-row md:items-start md:gap-4">
                            <div className="min-w-0 flex flex-col gap-1.5">
                              <h3 className="break-words font-mono text-xs text-muted-foreground">
                                {process}
                              </h3>
                              <p className="break-words text-xs text-muted-foreground">
                                {organ}
                              </p>
                            </div>
                            <div className="flex shrink-0 flex-wrap items-center gap-2 md:flex-col md:items-end">
                              <Badge
                                label={
                                  communication.identity_status === "pending"
                                    ? "Identidade pendente"
                                    : "Identidade completa"
                                }
                                variant={
                                  communication.identity_status === "pending"
                                    ? "warning"
                                    : "muted"
                                }
                              />
                              <Link
                                className="inline-flex min-h-8 items-center text-xs text-accent underline"
                                href={`/comunicacoes/${encodeURIComponent(communication.id)}`}
                                prefetch={false}
                              >
                                Ver íntegra
                                <span className="sr-only">
                                  {" "}
                                  do processo {process}, {organ}
                                </span>
                              </Link>
                            </div>
                          </div>
                          <IdentityWarning communication={communication} />
                        </li>
                      );
                    })}
                    {group.communications.length === 0 && (
                      <li className="px-5 py-4 text-sm text-muted-foreground">
                        Nenhuma comunicação disponível neste tribunal.
                      </li>
                    )}
                  </ul>
                </details>
              ))
            )}
          </div>
        </>
      )}
    </PageShell>
  );
}
