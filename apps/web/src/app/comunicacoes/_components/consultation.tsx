"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import styles from "../consultation.module.css";

export type ReadState<T> =
  | { status: "loading" }
  | { status: "ready"; data: T }
  | { status: "error"; error: unknown };

const loading = { status: "loading" } as const;

export function useRead<T>(path: string) {
  const [revision, setRevision] = useState(0);
  const key = `${path}:${revision}`;
  const [result, setResult] = useState<{ key: string; state: ReadState<T> }>({
    key,
    state: loading,
  });
  const reload = useCallback(() => setRevision((value) => value + 1), []);

  useEffect(() => {
    let current = true;
    api<T>(path).then(
      (data) => {
        if (current) setResult({ key, state: { status: "ready", data } });
      },
      (error: unknown) => {
        if (current) setResult({ key, state: { status: "error", error } });
      },
    );
    return () => {
      current = false;
    };
  }, [path, key]);

  return { state: result.key === key ? result.state : loading, reload };
}

export function ReadFeedback({
  state,
  retry,
  label,
  ownerOnly = false,
}: {
  state: { status: "loading" } | { status: "error"; error: unknown };
  retry: () => void;
  label: string;
  ownerOnly?: boolean;
}) {
  if (state.status === "loading") {
    return (
      <div className="panel stack" role="status" aria-busy="true">
        <p>Carregando {label}…</p>
        <div className={styles.loadingLines} aria-hidden="true">
          <span />
          <span />
          <span />
        </div>
      </div>
    );
  }

  const error = state.error;
  const status = error instanceof ApiError ? error.status : undefined;
  const onboarding =
    error instanceof ApiError && error.code === "onboarding_required";
  const message =
    error instanceof Error
      ? error.message
      : "A conexão com o servidor não foi concluída.";
  const title = onboarding
    ? "Perfil profissional necessário"
    : status === 401
      ? "Sua sessão não está disponível"
      : status === 403
        ? "Acesso não permitido"
        : status === 404
          ? "Registro não encontrado"
          : `Não foi possível carregar ${label}`;

  return (
    <div className="panel stack error" role="alert">
      <p>
        <strong>{title}</strong>
      </p>
      <p>{message}</p>
      {status === 403 && ownerOnly && (
        <p>
          O histórico de coleta e os marcos do Escrevente são exclusivos do
          advogado titular.
        </p>
      )}
      <div className="row">
        {onboarding ? (
          <Link href="/onboarding" prefetch={false}>
            Cadastrar perfil profissional
          </Link>
        ) : status === 401 ? (
          <Link href="/login" prefetch={false}>
            Entrar novamente
          </Link>
        ) : status === 403 ? (
          <Link href="/vinculos" prefetch={false}>
            Consultar vínculos disponíveis
          </Link>
        ) : (
          status !== 404 && (
            <button className="button-secondary" onClick={retry}>
              Tentar novamente
            </button>
          )
        )}
      </div>
    </div>
  );
}

const dateTime = new Intl.DateTimeFormat("pt-BR", {
  dateStyle: "short",
  timeStyle: "short",
  timeZone: "America/Sao_Paulo",
});

export function formatInstant(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : dateTime.format(date);
}

export function formatCalendarDate(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : value;
}

export function entityLabel(type: string) {
  return (
    (
      { lawyer: "Advogado", party: "Parte", process: "Processo" } as Record<
        string,
        string
      >
    )[type] ?? type
  );
}

export function EntityReference({ type, id }: { type: string; id: string }) {
  const href =
    type === "lawyer"
      ? "/monitoramentos"
      : type === "party"
        ? `/monitoramentos/partes/${encodeURIComponent(id)}`
        : type === "process"
          ? `/monitoramentos/processos/${encodeURIComponent(id)}`
          : undefined;
  return (
    <span className={styles.reference}>
      {href ? (
        <Link href={href} prefetch={false}>
          {entityLabel(type)} {type === "party" ? "monitorada" : "monitorado"}
        </Link>
      ) : (
        entityLabel(type)
      )}
      <code className={styles.identifier}>{id}</code>
    </span>
  );
}

export function mediumLabel(medium: string) {
  return medium === "D" ? "Diário Eletrônico (D)" : medium;
}
