import type { CatalogOperation, Court, GroupRule } from "./types";

type RuleInput = { operation?: string; effect?: string; court?: string | null };

export function prepareRuleInput({
  rule,
  operation,
  effect,
  selectedOperation,
  courtScope,
  court,
  courts,
}: {
  rule?: GroupRule;
  operation: string;
  effect: string;
  selectedOperation?: CatalogOperation;
  courtScope: string;
  court: string;
  courts: Court[] | null;
}): RuleInput {
  if (!selectedOperation || !["allow", "deny"].includes(effect))
    throw new Error(
      "Selecione uma operação do catálogo e escolha permitir ou negar.",
    );

  const selectedCourt =
    selectedOperation.scope === "court" && courtScope === "specific"
      ? court
      : null;
  if (
    selectedCourt !== null &&
    (!rule || selectedCourt !== rule.court) &&
    (!courts ||
      !courts.some((entry) => entry.code === selectedCourt) ||
      !/^[A-Za-z][A-Za-z0-9]{1,31}$/.test(selectedCourt))
  ) {
    throw new Error(
      "Selecione um tribunal válido do catálogo, aceito para regras de autorização.",
    );
  }

  if (!rule) return { operation, effect, court: selectedCourt };
  const body: RuleInput = {};
  if (operation !== rule.operation) body.operation = operation;
  if (effect !== rule.effect) body.effect = effect;
  if (selectedCourt !== rule.court) body.court = selectedCourt;
  if (Object.keys(body).length === 0)
    throw new Error("Altere ao menos um campo para salvar a regra.");
  return body;
}
