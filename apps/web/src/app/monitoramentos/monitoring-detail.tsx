"use client";

import Link from "next/link";
import { useState } from "react";
import { ApiError } from "@/lib/api";
import { isCompleteMonitoring, monitoringConfig } from "./monitoring";
import type {
  Monitoring,
  MonitoringKind,
  MonitoringWriteResult,
} from "./monitoring";
import { MonitoringDetails } from "./monitoring-details";
import { MonitoringForm } from "./monitoring-form";
import { RequestError } from "./request-error";
import { StatusActions } from "./status-actions";
import { useRemote } from "./use-remote";
import { AlertBanner, Badge, Icon, PageShell } from "@/components/ui";

export function MonitoringDetail({
  kind,
  recordId,
}: {
  kind: MonitoringKind;
  recordId: string;
}) {
  const config = monitoringConfig[kind];
  const remote = useRemote<Monitoring>(
    `${config.apiPath}/${encodeURIComponent(recordId)}`,
  );
  const [override, setOverride] = useState<{ record?: Monitoring }>();
  const [notice, setNotice] = useState("");
  const [editRevision, setEditRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const record = override ? override.record : remote.data;
  const readError = !record ? remote.error : undefined;
  const blocked =
    readError instanceof ApiError &&
    (readError.status === 401 || readError.status === 404);

  function saved(
    result: MonitoringWriteResult,
    message: string,
    resetForm = false,
  ) {
    const complete = isCompleteMonitoring(result);
    setOverride({ record: complete ? result : undefined });
    setNotice(
      `${message}${complete ? "" : " O servidor confirmou a gravação sem retornar os dados protegidos do cadastro. A situação e os demais dados não serão presumidos."}`,
    );
    if (resetForm) setEditRevision((revision) => revision + 1);
  }

  function reload() {
    setOverride(undefined);
    setNotice("");
    remote.reload();
  }

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
      <header className="flex items-start justify-between gap-3 mb-4">
        <h1 className="text-xl font-semibold font-headings text-foreground">
          {kind === "party"
            ? "Editar parte monitorada"
            : "Editar processo monitorado"}
        </h1>
        {record && (
          <Badge
            label={record.active ? "Ativo" : "Inativo"}
            variant={record.active ? "active" : "inactive"}
          />
        )}
      </header>
      <div className="flex flex-col gap-5">
        {remote.loading && (
          <p
            className="border border-border p-5 text-sm text-muted-foreground"
            role="status"
            aria-busy="true"
          >
            Carregando monitoramento…
          </p>
        )}
        {readError && <RequestError error={readError} onRetry={reload} />}
        {notice && <AlertBanner variant="success">{notice}</AlertBanner>}
        {record && (
          <details className="border border-border p-5 text-sm">
            <summary className="cursor-pointer font-medium text-foreground">
              Dados do cadastro
            </summary>
            <div className="mt-4">
              <MonitoringDetails record={record} />
            </div>
          </details>
        )}
        {!remote.loading && !blocked && (
          <>
            {!record && (
              <AlertBanner variant="info">
                Os dados do cadastro não estão disponíveis para leitura. Isso
                não concede nem revoga permissões de escrita: você pode enviar
                apenas a alteração que deseja realizar, e o servidor autorizará
                a ação. Manter o filtro não exige consultar seu conteúdo.
              </AlertBanner>
            )}
            <section
              className="flex flex-col gap-3"
              aria-labelledby="monitoring-edit-title"
            >
              <h2 id="monitoring-edit-title" className="text-sm font-semibold">
                Editar cadastro
              </h2>
              <p className="text-xs text-muted-foreground">
                O filtro atual é preservado por padrão, mesmo se um tribunal
                salvo deixar de constar no catálogo. Editar dados e desativar
                são operações independentes.
              </p>
              <MonitoringForm
                key={editRevision}
                kind={kind}
                recordId={recordId}
                record={record}
                locked={busy}
                onBusyChange={setBusy}
                onSaved={(result) => saved(result, "Alterações salvas.", true)}
              />
            </section>
            <StatusActions
              kind={kind}
              recordId={recordId}
              active={record?.active}
              locked={busy}
              onBusyChange={setBusy}
              onSaved={(result, active) =>
                saved(
                  result,
                  active
                    ? "Reativação confirmada pelo servidor."
                    : "Desativação confirmada pelo servidor.",
                )
              }
            />
          </>
        )}
        {!remote.loading && (
          <div className="flex flex-wrap items-center gap-3 text-sm text-accent underline">
            <Link href="/monitoramentos">Voltar aos monitoramentos</Link>
          </div>
        )}
      </div>
    </PageShell>
  );
}
