"use client";

import Link from "next/link";
import { useSession } from "@/components/session-provider";
import {
  courtDescription,
  monitoringConfig,
  monitoringName,
} from "./monitoring";
import type {
  LawyerMonitoring,
  Monitoring,
  MonitoringKind,
  PartyMonitoring,
  ProcessMonitoring,
} from "./monitoring";
import { RequestError } from "./request-error";
import { useRemote } from "./use-remote";
import styles from "./monitoramentos.module.css";

function OwnerOffice() {
  const profile = useRemote<{ profile: { office_name: string | null } }>(
    "/api/onboarding",
  );
  if (profile.loading)
    return <p role="status">Carregando dados do escritório…</p>;
  if (profile.error)
    return <RequestError error={profile.error} onRetry={profile.reload} />;
  return (
    <p>
      <span className="muted">Escritório: </span>
      {profile.data?.profile.office_name || "Não informado"}
    </p>
  );
}

function LawyerProfile() {
  const profile = useRemote<LawyerMonitoring>("/api/monitorings/lawyer");
  const { session } = useSession();
  return (
    <section
      className={styles.section}
      aria-labelledby="lawyer-monitoring-title"
      aria-busy={profile.loading}
    >
      <div className={styles.header}>
        <div>
          <h2 id="lawyer-monitoring-title">Advogado monitorado</h2>
          <p className="muted">
            Dados do perfil profissional do vínculo atual, sem um cadastro de
            monitoramento separado.
          </p>
        </div>
      </div>
      {profile.loading && (
        <p className="panel" role="status">
          Carregando perfil do advogado…
        </p>
      )}
      {profile.error && (
        <RequestError error={profile.error} onRetry={profile.reload} />
      )}
      {profile.data && (
        <div className="panel stack">
          <strong>{profile.data.full_name}</strong>
          {session?.role === "owner" && <OwnerOffice />}
          <div>
            <span className="muted">Inscrições OAB do perfil</span>
            <ul className={styles.oabs}>
              {profile.data.oabs.map((oab) => (
                <li
                  key={`${oab.uf}:${oab.number}`}
                  className={styles.identifier}
                >
                  OAB/{oab.uf} {oab.number}
                </li>
              ))}
            </ul>
          </div>
          <p className={styles.help}>
            O acompanhamento usa o nome completo ou uma das inscrições OAB do
            perfil. Número e sufixos da inscrição são mantidos como texto.
          </p>
        </div>
      )}
    </section>
  );
}

function MonitoringList({
  kind,
  records,
  loading,
  error,
  reload,
}: {
  kind: MonitoringKind;
  records?: Monitoring[];
  loading: boolean;
  error?: Error;
  reload: () => void;
}) {
  const config = monitoringConfig[kind];
  const headingId = `${kind}-monitoring-title`;
  return (
    <section
      className={styles.section}
      aria-labelledby={headingId}
      aria-busy={loading}
    >
      <div className={styles.header}>
        <div>
          <h2 id={headingId}>
            {kind === "party" ? "Partes monitoradas" : "Processos monitorados"}
          </h2>
          <p className="muted">
            {kind === "party"
              ? "Nomes completos de pessoas e empresas a acompanhar."
              : "Processos identificados pelo número CNJ, incluindo os zeros iniciais."}
          </p>
        </div>
        <Link className="button" href={config.newPath}>
          {kind === "party" ? "Nova parte" : "Novo processo"}
        </Link>
      </div>
      {loading && (
        <p className="panel" role="status">
          Carregando {kind === "party" ? "partes" : "processos"}…
        </p>
      )}
      {error && <RequestError error={error} onRetry={reload} />}
      {error && (
        <p className={styles.help}>
          Permissões de leitura e cadastro são independentes. O cadastro
          continua disponível e o servidor autoriza cada operação.
        </p>
      )}
      {records && records.length === 0 && (
        <div className="panel stack">
          <strong>
            {kind === "party"
              ? "Nenhuma parte cadastrada"
              : "Nenhum processo cadastrado"}
          </strong>
          <p>
            {kind === "party"
              ? "Cadastre uma parte pelo nome completo para acompanhar publicações correspondentes."
              : "Cadastre um processo pelo número CNJ para acompanhar suas publicações."}
          </p>
        </div>
      )}
      {records && records.length > 0 && (
        <ul className={styles.list}>
          {records.map((record) => (
            <li className={styles.item} key={record.id}>
              <div>
                <strong className={styles.identifier}>
                  {monitoringName(record)}
                </strong>
                <p className="muted">{courtDescription(record.courts)}</p>
              </div>
              <span className={styles.status}>
                {record.active ? "Ativo" : "Desativado"}
              </span>
              <Link
                href={`${config.path}/${encodeURIComponent(record.id)}`}
                aria-label={`Ver detalhes de ${monitoringName(record)}`}
              >
                Ver detalhes e editar
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default function MonitoramentosPage() {
  const parties = useRemote<{ parties: PartyMonitoring[] }>(
    "/api/monitorings/parties",
  );
  const processes = useRemote<{ processes: ProcessMonitoring[] }>(
    "/api/monitorings/processes",
  );
  return (
    <div className={`page ${styles.page}`}>
      <header className={styles.header}>
        <div>
          <h1>Monitoramentos</h1>
          <p className="muted">
            Gerencie o advogado, as partes e os processos usados no
            acompanhamento de publicações.
          </p>
        </div>
        <nav className={styles.actions} aria-label="Consulta de publicações">
          <Link href="/dashboard">Dashboard</Link>
          <Link href="/comunicacoes">Comunicações</Link>
        </nav>
      </header>
      <LawyerProfile />
      <MonitoringList
        kind="party"
        records={parties.data?.parties}
        loading={parties.loading}
        error={parties.error}
        reload={parties.reload}
      />
      <MonitoringList
        kind="process"
        records={processes.data?.processes}
        loading={processes.loading}
        error={processes.error}
        reload={processes.reload}
      />
    </div>
  );
}
