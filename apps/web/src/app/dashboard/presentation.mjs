const numberFormat = new Intl.NumberFormat("pt-BR");

const states = {
  succeeded: {
    label: "Coleta concluída",
    description:
      "Os tribunais autorizados apresentados concluíram integralmente a coleta. Zero representa ausência de registros novos qualificados no escopo concluído.",
  },
  partial: {
    label: "Resultado parcial",
    description:
      "As métricas incluem somente tribunais autorizados integralmente concluídos. Tribunais parciais, em andamento ou com falha não são tratados como zero.",
  },
  running: {
    label: "Coleta em andamento",
    description:
      "Há trabalho ainda não concluído. A ausência de contagem não significa zero comunicações.",
  },
  failed: {
    label: "Falha na coleta",
    description:
      "A coleta não produziu um resultado integral concluído no escopo atual. Falha não representa zero comunicações.",
  },
  no_work: {
    label: "Sem trabalho elegível",
    description:
      "O planejamento não encontrou trabalho elegível. Isso não significa que uma consulta à fonte tenha sido concluída sem publicações.",
  },
  unavailable: {
    label: "Resultado indisponível",
    description:
      "Não há resultado de coleta disponível neste escopo. Não é possível concluir que houve zero comunicações ou falha persistente.",
  },
  masked: {
    label: "Sem permissão para as métricas",
    description:
      "Todos os números protegidos são apresentados como *. Estados e avisos referem-se somente a tribunais cuja leitura foi autorizada.",
  },
};

export function statePresentation(state) {
  return Object.hasOwn(states, state)
    ? states[state]
    : {
        label: `Estado informado: ${state}`,
        description:
          "O servidor informou este estado sem uma descrição disponível na interface.",
      };
}

export function metricPresentation(value, masked = false) {
  if (masked || value === "*") return { value: "*", note: "Sem permissão" };
  if (value === null)
    return { value: "—", note: "Sem resultado integral concluído disponível" };
  return {
    value: numberFormat.format(value),
    note:
      value === 0 ? "Zero no escopo concluído" : "Contagem no escopo concluído",
  };
}
