"use client";

import Link from "next/link";
import { useSession } from "@/components/session-provider";
import {
  Badge,
  EmptyState,
  Icon,
  PageShell,
  SectionHeader,
} from "@/components/ui";
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

function OwnerOffice() {
  const profile = useRemote<{ profile: { office_name: string | null } }>(
    "/api/onboarding",
  );
  if (profile.loading)
    return <p role="status">Carregando dados do escritório…</p>;
  if (profile.error)
    return <RequestError error={profile.error} onRetry={profile.reload} />;
  return (
    <p className="text-xs text-muted-foreground">
      Escritório: {profile.data?.profile.office_name || "Não informado"}
    </p>
  );
}

function LawyerProfile() {
  const profile = useRemote<LawyerMonitoring>("/api/monitorings/lawyer");
  const { session } = useSession();
  return (
    <section
      className="mb-8"
      aria-label="Dados do advogado"
      aria-busy={profile.loading}
    >
      <SectionHeader
        title="Dados do advogado"
        subtitle="Informações do seu perfil usadas no monitoramento automático."
      />
      {profile.loading && (
        <p
          className="border border-border p-5 text-sm text-muted-foreground"
          role="status"
        >
          Carregando perfil do advogado…
        </p>
      )}
      {profile.error && (
        <RequestError error={profile.error} onRetry={profile.reload} />
      )}
      {profile.data && (
        <div className="border border-border p-5 flex flex-col gap-3">
          <div>
            <p className="text-sm font-medium text-foreground">
              {profile.data.full_name}
            </p>
            <ul
              aria-label="Inscrições OAB do perfil"
              className="mt-0.5 flex flex-wrap gap-x-3 text-xs text-muted-foreground"
            >
              {profile.data.oabs.map((oab) => (
                <li
                  key={`${oab.uf}:${oab.number}`}
                  className="break-all tabular-nums"
                >
                  OAB/{oab.uf} {oab.number}
                </li>
              ))}
            </ul>
          </div>
          {session?.role === "owner" && <OwnerOffice />}
          <p className="text-xs text-muted-foreground border-t border-border pt-3">
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
  return (
    <section
      className="mb-8"
      aria-label={
        kind === "party" ? "Partes monitoradas" : "Processos monitorados"
      }
      aria-busy={loading}
    >
      <SectionHeader
        title={
          kind === "party" ? "Partes monitoradas" : "Processos monitorados"
        }
        subtitle={
          kind === "party"
            ? "Nomes de pessoas ou empresas a acompanhar nas publicações."
            : "Números CNJ de processos a acompanhar."
        }
        action={
          <Link
            className="inline-flex items-center justify-center gap-2 border border-primary bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:opacity-90"
            href={config.newPath}
          >
            <Icon i="plus" size={13} />
            {kind === "party" ? "Nova parte" : "Novo processo"}
          </Link>
        }
      />
      {loading && (
        <p
          className="border border-border p-5 text-sm text-muted-foreground"
          role="status"
        >
          Carregando {kind === "party" ? "partes" : "processos"}…
        </p>
      )}
      {error && <RequestError error={error} onRetry={reload} />}
      {error && (
        <p className="mt-2 text-xs text-muted-foreground">
          Permissões de leitura e cadastro são independentes. O cadastro
          continua disponível e o servidor autoriza cada operação.
        </p>
      )}
      {records?.length === 0 && (
        <EmptyState
          icon={kind === "party" ? "users" : "folder"}
          title={
            kind === "party"
              ? "Nenhuma parte cadastrada"
              : "Nenhum processo cadastrado"
          }
          description={
            kind === "party"
              ? "Cadastre uma parte pelo nome completo para acompanhar publicações correspondentes."
              : "Cadastre um processo pelo número CNJ para acompanhar suas publicações."
          }
        />
      )}
      {records && records.length > 0 && (
        <ul className="border border-border flex flex-col">
          {records.map((record) => (
            <li
              className="border-b last:border-b-0 border-border px-5 py-3.5 flex items-center justify-between gap-4"
              key={record.id}
            >
              <div className="flex flex-col gap-0.5 flex-1 min-w-0">
                <span className="text-sm text-foreground font-medium break-words tabular-nums">
                  {monitoringName(record)}
                </span>
                <span className="text-xs text-muted-foreground break-words">
                  {courtDescription(record.courts)}
                </span>
              </div>
              <div className="flex flex-wrap items-center justify-end gap-3 shrink-0">
                <Badge
                  label={record.active ? "Ativo" : "Inativo"}
                  variant={record.active ? "active" : "inactive"}
                />
                <Link
                  className="text-xs text-accent underline"
                  href={`${config.path}/${encodeURIComponent(record.id)}`}
                  aria-label={`Ver detalhes de ${monitoringName(record)}`}
                >
                  detalhe
                </Link>
              </div>
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
    <PageShell maxWidth="max-w-4xl">
      <div className="mb-6">
        <h1 className="text-xl font-semibold font-headings text-foreground">
          Monitoramentos
        </h1>
        <p className="text-sm text-muted-foreground mt-0.5">
          Gerencie os dados usados para rastrear publicações: dados do advogado,
          partes e processos.
        </p>
      </div>
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
    </PageShell>
  );
}
