export type MonitoringKind = "party" | "process";

export type Court = { code: string; name: string };
export type CourtCatalog = { courts: Court[] };

export type LawyerMonitoring = {
  id: string;
  tenant_id: string;
  full_name: string;
  oabs: { number: string; uf: string }[];
};

type MonitoringBase = {
  id: string;
  tenant_id: string;
  courts: string[] | null;
  active: boolean;
};

export type PartyMonitoring = MonitoringBase & { name: string };
export type ProcessMonitoring = MonitoringBase & { number: string };
export type Monitoring = PartyMonitoring | ProcessMonitoring;
export type MonitoringWriteResult = Monitoring | { id: string } | undefined;

export const monitoringConfig = {
  party: {
    apiPath: "/api/monitorings/parties",
    path: "/monitoramentos/partes",
    newPath: "/monitoramentos/partes/nova",
    title: "Parte monitorada",
    newTitle: "Nova parte monitorada",
    field: "name",
    label: "Nome completo da parte",
  },
  process: {
    apiPath: "/api/monitorings/processes",
    path: "/monitoramentos/processos",
    newPath: "/monitoramentos/processos/novo",
    title: "Processo monitorado",
    newTitle: "Novo processo monitorado",
    field: "number",
    label: "Número CNJ",
  },
} as const;

export function monitoringName(record: Monitoring): string {
  return "name" in record ? record.name : record.number;
}

export function courtDescription(courts: string[] | null): string {
  return courts === null ? "Todos os tribunais disponíveis" : courts.join(", ");
}

export function isCompleteMonitoring(
  result: MonitoringWriteResult,
): result is Monitoring {
  return result !== undefined && "active" in result;
}

export function validCnj(number: string): boolean {
  return (
    (number.length === 20 || number.length === 25) &&
    /^(?:[0-9]{20}|[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[0-9]\.[0-9]{2}\.[0-9]{4})$/.test(
      number,
    )
  );
}

export function asError(error: unknown): Error {
  return error instanceof Error
    ? error
    : new Error("Não foi possível concluir a solicitação. Tente novamente.");
}
