# Mapa de capacidades: monitoramento jurídico

Mapa e seis especificações aprovados pelo solicitante como base funcional, mantendo as decisões técnicas pendentes como bloqueios antes da implementação. Requisitos e evidências anteriores: [especificação geral](docs/especificacao.md); [intenção confirmada](docs/intent/monitoramento-juridico.md).

| Módulo | Responsabilidade | Dependências | Especificação |
|---|---|---|---|
| identidade | Login, tenant, onboarding, expiração | — | [identidade](SPEC-identidade.md) |
| autorizacao | Usuários, grupos, operações, escopos | identidade | [autorizacao](SPEC-autorizacao.md) |
| monitoramentos | Advogado, partes, processos, filtros | identidade, autorizacao | [monitoramentos](SPEC-monitoramentos.md) |
| escrevente | Registros imutáveis do fluxo de coleta | identidade | [escrevente](SPEC-escrevente.md) |
| coleta | Planejamento somente D, caderno/fallback no primeiro slot, API direta no segundo, sanitização da API e deduplicação | monitoramentos, escrevente | [coleta](SPEC-coleta.md) |
| consulta | Comunicações, detalhes, volumetrias, avisos | autorizacao, coleta | [consulta](SPEC-consulta.md) |

Ordem: identidade → autorização e Escrevente → monitoramentos → coleta → consulta. Dependências expressam contratos lógicos, não exigem um serviço por módulo. A coleta inclui despachante/control plane e microaplicações de ETL separadas da aplicação central.

Regra vigente da coleta: somente Diário Eletrônico (`D`), sem editais (`E`), usando exclusivamente a data corrente. Primeiro slot: caderno com fallback API; segundo slot: API diretamente, sem caderno. Sanitizar apenas `texto` da API, não dos cadernos. A deduplicação conserva a primeira versão, que pode conter HTML; todo consumidor deve escapar o conteúdo na renderização. Evidências antigas com `E` não ampliam esse contrato.

Contratos compartilhados de especificação: contexto autenticado identifica usuário e tenant no servidor, respeita expiração e não aceita tenant enviado pelo cliente como prova de acesso. Autorização decide operação e escopo por tribunal/dashboard. Monitoramentos fornecem identidade da entidade e seu tenant; coleta persiste publicações com vínculos e status por execução/tribunal; Escrevente recebe registros de fluxo append-only. Formatos técnicos e transportes ainda não foram escolhidos.

O plano e checklist de monitoramento em `tasks/` registram os gates 1–3 e o estado de cada entrega. `dev` é a branch padrão; cada feature nasce de `dev`.

## Agenda e atendimento online

**Estado:** mapa de capacidades, fronteiras e ordem de dependência aprovados pelo solicitante. A especificação de agenda também foi aprovada como base funcional; as demais ainda não foram criadas. Essas aprovações não liberam implementação e não alteram o plano/checklist vigente de monitoramento jurídico. Fonte: [ideia refinada](docs/ideas/agenda-atendimento-online.md).

| Módulo | Responsabilidade | Dependências | Especificação / estado |
|---|---|---|---|
| agenda | Disponibilidade, compromissos presenciais/online, participantes, remarcação, cancelamento e prevenção de sobreposição; gestão pelo advogado e equipe autorizada | identidade, autorizacao | [SPEC-agenda.md](SPEC-agenda.md) — aprovada funcionalmente |
| reservas-clientes | Emissão e controle do link individual, acesso sem cadastro, exposição apenas de horários reserváveis e reserva direta pelas regras da agenda | agenda; identidade e autorizacao para gestão interna dos links | `SPEC-reservas-clientes.md` |
| reunioes-online | Sala vinculada ao compromisso, Jitsi integrado, convidados sem conta, anfitrião e admissão | agenda, identidade, autorizacao | `SPEC-reunioes-online.md` |
| integracao-google-agenda | Autorização específica do calendário e publicação, atualização e cancelamento do evento Google; estado da publicação; sem consultar ocupação ou importar alterações | agenda, identidade, autorizacao | `SPEC-integracao-google-agenda.md` |
| convites-reuniao | E-mails de confirmação, remarcação e cancelamento, detalhes do compromisso, link de entrada quando online e estado do envio | agenda, reunioes-online | `SPEC-convites-reuniao.md` |

Ordem de dependência: contratos existentes de identidade/autorização → agenda → reservas-clientes, reunioes-online e integracao-google-agenda → convites-reuniao. Os módulos são fronteiras lógicas, não serviços ou containers obrigatoriamente separados.

Fronteiras aprovadas:

- Agenda é a única dona das regras de disponibilidade e confirmação sem sobreposição, tanto para agendamento interno quanto para reserva externa.
- Cliente externo não é usuário de equipe; o link individual não concede acesso à área privada e não herda o contrato de convite de equipe.
- Operações de agenda delegáveis à secretária exigem especificação e aprovação no catálogo de autorização; permissões existentes não concedem essas operações por inferência.
- Falha de Google ou e-mail não desfaz a reserva confirmada nem libera seu horário. Reserva, disponibilidade da chamada, publicação e envio têm estados distinguíveis.
- Convites obtêm o acesso online de reunioes-online, sem depender da publicação no Google.
- Não há dependência desta iniciativa em monitoramentos, coleta, consulta ou Escrevente; o despachante da coleta não se torna agendador genérico da agenda.

Decisões confirmadas: duração única de 1 a 120 minutos, intervalo de 0 a 60 minutos e antecedência de 0 a 10.080 minutos, configurados pelo advogado sem defaults ou exceção automática à equipe; consulta de até 15 datas locais por requisição, não horizonte de reserva. AG01–AG03 concluídas documentalmente: convenções de tempo, preservação de compromissos, matriz canônica, schema, funções restritas, ABIs e HTTP aprovados. Disponibilidade mínima por cadastro/remarcação não concede detalhes de ocupantes. O backend de equipe e grupos foi implementado; as ABIs/contexto limitado da agenda e o frontend compartilhado ainda precisam ser comprovados em AG04. Nenhum componente da agenda foi implementado. As decisões dos demais módulos permanecem nos respectivos gates.

Plano, [checklist](tasks/agenda/todo.md) e [contrato técnico](SPEC-agenda.md#contrato-técnico-aprovado--ag01-e-ag03) aprovados. Gate atual: AG04/C0, comprovação de provedores compartilhados e ambiente reais; AG01–AG03 são conclusões documentais, não provas de runtime. Usar explicitamente `tasks/agenda/plan.md` e `tasks/agenda/todo.md`, preservando os arquivos padrão. As demais capacidades mantêm gates próprios.
