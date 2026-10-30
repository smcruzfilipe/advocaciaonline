import type { SourceValue } from "../comunicacoes/types";

export type CollectionRun = {
  id: string;
  collection_date: string;
  slot: number;
  status: "planned" | "no_work" | "planning_failed" | "interrupted";
};

export type RunList = { runs: CollectionRun[] };

export type CollectionJob = {
  id: string;
  entity_type: string;
  entity_id: string;
  source: string;
  court: string;
  medium: string;
  criteria: { [key: string]: SourceValue };
  status: string;
};

export type ExecutionJob = {
  job_id: string;
  court: string;
  medium: string;
  state: "pending" | "running" | "succeeded" | "failed";
};

export type CollectionEvent = {
  id: string;
  job_id: string;
  event_type: "started" | "completed";
  recorded_at: string;
  entity_type: string;
  entity_id: string;
  source: string;
  court: string;
  medium: string;
};

const plans: Record<string, { label: string; description: string }> = {
  planned: {
    label: "Planejamento concluído",
    description:
      "O plano foi persistido. Isso não confirma início, término ou quantidade de publicações da coleta.",
  },
  no_work: {
    label: "Sem trabalho elegível",
    description:
      "Nenhum trabalho elegível foi planejado; isso não é uma coleta concluída com zero publicações.",
  },
  planning_failed: {
    label: "Falha de planejamento",
    description:
      "O planejamento falhou. Não é confirmação de consulta à fonte nem resultado vazio.",
  },
  interrupted: {
    label: "Planejamento interrompido",
    description:
      "O planejamento não foi recuperado antes da mudança de data local. Não há consulta retroativa automática.",
  },
};

export function planningState(status: string) {
  return Object.hasOwn(plans, status)
    ? plans[status]
    : {
        label: status,
        description: "Estado de planejamento informado pelo servidor.",
      };
}

export function executionState(state: string) {
  const labels: Record<string, string> = {
    pending: "Pendente — ainda não iniciado",
    running: "Em andamento — processamento iniciado",
    succeeded: "Concluído — sucesso confirmado",
    failed: "Falha operacional",
  };
  return Object.hasOwn(labels, state) ? labels[state] : state;
}
