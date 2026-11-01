"use client";

import Link from "next/link";
import { useState } from "react";
import { isCompleteMonitoring, monitoringConfig } from "./monitoring";
import type { MonitoringKind, MonitoringWriteResult } from "./monitoring";
import { MonitoringDetails } from "./monitoring-details";
import { MonitoringForm } from "./monitoring-form";
import { AlertBanner, Btn, Icon, PageShell } from "@/components/ui";

export function NewMonitoring({ kind }: { kind: MonitoringKind }) {
  const config = monitoringConfig[kind];
  const [saved, setSaved] = useState<{ result: MonitoringWriteResult }>();
  return (
    <PageShell maxWidth="max-w-2xl">
      <nav
        className="flex items-center gap-2 text-sm text-muted-foreground mb-6"
        aria-label="Caminho da página"
      >
        <Link className="underline text-accent" href="/monitoramentos">
          Monitoramentos
        </Link>
        <Icon i="chevron-right" size={13} />
        <span>{config.title}</span>
      </nav>
      <header className="flex items-start justify-between mb-4">
        <h1 className="text-xl font-semibold font-headings text-foreground">
          {config.newTitle}
        </h1>
      </header>
      {saved ? (
        <section
          className="flex flex-col gap-5"
          aria-labelledby="monitoring-created-title"
        >
          <AlertBanner variant="success">
            <h2 id="monitoring-created-title" className="text-sm font-semibold">
              Monitoramento cadastrado
            </h2>
            <p>
              O servidor confirmou o cadastro. A permissão de consultar o
              detalhe é avaliada separadamente.
            </p>
          </AlertBanner>
          {isCompleteMonitoring(saved.result) && (
            <MonitoringDetails record={saved.result} />
          )}
          <div className="flex flex-wrap items-center gap-3 text-sm">
            {saved.result?.id && (
              <Link
                className="inline-flex items-center justify-center border border-primary bg-primary px-4 py-2 text-sm font-medium text-primary-foreground"
                href={`${config.path}/${encodeURIComponent(saved.result.id)}`}
              >
                Abrir cadastro
              </Link>
            )}
            <Btn
              variant="secondary"
              type="button"
              onClick={() => setSaved(undefined)}
            >
              {kind === "party"
                ? "Cadastrar outra parte"
                : "Cadastrar outro processo"}
            </Btn>
            <Link className="text-accent underline" href="/monitoramentos">
              Voltar aos monitoramentos
            </Link>
          </div>
        </section>
      ) : (
        <section
          className="flex flex-col gap-5"
          aria-label="Dados do novo monitoramento"
        >
          <p className="text-xs text-muted-foreground">
            Um alvo desativado continua cadastrado. Se houver duplicidade, edite
            ou reative o existente em vez de criar outro.
          </p>
          <MonitoringForm
            kind={kind}
            onSaved={(result) => setSaved({ result })}
          />
        </section>
      )}
    </PageShell>
  );
}
