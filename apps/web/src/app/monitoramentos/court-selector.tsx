"use client";

import { useId, useState } from "react";
import type { CourtCatalog } from "./monitoring";
import { RequestError } from "./request-error";
import styles from "./monitoramentos.module.css";

export type CourtMode = "keep" | "all" | "selected";

type Props = {
  editing: boolean;
  mode: CourtMode;
  selected: string[];
  savedCourts?: string[] | null;
  catalog?: CourtCatalog;
  loading: boolean;
  catalogError?: Error;
  error?: string;
  disabled: boolean;
  onModeChange: (mode: CourtMode) => void;
  onSelectionChange: (codes: string[]) => void;
  onRetry: () => void;
};

export function CourtSelector({
  editing,
  mode,
  selected,
  savedCourts,
  catalog,
  loading,
  catalogError,
  error,
  disabled,
  onModeChange,
  onSelectionChange,
  onRetry,
}: Props) {
  const id = useId();
  const [search, setSearch] = useState("");
  const unavailable = catalog
    ? selected.filter(
        (code) => !catalog.courts.some((court) => court.code === code),
      )
    : [];
  const query = search.trim().toLocaleLowerCase("pt-BR");
  const courts = catalog?.courts.filter((court) =>
    `${court.code} ${court.name}`.toLocaleLowerCase("pt-BR").includes(query),
  );

  return (
    <fieldset
      className={styles.fieldset}
      disabled={disabled}
      aria-describedby={`${id}-help${error ? ` ${id}-error` : ""}`}
      aria-invalid={Boolean(error)}
    >
      <legend>Tribunais</legend>
      <p id={`${id}-help`} className={styles.help}>
        Todos abrange os tribunais disponibilizados pela fonte. Uma seleção
        específica exige ao menos um tribunal do catálogo real.
      </p>
      {editing && (
        <label className={styles.choice}>
          <input
            type="radio"
            name={`${id}-mode`}
            value="keep"
            checked={mode === "keep"}
            onChange={() => onModeChange("keep")}
          />
          <span>
            Manter filtro atual
            {savedCourts === null
              ? " — todos os tribunais disponíveis"
              : savedCourts
                ? ` — ${savedCourts.join(", ")}`
                : " (sem consultar os dados protegidos)"}
          </span>
        </label>
      )}
      <label className={styles.choice}>
        <input
          type="radio"
          name={`${id}-mode`}
          value="all"
          checked={mode === "all"}
          onChange={() => onModeChange("all")}
        />
        <span>Todos os tribunais disponíveis</span>
      </label>
      <label className={styles.choice}>
        <input
          type="radio"
          name={`${id}-mode`}
          value="selected"
          checked={mode === "selected"}
          onChange={() => onModeChange("selected")}
        />
        <span>Selecionar tribunais específicos</span>
      </label>
      {mode === "selected" && (
        <div className="stack" aria-busy={loading}>
          {loading && <p role="status">Carregando catálogo de tribunais…</p>}
          {catalogError && (
            <RequestError
              error={catalogError}
              onRetry={onRetry}
              title="Catálogo de tribunais indisponível"
            />
          )}
          {catalog && (
            <>
              <div className="field">
                <label htmlFor={`${id}-search`}>
                  Buscar tribunal no catálogo
                </label>
                <input
                  id={`${id}-search`}
                  type="search"
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
              </div>
              <p className={styles.help}>
                {selected.length} tribunal(is) na nova seleção.
              </p>
              {catalog.courts.length === 0 ? (
                <p>
                  Nenhum tribunal foi disponibilizado pela fonte. Use todos os
                  tribunais ou mantenha o filtro salvo.
                </p>
              ) : courts?.length === 0 ? (
                <p>Nenhum tribunal corresponde à busca.</p>
              ) : (
                <div className={styles.catalog}>
                  {courts?.map((court) => (
                    <label className={styles.choice} key={court.code}>
                      <input
                        type="checkbox"
                        checked={selected.includes(court.code)}
                        onChange={(event) =>
                          onSelectionChange(
                            event.target.checked
                              ? [...selected, court.code]
                              : selected.filter((code) => code !== court.code),
                          )
                        }
                      />
                      <span>
                        <strong>{court.code}</strong> — {court.name}
                      </span>
                    </label>
                  ))}
                </div>
              )}
              {unavailable.length > 0 && (
                <div className="notice stack">
                  <p>
                    Os códigos abaixo estavam salvos, mas não constam no
                    catálogo atual. Eles não serão substituídos por todos os
                    tribunais. Mantenha o filtro atual ou remova-os da nova
                    seleção.
                  </p>
                  {unavailable.map((code) => (
                    <div className={styles.actions} key={code}>
                      <span>{code} — indisponível no catálogo atual</span>
                      <button
                        className="button-secondary"
                        type="button"
                        onClick={() =>
                          onSelectionChange(
                            selected.filter(
                              (selectedCode) => selectedCode !== code,
                            ),
                          )
                        }
                      >
                        Remover {code} da nova seleção
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      )}
      {mode !== "selected" && catalogError && (
        <p className={styles.help}>
          O catálogo não pôde ser consultado.{" "}
          {mode === "keep"
            ? "O filtro salvo será preservado."
            : "Todos os tribunais continua significando ausência de filtro específico."}{" "}
          Para alterar a seleção, consulte o catálogo novamente.
        </p>
      )}
      {error && (
        <span id={`${id}-error`} className={styles.fieldError}>
          {error}
        </span>
      )}
    </fieldset>
  );
}
