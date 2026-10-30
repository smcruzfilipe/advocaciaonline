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
import styles from "./monitoramentos.module.css";

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
    <div className={`page ${styles.page}`}>
      <nav aria-label="Caminho da página">
        <Link href="/monitoramentos">Monitoramentos</Link> / {config.title}
      </nav>
      <header className={styles.header}>
        <div>
          <h1>{config.title}</h1>
          <p className="muted">
            Consulte e mantenha este alvo no vínculo autenticado. A autorização
            é verificada no servidor a cada operação.
          </p>
        </div>
        <div className={styles.actions}>
          <Link href="/comunicacoes">Consultar comunicações</Link>
          <Link href="/dashboard">Dashboard</Link>
        </div>
      </header>
      {remote.loading && (
        <p className="panel" role="status" aria-busy="true">
          Carregando monitoramento…
        </p>
      )}
      {readError && <RequestError error={readError} onRetry={reload} />}
      {notice && (
        <div className="notice" role="status">
          {notice}
        </div>
      )}
      {record && (
        <section
          className="panel stack"
          aria-labelledby="monitoring-details-title"
        >
          <h2 id="monitoring-details-title">Dados do cadastro</h2>
          <MonitoringDetails record={record} />
        </section>
      )}
      {!remote.loading && !blocked && (
        <>
          {!record && (
            <p className="notice">
              Os dados do cadastro não estão disponíveis para leitura. Isso não
              concede nem revoga permissões de escrita: você pode enviar apenas
              a alteração que deseja realizar, e o servidor autorizará a ação.
              Manter o filtro não exige consultar seu conteúdo.
            </p>
          )}
          <section
            className="panel stack"
            aria-labelledby="monitoring-edit-title"
          >
            <h2 id="monitoring-edit-title">Editar cadastro</h2>
            <p className={styles.help}>
              O filtro atual é preservado por padrão, mesmo se um tribunal salvo
              deixar de constar no catálogo. Editar dados e desativar são
              operações independentes.
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
        <div className={styles.actions}>
          <Link href="/monitoramentos">Voltar aos monitoramentos</Link>
        </div>
      )}
    </div>
  );
}
