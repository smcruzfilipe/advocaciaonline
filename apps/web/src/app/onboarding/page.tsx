"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { api, ApiError } from "@/lib/api";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { useSession } from "@/components/session-provider";

const UFS = [
  "AC",
  "AL",
  "AP",
  "AM",
  "BA",
  "CE",
  "DF",
  "ES",
  "GO",
  "MA",
  "MT",
  "MS",
  "MG",
  "PA",
  "PB",
  "PR",
  "PE",
  "PI",
  "RJ",
  "RN",
  "RS",
  "RO",
  "RR",
  "SC",
  "SP",
  "SE",
  "TO",
];
type Registration = { id: number; number: string; uf: string };

export default function OnboardingPage() {
  const router = useRouter();
  const { session, loading, pendingInvitation } = useSession();
  const [name, setName] = useState("");
  const [office, setOffice] = useState("");
  const [primaryNumber, setPrimaryNumber] = useState("");
  const [primaryUf, setPrimaryUf] = useState("");
  const [secondary, setSecondary] = useState<Registration[]>([]);
  const nextId = useRef(0);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [details, setDetails] = useState<Record<string, string[]>>({});
  const errorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (loading || !session) return;
    if (pendingInvitation) router.replace("/convite");
    else if (!session.authenticated) router.replace("/login");
    else if (session.selection_required) router.replace("/vinculos");
    else if (session.onboarded) router.replace("/dashboard");
  }, [loading, pendingInvitation, router, session]);
  useEffect(() => {
    if (error) errorRef.current?.focus();
  }, [error]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    setSaving(true);
    setError(null);
    setDetails({});
    try {
      await api("/api/onboarding", {
        method: "POST",
        body: {
          full_name: name,
          office_name: office || null,
          primary_oab: { number: primaryNumber, uf: primaryUf },
          secondary_oabs: secondary.map(({ number, uf }) => ({ number, uf })),
        },
      });
      setSaved(true);
      navigateAfterIdentityChange("/dashboard");
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : "Não foi possível cadastrar seu perfil.",
      );
      if (
        reason instanceof ApiError &&
        reason.details &&
        typeof reason.details === "object"
      ) {
        const fields: Record<string, string[]> = {};
        for (const [key, value] of Object.entries(reason.details)) {
          if (Array.isArray(value))
            fields[key] = value.filter(
              (item): item is string => typeof item === "string",
            );
        }
        setDetails(fields);
      }
      setSaving(false);
    }
  }

  function updateRegistration(
    id: number,
    field: "number" | "uf",
    value: string,
  ) {
    setSecondary((rows) =>
      rows.map((row) => (row.id === id ? { ...row, [field]: value } : row)),
    );
  }

  if (
    loading ||
    !session?.authenticated ||
    session.onboarded ||
    session.selection_required ||
    pendingInvitation
  ) {
    return (
      <section className="page access-page" aria-busy="true">
        <h1>Perfil profissional</h1>
        <p role="status">Consultando seu acesso…</p>
      </section>
    );
  }

  return (
    <section className="page onboarding-page stack">
      <header className="stack">
        <span className="eyebrow">Primeiro acesso</span>
        <h1>Cadastre seu perfil profissional</h1>
        <p className="muted">
          Seu ambiente pertence a você, advogado titular. O nome do escritório é
          opcional e não cria um ambiente separado.
        </p>
      </header>
      {error && (
        <div className="error stack" role="alert" tabIndex={-1} ref={errorRef}>
          <strong>Não foi possível cadastrar o perfil</strong>
          <p>{error}</p>
        </div>
      )}
      {saved && (
        <p className="notice" role="status">
          Perfil cadastrado. Abrindo seu ambiente…
        </p>
      )}
      <form
        className="stack"
        onSubmit={(event) => void save(event)}
        aria-busy={saving}
      >
        <fieldset className="stack" disabled={saving}>
          <legend>Seus dados</legend>
          <div className="field">
            <label htmlFor="full-name">Nome completo (obrigatório)</label>
            <input
              id="full-name"
              name="full_name"
              autoComplete="name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              required
              aria-invalid={Boolean(details.full_name?.length)}
              aria-describedby={
                details.full_name?.length ? "full-name-error" : undefined
              }
            />
            {details.full_name?.length > 0 && (
              <p id="full-name-error" className="field-error">
                {details.full_name.join(" ")}
              </p>
            )}
          </div>
          <div className="field">
            <label htmlFor="office-name">Nome do escritório (opcional)</label>
            <input
              id="office-name"
              name="office_name"
              autoComplete="organization"
              value={office}
              onChange={(event) => setOffice(event.target.value)}
              aria-invalid={Boolean(details.office_name?.length)}
              aria-describedby="office-help office-error"
            />
            <p id="office-help" className="muted small">
              O escritório não altera sua identidade ou a titularidade do
              ambiente.
            </p>
            <p id="office-error" className="field-error">
              {details.office_name?.join(" ")}
            </p>
          </div>
        </fieldset>
        <fieldset
          className="stack"
          disabled={saving}
          aria-describedby="primary-oab-help primary-oab-error"
        >
          <legend>OAB principal (obrigatória)</legend>
          <p id="primary-oab-help" className="muted small">
            Informe o número exatamente como na inscrição, preservando zeros e
            sufixos. Não há verificação externa de inscrição.
          </p>
          <div className="form-columns">
            <div className="field">
              <label htmlFor="primary-number">Número da OAB</label>
              <input
                id="primary-number"
                name="primary_number"
                value={primaryNumber}
                onChange={(event) => setPrimaryNumber(event.target.value)}
                required
                aria-invalid={Boolean(details.primary_oab?.length)}
                aria-describedby="primary-oab-error"
              />
            </div>
            <div className="field">
              <label htmlFor="primary-uf">UF da OAB</label>
              <select
                id="primary-uf"
                name="primary_uf"
                value={primaryUf}
                onChange={(event) => setPrimaryUf(event.target.value)}
                required
                aria-invalid={Boolean(details.primary_oab?.length)}
                aria-describedby="primary-oab-error"
              >
                <option value="">Selecione a UF</option>
                {UFS.map((uf) => (
                  <option value={uf} key={uf}>
                    {uf}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <p id="primary-oab-error" className="field-error">
            {details.primary_oab?.join(" ")}
          </p>
        </fieldset>
        <fieldset
          className="stack"
          disabled={saving}
          aria-describedby="secondary-oab-help secondary-oab-error"
        >
          <legend>OABs secundárias (opcionais)</legend>
          <p id="secondary-oab-help" className="muted small">
            Adicione apenas as inscrições que você possui. Não repita o mesmo
            número e UF.
          </p>
          {secondary.map((registration, index) => (
            <div className="registration-row stack" key={registration.id}>
              <h3>Inscrição secundária {index + 1}</h3>
              <div className="form-columns">
                <div className="field">
                  <label htmlFor={`secondary-number-${registration.id}`}>
                    Número da OAB
                  </label>
                  <input
                    id={`secondary-number-${registration.id}`}
                    value={registration.number}
                    onChange={(event) =>
                      updateRegistration(
                        registration.id,
                        "number",
                        event.target.value,
                      )
                    }
                    required
                    aria-invalid={Boolean(details.secondary_oabs?.length)}
                    aria-describedby="secondary-oab-error"
                  />
                </div>
                <div className="field">
                  <label htmlFor={`secondary-uf-${registration.id}`}>
                    UF da OAB
                  </label>
                  <select
                    id={`secondary-uf-${registration.id}`}
                    value={registration.uf}
                    onChange={(event) =>
                      updateRegistration(
                        registration.id,
                        "uf",
                        event.target.value,
                      )
                    }
                    required
                    aria-invalid={Boolean(details.secondary_oabs?.length)}
                    aria-describedby="secondary-oab-error"
                  >
                    <option value="">Selecione a UF</option>
                    {UFS.map((uf) => (
                      <option value={uf} key={uf}>
                        {uf}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
              <button
                className="button-secondary"
                type="button"
                onClick={() =>
                  setSecondary((rows) =>
                    rows.filter((row) => row.id !== registration.id),
                  )
                }
              >
                Remover inscrição secundária {index + 1}
              </button>
            </div>
          ))}
          <p id="secondary-oab-error" className="field-error">
            {details.secondary_oabs?.join(" ")}
          </p>
          <button
            className="button-secondary"
            type="button"
            onClick={() => {
              const id = nextId.current++;
              setSecondary((rows) => [...rows, { id, number: "", uf: "" }]);
            }}
          >
            Adicionar OAB secundária
          </button>
        </fieldset>
        <div className="row">
          <button className="button" type="submit" disabled={saving}>
            {saving ? "Cadastrando…" : "Concluir cadastro"}
          </button>
          <Link href="/convite">Recebi um convite de equipe</Link>
        </div>
      </form>
    </section>
  );
}
