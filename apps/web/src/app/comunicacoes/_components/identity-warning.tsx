import { AlertBanner } from "@/components/ui";
import type { Communication } from "../types";

export function IdentityWarning({
  communication,
}: {
  communication: Communication;
}) {
  if (
    communication.identity_status !== "pending" &&
    communication.warning !== "possible_duplicate"
  )
    return null;

  return (
    <AlertBanner variant="warning">
      <strong>Identidade pendente — possível duplicidade.</strong> A fonte não
      forneceu uma combinação válida de identificador e hash. Esta comunicação
      permanece separada e não compõe as métricas do painel.
    </AlertBanner>
  );
}
