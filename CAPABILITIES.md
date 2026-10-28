# Mapa de capacidades: monitoramento jurídico

Mapa e seis especificações aprovados pelo solicitante como base funcional, mantendo as decisões técnicas pendentes como bloqueios antes da implementação. Requisitos e evidências anteriores: [especificação geral](docs/especificacao.md); [intenção confirmada](docs/intent/monitoramento-juridico.md).

| Módulo | Responsabilidade | Dependências | Especificação |
|---|---|---|---|
| identidade | Login, tenant, onboarding, expiração | — | [identidade](SPEC-identidade.md) |
| autorizacao | Usuários, grupos, operações, escopos | identidade | [autorizacao](SPEC-autorizacao.md) |
| monitoramentos | Advogado, partes, processos, filtros | identidade, autorizacao | [monitoramentos](SPEC-monitoramentos.md) |
| escriba | Registros imutáveis do fluxo de coleta | identidade | [escriba](SPEC-escriba.md) |
| coleta | Planejamento, cadernos, fallback, normalização, deduplicação | monitoramentos, escriba | [coleta](SPEC-coleta.md) |
| consulta | Comunicações, detalhes, volumetrias, avisos | autorizacao, coleta | [consulta](SPEC-consulta.md) |

Ordem: identidade → autorização e Escriba → monitoramentos → coleta → consulta. Dependências expressam contratos lógicos, não exigem um serviço por módulo. A coleta inclui planejador/control plane e microaplicações de ETL separadas da aplicação central.

Contratos compartilhados de especificação: contexto autenticado identifica usuário e tenant no servidor, respeita expiração e não aceita tenant enviado pelo cliente como prova de acesso. Autorização decide operação e escopo por tribunal/dashboard. Monitoramentos fornecem identidade da entidade e seu tenant; coleta persiste publicações com vínculos e status por execução/tribunal; Escriba recebe registros de fluxo append-only. Formatos técnicos e transportes ainda não foram escolhidos.

O plano e checklist existentes em `tasks/` foram aprovados pelo solicitante e revisados pelo advisor; as decisões técnicas bloqueantes continuam pendentes antes da implementação. `dev` é a branch padrão; cada feature nasce de `dev`. Toda conclusão depende de feedback do advisor conforme [regras do projeto](AGENTS.md).
