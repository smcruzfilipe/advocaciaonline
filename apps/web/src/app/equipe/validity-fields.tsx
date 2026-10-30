"use client";

import styles from "./admin.module.css";

export type ValidityChoice = "" | "unlimited" | "days";

export function validityValue(
  choice: ValidityChoice,
  days: string,
): number | null {
  if (choice === "unlimited") return null;
  const value = Number(days);
  if (
    choice !== "days" ||
    !/^[0-9]+$/.test(days) ||
    !Number.isInteger(value) ||
    value < 1 ||
    value > 2_147_483_647
  ) {
    throw new Error(
      "Escolha sem expiração ou informe um número inteiro positivo de dias (até 2.147.483.647).",
    );
  }
  return value;
}

export default function ValidityFields({
  id,
  choice,
  days,
  onChoice,
  onDays,
  disabled,
}: {
  id: string;
  choice: ValidityChoice;
  days: string;
  onChoice: (value: ValidityChoice) => void;
  onDays: (value: string) => void;
  disabled?: boolean;
}) {
  return (
    <fieldset
      className="stack"
      disabled={disabled}
      aria-describedby={`${id}-help`}
    >
      <legend>Validade da credencial (obrigatória)</legend>
      <label className={styles.choice}>
        <input
          type="radio"
          name={`${id}-validity`}
          value="unlimited"
          required
          checked={choice === "unlimited"}
          onChange={() => onChoice("unlimited")}
        />
        Sem expiração
      </label>
      <label className={styles.choice}>
        <input
          type="radio"
          name={`${id}-validity`}
          value="days"
          required
          checked={choice === "days"}
          onChange={() => onChoice("days")}
        />
        Número de dias
      </label>
      {choice === "days" && (
        <div className="field">
          <label htmlFor={`${id}-days`}>Dias inteiros positivos</label>
          <input
            id={`${id}-days`}
            type="number"
            inputMode="numeric"
            min="1"
            max="2147483647"
            step="1"
            required
            value={days}
            onChange={(event) => onDays(event.target.value)}
          />
        </div>
      )}
      <p id={`${id}-help`} className="muted">
        Cada dia corresponde a 24 horas, contadas desde a criação ou renovação,
        não desde o aceite.
      </p>
    </fieldset>
  );
}
