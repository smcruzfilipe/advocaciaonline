# Tarefas: monitoramento jurídico

Plano: [plan.md](plan.md). As seis specs, o plano e este checklist foram aprovados pelo solicitante. O advisor revisou o planejamento sem impedimentos para versionamento. A implementação continua condicionada à resolução das decisões bloqueantes 1–3. Nenhuma tarefa de execução está concluída.

## Regras de execução e rastreio

- Preservar os IDs principais 1–16; as fatias `a/b/c` ficam dentro do ID principal. O plano referencia somente os IDs principais.
- Cada fatia limita o aceite a três critérios, traz verificação comportamental e smoke próprios, dependências, escopo e até cinco áreas previstas de arquivos.
- Áreas são módulos/artefatos lógicos, não caminhos inventados. Depois da decisão técnica 3a, registrar os caminhos exatos antes de executar cada fatia; se exceder cinco arquivos, redividir antes de executar.
- Não escolher stack, comandos, ferramentas, estruturas, formatos ou transportes antes das decisões 3a–3b. As verificações abaixo são propostas, não executadas; nenhum gate, teste, lint ou formatador foi rodado.
- Fonte lógica DJEN: cadernos ZIP/JSON são o caminho principal; comunicações paginadas são fallback; ambos usam exclusivamente a data corrente. Não revalidar retroativamente a premissa aceita de estabilidade de `id`/`hash`, nem iniciar recuperação histórica.
- Implementação futura parte de `dev`; o branch atual de documentação não é base de feature. E-mail e outras fontes ficam fora da primeira entrega.

## Decisões bloqueantes — tarefas 1–3

### 1. Confirmar contrato da fonte

