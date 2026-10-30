export type GroupRule = {
  id: string;
  operation: string;
  effect: "allow" | "deny";
  court: string | null;
};

export type AuthorizationGroup = {
  id: string;
  name: string;
  rules: GroupRule[];
  membership_ids: string[];
};

export type CatalogOperation = {
  operation: string;
  scope: "tenant" | "court";
};

export type Court = { code: string; name: string };

const operationLabels: Record<string, string> = {
  consultar_monitoramentos: "Consultar monitoramentos",
  consultar_comunicacoes: "Consultar comunicações",
  consultar_dashboard: "Consultar dashboard",
  cadastrar_monitoramento: "Cadastrar monitoramento",
  editar_monitoramento: "Editar monitoramento",
  desativar_monitoramento: "Desativar monitoramento",
  consultar_agenda: "Consultar agenda",
  cadastrar_compromisso: "Cadastrar compromisso",
  remarcar_compromisso: "Remarcar compromisso",
  cancelar_compromisso: "Cancelar compromisso",
};

export function operationLabel(operation: string) {
  return operationLabels[operation] ?? operation;
}
