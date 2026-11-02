"use client";

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
  compact = false,
}: {
  id: string;
  choice: ValidityChoice;
  days: string;
  onChoice: (value: ValidityChoice) => void;
  onDays: (value: string) => void;
  disabled?: boolean;
  compact?: boolean;
}) {
  return (
    <fieldset
      className="flex flex-col gap-2 text-sm min-w-0"
      disabled={disabled}
      aria-describedby={`${id}-help`}
    >
      <legend className="text-sm font-medium text-foreground mb-2">
        {compact ? "Alterar validade" : "Validade da credencial (obrigatória)"}
      </legend>
      <div
        className={
          compact
            ? "grid grid-cols-1 min-[400px]:grid-cols-2 gap-3"
            : "flex flex-col gap-2"
        }
      >
        <label
          className={`flex items-center gap-2 px-3 ${compact ? "py-2" : "py-2.5"} border ${choice === "unlimited" ? "border-foreground bg-secondary" : "border-border bg-background"}`}
        >
          <input
            type="radio"
            name={`${id}-validity`}
            value="unlimited"
            required
            checked={choice === "unlimited"}
            onChange={() => onChoice("unlimited")}
          />
          <span>Sem expiração</span>
        </label>
        <div
          className={`flex items-center gap-2 px-3 ${compact ? "py-2" : "py-2.5"} border ${choice === "days" ? "border-foreground bg-secondary" : "border-border bg-background"}`}
        >
          <label className="flex items-center gap-2 shrink-0">
            <input
              type="radio"
              name={`${id}-validity`}
              value="days"
              required
              checked={choice === "days"}
              onChange={() => onChoice("days")}
            />
            <span>{compact ? "Dias:" : "Número de dias"}</span>
          </label>
          <input
            id={`${id}-days`}
            aria-label="Dias inteiros positivos"
            className={`${compact ? "w-16 bg-background px-2 py-0.5" : "w-24 bg-input px-3 py-1 ml-2"} min-w-0 border border-border text-sm disabled:opacity-50`}
            type="number"
            inputMode="numeric"
            min="1"
            max="2147483647"
            step="1"
            placeholder="Ex.: 30"
            disabled={choice !== "days"}
            required={choice === "days"}
            value={days}
            onChange={(event) => onDays(event.target.value)}
          />
        </div>
      </div>
      <p id={`${id}-help`} className="text-xs text-muted-foreground">
        Cada dia corresponde a 24 horas, contadas desde a criação ou renovação,
        não desde o aceite.
      </p>
    </fieldset>
  );
}
