# Tarefas: monitoramento jurídico

Plano: [plan.md](plan.md). As seis specs, o plano e este checklist foram aprovados pelo solicitante; decisões 1–3 estão registradas. As tarefas implementadas e suas evidências constam nas respectivas seções. Essas evidências são anteriores à renomeação para processador, à API direta no segundo slot e à restrição ao meio D; não comprovam essas alterações nem foram repetidas nesta revisão. Referências históricas a E não autorizam coleta de editais.

## Regras de execução e rastreio

- Preservar os IDs principais 1–16; as fatias `a/b/c` ficam dentro do ID principal. O plano referencia somente os IDs principais.
- Cada fatia limita o aceite a três critérios, traz verificação comportamental e smoke próprios, dependências, escopo e até cinco áreas previstas de arquivos.
- **Fontes na implementação:** aplicar `source-driven-development` em cada fatia que dependa de framework, biblioteca ou serviço externo: identificar as versões efetivamente fixadas, consultar a documentação oficial específica antes de codificar, seguir as APIs documentadas e registrar os links que sustentam decisões não triviais. Conflitos com o código ou ausência de documentação devem ser explicitados; nenhuma consulta substitui teste ou verificação em execução.
- Áreas são módulos/artefatos lógicos, não caminhos inventados. Depois da decisão técnica 3a, registrar os caminhos exatos antes de executar cada fatia; se exceder cinco arquivos, redividir antes de executar.
- Não escolher stack, comandos, ferramentas, estruturas, formatos ou transportes antes das decisões 3a–3b. Resultados efetivos e verificações pendentes devem ser distinguidos nas respectivas tarefas.
- Fonte lógica DJEN, somente Diário Eletrônico (`D`), sem coleta de editais (`E`): no primeiro slot, cadernos ZIP/JSON com fallback API paginada; no segundo, API paginada diretamente, sem caderno; ambos usam exclusivamente a data corrente. Sanitizar apenas `texto` da API, não do caderno. Preservar a primeira versão deduplicada, que pode conter HTML e exige escape pelo consumidor. Não revalidar retroativamente a premissa aceita de estabilidade de `id`/`hash`, nem iniciar recuperação histórica.
- Implementação futura parte de `dev`; o branch atual de documentação não é base de feature. Convite de equipe por e-mail está no escopo aprovado; relatórios e avisos por e-mail e outras fontes ficam fora da primeira entrega.
- **Schema inicial consolidado:** para banco inicial vazio, as migrations criam diretamente o estado final, sem alterações intermediárias ou backfills históricos. `backend/db/migrate/20261028000003_create_collection_planning.rb` integra as antigas migrations 04–06; `backend/db/migrate/20261028000004_create_escrevente.rb` substitui a antiga 07. Não há rollback destrutivo nem upgrade automático de banco pré-existente.
- **Verificação da consolidação:** PostgreSQL isolado criou o schema novo; comparação com a sequência anterior confirmou 86 colunas, 138 constraints, 36 índices, 27 políticas, 15 funções e RLS/grants de 14 tabelas. Suíte: 276 testes, 7.678 assertions, sem falhas; smoke de onboarding e leitura autenticada passou. Evidências anteriores continuam históricas.

## Decisões bloqueantes — tarefas 1–3

### 1. Confirmar contrato da fonte