- [ ] **1a — Fixar o contrato do caderno DJEN.**
  **Aceite:** (1) documentar tribunal e meio aplicáveis, ZIP e processamento de todos os JSONs; (2) mapear os campos e limitações observados para advogado/OAB, parte e processo, sem decidir regras de correspondência; (3) fixar somente a data corrente da execução.
  **Verificação comportamental:** revisar um caderno válido e cenários de ZIP incompleto/inválido, avaliando os campos disponíveis para cada tipo de entidade sem exigir decisão de matching.
  **Smoke específico:** percorrer, em revisão de contrato, um caderno JSON de um tribunal/data/meio e identificar os campos e limitações observados, sem executar coleta nem fixar correspondências.
  **Dep.:** nenhuma. **Escopo:** contrato funcional da fonte principal.
  **Áreas previstas (≤5):** especificação de coleta; referência do contrato DJEN.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [ ] **1b — Fixar fallback e tratamento da fonte.**
  **Aceite:** (1) definir condições de fallback e paginação da consulta de comunicações; (2) garantir datas inicial/final iguais à data corrente e distinguir resposta válida vazia de falha; (3) manter caderno e API como a mesma fonte lógica DJEN.
  **Verificação comportamental:** avaliar cenários de página única, múltiplas páginas, resposta vazia válida e caderno problemático contra as condições aprovadas.
  **Smoke específico:** revisão de um fluxo de fallback paginado com data atual, confirmando que não solicita dia anterior.
  **Dep.:** 1a. **Escopo:** contrato do caminho alternativo, sem implementar o conector.
  **Áreas previstas (≤5):** especificação de coleta; referência do contrato DJEN.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [ ] **1c — Fixar operação diária, tentativas e falha.**
  **Aceite:** (1) decidir horários/fuso/elegibilidade para duas execuções diárias; (2) aprovar limites, backoff, parada, retomada e critérios de falha por execução/tribunal; (3) permitir recuperação na execução posterior do mesmo dia, sem coleta retroativa.
  **Verificação comportamental:** revisar cenários de interrupção, tentativas esgotadas, falha persistente e sucesso posterior no mesmo dia; cada resultado distingue falha de zero publicações.
  **Smoke específico:** exercício de mesa “falha na primeira execução, sucesso na segunda, mesma data” e conferência do estado esperado.
  **Dep.:** 1a–1b. **Escopo:** decisões operacionais, sem executar agendamento/coleta.
  **Áreas previstas (≤5):** especificação de coleta; critérios de operação.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios); [Fronteiras](../SPEC-coleta.md#fronteiras).

### 2. Fechar decisões de segurança, dados e desempenho

- [ ] **2a — Aprovar política de identidade e validade.**
  **Aceite:** (1) decidir escopo da validade (advogado/equipe), criação e ciclo de vida das credenciais e início/fuso/instante da contagem; (2) definir efeitos de renovação, alteração e revogação em credenciais/sessões; (3) preservar a recusa server-side após expiração mesmo para sessão ativa.
  **Verificação comportamental:** revisão dos cenários sem expiração, validade em dias e operação protegida depois do vencimento numa sessão previamente aberta.
  **Smoke específico:** tabela de decisão para sessão ativa antes/depois do instante aprovado de expiração.
  **Dep.:** 1a–1c quando afetarem credenciais. **Escopo:** política, sem escolher mecanismo de login.
  **Áreas previstas (≤5):** especificação de identidade; política de credenciais.
  **Rastreio:** [SPEC-identidade.md — Requisitos](../SPEC-identidade.md#requisitos); [Critérios observáveis](../SPEC-identidade.md#critérios-observáveis); [Questões abertas](../SPEC-identidade.md#questões-abertas); [Fronteiras](../SPEC-identidade.md#fronteiras).

- [ ] **2b — Aprovar composição de grupos e operações.**
  **Aceite:** (1) decidir composição/conflito de grupos e operações, inclusive concessões de escrita; (2) manter leitura ampla sem grupo sem conceder escrita e preservar `Consulta TJSP` como somente leitura de TJSP quando não conflitante; (3) definir o escopo de tribunal aplicado a lista, detalhe e agregações.
  **Verificação comportamental:** matriz aprovada para sem grupo, `Consulta TJSP`, outros grupos/conflitos e operações de leitura/escrita.
  **Smoke específico:** revisão de chamadas permitidas e negadas para TJSP, outro tribunal e escrita.
  **Dep.:** 2a. **Escopo:** contrato de autorização, sem inventar roles.
  **Áreas previstas (≤5):** especificação de autorização; matriz de decisões.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Critérios observáveis](../SPEC-autorizacao.md#critérios-observáveis); [Questões abertas](../SPEC-autorizacao.md#questões-abertas); [Fronteiras](../SPEC-autorizacao.md#fronteiras).

- [ ] **2c — Aprovar dashboard, dados e metas de capacidade.**
  **Aceite:** (1) definir métricas, unidade/período, escopo parcial de tribunal e regra de `*` para números negados; (2) decidir retenção/tratamento de dados pessoais do Escriba e distinção entre zero, falha e indisponível; (3) fixar perfil de carga, duração, ambiente, latência e taxa de erro para comprovar pelo menos 300 usuários simultâneos.
  **Verificação comportamental:** revisão dos cenários de dashboard restrita, métrica parcial, falha persistente, retenção e carga representativa com limites numéricos aprovados.
  **Smoke específico:** conferir uma tabela de métricas/estados com valores autorizados, negados (`*`), zero e falha, sem expor valor protegido.
  **Dep.:** 2b e 1c. **Escopo:** políticas e critérios mensuráveis, sem executar carga.
  **Áreas previstas (≤5):** especificações de autorização, Escriba e consulta; critérios de desempenho/dados.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Questões abertas](../SPEC-autorizacao.md#questões-abertas); [SPEC-escriba.md — Fronteiras](../SPEC-escriba.md#fronteiras); [SPEC-consulta.md — Requisitos](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Questões abertas](../SPEC-consulta.md#questões-abertas-e-bloqueios).

### 3. Definir stack e contratos

- [ ] **3a — Decidir stack, arquitetura física e ferramentas.**
  **Aceite:** (1) completar a stack central escolhida — Rails API-only, Next.js, PostgreSQL com RLS — com versões, ETL, layout, convenções, políticas RLS e comandos reais, conforme [registro técnico](../docs/stack.md); (2) mapear áreas e caminhos exatos dos arquivos/testes de cada fatia antes da execução; (3) redividir qualquer fatia que exija mais de cinco arquivos.
  **Verificação comportamental:** revisão de que cada área física tem dono e que nenhum comando/caminho presumido entrou no checklist.
  **Smoke específico:** percorrer um fluxo representativo do mapa até os arquivos/camadas definidos, sem criar código.
  **Dep.:** 1a–1c e 2a–2c. **Escopo:** decisão técnica, sem implementação.
  **Áreas previstas (≤5):** decisão de stack; arquitetura; convenções; estratégia de testes.
  **Rastreio:** [SPEC-identidade.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-identidade.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-autorizacao.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-autorizacao.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-monitoramentos.md — Ambiente de implementação e teste: pendências bloqueantes](../SPEC-monitoramentos.md#ambiente-de-implementação-e-teste-pendências-bloqueantes); [SPEC-escriba.md — Comandos, estrutura e estilo](../SPEC-escriba.md#comandos-estrutura-e-estilo); [SPEC-coleta.md — Comandos, estrutura e estilo](../SPEC-coleta.md#comandos-estrutura-e-estilo); [SPEC-consulta.md — Comandos, estrutura e estilo](../SPEC-consulta.md#comandos-estrutura-e-estilo); [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico).

- [ ] **3b — Definir contratos entre aplicação e módulos lógicos.**
  **Aceite:** (1) definir contratos de identidade/tenant server-side, autorização, monitoramentos, coleta, estado por tribunal e consulta; (2) preservar planner/control plane e ETL como responsabilidades distintas da aplicação central sem impor serviço/processo/diretório; (3) definir entrada append-only do Escriba e manter estado/detalhes de falha fora dele.
  **Verificação comportamental:** revisão de contrato para tenant adulterado pelo cliente, vínculo de execução/entidade/tribunal e resposta autorizada.
  **Smoke específico:** seguir um diagrama de sequência de onboarding até consulta, identificando consumidor/dono de cada dado.
  **Dep.:** 3a. **Escopo:** interfaces lógicas; transporte/formato só quando aprovados.
  **Áreas previstas (≤5):** contratos de identidade/autorização; monitoramentos; coleta/Escriba; consulta.
  **Rastreio:** [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico); [SPEC-identidade.md — Escopo e dono dos contratos](../SPEC-identidade.md#escopo-e-dono-dos-contratos); [SPEC-autorizacao.md — Escopo e dono dos contratos](../SPEC-autorizacao.md#escopo-e-dono-dos-contratos); [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [SPEC-escriba.md — Escopo e contratos lógicos](../SPEC-escriba.md#escopo-e-contratos-lógicos); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [SPEC-consulta.md — Escopo e contratos lógicos](../SPEC-consulta.md#escopo-e-contratos-lógicos).

- [ ] **3c — Resolver decisões de domínio restantes antes de codificar.**
  **Aceite:** (1) aprovar validação/normalização e correspondência de nome, OAB e processo, homônimos, duplicidade e filtros de tribunal; (2) decidir tratamento de `id`/`hash` ausente, inválido ou inconsistente sem alterar a chave conjunta aceita; (3) registrar explicitamente o que permanece fora do escopo sem presumir fluxo de convite, edição/remoção, e-mail ou recuperação histórica.
  **Verificação comportamental:** revisão de casos limítrofes e fronteiras de cada spec; estabilidade/unicidade global de `id`/`hash` não é revalidada.
  **Smoke específico:** walkthrough de monitoramento com homônimo/filtro indisponível e publicação sem chave válida, confirmando decisão explícita para cada caso.
  **Dep.:** 1a–1c, 2a–2c e 3b. **Escopo:** fechar pendências funcionais, sem ampliar produto.
  **Áreas previstas (≤5):** especificações de identidade, monitoramentos e coleta; decisões de domínio.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-monitoramentos.md — Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

## Checkpoint 1 — após decisões 1–3
- [ ] Decisões bloqueantes resolvidas e alinhadas com a base funcional das seis specs; sem iniciar implementação antes da aprovação humana.
- [ ] Feedback obrigatório do advisor recebido e apontamentos pertinentes tratados; aprovação humana registrada antes de avançar (`AGENTS.md`).

## Implementação — tarefas 4–16

### 4. Onboarding do advogado

- [ ] **4a — Persistir perfil profissional e tenant próprio.**
  **Aceite:** (1) onboarding registra nome completo, OAB principal e OABs secundárias informadas; (2) cada advogado pertence ao próprio tenant e escritório/nome comercial opcional não define tenant.
  **Verificação comportamental:** concluir onboarding e ler o perfil e tenant; comparar dois advogados/tenants sem inferir monitoramentos.
  **Smoke específico:** primeiro acesso de advogado com OAB principal e sem OAB secundária, conferindo vínculo ao tenant próprio.
  **Dep.:** 3a–3c. **Escopo:** onboarding, perfil profissional e vínculo ao tenant.
  **Áreas previstas (≤5):** identidade; persistência de perfil; onboarding/interface.
  **Rastreio:** [SPEC-identidade.md — Contratos lógicos](../SPEC-identidade.md#contratos-lógicos); [Requisitos](../SPEC-identidade.md#requisitos).

- [ ] **4b — Derivar contexto autenticado no servidor.**
  **Aceite:** (1) cada operação protegida recebe identidade e tenant do contexto server-side; (2) tenant enviado pelo cliente não altera o contexto nem permite acesso cruzado; (3) contexto expirado não é apresentado como identidade válida.
  **Verificação comportamental:** tentar operar em outro tenant enviando tenant/ID conhecido e confirmar negação.
  **Smoke específico:** chamada autenticada com tenant adulterado continua restrita ao tenant da identidade.
  **Dep.:** 4a, 3b. **Escopo:** fronteira de identidade, sem decidir mecanismo de login além de 2a.
  **Áreas previstas (≤5):** identidade; contexto de requisição; autorização de tenant.
  **Rastreio:** [SPEC-identidade.md — Contratos lógicos](../SPEC-identidade.md#contratos-lógicos); [Fronteiras](../SPEC-identidade.md#fronteiras); [SPEC-autorizacao.md — Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).

### 5. Gestão de usuários e expiração

- [ ] **5a — Aplicar validade às credenciais e sessões.**
  **Aceite:** (1) permitir validade sem expiração ou em dias conforme política aprovada; (2) após vencimento, negar operação protegida no servidor mesmo se a sessão já estava ativa; (3) aplicar renovação/alteração/revogação conforme a decisão 2a.
  **Verificação comportamental:** comparar acesso válido, sem expiração, após vencimento e sessão aberta antes do vencimento.
  **Smoke específico:** renovar ou expirar uma credencial numa sessão ativa e tentar imediatamente uma nova operação protegida.
  **Dep.:** 4b, 2a, 3a. **Escopo:** validade de credencial e checagem server-side.
  **Áreas previstas (≤5):** identidade/autenticação; política de credenciais; interface de validade.
  **Rastreio:** [SPEC-identidade.md — Requisitos](../SPEC-identidade.md#requisitos); [Fronteiras](../SPEC-identidade.md#fronteiras); [Questões abertas](../SPEC-identidade.md#questões-abertas).

- [ ] **5b — Administrar ciclo de usuários aprovado.**
  **Aceite:** (1) executar somente ações de usuário aprovadas em 2a/2b; (2) vincular usuários ao tenant do advogado sem assumir convite, credencial ou login não aprovados.
  **Verificação comportamental:** criar/alterar o estado previsto para usuário da equipe e confirmar que outro tenant não pode administrá-lo.
  **Smoke específico:** operação de administração autorizada num tenant e tentativa negada usando identificador de outro tenant.
  **Dep.:** 5a, 2a, 2b, 3b. **Escopo:** gestão de usuários dentro do ciclo aprovado.
  **Áreas previstas (≤5):** autorização/administração; identidade de equipe; persistência de usuários.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Questões abertas](../SPEC-autorizacao.md#questões-abertas).

### 6. Grupos e escopo de tribunais

- [ ] **6a — Administrar grupos no tenant correto.**
  **Aceite:** (1) advogado administra os grupos aprovados somente no próprio tenant; (2) decisões de composição e ciclo de vida de grupo seguem a política 2b, sem roles presumidas.
  **Verificação comportamental:** administrar grupo no tenant próprio e negar leitura/alteração de grupo alheio por ID enviado pelo cliente.
  **Smoke específico:** abrir a administração de grupos com contexto de dois tenants e conferir isolamento.
  **Dep.:** 5b, 4b, 2b. **Escopo:** administração lógica de grupos.
  **Áreas previstas (≤5):** autorização/administração; persistência de grupos; interface administrativa.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).

- [ ] **6b — Aplicar permissões por operação e tribunal.**
  **Aceite:** (1) sem grupos, permitir leitura ampla dos tribunais sem conceder escrita; (2) `Consulta TJSP` permite somente leitura TJSP quando avaliado sem conflito; (3) aplicar regras aprovadas pelo servidor ao dado retornado.
  **Verificação comportamental:** matriz de leitura/escrita, TJSP/outro tribunal e composição de grupos decidida em 2b.
  **Smoke específico:** usuário sem grupo e usuário `Consulta TJSP` tentam ler TJSP, ler outro tribunal e escrever.
  **Dep.:** 6a, 4b, 2b. **Escopo:** decisão de acesso aplicada em cada operação.
  **Áreas previstas (≤5):** autorização; política de operações; filtros de dados.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos).

- [ ] **6c — Aplicar a decisão de autorização da dashboard.**
  **Aceite:** (1) decidir o acesso à dashboard conforme política aprovada, tenant e escopo de tribunal; (2) aplicar a decisão no servidor e não retornar valores protegidos quando negada, sem definir sua representação visual.
  **Verificação comportamental:** comparar respostas do servidor para chamadas autorizadas, negadas e parcialmente permitidas, conferindo escopo e ausência de valores protegidos nas negadas.
  **Smoke específico:** chamada controlada à operação da dashboard com acesso negado não retorna valores protegidos; a exibição na interface é verificada em 15b.
  **Dep.:** 6b, 2b–2c. **Escopo:** decisão e aplicação server-side da autorização da dashboard.
  **Áreas previstas (≤5):** autorização; consulta/agregação; filtros server-side.
  **Rastreio:** [SPEC-autorizacao.md — Requisitos](../SPEC-autorizacao.md#requisitos); [Contratos lógicos](../SPEC-autorizacao.md#contratos-lógicos); [SPEC-consulta.md — Requisitos](../SPEC-consulta.md#requisitos-e-critérios-observáveis).

## Checkpoint 2 — após tarefas 4–6
- [ ] Onboarding, expiração em sessão ativa, isolamento e regras de autorização demonstrados nos cenários propostos.
- [ ] Feedback do advisor recebido/tratado e aprovação humana registrada antes de avançar.

### 7. Cadastro de partes

- [ ] **7a — Fornecer ao monitoramento o perfil do advogado.**
  **Aceite:** (1) entidade advogado reflete nome e OABs da identidade; (2) não duplica perfil nem transforma escritório em tenant; (3) identidade e tenant ficam disponíveis à coleta.
  **Verificação comportamental:** editar/ler perfil conforme operações aprovadas e conferir saída lógica consumida pela coleta.
  **Smoke específico:** seguir perfil de um advogado até sua entidade de monitoramento e confirmar tenant próprio.
  **Dep.:** 4a, 4b, 6b, 3b. **Escopo:** vínculo lógico de identidade ao monitoramento.
  **Áreas previstas (≤5):** identidade; monitoramentos; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Critérios observáveis](../SPEC-monitoramentos.md#critérios-observáveis).

- [ ] **7b — Cadastrar partes e filtros suportados.**
  **Aceite:** (1) cadastrar/ler nome de parte sob tenant autenticado; (2) oferecer somente filtros de tribunal disponibilizados e suportados pela fonte; (3) fornecer identidade lógica, tenant e dados de busca à coleta sem prometer matching não aprovado.
  **Verificação comportamental:** cadastrar/ler parte autorizada, tentar acesso cruzado e verificar filtros contra a lista aprovada da fonte.
  **Smoke específico:** cadastrar uma parte com tribunal suportado e confirmar tenant/filtro na saída lógica, sem disparar coleta.
  **Dep.:** 7a, 3c, 6b. **Escopo:** cadastro e leitura de partes.
  **Áreas previstas (≤5):** monitoramentos; filtros de tribunal; interface de partes; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas).

### 8. Cadastro de processos

- [ ] **8a — Cadastrar processo e filtros suportados.**
  **Aceite:** (1) cadastrar/ler número de processo no tenant autenticado; (2) vincular apenas filtros de tribunal aprovados e suportados pela fonte; (3) fornecer identidade lógica, tenant e critérios decididos à coleta.
  **Verificação comportamental:** cadastrar e ler processo autorizado e negar leitura por outro tenant ou tribunal sem acesso.
  **Smoke específico:** cadastrar um processo com tribunal suportado e conferir número, tenant e filtro entregues ao consumidor lógico.
  **Dep.:** 6b, 3b, 3c. **Escopo:** cadastro e leitura de processos.
  **Áreas previstas (≤5):** monitoramentos; filtros de tribunal; interface de processos; contrato de coleta.
  **Rastreio:** [SPEC-monitoramentos.md — Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos); [Requisitos](../SPEC-monitoramentos.md#requisitos); [Questões abertas](../SPEC-monitoramentos.md#questões-abertas).

- [ ] **8b — Disponibilizar páginas e navegação autorizadas.**
  **Aceite:** (1) disponibilizar páginas de cadastro/leitura de partes e processos; (2) navegação entre esses cadastros respeita autorização também em acesso direto; (3) aplicar operações de ciclo de vida somente conforme aprovadas.
  **Verificação comportamental:** abrir páginas de cadastro/leitura com ator autorizado e restrito, incluindo chamada direta a destino de cadastro negado.
  **Smoke específico:** navegar entre os cadastros de parte e processo com usuário autorizado e repetir acesso direto sem autorização; resultados e dashboard ficam para a integração após 14–15.
  **Dep.:** 7b, 8a, 6b. **Escopo:** apresentação/navegação dos cadastros; integração com resultados/dashboard em 16a, após 14–15.
  **Áreas previstas (≤5):** interface de monitoramentos; navegação; autorização de destinos.
  **Rastreio:** [SPEC-monitoramentos.md — Requisitos](../SPEC-monitoramentos.md#requisitos); [Escopo e dono dos contratos](../SPEC-monitoramentos.md#escopo-e-dono-dos-contratos).

### 9. Escriba append-only

- [ ] **9a — Acrescentar marcos do fluxo de coleta.**
  **Aceite:** (1) registrar início e término como novos marcos com contexto/rastreio disponível de tenant, execução, fonte, entidade, advogado, tribunal e processos associados; (2) registros gravados não são editados nem removidos por operações normais; (3) ausência de término permanece sem término, sem evento retroativo inferido.
  **Verificação comportamental:** consultar sequência de marcos após início/término e tentar alteração/remoção; confirmar conteúdo histórico idêntico.
  **Smoke específico:** registrar início e conclusão e conferir dois acréscimos rastreáveis, sem sobrescrever o primeiro.
  **Dep.:** 3b, 4b. **Escopo:** registro append-only do fluxo.
  **Áreas previstas (≤5):** Escriba; persistência de marcos; contrato de coleta.
  **Rastreio:** [SPEC-escriba.md — Escopo e contratos lógicos](../SPEC-escriba.md#escopo-e-contratos-lógicos); [Requisitos](../SPEC-escriba.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-escriba.md#fronteiras).

- [ ] **9b — Separar falhas do registro imutável.**
  **Aceite:** (1) Escriba não recebe ações de usuário nem detalhes técnicos de erro; (2) estado de sucesso/falha permanece consultável fora do Escriba e relacionado à execução/tribunal; (3) tenant de registro deriva do contexto server-side.
  **Verificação comportamental:** exercitar a fronteira com uma chamada controlada que informa o resultado operacional definido no contrato; verificar estado externo, tenant adulterado e ausência de marco final, sem depender de execução do coletor.
  **Smoke específico:** invocar a fronteira com resultado controlado de falha e confirmar estado externo consultável conforme contrato, sem texto técnico ou ação de usuário no Escriba.
  **Dep.:** 9a, 3b, 4b. **Escopo:** fronteira entre ledger append-only e estado operacional.
  **Áreas previstas (≤5):** Escriba; estado de execução; contexto de identidade.
  **Rastreio:** [SPEC-escriba.md — Escopo e contratos lógicos](../SPEC-escriba.md#escopo-e-contratos-lógicos); [Requisitos](../SPEC-escriba.md#requisitos-e-critérios-observáveis); [Fronteiras](../SPEC-escriba.md#fronteiras).

## Checkpoint 3 — após tarefas 7–9
- [ ] Monitoramentos de advogado/parte/processo entregam tenant e identidade corretos; Escriba permanece append-only e sem ações/erros técnicos.
- [ ] Feedback do advisor recebido/tratado e aprovação humana registrada antes de avançar.

### 10. Planejamento da coleta

- [ ] **10a — Planejar por tenant, entidade, fonte e tribunal.**
  **Aceite:** (1) trabalho identifica tenant, entidade/monitoramento, execução, fonte lógica e tribunal aplicável; (2) inclui advogado, partes e processos elegíveis conforme filtros decididos; (3) não aceita tenant do cliente como prova de propriedade.
  **Verificação comportamental:** planejar entidades de mais de um tenant e conferir que cada linha mantém seus vínculos sem cruzamento.
  **Smoke específico:** planejar um advogado, uma parte e um processo em dois tenants e inspecionar os vínculos resultantes.
  **Dep.:** 7a–7b, 8a, 4b, 9a. **Escopo:** trabalho planejado, sem ainda executar a fonte.
  **Áreas previstas (≤5):** planejador; contrato de monitoramentos; contexto de tenant; execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).

- [ ] **10b — Agendar as duas execuções e manter fronteiras lógicas.**
  **Aceite:** (1) configurar dois acionamentos diários conforme horário/fuso/elegibilidade aprovados; (2) manter planner/control plane e ETL como responsabilidades distintas da aplicação central; (3) cada acionamento planejado tem identidade própria e associação à fonte/tribunal, sem executar ETL nesta fatia.
  **Verificação comportamental:** inspecionar os dois acionamentos planejados para o mesmo dia e confirmar distinção de execução e fronteiras sem exigir serviços/diretórios separados ou execução do ETL.
  **Smoke específico:** gerar dois acionamentos planejados para o mesmo dia e conferir identificadores/contexto separados, sem iniciar coleta.
  **Dep.:** 10a, 1c, 3a–3b. **Escopo:** planejamento da agenda; execução completa da coleta em 13a, após 11.
  **Áreas previstas (≤5):** planejador; contrato de acionamento do ETL; execução; configuração da agenda.
  **Rastreio:** [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico); [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

### 11. Coleta e persistência reais

- [ ] **11a — Coletar pelo caderno ZIP/JSON principal.**
  **Aceite:** (1) obter caderno por tribunal/data/meio e processar todos os JSONs do ZIP; (2) pesquisar advogado por nome/OAB, processo por número e parte por nome conforme regras aprovadas; (3) consultar somente o dia corrente da execução.
  **Verificação comportamental:** executar cenário controlado de ZIP com vários JSONs e correspondências dos três tipos, incluindo resultado válido vazio.
  **Smoke específico:** processar um caderno controlado e confirmar cada correspondência e ausência de consulta de dia anterior.
  **Dep.:** 10a, 10b, 1a, 3c. **Escopo:** caminho principal de coleta.
  **Áreas previstas (≤5):** conector de cadernos; processamento ZIP/JSON; matching; persistência de publicações; estado de execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).

- [ ] **11b — Acionar fallback paginado para problema no caderno.**
  **Aceite:** (1) sob condições de falha aprovadas, consultar API paginada como fallback da mesma fonte DJEN; (2) percorrer páginas necessárias segundo limites decididos e enviar início/fim iguais ao dia corrente; (3) resposta válida vazia não vira falha nem inclui dia anterior.
  **Verificação comportamental:** cenário de caderno problemático seguido por várias páginas, resposta vazia válida e tentativa de data fora do dia corrente.
  **Smoke específico:** executar um fallback controlado com mais de uma página e inspecionar os dois filtros de data iguais.
  **Dep.:** 10a–10b, 1b, 1c, 3a. **Escopo:** caminho alternativo da coleta.
  **Áreas previstas (≤5):** conector paginado; política de fallback; processamento de resposta; estado de execução.
  **Rastreio:** [SPEC-coleta.md — Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-coleta.md#questões-abertas-e-bloqueios).

- [ ] **11c — Persistir comunicações, vínculos e estado por tribunal.**
  **Aceite:** (1) normalizar e persistir comunicações encontradas no tenant correto e com identidade da fonte lógica DJEN; (2) manter vínculos e estado por execução/tribunal, distinguindo sucesso vazio de falha; (3) deixar falha consultável sem registrar detalhes no Escriba.
  **Verificação comportamental:** conferir publicação e estado de resultados do caderno e fallback, inclusive ausência de itens e falha técnica.
  **Smoke específico:** persistir resultado controlado de cada caminho e ler a comunicação, vínculo e estado do tribunal correspondente.
  **Dep.:** 11a–11b, 9a–9b, 10a. **Escopo:** persistência e status de execução.
  **Áreas previstas (≤5):** persistência de comunicações; vínculos; estado por tribunal; integração Escriba.
  **Rastreio:** [SPEC-coleta.md — Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis); [Escopo e contratos lógicos](../SPEC-coleta.md#escopo-e-contratos-lógicos).

### 12. Deduplicação

- [ ] **12a — Deduplicar pela chave conjunta DJEN/tenant.**
  **Aceite:** (1) usar conjuntamente `id` e `hash`, escopados por tenant e fonte lógica DJEN; (2) manter uma comunicação quando a chave coincide entre caderno, API e execuções; (3) não fundir registros quando qualquer componente da chave difere ou apenas processo/tribunal coincide.
  **Verificação comportamental:** cenário com publicação repetida em ambos os caminhos/execuções, chave com cada componente alterado e mesma chave em tenants diferentes.
  **Smoke específico:** inserir repetição cross-path e conferir uma comunicação para chave igual e registros distintos onde a chave não é igual.
  **Dep.:** 11c, 1a–1b, 3c. **Escopo:** chave deduplicadora aprovada; sem revalidar estabilidade assumida.
  **Áreas previstas (≤5):** persistência de comunicações; regra de deduplicação; chave de origem/tenant.
  **Rastreio:** [SPEC-coleta.md — Deduplicação e vínculos](../SPEC-coleta.md#deduplicação-e-vínculos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).

- [ ] **12b — Preservar todos os vínculos de monitoramento.**
  **Aceite:** (1) cada monitoramento que encontra comunicação mantém vínculo consultável mesmo quando a comunicação já existe; (2) repetição não remove vínculos anteriores nem cruza tenants; (3) comunicações distintas continuam independentes.
  **Verificação comportamental:** buscar uma comunicação por várias entidades/execuções e confirmar todos os vínculos; consultar tenant distinto e confirmar isolamento.
  **Smoke específico:** duas entidades do mesmo tenant encontram a mesma chave por caderno e API; consultar uma comunicação e verificar ambos os vínculos.
  **Dep.:** 12a, 10a, 11c. **Escopo:** relação comunicação-monitoramento.
  **Áreas previstas (≤5):** persistência de vínculos; consulta de vínculos; autorização por tenant.
  **Rastreio:** [SPEC-coleta.md — Deduplicação e vínculos](../SPEC-coleta.md#deduplicação-e-vínculos); [Requisitos e critérios observáveis](../SPEC-coleta.md#requisitos-e-critérios-observáveis).

## Checkpoint 4 — após tarefas 10–12
- [ ] Caderno principal, fallback paginado, estado por tribunal, deduplicação conjunta e vínculos demonstrados em cenários propostos, sem coleta histórica.
- [ ] Feedback do advisor recebido/tratado e aprovação humana registrada antes de avançar.

### 13. Agenda e falhas

- [ ] **13a — Executar agenda e registrar tentativas e falha por execução/tribunal.**
  **Aceite:** (1) executar, com o ETL de 11, os acionamentos definidos em 10b; (2) aplicar tentativas, backoff, parada e fallback conforme limites aprovados; (3) estado final identifica falha por tribunal e execução, sem confundi-la com zero publicações nem registrar detalhes técnicos no Escriba.
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
  **Aceite:** (1) apresentar cada comunicação independentemente, agrupada por tribunal sem fundir por processo; (2) detalhe inclui tribunal, número do processo e conteúdo fornecido pela fonte; (3) omissões da fonte não são preenchidas como se fossem dados existentes.
  **Verificação comportamental:** abrir várias comunicações do mesmo processo/tribunal e confirmar independência e conteúdo de origem no detalhe.
  **Smoke específico:** abrir um resultado agrupado e conferir tribunal, número e conteúdo recebido da fonte.
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
- [ ] Feedback do advisor recebido/tratado e aprovação humana registrada antes da verificação integrada.

### 16. Verificação integrada e carga

- [ ] **16a — Percorrer fluxo integrado e fronteiras.**
  **Aceite:** (1) percorrer onboarding/contexto, autorização, monitoramentos, planejamento, caderno e fallback, Escriba, persistência, consulta e dashboard; (2) manter isolamento tenant/tribunal e vínculos, sem alterar a premissa aceita de estabilidade de IDs nem buscar dias anteriores; (3) demonstrar falha/recuperação no mesmo dia e diferença entre zero/falha.
  **Verificação comportamental:** cenário ponta a ponta controlado com usuários/tenants e resultados de ambos os caminhos, conferindo critérios de cada spec sem revalidar a fonte historicamente.
  **Smoke específico:** fluxo único de ponta a ponta: coleta do dia falha no caderno, fallback entrega resultado, repetição preserva dedup/vínculos, consulta respeita escopo e dashboard sinaliza estado correto.
  **Dep.:** 14a–14b, 15a–15b, 13a–13b, 9a–9b. **Escopo:** integração dos contratos, sem alterar specs aprovadas.
  **Áreas previstas (≤5):** cenário integrado; monitoramentos/coleta; Escriba/estado; consulta/dashboard; autorização.
  **Rastreio:** [SPEC-identidade.md — Critérios observáveis](../SPEC-identidade.md#critérios-observáveis); [SPEC-autorizacao.md — Critérios observáveis](../SPEC-autorizacao.md#critérios-observáveis); [SPEC-monitoramentos.md — Critérios observáveis](../SPEC-monitoramentos.md#critérios-observáveis); [SPEC-escriba.md — Critérios de sucesso](../SPEC-escriba.md#critérios-de-sucesso); [SPEC-coleta.md — Critérios de sucesso](../SPEC-coleta.md#critérios-de-sucesso); [SPEC-consulta.md — Critérios de sucesso](../SPEC-consulta.md#critérios-de-sucesso); [CAPABILITIES.md — Mapa de capacidades: monitoramento jurídico](../CAPABILITIES.md#mapa-de-capacidades-monitoramento-jurídico).

- [ ] **16b — Comprovar carga de 300 usuários simultâneos.**
  **Aceite:** (1) exercitar perfil de carga representativo com pelo menos 300 usuários simultâneos; (2) medir latência, taxa de erro e estabilidade contra limites numéricos/ambiente aprovados em 2c; (3) registrar resultado e condições de reprodução sem declarar capacidade antes da medição.
  **Verificação comportamental:** executar o perfil aprovado e avaliar cada limite, incluindo operações protegidas e consultas representativas.
  **Smoke específico:** cenário de carga configurado com exatamente o limite mínimo aprovado e verificação de sucesso/erro e isolamento entre tenants; comando somente após stack/ferramenta aprovadas.
  **Dep.:** 16a, 2c, 3a. **Escopo:** medição de capacidade, sem inventar perfil, limiares ou comando.
  **Áreas previstas (≤5):** cenário de carga; ferramenta/configuração aprovada; relatório de resultados.
  **Rastreio:** [SPEC-identidade.md — Questões abertas](../SPEC-identidade.md#questões-abertas); [SPEC-autorizacao.md — Questões abertas](../SPEC-autorizacao.md#questões-abertas); [SPEC-monitoramentos.md — Questões abertas](../SPEC-monitoramentos.md#questões-abertas); [SPEC-consulta.md — Requisitos e critérios observáveis](../SPEC-consulta.md#requisitos-e-critérios-observáveis); [Questões abertas e bloqueios](../SPEC-consulta.md#questões-abertas-e-bloqueios).

## Checkpoint final — após tarefa 16
- [ ] Critérios das seis specs e dependências do mapa demonstrados; registrar resultados e limitações, sem declarar concluído o que não foi exercitado.
- [ ] Feedback obrigatório do advisor recebido e apontamentos pertinentes tratados; aprovação humana final registrada.
