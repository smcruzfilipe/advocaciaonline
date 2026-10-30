"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { ErrorNotice, PolicyNotice } from "../equipe/admin-ui";
import type { TeamCredential } from "../equipe/types";
import type { AuthorizationGroup, CatalogOperation, Court } from "./types";
import GroupRules from "./group-rules";
import GroupMembers from "./group-members";
import GroupSettings from "./group-settings";
import styles from "../equipe/admin.module.css";

export default function GroupDetail({ id }: { id: string }) {
  const [group, setGroup] = useState<AuthorizationGroup | null>(null);
  const [groupError, setGroupError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [operations, setOperations] = useState<CatalogOperation[] | null>(null);
  const [operationsError, setOperationsError] = useState<unknown>(null);
  const [courts, setCourts] = useState<Court[] | null>(null);
  const [courtsError, setCourtsError] = useState<unknown>(null);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [credentials, setCredentials] = useState<TeamCredential[] | null>(null);
  const [credentialsError, setCredentialsError] = useState<unknown>(null);
  const [membersLoading, setMembersLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [deleted, setDeleted] = useState(false);

  const loadGroup = useCallback(
    () =>
      api<AuthorizationGroup>(
        `/api/authorization/groups/${encodeURIComponent(id)}`,
      )
        .then(
          (result) => {
            setGroup(result);
            setGroupError(null);
          },
          (caught: unknown) => {
            setGroupError(caught);
            setGroup(null);
          },
        )
        .finally(() => setLoading(false)),
    [id],
  );

  const loadCatalogs = useCallback(
    () =>
      Promise.allSettled([
        api<{ operations: CatalogOperation[] }>("/api/authorization/catalog"),
        api<{ courts: Court[] }>("/api/courts"),
      ]).then(([operationResult, courtResult]) => {
        if (operationResult.status === "fulfilled") {
          setOperations(operationResult.value.operations);
          setOperationsError(null);
        } else {
          setOperations(null);
          setOperationsError(operationResult.reason);
        }
        if (courtResult.status === "fulfilled") {
          setCourts(courtResult.value.courts);
          setCourtsError(null);
        } else {
          setCourts(null);
          setCourtsError(courtResult.reason);
        }
        setCatalogLoading(false);
      }),
    [],
  );

  const loadMembers = useCallback(
    () =>
      api<{ credentials: TeamCredential[] }>("/api/team/credentials")
        .then(
          (result) => {
            setCredentials(result.credentials);
            setCredentialsError(null);
          },
          (caught: unknown) => {
            setCredentials(null);
            setCredentialsError(caught);
          },
        )
        .finally(() => setMembersLoading(false)),
    [],
  );

  useEffect(() => {
    void loadGroup();
    void loadCatalogs();
    void loadMembers();
  }, [loadGroup, loadCatalogs, loadMembers]);

  return (
    <div className="page stack">
      <header className={styles.header}>
        <div className="stack">
          <Link href="/grupos">← Grupos e permissões</Link>
          <h1>
            {deleted ? "Grupo excluído" : (group?.name ?? "Detalhes do grupo")}
          </h1>
          <p className="muted">
            Regras e associações deste ambiente. Administração exclusiva do
            titular.
          </p>
        </div>
        <button
          className="button-secondary"
          type="button"
          disabled={
            loading || catalogLoading || membersLoading || busy || deleted
          }
          onClick={() => {
            setLoading(true);
            setCatalogLoading(true);
            setMembersLoading(true);
            void loadGroup();
            void loadCatalogs();
            void loadMembers();
          }}
        >
          Atualizar grupo
        </button>
      </header>
      {deleted ? (
        <div className="notice" role="status">
          Grupo excluído, incluindo suas regras e associações. As credenciais
          não foram revogadas. <Link href="/grupos">Voltar aos grupos</Link>.
        </div>
      ) : (
        <>
          {loading && <p role="status">Carregando grupo…</p>}
          {groupError != null && (
            <ErrorNotice
              error={groupError}
              onRetry={() => {
                setLoading(true);
                void loadGroup();
              }}
            />
          )}
          {group && (
            <>
              <PolicyNotice />
              {catalogLoading && (
                <p role="status">
                  Carregando catálogos de operações e tribunais…
                </p>
              )}
              <GroupRules
                group={group}
                operations={operations}
                operationsError={operationsError}
                courts={courts}
                courtsError={courtsError}
                disabled={busy || loading || catalogLoading}
                onChanged={setGroup}
                onReloadCatalogs={() => {
                  if (!busy && !catalogLoading) {
                    setCatalogLoading(true);
                    void loadCatalogs();
                  }
                }}
                onBusyChange={setBusy}
              />
              {membersLoading && (
                <p role="status">Carregando credenciais da equipe…</p>
              )}
              <GroupMembers
                group={group}
                credentials={credentials}
                credentialsError={credentialsError}
                disabled={busy || loading || membersLoading}
                onChanged={setGroup}
                onReload={() => {
                  if (!busy && !membersLoading) {
                    setMembersLoading(true);
                    void loadMembers();
                  }
                }}
                onBusyChange={setBusy}
              />
              <GroupSettings
                key={group.id}
                group={group}
                disabled={busy || loading}
                onChanged={setGroup}
                onDeleted={() => {
                  setDeleted(true);
                  setGroup(null);
                }}
                onBusyChange={setBusy}
              />
            </>
          )}
        </>
      )}
    </div>
  );
}
