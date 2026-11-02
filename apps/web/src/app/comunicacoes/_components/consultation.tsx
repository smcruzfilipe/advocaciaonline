"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api, ApiError } from "@/lib/api";
import { AlertBanner, Btn } from "@/components/ui";

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
      <div
        className="flex flex-col gap-4 border border-border p-5"
        role="status"
        aria-busy="true"
      >
        <p className="text-sm text-muted-foreground">Carregando {label}…</p>
        <div className="flex animate-pulse flex-col gap-3" aria-hidden="true">
          <span className="h-4 bg-muted" />
          <span className="h-4 bg-muted" />
          <span className="h-4 w-2/3 bg-muted" />
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
    <AlertBanner variant={status === 403 ? "warning" : "error"}>
      <div className="flex flex-col gap-3">
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
        <div className="flex flex-wrap gap-3 text-accent underline">
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
              <Btn variant="secondary" onClick={retry}>
                Tentar novamente
              </Btn>
            )
          )}
        </div>
      </div>
    </AlertBanner>
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

export function EntityReference({
  type,
  id,
  showIdentifier = true,
}: {
  type: string;
  id: string;
  showIdentifier?: boolean;
}) {
  const href =
    type === "lawyer"
      ? "/monitoramentos"
      : type === "party"
        ? `/monitoramentos/partes/${encodeURIComponent(id)}`
        : type === "process"
          ? `/monitoramentos/processos/${encodeURIComponent(id)}`
          : undefined;
  return (
    <span className="flex min-w-0 flex-col gap-1">
      {href ? (
        <Link className="text-accent underline" href={href} prefetch={false}>
          {entityLabel(type)} {type === "party" ? "monitorada" : "monitorado"}
        </Link>
      ) : (
        entityLabel(type)
      )}
      {showIdentifier && <code className="break-all text-xs">{id}</code>}
    </span>
  );
}

export function mediumLabel(medium: string) {
  return medium === "D"
    ? "Diário Eletrônico (D)"
    : medium === "A"
      ? "Andamentos (A)"
      : medium;
}
