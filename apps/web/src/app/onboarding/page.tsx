"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { api, ApiError } from "@/lib/api";
import { navigateAfterIdentityChange } from "@/lib/identity-navigation";
import { useSession } from "@/components/session-provider";
import { AlertBanner, Btn, FormField, Icon } from "@/components/ui";

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
      <section className="mx-auto max-w-xl px-4 py-12 sm:px-0" aria-busy="true">
        <h1 className="mb-2 text-2xl font-semibold">Perfil profissional</h1>
        <p className="text-sm text-muted-foreground" role="status">
          Consultando seu acesso…
        </p>
      </section>
    );
  }

  return (
    <section className="mx-auto flex w-full max-w-xl flex-col gap-6 px-4 py-12 sm:px-0">
      <header>
        <h1 className="mb-1 font-headings text-2xl font-semibold text-foreground">
          Complete seu perfil
        </h1>
        <p className="text-sm text-muted-foreground">
          Informe seus dados profissionais para começar a usar a plataforma.
        </p>
      </header>
      {error && (
        <div tabIndex={-1} ref={errorRef}>
          <AlertBanner variant="error">
            <strong>Não foi possível cadastrar o perfil. </strong>
            {error}
          </AlertBanner>
        </div>
      )}
      {saved && (
        <AlertBanner variant="success">
          Perfil cadastrado. Abrindo seu ambiente…
        </AlertBanner>
      )}
      {saving && !saved && (
        <AlertBanner variant="info">Salvando suas informações…</AlertBanner>
      )}
      <form
        className="flex flex-col gap-6"
        onSubmit={(event) => void save(event)}
        aria-busy={saving}
      >
        <fieldset
          disabled={saving}
          className="flex min-w-0 flex-col gap-5 border border-border p-6 [&_input]:w-full [&_input]:border [&_input]:border-border [&_input]:bg-input [&_input]:px-3 [&_input]:py-2 [&_input]:text-sm [&_select]:w-full [&_select]:border [&_select]:border-border [&_select]:bg-input [&_select]:px-3 [&_select]:py-2 [&_select]:text-sm"
        >
          <legend className="sr-only">Seus dados profissionais</legend>
          <FormField
            label="Nome completo"
            required
            htmlFor="full-name"
            error={details.full_name?.join(" ")}
          >
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
          </FormField>
          <div className="border-t border-border pt-5">
            <h2 className="mb-3 text-sm font-medium">OAB principal</h2>
            <div className="flex gap-3">
              <div className="min-w-0 flex-1">
                <FormField label="Número" required htmlFor="primary-number">
                  <input
                    id="primary-number"
                    name="primary_number"
                    value={primaryNumber}
                    onChange={(event) => setPrimaryNumber(event.target.value)}
                    required
                    aria-invalid={Boolean(details.primary_oab?.length)}
                    aria-describedby="primary-oab-help primary-oab-error"
                  />
                </FormField>
              </div>
              <div className="w-24 shrink-0">
                <FormField label="Estado" required htmlFor="primary-uf">
                  <select
                    id="primary-uf"
                    name="primary_uf"
                    value={primaryUf}
                    onChange={(event) => setPrimaryUf(event.target.value)}
                    required
                    aria-invalid={Boolean(details.primary_oab?.length)}
                    aria-describedby="primary-oab-error"
                  >
                    <option value="">UF</option>
                    {UFS.map((uf) => (
                      <option value={uf} key={uf}>
                        {uf}
                      </option>
                    ))}
                  </select>
                </FormField>
              </div>
            </div>
            <p
              id="primary-oab-help"
              className="mt-2 text-xs text-muted-foreground"
            >
              Preserve zeros e sufixos da inscrição. Não há verificação externa
              de inscrição.
            </p>
            <p id="primary-oab-error" className="mt-1 text-xs text-error">
              {details.primary_oab?.join(" ")}
            </p>
          </div>
          <div className="border-t border-border pt-5">
            <div className="mb-3 flex items-center justify-between gap-3">
              <h2 className="text-sm font-medium">OABs secundárias</h2>
              <button
                className="flex items-center gap-1 text-xs text-accent underline"
                type="button"
                onClick={() => {
                  const id = nextId.current++;
                  setSecondary((rows) => [...rows, { id, number: "", uf: "" }]);
                }}
              >
                <Icon i="plus" size={13} />
                Adicionar
              </button>
            </div>
            <div className="flex flex-col gap-3">
              {secondary.map((registration, index) => (
                <div className="flex items-end gap-3" key={registration.id}>
                  <div className="min-w-0 flex-1">
                    <FormField
                      label="Número"
                      htmlFor={`secondary-number-${registration.id}`}
                    >
                      <input
                        id={`secondary-number-${registration.id}`}
                        aria-label={`Número da OAB secundária ${index + 1}`}
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
                    </FormField>
                  </div>
                  <div className="w-24 shrink-0">
                    <FormField
                      label="Estado"
                      htmlFor={`secondary-uf-${registration.id}`}
                    >
                      <select
                        id={`secondary-uf-${registration.id}`}
                        aria-label={`Estado da OAB secundária ${index + 1}`}
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
                        <option value="">UF</option>
                        {UFS.map((uf) => (
                          <option value={uf} key={uf}>
                            {uf}
                          </option>
                        ))}
                      </select>
                    </FormField>
                  </div>
                  <button
                    className="shrink-0 pb-2 text-muted-foreground"
                    type="button"
                    aria-label={`Remover inscrição secundária ${index + 1}`}
                    onClick={() =>
                      setSecondary((rows) =>
                        rows.filter((row) => row.id !== registration.id),
                      )
                    }
                  >
                    <Icon i="x" size={16} />
                  </button>
                </div>
              ))}
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Opcional. Não repita o mesmo número e UF.
            </p>
            <p id="secondary-oab-error" className="mt-1 text-xs text-error">
              {details.secondary_oabs?.join(" ")}
            </p>
          </div>
          <div className="border-t border-border pt-5">
            <FormField
              label="Nome do escritório"
              htmlFor="office-name"
              hint="Opcional. Identificação do seu escritório na plataforma; não cria um ambiente separado."
              error={details.office_name?.join(" ")}
            >
              <input
                id="office-name"
                name="office_name"
                autoComplete="organization"
                value={office}
                onChange={(event) => setOffice(event.target.value)}
                aria-invalid={Boolean(details.office_name?.length)}
                aria-describedby={`office-name-hint${details.office_name?.length ? " office-name-error" : ""}`}
              />
            </FormField>
          </div>
        </fieldset>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Link className="text-xs text-accent underline" href="/convite">
            Recebi um convite de equipe
          </Link>
          <Btn type="submit" disabled={saving}>
            {saving ? "Salvando…" : "Salvar perfil"}
          </Btn>
        </div>
      </form>
    </section>
  );
}
