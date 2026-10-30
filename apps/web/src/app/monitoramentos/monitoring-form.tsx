"use client";

import Link from "next/link";
import { useId, useRef, useState } from "react";
import type { FormEvent } from "react";
import { api } from "@/lib/api";
import { CourtSelector } from "./court-selector";
import type { CourtMode } from "./court-selector";
import {
  asError,
  monitoringConfig,
  monitoringName,
  validCnj,
} from "./monitoring";
import type {
  CourtCatalog,
  Monitoring,
  MonitoringKind,
  MonitoringWriteResult,
} from "./monitoring";
import { RequestError } from "./request-error";
import { useRemote } from "./use-remote";
import styles from "./monitoramentos.module.css";

export function MonitoringForm({
  kind,
  recordId,
  record,
  locked = false,
  onSaved,
  onBusyChange,
}: {
  kind: MonitoringKind;
  recordId?: string;
  record?: Monitoring;
  locked?: boolean;
  onSaved: (result: MonitoringWriteResult) => void;
  onBusyChange?: (busy: boolean) => void;
}) {
  const id = useId();
  const config = monitoringConfig[kind];
  const editing = Boolean(recordId);
  const [baseline] = useState(() => (record ? monitoringName(record) : ""));
  const [value, setValue] = useState(baseline);
  const [mode, setMode] = useState<CourtMode>(editing ? "keep" : "all");
  const [selected, setSelected] = useState<string[]>(record?.courts ?? []);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<Error>();
  const [valueError, setValueError] = useState<string>();
  const [courtError, setCourtError] = useState<string>();
  const [formError, setFormError] = useState<string>();
  const input = useRef<HTMLInputElement>(null);
  const catalog = useRemote<CourtCatalog>("/api/courts");
  const disabled = pending || locked;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (disabled) return;
    setError(undefined);
    setValueError(undefined);
    setCourtError(undefined);
    setFormError(undefined);
    const sendValue = !editing || value !== baseline;
    const invalidValue =
      sendValue &&
      (kind === "party" ? value.trim().length === 0 : !validCnj(value));
    const invalidCourts =
      mode === "selected" &&
      (!catalog.data ||
        selected.length === 0 ||
        selected.some(
          (code) => !catalog.data?.courts.some((court) => court.code === code),
        ));
    if (invalidValue || invalidCourts) {
      if (invalidValue) {
        setValueError(
          kind === "party"
            ? "Informe o nome completo da parte, não apenas espaços."
            : "Informe exatamente 20 dígitos ou a máscara NNNNNNN-DD.AAAA.J.TR.OOOO, sem espaços.",
        );
        input.current?.focus();
      }
      if (invalidCourts)
        setCourtError(
          !catalog.data
            ? "Consulte o catálogo antes de salvar uma seleção específica. Você também pode manter o filtro atual ou usar todos os tribunais."
            : "Selecione ao menos um tribunal do catálogo atual; remova códigos que não estão disponíveis.",
        );
      return;
    }
    const body: Record<string, unknown> = {};
    if (sendValue) body[config.field] = value;
    if (mode === "all") body.courts = null;
    if (mode === "selected") body.courts = selected;
    if (Object.keys(body).length === 0) {
      setFormError(
        "Nenhuma alteração informada. Altere o nome ou número, ou escolha um novo filtro de tribunais.",
      );
      return;
    }
    setPending(true);
    onBusyChange?.(true);
    try {
      const result = await api<MonitoringWriteResult>(
        recordId
          ? `${config.apiPath}/${encodeURIComponent(recordId)}`
          : config.apiPath,
        {
          method: editing ? "PATCH" : "POST",
          body,
        },
      );
      onSaved(result);
    } catch (reason: unknown) {
      setError(asError(reason));
    } finally {
      setPending(false);
      onBusyChange?.(false);
    }
  }

  return (
    <form
      className={styles.form}
      onSubmit={submit}
      noValidate
      aria-busy={pending}
    >
      <div className="field">
        <label htmlFor={`${id}-value`}>
          {config.label}{" "}
          {!editing || record
            ? "(obrigatório)"
            : "(opcional, apenas para substituir)"}
        </label>
        <input
          ref={input}
          id={`${id}-value`}
          name={config.field}
          type="text"
          inputMode={kind === "process" ? "numeric" : "text"}
          value={value}
          onChange={(event) => {
            setValue(event.target.value);
            setValueError(undefined);
          }}
          required={!editing || Boolean(record)}
          disabled={disabled}
          autoComplete="off"
          spellCheck={kind === "party"}
          aria-invalid={Boolean(valueError)}
          aria-describedby={`${id}-help${valueError ? ` ${id}-value-error` : ""}`}
        />
        <p id={`${id}-help`} className={styles.help}>
          {kind === "party"
            ? "Use o nome completo da pessoa ou empresa. Homônimos podem corresponder ao mesmo alvo; não há busca aproximada nem desambiguação automática."
            : "Digite 20 dígitos ou use NNNNNNN-DD.AAAA.J.TR.OOOO. Os zeros iniciais são preservados; o número não é convertido em valor numérico."}
        </p>
        {valueError && (
          <span
            id={`${id}-value-error`}
            className={styles.fieldError}
            role="alert"
          >
            {valueError}
          </span>
        )}
      </div>
      <CourtSelector
        editing={editing}
        mode={mode}
        selected={selected}
        savedCourts={record?.courts}
        catalog={catalog.data}
        loading={catalog.loading}
        catalogError={catalog.error}
        error={courtError}
        disabled={disabled}
        onModeChange={(next) => {
          setMode(next);
          setCourtError(undefined);
        }}
        onSelectionChange={(codes) => {
          setSelected(codes);
          setCourtError(undefined);
        }}
        onRetry={catalog.reload}
      />
      {formError && (
        <p className="error" role="alert">
          {formError}
        </p>
      )}
      {error && (
        <RequestError
          error={error}
          title="Não foi possível salvar o monitoramento"
        />
      )}
      {error && (
        <p className={styles.help}>
          Os dados preenchidos foram mantidos. Corrija o que for necessário e
          tente salvar novamente.
        </p>
      )}
      <div className={styles.actions}>
        <button className="button" type="submit" disabled={disabled}>
          {pending
            ? "Salvando…"
            : editing
              ? "Salvar alterações"
              : "Cadastrar monitoramento"}
        </button>
        <Link href="/monitoramentos" className="button-secondary">
          Voltar aos monitoramentos
        </Link>
      </div>
    </form>
  );
}