- [x] **1a — Fixar o contrato do caderno DJEN.**
  **Aceite:** (1) documentar tribunal e meio aplicáveis, ZIP e processamento de todos os JSONs; (2) mapear os campos e limitações observados para advogado/OAB, parte e processo, sem decidir regras de correspondência; (3) fixar somente a data corrente da execução.
  **Verificação comportamental:** revisar um caderno válido e cenários de ZIP incompleto/inválido, avaliando os campos disponíveis para cada tipo de entidade sem exigir decisão de matching.
  **Smoke específico:** percorrer, em revisão de contrato, um caderno JSON de um tribunal/data/meio e identificar os campos e limitações observados, sem executar coleta nem fixar correspondências.
  **Dep.:** nenhuma. **Escopo:** contrato funcional da fonte principal.
  **Áreas previstas (≤5):** especificação de coleta; referência do contrato DJEN.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [x] **1b — Fixar fallback e tratamento da fonte.**
  **Aceite:** (1) definir condições de fallback da primeira coleta e paginação da API, usada diretamente na segunda, sem caderno; (2) garantir meio `D` e datas inicial/final iguais à data corrente, distinguindo resposta válida vazia de falha; (3) manter caderno e API como a mesma fonte lógica DJEN, sem coleta de editais (`E`).
  **Verificação comportamental:** avaliar cenários de página única, múltiplas páginas, resposta vazia válida e caderno problemático contra as condições aprovadas.
  **Smoke específico:** revisão de um fluxo de fallback paginado com data atual, confirmando que não solicita dia anterior.
  **Evidência histórica, anterior à restrição ao meio D:** TJAP/D, em 28/10/2026, teve páginas de 100, 100, 100, 100, 67 e 0 itens; as 467 chaves coincidiram com as do caderno. TJRR/E apresentou página inicial vazia e caderno sem comunicações; essa amostra E não integra a coleta vigente. Todas as consultas usaram a mesma data inicial e final. Erros de resposta são falhas no contrato, não resultados vazios. Detalhes e limites em [contrato DJEN](../docs/contrato-djen.md#verificações-adicionais-de-28102026).
  **Dep.:** 1a. **Escopo:** contrato do caminho alternativo, sem implementar o conector.
  **Áreas previstas (≤5):** especificação de coleta; referência do contrato DJEN.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [x] **1c — Fixar operação diária, tentativas e falha.**
  **Aceite:** (1) decidir horários/fuso/elegibilidade para duas execuções diárias; (2) aprovar limites, backoff, parada, retomada e critérios de falha por execução/tribunal; (3) permitir recuperação na execução posterior do mesmo dia, sem coleta retroativa.
  **Verificação comportamental:** revisar cenários de interrupção, tentativas esgotadas, falha persistente e sucesso posterior no mesmo dia; cada resultado distingue falha de zero publicações.
  **Smoke específico:** exercício de mesa “falha na primeira execução, sucesso na segunda, mesma data” e conferência do estado esperado.
  **Dep.:** 1a–1b. **Escopo:** decisões operacionais, sem executar agendamento/coleta.
  **Áreas previstas (≤5):** especificação de coleta; critérios de operação.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios); [Fronteiras](../SPEC-coleta.md#fronteiras).

### 2. Fechar decisões de segurança, dados e desempenho

- [x] **2a — Aprovar política de identidade e validade.**
  **Aceite:** (1) decidir escopo da validade (advogado/equipe), criação e ciclo de vida das credenciais e início/fuso/instante da contagem; (2) definir efeitos de renovação, alteração e revogação em credenciais/sessões; (3) preservar a recusa server-side após expiração mesmo para sessão ativa.
  **Verificação comportamental:** revisão dos cenários sem expiração, validade em dias e operação protegida depois do vencimento numa sessão previamente aberta.
  **Smoke específico:** tabela de decisão para sessão ativa antes/depois do instante aprovado de expiração.
  **Dep.:** 1a–1c quando afetarem credenciais. **Escopo:** política, sem escolher mecanismo de login.
  **Áreas previstas (≤5):** especificação de identidade; política de credenciais.
  **Rastreio:** [SPEC-identidade.md — Requisitos](../SPEC-identidade.md#requisitos); [Critérios observáveis](../SPEC-identidade.md#critérios-observáveis); [Questões abertas](../SPEC-identidade.md#questões-abertas); [Fronteiras](../SPEC-identidade.md#fronteiras).

- [x] **2b — Aprovar composição de grupos e operações.**
  **Aceite:** (1) decidir composição/conflito de grupos e operações, inclusive concessões de escrita; (2) manter leitura ampla sem grupo sem conceder escrita e preservar `Consulta TJSP` como somente leitura de TJSP quando não conflitante; (3) definir o escopo de tribunal aplicado a lista, detalhe e agregações.
  **Verificação comportamental:** matriz aprovada para sem grupo, `Consulta TJSP`, outros grupos/conflitos e operações de leitura/escrita.
  **Smoke específico:** revisão de chamadas permitidas e negadas para TJSP, outro tribunal e escrita.
  **Dep.:** 2a. **Escopo:** contrato de autorização, sem inventar roles.
  **Áreas previstas (≤5):** especificação de autorização; matriz de decisões.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Critérios observáveis](../SPEC-autorizacao.md#critérios-observáveis); [Questões abertas](../SPEC-autorizacao.md#questões-abertas); [Fronteiras](../SPEC-autorizacao.md#fronteiras).

- [x] **2c — Aprovar dashboard, dados e estratégia de capacidade.**
  **Aceite:** (1) definir métricas, unidade/período, escopo parcial de tribunal e regra de `*`; (2) decidir tratamento dos dados do Escrevente e distinção entre zero, falha e indisponível; (3) registrar 300 usuários como referência para avaliação futura, sem bloquear esta entrega.
  **Verificação comportamental:** revisão dos cenários de dashboard restrita, métrica parcial, falha persistente, retenção e estratégia de medição.
  **Smoke específico:** conferir uma tabela de métricas/estados com valores autorizados, negados (`*`), zero e falha, sem expor valor protegido.
  **Dep.:** 2b e 1c. **Escopo:** políticas e estratégia de capacidade, sem executar carga.
  **Áreas previstas (≤5):** especificações de autorização, Escrevente e consulta; critérios de desempenho/dados.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Questões abertas](../SPEC-autorizacao.md#questões-abertas); [SPEC-escrevente.md — Fronteiras](../SPEC-escrevente.md#fronteiras); [SPEC-consulta.md — Requisitos](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Questões abertas](../SPEC-consulta.md#questões-abertas-e-bloqueios).

### 3. Definir stack e contratos

- [x] **3a — Decidir stack, arquitetura física e ferramentas.**
  **Aceite:** (1) registrar decisões de versões, ETL, layout, ferramentas, políticas RLS e comandos previstos; (2) mapear áreas físicas e responsáveis; (3) exigir caminhos exatos e subdivisão em até cinco arquivos antes de executar cada fatia. Comandos serão confirmados após geração da aplicação, sem presumir execução nesta etapa.
  **Verificação comportamental:** revisar fronteiras e responsabilidades em [arquitetura](../docs/arquitetura.md) e [mapa físico](../docs/mapa-implementacao.md).
  **Smoke específico:** exercício de mesa do fluxo de onboarding à consulta registrado em [arquitetura](../docs/arquitetura.md#verificação-de-arquitetura); não é execução da aplicação.
  **Situação:** propostas registradas; compatibilidade, comandos reais e isolamento RLS exigem verificação durante implementação e antes de produção. O solicitante dispensou retenção automática do Escrevente nesta etapa.
  **Dep.:** 1a–1c e 2a–2c. **Escopo:** decisão técnica, sem implementação.
  **Áreas previstas (≤5):** decisão de stack; arquitetura; convenções; estratégia de testes.
  **Rastreio:** [SPEC-identidade.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-identidade.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-autorizacao.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-autorizacao.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-monitoramentos.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-monitoramentos.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-escrevente.md — Comandos, estrutura e estilo](../SPEC-escrevente.md#comandos-estrutura-e-estilo); [SPEC-coleta.md — Comandos, estrutura e estilo](../SPEC-coleta.md#comandos-estrutura-e-estilo); [SPEC-consulta.md — Comandos, estrutura e estilo](../SPEC-consulta.md#comandos-estrutura-e-estilo); [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico).

- [x] **3b — Definir contratos entre aplicação e módulos lógicos.**
  **Aceite:** (1) definir contratos de identidade/tenant server-side, autorização, monitoramentos, coleta, estado por tribunal e consulta; (2) preservar despachante/control plane e ETL como responsabilidades distintas da aplicação central sem impor serviço/processo/diretório; (3) definir entrada append-only do Escrevente e manter estado/detalhes de falha fora dele.
  **Verificação comportamental:** revisão de contrato para tenant adulterado pelo cliente, vínculo de execução/entidade/tribunal e resposta autorizada.
  **Smoke específico:** seguir um diagrama de sequência de onboarding até consulta, identificando consumidor/dono de cada dado.
  **Evidência:** contratos e sequência de revisão documental em [arquitetura](../docs/arquitetura.md#verificação-de-arquitetura).
  **Dep.:** 3a. **Escopo:** interfaces lógicas; transporte/formato só quando aprovados.
  **Áreas previstas (≤5):** contratos de identidade/autorização; monitoramentos; coleta/Escrevente; consulta.
  **Rastreio:** [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico); [SPEC-identidade.md — Escopo e dono dos contratos](../SPEC-identidade.md#escopo-e-dono-dos-contratos); [SPEC-autorizacao.md — Escopo e dono dos contratos](../SPEC-autorizacao.md#escopo-e-dono-dos-contratos); [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [SPEC-escrevente.md — Escopo e contratos lógicos](../SPEC-escrevente.md#escopo-e-contratos-lógicos); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [SPEC-consulta.md — Escopo e contratos lógicos](../SPEC-consulta.md#escopo-e-contratos-lógicos).

- [x] **3c — Resolver decisões de domínio restantes antes de codificar.**
  **Aceite:** (1) aprovar validação/normalização e correspondência de nome, OAB e processo, homônimos, duplicidade e filtros de tribunal; (2) decidir tratamento de `id`/`hash` ausente, inválido ou inconsistente sem alterar a chave conjunta aceita; (3) preservar o convite e edição/desativação aprovados, sem acrescentar exclusão de cadastro, relatórios/avisos por e-mail ou recuperação histórica.
  **Verificação comportamental:** revisão de casos limítrofes e fronteiras de cada spec; estabilidade/unicidade global de `id`/`hash` não é revalidada.
  **Smoke específico:** walkthrough de monitoramento com homônimo/filtro indisponível e publicação sem chave válida, confirmando decisão explícita para cada caso.
  **Evidência:** regras e exercício de bordas em [monitoramentos](../SPEC-monitoramentos.md#contratos-lógicos), [coleta](../SPEC-coleta.md#deduplicação-e-vínculos) e [arquitetura](../docs/arquitetura.md#verificação-de-arquitetura).
  **Dep.:** 1a–1c, 2a–2c e 3b. **Escopo:** fechar pendências funcionais, sem ampliar produto.
  **Áreas previstas (≤5):** especificações de identidade, monitoramentos e coleta; decisões de domínio.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-monitoramentos.md — Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

## Checkpoint 1 — após decisões 1–3
- [x] Decisões dos gates 1–3 registradas; verificações de execução e retenção permanecem obrigatórias nas tarefas correspondentes.
- [x] O solicitante autorizou resolver as decisões por recomendação e destravar o andamento; isso não equivale a aprovação de produção ou de resultados ainda não medidos.

## Implementação — tarefas 4–16

### 4. Onboarding do advogado

- [x] **4a — Persistir perfil profissional e tenant próprio.**
  **Aceite:** (1) onboarding registra nome completo, OAB principal e OABs secundárias informadas; (2) cada advogado pertence ao próprio tenant e escritório/nome comercial opcional não define tenant.
  **Verificação comportamental:** concluir onboarding e ler o perfil e tenant; comparar dois advogados/tenants sem inferir monitoramentos.
  **Smoke específico:** primeiro acesso pela API de advogado com OAB principal e sem OAB secundária, conferindo vínculo ao tenant próprio.
  **Dep.:** 3a–3c. **Escopo:** backend de onboarding, perfil profissional e vínculo ao tenant; interface frontend fica para etapa posterior, conforme decisão do solicitante.
  **Áreas previstas (≤5):** identidade; persistência de perfil; API de onboarding.
  **Rastreio:** [SPEC-identidade.md — Contratos lógicos](../SPEC-identidade.md#contratos-lógicos); [Requisitos](../SPEC-identidade.md#requisitos).
  **Estado:** testes de onboarding passaram com roles reais em banco isolado (12 testes, 98 assertions); smoke HTTP real criou e leu perfil com OAB principal e sem secundárias. A sessão foi preparada para teste: login Google real com cliente OAuth e callback HTTPS continua pendente, independentemente deste aceite.

- [x] **4b — Derivar contexto autenticado no servidor.**
  **Aceite:** (1) cada operação protegida recebe identidade e tenant do contexto server-side; (2) tenant enviado pelo cliente não altera o contexto nem permite acesso cruzado; (3) contexto expirado não é apresentado como identidade válida.
  **Verificação comportamental:** tentar operar em outro tenant enviando tenant/ID conhecido e confirmar negação.
  **Smoke específico:** chamada autenticada com tenant adulterado continua restrita ao tenant da identidade.
  **Dep.:** 4a, 3b. **Escopo:** fronteira de identidade, sem decidir mecanismo de login além de 2a.
  **Áreas previstas (≤5):** identidade; contexto de requisição; autorização de tenant.
  **Rastreio:** [SPEC-identidade.md — Contratos lógicos](../SPEC-identidade.md#contratos-lógicos); [Fronteiras](../SPEC-identidade.md#fronteiras); [SPEC-autorizacao.md — Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).
  **Estado:** testes com PostgreSQL isolado e roles reais passaram: `tenant_isolation_test.rb`, `session_validity_test.rb` e `onboarding_profile_http_test.rb`, 9 testes e 66 assertions, sem falhas. Cobrem tenant adulterado, expiração e sessão revogada; smoke HTTP real confirmou que tenant adulterado não altera o perfil da sessão. OAuth Google real é verificação independente, não critério de aceite de 4b.

- [ ] **4c — Implementar interface de onboarding em etapa posterior.**
  **Aceite:** interface Next.js integra login Google e onboarding ao backend, incluindo OAB principal, secundárias opcionais, escritório opcional e estados de erro/sucesso.
  **Verificação:** navegar no navegador real e concluir o fluxo autenticado, respeitando as decisões de identidade e acessibilidade.
  **Dep.:** 4a–4b. **Escopo:** frontend; não iniciar nesta etapa de backend.
  **Áreas previstas (≤5):** interface de identidade; cliente da API; configuração do frontend.

### 5. Gestão de usuários e expiração

**Implementação backend de identidade, equipe e autorização — branch `feature/identidade-equipe-autorizacao`:** manter frontend fora desta entrega. Para banco inicial vazio, o contexto de identidade será consolidado na migration inicial; não há upgrade automático de banco preexistente.

- Identidade/schema: `backend/db/migrate/20261028000000_create_identity_and_lawyer_profiles.rb`, `backend/db/migrate/20261028000005_create_team_credentials.rb`. Vínculos por tenant, sessão selecionada e credenciais com validade/revogação.
- Sessões: `backend/app/services/identity_store.rb`, `backend/app/controllers/sessions_controller.rb`, `backend/app/controllers/google_sessions_controller.rb`, `backend/config/routes.rb`, `backend/test/integration/tenant_memberships_test.rb`.
- Credenciais: `backend/app/controllers/team_credentials_controller.rb`, `backend/test/integration/team_credentials_http_test.rb`, `backend/test/integration/team_credential_lifecycle_test.rb`.
- Convites: `backend/app/controllers/team_invitations_controller.rb`, `backend/test/integration/team_invitations_test.rb`; token em fragmento de URL e aceite por POST autenticado, sem registrar token ou conteúdo do convite.
- Correio: `backend/app/services/team_invitation_mailer.rb`, `backend/test/services/team_invitation_mailer_test.rb`; configuração SMTP e variáveis serão registradas no README antes de concluir a entrega.
- Política de autorização: `backend/app/services/authorization_policy.rb`, `backend/test/services/authorization_policy_test.rb`. Grupos, administração, integração com operações existentes e verificações serão detalhados antes de seu fechamento.
- Configuração SMTP: `backend/app/services/app_settings.rb`, `backend/test/services/app_settings_test.rb`, `README.md`. Credenciais externas, porta explícita e transporte seguro; nenhuma configuração no corpo da requisição.
- Grupos: `backend/db/migrate/20261028000006_create_authorization_groups.rb`, `backend/app/services/authorization_group_store.rb`, `backend/app/controllers/authorization_groups_controller.rb`, `backend/test/integration/authorization_groups_test.rb`, `backend/test/integration/authorization_groups_http_test.rb`.
- Fronteira das permissões: `backend/app/controllers/application_controller.rb`, `backend/test/integration/monitoring_authorization_http_test.rb`.
- Monitoramentos: `backend/app/controllers/party_monitorings_controller.rb`, `backend/app/controllers/process_monitorings_controller.rb`, `backend/app/controllers/lawyer_monitorings_controller.rb`.
- Consultas auxiliares: `backend/app/controllers/court_catalogs_controller.rb`, `backend/app/controllers/collection_runs_controller.rb`, `backend/app/controllers/escrevente_controller.rb`, `backend/app/controllers/onboardings_controller.rb`. O Escrevente e os dados administrativos de coleta permanecem exclusivos do titular.

- [x] **5a — Aplicar validade às credenciais e sessões.**
  **Aceite:** (1) permitir validade sem expiração ou em dias conforme política aprovada; (2) após vencimento, negar operação protegida no servidor mesmo se a sessão já estava ativa; (3) aplicar renovação/alteração/revogação conforme a decisão 2a.
  **Verificação comportamental:** comparar acesso válido, sem expiração, após vencimento e sessão aberta antes do vencimento.
  **Smoke específico:** renovar ou expirar uma credencial numa sessão ativa e tentar imediatamente uma nova operação protegida.
  **Dep.:** 4b, 2a, 3a. **Escopo:** validade de credencial e checagem server-side.
  **Áreas previstas (≤5):** identidade/autenticação; política de credenciais; interface de validade.
  **Rastreio:** [SPEC-identidade.md — Requisitos](../SPEC-identidade.md#requisitos); [Fronteiras](../SPEC-identidade.md#fronteiras); [Questões abertas](../SPEC-identidade.md#questões-abertas).
  **Estado:** backend verificado em PostgreSQL com roles reais; testes cobrem vencimento, alteração, renovação e revogação em sessão aberta. Smoke HTTP confirmou revogação seguida de `401` na operação protegida.

- [ ] **5b — Administrar ciclo de usuários aprovado.**
  **Aceite:** (1) executar somente ações de usuário aprovadas em 2a/2b; (2) vincular usuários ao tenant do advogado sem assumir convite, credencial ou login não aprovados.
  **Verificação comportamental:** criar/alterar o estado previsto para usuário da equipe e confirmar que outro tenant não pode administrá-lo.
  **Smoke específico:** operação de administração autorizada num tenant e tentativa negada usando identificador de outro tenant.
  **Dep.:** 5a, 2a, 2b, 3b. **Escopo:** gestão de usuários dentro do ciclo aprovado.
  **Áreas previstas (≤5):** autorização/administração; identidade de equipe; persistência de usuários.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Questões abertas](../SPEC-autorizacao.md#questões-abertas).
  **Estado:** backend implementado; testes cobrem convites, seleção de tenant e administração isolada. Smoke HTTP enviou convite a um servidor SMTP local com STARTTLS, aceitou o convite e confirmou que equipe não administra credenciais. A prova de login Google real ainda depende de credenciais externas; o smoke usou sessões preparadas.

### 6. Grupos e escopo de tribunais

- [ ] **6a — Administrar grupos no tenant correto.**
  **Aceite:** (1) advogado administra os grupos aprovados somente no próprio tenant; (2) decisões de composição e ciclo de vida de grupo seguem a política 2b, sem roles presumidas.
  **Verificação comportamental:** administrar grupo no tenant próprio e negar leitura/alteração de grupo alheio por ID enviado pelo cliente.
  **Smoke específico:** abrir a administração de grupos com contexto de dois tenants e conferir isolamento.
  **Dep.:** 5b, 4b, 2b. **Escopo:** administração lógica de grupos.
  **Áreas previstas (≤5):** autorização/administração; persistência de grupos; interface administrativa.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).
  **Estado:** backend implementado e testes de isolamento entre tenants aprovados; smoke HTTP criou e listou grupo com titular e recusou acesso anônimo. A interface frontend e o smoke administrativo com dois tenants permanecem pendentes.

- [ ] **6b — Aplicar permissões por operação e tribunal.**
  **Aceite:** (1) sem grupos, permitir leitura ampla dos tribunais sem conceder escrita; (2) `Consulta TJSP` permite somente leitura TJSP quando avaliado sem conflito; (3) aplicar regras aprovadas pelo servidor ao dado retornado.
  **Verificação comportamental:** matriz de leitura/escrita, TJSP/outro tribunal e composição de grupos decidida em 2b.
  **Smoke específico:** usuário sem grupo e usuário `Consulta TJSP` tentam ler TJSP, ler outro tribunal e escrever.
  **Dep.:** 6a, 4b, 2b. **Escopo:** decisão de acesso aplicada em cada operação.
  **Áreas previstas (≤5):** autorização; política de operações; filtros de dados.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).
  **Estado:** política por operação/tribunal implementada, testada e aplicada aos consumidores de monitoramento existentes. A consulta de comunicações e suas respostas por tribunal ainda não existem; a verificação de 6b nessas superfícies permanece pendente.

- [ ] **6c — Aplicar a decisão de autorização da dashboard.**
  **Aceite:** (1) decidir o acesso à dashboard conforme política aprovada, tenant e escopo de tribunal; (2) aplicar a decisão no servidor e não retornar valores protegidos quando negada, sem definir sua representação visual.
  **Verificação comportamental:** comparar respostas do servidor para chamadas autorizadas, negadas e parcialmente permitidas, conferindo escopo e ausência de valores protegidos nas negadas.
  **Smoke específico:** chamada controlada à operação da dashboard com acesso negado não retorna valores protegidos; a exibição na interface é verificada em 15b.
  **Dep.:** 6b, 2b–2c. **Escopo:** decisão e aplicação server-side da autorização da dashboard.
  **Áreas previstas (≤5):** autorização; consulta/agregação; filtros server-side.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos); [SPEC-consulta.md — Requisitos](../SPEC-consulta.md#requisitos-e-critérios-observáveis).
  **Estado:** a decisão `consultar_dashboard` integra o catálogo e a matriz testada; não existe operação real de dashboard/agregação à qual aplicá-la ou submetê-la ao smoke exigido.

## Checkpoint 2 — após tarefas 4–6
- [ ] Onboarding, expiração em sessão ativa, isolamento e regras de autorização demonstrados nos cenários propostos.
- [ ] Aprovação humana registrada antes de avançar.

### 7. Cadastro de partes

**Primeiras fatias backend, antes de partes/processos e planejamento:**

- Catálogo DJEN: `backend/test/integration/court_catalog_http_test.rb`, `backend/app/services/court_catalog.rb`, `backend/app/controllers/court_catalogs_controller.rb`, `backend/config/routes.rb`. Validar catálogo atual da fonte; indisponibilidade não vira lista vazia nem catálogo inventado. Durante o desenvolvimento, tráfego DJEN sai pelo nó Tailscale `100.118.186.77`; em produção Tailscale não é requisito e usa-se a saída normal da infraestrutura.
- Advogado monitorado: `backend/test/integration/lawyer_monitoring_http_test.rb`, `backend/app/controllers/lawyer_monitorings_controller.rb`, `backend/config/routes.rb`. Projeção autenticada do perfil existente, incluindo OABs e tenant derivado no servidor; não duplicar o perfil nem liberar acesso de equipe sem autorização.

Os cadastros de partes/processos e o despachante dependem dessas fronteiras e serão detalhados nas tarefas 7b, 8a e 10; frontend permanece adiado.

- [ ] **7a — Fornecer ao monitoramento o perfil do advogado.**
  **Aceite:** (1) entidade advogado reflete nome e OABs da identidade; (2) não duplica perfil nem transforma escritório em tenant; (3) identidade e tenant ficam disponíveis à coleta.
  **Verificação comportamental:** editar/ler perfil conforme operações aprovadas e conferir saída lógica consumida pela coleta.
  **Smoke específico:** seguir perfil de um advogado até sua entidade de monitoramento e confirmar tenant próprio.
  **Dep.:** 4a, 4b, 6b, 3b. **Escopo:** vínculo lógico de identidade ao monitoramento.
  **Áreas previstas (≤5):** identidade; monitoramentos; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Critérios observáveis](../SPEC-monitoramentos.md#critérios-observáveis).
  **Estado:** projeção do perfil existente validada por testes de dois tenants; autorização de equipe e consumo no despachante ainda pendentes.

- [ ] **7b — Cadastrar partes e filtros suportados.**
  **Aceite:** (1) cadastrar/ler nome de parte sob tenant autenticado; (2) oferecer somente filtros de tribunal disponibilizados e suportados pela fonte; (3) fornecer identidade lógica, tenant e dados de busca à coleta sem prometer matching não aprovado.
  **Verificação comportamental:** cadastrar/ler parte autorizada, tentar acesso cruzado e verificar filtros contra a lista aprovada da fonte.
  **Smoke específico:** cadastrar uma parte com tribunal suportado e confirmar tenant/filtro na saída lógica, sem disparar coleta.
  **Dep.:** 7a, 3c, 6b. **Escopo:** cadastro e leitura de partes.
  **Áreas previstas (≤5):** monitoramentos; filtros de tribunal; interface de partes; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas).
  **Arquivos previstos:** `backend/test/integration/party_monitorings_http_test.rb`, `backend/db/migrate/20261028000001_create_party_monitorings.rb`, `backend/app/models/party_monitoring.rb`, `backend/app/controllers/party_monitorings_controller.rb`, `backend/config/routes.rb`. Cadastro, leitura, edição e desativação: tenant de sessão; nome canônico único inclusive desativado; filtro `null` equivale a todos, lista explícita não pode ser vazia e deve ser validada pelo catálogo real.
  **Estado:** cadastro, leitura, edição, desativação e isolamento de dois titulares exercitados por HTTP com catálogo DJEN real; acesso de equipe/autorização 6b e consumo pelo despachante ainda pendentes.

### 8. Cadastro de processos

- [ ] **8a — Cadastrar processo e filtros suportados.**
  **Aceite:** (1) cadastrar/ler número de processo no tenant autenticado; (2) vincular apenas filtros de tribunal aprovados e suportados pela fonte; (3) fornecer identidade lógica, tenant e critérios decididos à coleta.
  **Verificação comportamental:** cadastrar e ler processo autorizado e negar leitura por outro tenant ou tribunal sem acesso.
  **Smoke específico:** cadastrar um processo com tribunal suportado e conferir número, tenant e filtro entregues ao consumidor lógico.
  **Dep.:** 6b, 3b, 3c. **Escopo:** cadastro e leitura de processos.
  **Áreas previstas (≤5):** monitoramentos; filtros de tribunal; interface de processos; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas).
  **Arquivos previstos:** `backend/test/integration/process_monitorings_http_test.rb`, `backend/db/migrate/20261028000002_create_process_monitorings.rb`, `backend/app/models/process_monitoring.rb`, `backend/app/controllers/process_monitorings_controller.rb`, `backend/config/routes.rb`. Cadastro, leitura, edição e desativação: tenant de sessão; CNJ canônico de 20 dígitos único inclusive desativado; filtros seguem as mesmas regras de 7b.
  **Estado:** cadastro, leitura, edição, desativação e isolamento de dois titulares exercitados por HTTP com catálogo DJEN real; acesso de equipe/autorização 6b e consumo pelo despachante ainda pendentes.

- [ ] **8b — Disponibilizar páginas e navegação autorizadas.**
  **Aceite:** (1) disponibilizar páginas de cadastro/leitura de partes e processos; (2) navegação entre esses cadastros respeita autorização também em acesso direto; (3) aplicar operações de ciclo de vida somente conforme aprovadas.
  **Verificação comportamental:** abrir páginas de cadastro/leitura com ator autorizado e restrito, incluindo chamada direta a destino de cadastro negado.
  **Smoke específico:** navegar entre os cadastros de parte e processo com usuário autorizado e repetir acesso direto sem autorização; resultados e dashboard ficam para a integração após 14–15.
  **Dep.:** 7b, 8a, 6b. **Escopo:** apresentação/navegação dos cadastros; integração com resultados/dashboard em 16a, após 14–15.
  **Áreas previstas (≤5):** interface de monitoramentos; navegação; autorização de destinos.
  **Rastreio:** [SPEC-monitoramentos.md — Requisitos](../SPEC-monitoramentos.md#requisitos); [Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos).

### 9. Escrevente append-only

- [x] **9a — Acrescentar marcos do fluxo de coleta.**
  **Aceite:** (1) registrar início e término como novos marcos com contexto/rastreio disponível de tenant, execução, fonte, entidade, advogado, tribunal e processos associados; (2) registros gravados não são editados nem removidos por operações normais; (3) ausência de término permanece sem término, sem evento retroativo inferido.
  **Verificação comportamental:** consultar sequência de marcos após início/término e tentar alteração/remoção; confirmar conteúdo histórico idêntico.
  **Smoke específico:** registrar início e conclusão e conferir dois acréscimos rastreáveis, sem sobrescrever o primeiro.
  **Dep.:** 3b, 4b. **Escopo:** registro append-only do fluxo.
  **Áreas previstas (≤5):** Escrevente; persistência de marcos; contrato de coleta.
  **Rastreio:** [SPEC-escrevente.md — Escopo e contratos lógicos](../SPEC-escrevente.md#escopo-e-contratos-lógicos); [Requisitos](../SPEC-escrevente.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-escrevente.md#fronteiras).
  **Estado:** granularidade aprovada e contrato implementado em [SPEC-escrevente.md](../SPEC-escrevente.md#contrato-técnico-implementado--granularidade-aprovada). A dependência 4b foi verificada; testes com roles reais e smoke HTTP/SQL confirmaram dois acréscimos rastreáveis, idempotência, isolamento e append-only. O executor ETL permanece não implementado.

- [x] **9b — Separar falhas do registro imutável.**
  **Aceite:** (1) Escrevente não recebe ações de usuário nem detalhes técnicos de erro; (2) estado de sucesso/falha permanece consultável fora do Escrevente e relacionado à execução/tribunal; (3) tenant de registro deriva do contexto server-side.
  **Verificação comportamental:** exercitar a fronteira com uma chamada controlada que informa o resultado operacional definido no contrato; verificar estado externo, tenant adulterado e ausência de marco final, sem depender de execução do processador.
  **Smoke específico:** invocar a fronteira com resultado controlado de falha e confirmar estado externo consultável conforme contrato, sem texto técnico ou ação de usuário no Escrevente.
  **Dep.:** 9a, 3b, 4b. **Escopo:** fronteira entre ledger append-only e estado operacional.
  **Áreas previstas (≤5):** Escrevente; estado de execução; contexto de identidade.
  **Rastreio:** [SPEC-escrevente.md — Escopo e contratos lógicos](../SPEC-escrevente.md#escopo-e-contratos-lógicos); [Requisitos](../SPEC-escrevente.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-escrevente.md#fronteiras).
  **Estado:** `collection_job_executions` mantém o estado por trabalho fora dos marcos. Testes e smoke confirmaram falha consultável por execução/tribunal com início sem término e tenant derivado do trabalho, sem executar o processador ETL. Os testes específicos passaram com 29 testes e 813 assertions; a suíte completa, 276 testes e 7.678 assertions.

## Checkpoint 3 — após tarefas 7–9
- [ ] Monitoramentos de advogado/parte/processo entregam tenant e identidade corretos; Escrevente permanece append-only e sem ações/erros técnicos.
- [ ] Aprovação humana registrada antes de avançar.

### 10. Planejamento da coleta

- [x] **10a — Planejar por tenant, entidade, fonte e tribunal.**
  **Aceite:** (1) trabalho identifica tenant, entidade/monitoramento, execução, fonte lógica, tribunal aplicável e meio exclusivo `D`; (2) inclui advogado, partes e processos elegíveis conforme filtros decididos, sem planejar `E`; (3) não aceita tenant do cliente como prova de propriedade.
  **Verificação comportamental:** planejar entidades de mais de um tenant e conferir que cada linha mantém seus vínculos sem cruzamento.
  **Smoke específico:** planejar um advogado, uma parte e um processo em dois tenants e inspecionar os vínculos resultantes.
  **Dep.:** 7a–7b, 8a, 4b, 9a. **Escopo:** trabalho planejado, sem ainda executar a fonte.
  **Áreas previstas (≤5):** despachante; contrato de monitoramentos; contexto de tenant; execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).
  **Fatia de persistência e planejamento:** `backend/test/integration/collection_planning_test.rb`, `backend/db/provision_despachante.sql`, `backend/db/migrate/20261028000003_create_collection_planning.rb`, `backend/despachante/collection_despachante.rb`, `README.md`. Um processo de confiança usa credencial PostgreSQL própria sem `BYPASSRLS`; somente ele pode ler os monitoramentos de todos os tenants para formar planos. Web continua restrito pela sessão. Cada execução por data/slot possui trabalhos imutáveis por tenant, entidade, tribunal e meio exclusivo `D`, com critérios fixados ao planejar; falha não é tratada como trabalho vazio.
  **Fatia de integridade:** `backend/test/integration/collection_planning_test.rb`, `backend/db/migrate/20261028000003_create_collection_planning.rb`. A integridade antes introduzida pela migration 04 agora faz parte da criação inicial: as referências de advogado, parte e processo dos trabalhos devem pertencer ao mesmo tenant no banco, inclusive para escritas da role despachante.
  **Fatia de leitura:** `backend/test/integration/collection_runs_http_test.rb`, `backend/db/migrate/20261028000003_create_collection_planning.rb`, `backend/despachante/collection_despachante.rb`, `backend/app/controllers/collection_runs_controller.rb`, `backend/config/routes.rb`. A audiência antes criada pela migration 05 agora faz parte da criação inicial: é fixada por tenant mesmo sem trabalhos; respostas limitadas ao tenant autenticado. Documentar contrato no README; autorização de equipe permanece pendente de 6b.
  **Evidência histórica, anterior à restrição ao meio D:** migrations então vigentes exercitadas em PostgreSQL 18.6 isolado, com roles reais. Os testes focados de planejamento, agenda e leitura HTTP passaram com 72 testes e 1.248 assertions; incluem dois tenants, os três tipos de entidade, filtros, RLS, vínculos cruzados negados e critérios congelados. O teste de perfil sem OAB principal demonstrou falha integral e retomada da mesma execução após restauração do perfil. Um smoke na imagem final então vigente com catálogo controlado gerou dois slots `planned`: cada um continha advogado, parte e processo em dois tenants, com seis trabalhos por tenant para TJAC/D e TJAC/E, critérios e identificadores conferidos; a repetição manteve os slots. Esse smoke preserva o comportamento antigo, não autoriza E nem verifica a restrição vigente. O smoke anterior com DJEN real também é histórico; a autorização de equipe (6b) e as dependências desta tarefa permanecem pendentes.
  **Verificação atual:** testes focados Rails de planejamento, agenda, leitura e persistência: 94 testes e 1.649 assertions, sem falhas, erros ou skips. Em PostgreSQL descartável, o despachante planejou dois slots para dois tenants, cada qual com advogado, parte e processo no TJAC/D: 12 trabalhos com entidade e tenant associados.

- [x] **10b — Agendar as duas execuções e manter fronteiras lógicas.**
  **Aceite:** (1) configurar dois acionamentos diários conforme horário/fuso/elegibilidade aprovados; (2) manter despachante/control plane e ETL como responsabilidades distintas da aplicação central; (3) cada acionamento planejado tem identidade própria e associação à fonte/tribunal, sem executar ETL nesta fatia.
  **Verificação comportamental:** inspecionar os dois acionamentos planejados para o mesmo dia e confirmar distinção de execução e fronteiras sem exigir serviços/diretórios separados ou execução do ETL.
  **Smoke específico:** gerar dois acionamentos planejados para o mesmo dia e conferir identificadores/contexto separados, sem iniciar coleta.
  **Dep.:** 10a, 1c, 3a–3b. **Escopo:** planejamento da agenda; execução completa da coleta em 13a, após 11.
  **Áreas previstas (≤5):** despachante; contrato de acionamento do ETL; execução; configuração da agenda.
  **Rastreio:** [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).
  **Fatia de agenda:** `backend/test/services/collection_schedule_test.rb`, `backend/despachante/collection_schedule.rb`, `README.md`. Validar horários sem defaults e calcular slots devidos em `America/Sao_Paulo`. Execução independente: `backend/test/integration/despachante_execution_test.rb`, `backend/despachante/run.rb`, `backend/Dockerfile`, `README.md`, `tasks/todo.md`; não executar ETL nesta etapa.
  **Fatia de virada de data:** `backend/test/integration/despachante_execution_test.rb`, `backend/db/migrate/20261028000003_create_collection_planning.rb`, `backend/despachante/collection_despachante.rb`, `backend/despachante/run.rb`, `README.md`. O estado `interrupted`, antes acrescentado pela migration 06, agora faz parte da criação inicial. Não publicar nem retomar trabalhos de dia anterior após uma espera externa; identificar a interrupção sem executar coleta retroativa.
  **Fatia da imagem mínima:** `backend/despachante/Gemfile`, `backend/despachante/Gemfile.lock`, `backend/despachante/run.rb`, `backend/Dockerfile`, `README.md`. Instalar apenas as gems usadas pelo processo de planejamento, manter build em estágio separado e verificar a imagem final em execução como usuário não root.
  **Evidência histórica, anterior à restrição ao meio D:** testes focados passaram com 72 testes e 1.248 assertions, cobrindo slots, retomada, concorrência, 429 e virada de data. A imagem final do despachante então vigente foi construída; smoke com catálogo controlado persistiu dois slots `planned` distintos e idempotentes, executando com UID/GID 1000:1000. Isso não comprova a restrição vigente ao meio D, conectividade DJEN real nem execução de ETL. Execução dos jobs e interrupção de jobs já planejados ao mudar o dia pertencem à tarefa 13.
  **Verificação atual:** os testes focados acima abrangem horários, retomada e virada de data. O processo da imagem final do despachante retornou dois slots distintos e idempotentes com UID 1000; a seleção e execução automática dos trabalhos continuam na tarefa 13.

### 11. Coleta e persistência reais

- [x] **11a — Coletar pelo caderno ZIP/JSON principal no primeiro slot.**
  **Aceite:** (1) no primeiro slot, obter caderno por tribunal/data corrente/meio `D` e processar todos os JSONs do ZIP, sem sanitizar seu texto; (2) pesquisar advogado por nome/OAB, processo por número e parte por nome conforme regras aprovadas; (3) não consultar caderno no segundo slot nem coletar editais (`E`).
  **Verificação comportamental:** executar cenário controlado de ZIP com vários JSONs e correspondências dos três tipos, incluindo resultado válido vazio.
  **Smoke específico:** processar um caderno controlado e confirmar cada correspondência e ausência de consulta de dia anterior.
  **Dep.:** 10a, 10b, 1a, 3c. **Escopo:** caminho principal de coleta.
  **Áreas previstas (≤5):** conector de cadernos; processamento ZIP/JSON; matching; persistência de publicações; estado de execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).
  **Estado:** suíte anterior do processador com 98 testes e 1.004 assertions; smoke controlado processou caderno com dois JSONs e correspondências de advogado, parte e processo. Antes da alteração de fonte no segundo slot, o comando definitivo consultou caderno TJAC/D real e terminou com sucesso e zero correspondências para o trabalho controlado.

- [x] **11b — Consultar API paginada como fallback no primeiro slot e diretamente no segundo.**
  **Aceite:** (1) no primeiro slot, sob condições de falha aprovadas, consultar API como fallback; no segundo, iniciar diretamente na API, sem caderno; (2) consultar somente `D`, percorrer páginas necessárias segundo limites decididos e enviar início/fim iguais ao dia corrente; (3) resposta válida vazia não vira falha nem inclui dia anterior.
  **Verificação comportamental:** cenário de caderno problemático no primeiro slot seguido por várias páginas, segundo slot sem chamada ao caderno, resposta vazia válida e tentativa de data fora do dia corrente.
  **Smoke específico:** executar fallback controlado no primeiro slot e API direta no segundo, com mais de uma página, meio `D` e ambos os filtros de data iguais.
  **Dep.:** 10a–10b, 1b, 1c, 3a. **Escopo:** API paginada como caminho alternativo do primeiro slot e caminho direto do segundo.
  **Áreas previstas (≤5):** conector paginado; política de fallback; processamento de resposta; estado de execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).
  **Estado:** testes controlados verificaram múltiplas páginas, datas iguais, sanitização da API, descarte parcial e retomada na primeira página. O runtime definitivo executou o segundo slot TJAC/D contra a API real: sucesso, zero correspondências, uma tentativa da API e nenhuma do caderno.

- [x] **11c — Persistir comunicações, vínculos e estado por tribunal.**
  **Aceite:** (1) persistir comunicações no tenant correto e na fonte lógica DJEN, convertendo apenas `texto` da API em texto simples, sem sanitizar cadernos; (2) manter vínculos e estado por execução/tribunal, distinguindo sucesso vazio de falha; (3) deixar falha consultável sem registrar detalhes no Escrevente.
  **Verificação comportamental:** conferir publicação e estado de resultados do caderno e fallback, inclusive ausência de itens e falha técnica.
  **Smoke específico:** persistir resultado controlado de cada caminho e ler a comunicação, vínculo e estado do tribunal correspondente.
  **Dep.:** 11a–11b, 9a–9b, 10a. **Escopo:** persistência e status de execução.
  **Áreas previstas (≤5):** persistência de comunicações; vínculos; estado por tribunal; integração Escrevente.
  **Rastreio:** [SPEC-coleta.md — Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos).
  **Estado:** smoke anterior de seis trabalhos planejados produziu uma comunicação e seis vínculos; PostgreSQL confirmou todos concluídos. Testes de roles e tenants verificaram sucesso vazio, falha e agregado por tribunal sem registrar erro no Escrevente.

### 12. Deduplicação

- [x] **12a — Deduplicar pela chave conjunta DJEN/tenant.**
  **Aceite:** (1) usar conjuntamente `id` e `hash`, escopados por tenant e fonte lógica DJEN; (2) manter uma comunicação e sua primeira versão quando a chave coincide entre caderno, API e execuções, inclusive HTML do caderno; (3) não fundir registros quando qualquer componente da chave difere ou apenas processo/tribunal coincide.
  **Verificação comportamental:** cenário com publicação repetida em ambos os caminhos/execuções, preservando HTML recebido primeiro do caderno mesmo após texto sanitizado da API, chave com cada componente alterado e mesma chave em tenants diferentes.
  **Smoke específico:** inserir repetição cross-path e conferir uma comunicação com a primeira versão preservada para chave igual e registros distintos onde a chave não é igual.
  **Dep.:** 11c, 1a–1b, 3c. **Escopo:** chave deduplicadora aprovada; sem revalidar estabilidade assumida.
  **Áreas previstas (≤5):** persistência de comunicações; regra de deduplicação; chave de origem/tenant.
  **Rastreio:** [SPEC-coleta.md — Deduplicação e vínculos](../SPEC-coleta.md#deduplicação-e-vínculos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).
  **Verificação atual:** o teste de integração do processador exercitou caderno seguido da API com a mesma chave e preservou o HTML inicial; testes Rails focados cobrem chaves alteradas e tenants distintos. No smoke controlado com dois tenants, os 12 trabalhos produziram uma comunicação por tenant.

- [x] **12b — Preservar todos os vínculos de monitoramento.**
  **Aceite:** (1) cada monitoramento que encontra comunicação mantém vínculo consultável mesmo quando a comunicação já existe; (2) repetição não remove vínculos anteriores nem cruza tenants; (3) comunicações distintas continuam independentes.
  **Verificação comportamental:** buscar uma comunicação por várias entidades/execuções e confirmar todos os vínculos; consultar tenant distinto e confirmar isolamento.
  **Smoke específico:** duas entidades do mesmo tenant encontram a mesma chave por caderno e API; consultar uma comunicação e verificar ambos os vínculos.
  **Dep.:** 12a, 10a, 11c. **Escopo:** relação comunicação-monitoramento.
  **Áreas previstas (≤5):** persistência de vínculos; consulta de vínculos; autorização por tenant.
  **Rastreio:** [SPEC-coleta.md — Deduplicação e vínculos](../SPEC-coleta.md#deduplicação-e-vínculos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).
  **Verificação atual:** no smoke controlado, cada comunicação manteve seis vínculos — advogado, parte e processo em duas execuções — com isolamento por tenant; `processador_persistence_test.rb` também verifica leitura RLS e recusa de vínculos cruzados.

## Checkpoint 4 — após tarefas 10–12
- [x] Somente D, sem editais E: caderno com fallback no primeiro slot, API direta sem caderno no segundo, sanitização somente API, estado por tribunal, deduplicação conjunta com primeira versão preservada e vínculos demonstrados em cenários propostos, sem coleta histórica.
- [ ] Aprovação humana registrada antes de avançar.

### 13. Agenda e falhas

- [ ] **13a — Executar agenda e registrar tentativas e falha por execução/tribunal.**
  **Aceite:** (1) executar, com o ETL de 11, os acionamentos definidos em 10b; (2) aplicar tentativas, backoff, parada e fallback conforme limites aprovados; (3) estado final identifica falha por tribunal e execução, sem confundi-la com zero publicações nem registrar detalhes técnicos no Escrevente.
  **Verificação comportamental:** fazer a fonte falhar até esgotar tentativas e depois responder; verificar contagem/estado dentro dos limites decididos.
  **Smoke específico:** executar os acionamentos planejados com resultado controlado e conferir a execução/estado de cada um, incluindo falha de tribunal distinta de sucesso sem publicações.
  **Dep.:** 10b, 11a–11c, 1c, 9b. **Escopo:** execução da agenda, tentativas e estado operacional.
  **Áreas previstas (≤5):** execução; política de retries; estado por tribunal; consulta de falhas.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [ ] **13b — Recuperar no mesmo dia sem retroatividade.**
  **Aceite:** (1) execução posterior no mesmo dia pode persistir publicações após falha anterior; (2) deduplicação preserva chave/vínculos entre as execuções; (3) nenhuma execução busca automaticamente data anterior.
  **Verificação comportamental:** primeira execução falha e a seguinte tem sucesso na mesma data; comparar registros, estado e data enviada.
  **Smoke específico:** repetir coleta do dia corrente após falha e confirmar recuperação sem duplicar publicação e sem consulta histórica.
  **Dep.:** 13a, 12a–12b, 1c. **Escopo:** recuperação pela execução posterior, não reprocessamento retroativo.
  **Áreas previstas (≤5):** execução; persistência; deduplicação; política de datas.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Deduplicação e vínculos](../SPEC-coleta.md#deduplicação-e-vínculos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).

### 14. Consulta de comunicações

- [ ] **14a — Listar comunicações e apresentar detalhes.**
  **Aceite:** (1) apresentar cada comunicação independentemente, agrupada por tribunal sem fundir por processo; (2) detalhe inclui tribunal, número do processo e conteúdo da fonte sempre escapado, inclusive HTML preservado da primeira versão de caderno; (3) omissões da fonte não são preenchidas como se fossem dados existentes.
  **Verificação comportamental:** abrir várias comunicações do mesmo processo/tribunal e confirmar independência e conteúdo de origem no detalhe, sem executar nem inserir HTML bruto da fonte.
  **Smoke específico:** abrir resultado agrupado com HTML persistido do caderno e conferir tribunal, número e conteúdo escapado, sem presumir que a sanitização da API alterou a primeira versão deduplicada.
  **Dep.:** 12b, 11c, 6b. **Escopo:** leitura, agrupamento visual e detalhe.
  **Áreas previstas (≤5):** consulta; interface de resultados; detalhe; projeção de dados de origem.
  **Rastreio:** [SPEC-consulta.md — Escopo e contratos lógicos](../SPEC-consulta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis).

- [ ] **14b — Autorizar lista, detalhe e agregações.**
  **Aceite:** (1) filtrar cada resposta no servidor pelo tenant autenticado e tribunais permitidos; (2) não permitir acesso cruzado por ID/tenant enviado pelo cliente; (3) aplicar restrição também a detalhes e agregações, não apenas à lista/UI.
  **Verificação comportamental:** chamadas diretas a lista, detalhe e agregação com usuário restrito e tenant diferente.
  **Smoke específico:** abrir ID de comunicação de outro tenant e tribunal não permitido; nenhuma resposta expõe dados.
  **Dep.:** 14a, 4b, 6b–6c, 12b. **Escopo:** autorização de todas as superfícies de consulta.
  **Áreas previstas (≤5):** consulta; filtros de autorização; detalhes; agregações.
  **Rastreio:** [SPEC-consulta.md — Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-consulta.md#fronteiras).

### 15. Dashboard e restrição

- [ ] **15a — Calcular volumetrias aprovadas.**
  **Aceite:** (1) calcular unidades/períodos segundo definições aprovadas em 2c; (2) respeitar tenant, tribunais e escopo de dashboard permitido; (3) não inferir métricas de fonte ou tratar comunicações independentes como uma só por processo.
  **Verificação comportamental:** conferir cálculos em recortes/períodos aprovados e ausência de dados de tribunal/tenant não autorizado.
  **Smoke específico:** comparar uma volumetria controlada da dashboard com a definição aprovada de unidade, janela e escopo.
  **Dep.:** 14b, 2c, 12a–12b, 13a. **Escopo:** agregações da dashboard, sem notificação por e-mail.
  **Áreas previstas (≤5):** consulta/agregação; critérios de métricas; autorização; interface da dashboard.
  **Rastreio:** [SPEC-consulta.md — Objetivo](../SPEC-consulta.md#objetivo); [Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-consulta.md#questões-abertas-e-bloqueios); [Critérios de sucesso](../SPEC-consulta.md#critérios-de-sucesso).

- [ ] **15b — Exibir `*` e avisos de falha sem vazamento.**
  **Aceite:** (1) exibir `*` para valores numericamente negados e nunca entregar os valores protegidos por rota/aggregate alternativo; (2) avisar tribunal com falha persistente e distingui-la de sucesso com zero publicações; (3) manter acesso a cada aviso/métrica dentro de tenant e tribunal autorizados.
  **Verificação comportamental:** comparar dashboard, API e chamada direta com papéis permitidos/restritos em estados de zero, sucesso, falha e dashboard negada.
  **Smoke específico:** tribunal falho aparece como falha; usuário sem acesso vê `*` e não obtém o número por chamada direta.
  **Dep.:** 15a, 6c, 13a, 14b. **Escopo:** apresentação protegida e estado operacional.
  **Áreas previstas (≤5):** dashboard; aviso por tribunal; autorização; consulta de estado.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Fronteiras](../SPEC-autorizacao.md#fronteiras); [SPEC-consulta.md — Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-consulta.md#fronteiras).

## Checkpoint 5 — após tarefas 13–15
- [ ] Recuperação no mesmo dia, consulta, volumetrias, `*`, isolamento e diferença entre falha/zero demonstrados nos cenários propostos.
- [ ] E-mail e outras fontes seguem fora da entrega.
- [ ] Aprovação humana registrada antes da verificação integrada.

### 16. Verificação integrada e carga

- [ ] **16a — Percorrer fluxo integrado e fronteiras.**
  **Aceite:** (1) percorrer onboarding/contexto, autorização, monitoramentos, planejamento, caderno e fallback, Escrevente, persistência, consulta e dashboard; (2) manter isolamento tenant/tribunal e vínculos, sem alterar a premissa aceita de estabilidade de IDs nem buscar dias anteriores; (3) demonstrar falha/recuperação no mesmo dia e diferença entre zero/falha.
  **Verificação comportamental:** cenário ponta a ponta controlado com usuários/tenants e resultados de ambos os caminhos, conferindo critérios de cada spec sem revalidar a fonte historicamente.
  **Smoke específico:** fluxo único de ponta a ponta: coleta do dia falha no caderno, fallback entrega resultado, repetição preserva dedup/vínculos, consulta respeita escopo e dashboard sinaliza estado correto.
  **Dep.:** 14a–14b, 15a–15b, 13a–13b, 9a–9b. **Escopo:** integração dos contratos, sem alterar specs aprovadas.
  **Áreas previstas (≤5):** cenário integrado; monitoramentos/coleta; Escrevente/estado; consulta/dashboard; autorização.
  **Rastreio:** [SPEC-identidade.md — Critérios observáveis](../SPEC-identidade.md#critérios-observáveis); [SPEC-autorizacao.md — Critérios observáveis](../SPEC-autorizacao.md#critérios-observáveis); [SPEC-monitoramentos.md — Critérios observáveis](../SPEC-monitoramentos.md#critérios-observáveis); [SPEC-escrevente.md — Critérios de sucesso](../SPEC-escrevente.md#critérios-de-sucesso); [SPEC-coleta.md — Critérios de sucesso](../SPEC-coleta.md#critérios-de-sucesso); [SPEC-consulta.md — Critérios de sucesso](../SPEC-consulta.md#critérios-de-sucesso); [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico).

- [ ] **16b — Avaliar capacidade futuramente (não bloqueia esta entrega).**
  **Referência:** 300 usuários simultâneos orientam o planejamento, sem constituir meta comprovada ou critério de aceite atual.
  **Verificação futura:** definir perfil, ambiente, duração e limites; medir e registrar resultados antes de afirmar capacidade.
  **Dep.:** aplicação implementada. **Escopo:** teste posterior de capacidade.
  **Áreas previstas (≤5):** cenário de carga; ferramenta/configuração aprovada; relatório de resultados.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-autorizacao.md — Questões abertas](../SPEC-autorizacao.md#questões-abertas); [SPEC-monitoramentos.md — Questões abertas](../SPEC-monitoramentos.md#questões-abertas); [SPEC-consulta.md — Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-consulta.md#questões-abertas-e-bloqueios).

## Checkpoint final — após tarefa 16
- [ ] Critérios das seis specs e dependências do mapa demonstrados; registrar resultados e limitações, sem declarar concluído o que não foi exercitado.
- [ ] Aprovação humana final registrada.
