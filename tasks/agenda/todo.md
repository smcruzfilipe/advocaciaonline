# Tarefas: agenda

**Estado:** checklist, spec, plano e contrato técnico aprovados pelo solicitante. AG01–AG03 concluídas documentalmente; AG04 bloqueada pela entrega real dos provedores e ambiente. Nenhuma implementação iniciada. Base: [spec](../../SPEC-agenda.md), [plano](plan.md) e [mapa](../../CAPABILITIES.md#agenda-e-atendimento-online). Conclusão documental não libera C0.

## Caminhos, escopo e gates

- Selecionar explicitamente `tasks/agenda/plan.md` e `tasks/agenda/todo.md`. Não substituir, renumerar, encerrar ou mover trabalho de `tasks/plan.md` e `tasks/todo.md`.
- IDs principais AG01–AG29 são estáveis; AG12 tem subfatias AG12a/AG12b. Cada folha tem aceite, dependências e limite próprios; AG12 é agregadora, sem execução adicional de código. Aprovação não significa implementação concluída.
- AG01–AG03 aprovadas e concluídas documentalmente; AG04 exige equipe/autorização, ABIs/contexto limitado, frontend e ambiente reais. P1–P4 dependem de C0. Nenhum gate é liberado por mock, flag local ou titular disfarçado de equipe.
- Não implementar aqui links individuais, Jitsi, Calendar, e-mails, lembretes, recorrência, equipe/grupos genéricos ou base frontend alternativa. Contexto limitado de consumidor é contrato com resolução confiável no servidor; o transporte externo real pertence a reservas-clientes.
- Caminhos novos abaixo são previsões ratificadas em AG03, não arquivos existentes. AG04 ainda registra scripts reais do frontend. Atribuir timestamps de migrations antes de executar. Se a base adotar outra organização, atualizar esta previsão e revalidar a fatia antes de codificar, sem criar convenção paralela.
- Cada tarefa admite até cinco arquivos **incluindo este checklist para rastreio**. Listas abaixo contêm até quatro arquivos funcionais; este arquivo é implícito quando não listado. Se outro arquivo, documentação, variável/README ou correção tornar a fatia maior, subdividir antes de executar, preservando dependências e aceite. Não esconder arquivos em um glob.
- Testes permanentes devem provar comportamento, limites, invariantes ou transições, não forwarding, cópias, texto incidental, presença de wiring ou eco de mocks. UI é verificada no navegador real; não criar suíte nova de UI por suposição.
- Em cada fatia, consultar as fontes oficiais das versões fixadas antes de usar APIs dependentes de tecnologia. Ao final, executar uma vez os checks pertinentes e o smoke da superfície alterada; registrar resultado e limitações. Remover instrumentos descartáveis após a prova, sem versionar segredos.
- Identidade/autorização e frontend compartilhados mantêm seus próprios donos/gates. Sua ausência bloqueia a entrega integral; backend somente titular não conclui agenda. Smoke com sessão preparada não demonstra OAuth Google real.

## Verificação comum da execução futura

Backend usa Rails/Minitest e PostgreSQL real. Executar com diretório de trabalho `backend/`, Ruby/gems do lockfile e variáveis protegidas do README. A suíte existente é `RAILS_ENV=test ruby bin/rails test`; API real para smoke: `bundle exec puma -C config/puma.rb`. Migration autorizada em teste usa `RAILS_ENV=test ruby bin/migrate`, nunca a role web. Da raiz, build existente: `docker build --target runtime -t advocacia-backend:local backend`. São comandos documentados, **não executados agora**.

Banco de teste deve estar separado, provisionado/migrado e acessível como `advocacia_runtime`; migrator só para procedimento/fixture administrativa. A suíte completa também usa as URLs específicas registradas no README. Não instalar PostgreSQL no deploy nem iniciar containers ou etapas privilegiadas por inferência deste checklist.

Comandos focados mostrados em cada tarefa são **futuros, condicionados à criação dos arquivos previstos**. Não confundir com suíte já disponível. Para UI, AG04 deve copiar comandos dos scripts reais e seus pré-requisitos; não inventar `npm test`, build/lint ou runner. Browser smoke é obrigatório em cada mudança de interface, mesmo que testes existam.

Provas de corrida usam dados commitados, contextos/conexões independentes e barreiras explícitas; testes não compartilham uma transação que esconda concorrência. Não usar sleeps como oráculo nem timeout genérico como conflito esperado. Propagar erros/limpar workers e respeitar pool/timeouts existentes.

## Ordem e paralelização

AG01 e AG02 são independentes; AG03 integra seus contratos. Após C0, AG07 e AG08 podem ser preparadas em paralelo após AG06, com dono único das áreas compartilhadas; AG09 depende de ambas. As demais dependências preservam a sequência vertical aprovada: fechar configuração, agendamento, remarcação e cancelamento, em vez de acumular toda a UI no final. Migrations são sequenciais; nunca executar suítes que limpem o mesmo banco em paralelo. Checkpoints intermediários são técnicos; C0/C1/C2/C3/C4 exigem revisão correspondente antes de avançar em caso de bloqueio/divergência.

## P0

### AG01 — Fechar limites e consulta temporal

- [x] Concluir AG01.

**Objetivo:** Transformar pendências humanas em regras suficientes para validar e oferecer horários.

**Aceite:**
- [x] Registrar decisão do solicitante sobre os máximos de duração, intervalo, antecedência e extensão de consulta, sem defaults.
- [x] Fechar representação de janelas explícitas, precisão, inclusividade da consulta e enumeração/alinhamento dos horários; duração não define uma grade por inferência.
- [x] Preservar minutos inteiros, UTC/tempo decorrido, America/Sao_Paulo, encaixe integral e as fronteiras temporais já aprovadas.

**Dependências:** nenhuma tarefa anterior; gate humano deste checklist continua obrigatório.

**Evidência/gate:** Solicitante confirmou limites e aprovou representação temporal: janelas absolutas, precisão de microssegundos, união da cobertura, conjuntos contínuos de inícios e consulta por 1–15 datas locais com início inclusivo/fim exclusivo. Revisão documental e modelo matemático registrados em AG03; não é prova da aplicação. Valores não são defaults nem horizonte de reserva.

**Verificação e smoke (futuros):**
- Exercício de contrato: configuração ausente, janelas vazias, término no limite da janela e instante exato da antecedência; todos devem ter resultado decidível.

**Arquivos previstos:**
- `SPEC-agenda.md`
- `tasks/agenda/plan.md`

**Escopo:** 2 arquivo(s) listado(s), 3 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 1, 2, 3, 4 de SPEC-agenda.md; fase P0 do plano.

### AG02 — Incorporar operações ao catálogo canônico

- [x] Concluir AG02.

**Objetivo:** Alinhar o provedor de autorização com a matriz funcional aprovada, sem implementar equipe/grupos.

**Aceite:**
- [x] Incorporar consulta, criação, remarcação, cancelamento e configuração exclusiva do titular sem mudar regras dos outros módulos.
- [x] Fechar decisão/revalidação por operação, vínculo e validade, incluindo negação explícita e expiração/revogação em sessão aberta.
- [x] Definir consulta de disponibilidade e resposta mínima da mutação para concessões isoladas, sem conceder GET de lista/detalhe por conveniência.

**Dependências:** nenhuma tarefa anterior; gate humano deste checklist continua obrigatório.

**Bloqueio/gate:** Revisão funcional concluída com a decisão explícita do solicitante sobre horários livres; implementação real do provedor permanece dependência de AG04/C0, não parte desta tarefa documental.

**Verificação e smoke (futuros):**
- Exercício de matriz: titular, equipe sem grupos, somente criação, concessão mais negação e permissão só de monitoramento; nenhum caso ganha consulta implícita.

**Evidência de AG02:** matriz incorporada em SPEC-autorizacao.md e alinhada a SPEC-agenda.md. Solicitante decidiu permitir somente horários livres por criação/remarcação, sem ocupantes ou detalhes. Resultado mínimo da mutação não exige consulta implícita. Revisão documental cobriu titular, equipe sem grupos, somente cadastro, concessão mais negação, remarcação concedida com cadastro negado, tenant errado e validade revogada/expirada. As regras anteriores permanecem. Nenhum teste do provedor foi executado; conclusão é documental.

**Arquivos previstos:**
- `SPEC-autorizacao.md`
- `SPEC-agenda.md`

**Escopo:** 2 arquivo(s) listado(s), 3 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 9, 11 de SPEC-agenda.md; fase P0 do plano.

### AG03 — Aprovar persistência e fronteiras técnicas

- [x] Concluir AG03.

**Objetivo:** Fechar esquema, protocolo e HTTP antes de migrations; registrar fontes oficiais das APIs escolhidas.

**Aceite:**
- [x] Definir linha própria estável, primeira criação concorrente, configuração/janelas, compromissos/participantes, identidade estável e marcador de estado; aprovar constraints, RLS e grants.
- [x] Enumerar escritores e contrato de lock/releitura/relógio pós-espera; fechar contexto interno e limitado reconhecido no servidor sem bypass RLS ou cliente como equipe.
- [x] Fechar payloads, erros/status e consulta temporal; fontes oficiais das versões fixadas sustentam locks, relógio, transações/RLS e interfaces utilizadas; ratificar caminhos previstos neste checklist.

**Dependências:** AG01, AG02.

**Evidência/gate:** Contrato técnico aprovado explicitamente pelo solicitante; schema, funções restritas, ABIs e HTTP ratificados. A implementação dos provedores e a prova de execução continuam em AG04/C0; nenhuma migration foi executada.

**Verificação e smoke (futuros):**
- Percorrer duas primeiras configurações simultâneas, disponibilidade que fica obsoleta, confirmação só com permissão de criar e referência cruzada de tenant; identificar onde cada recusa/serialização ocorre.

**Evidência de AG03:** [contrato técnico aprovado](../../SPEC-agenda.md#contrato-técnico-aprovado--ag01-e-ag03), com fontes oficiais PostgreSQL 18/Rails 8.1.4. Inclui representação restante de AG01 e funções SQL como fronteira autoritativa. Previsões de arquivos abaixo adaptadas; AG12 subdividida em AG12a/AG12b antes da execução. Nenhuma função stub, provedor ou rota foi implementado.

**Verificação documental exercitada:** links/âncoras locais e modelo matemático descartável de 15 cenários temporais, incluindo início único, futuro estrito sem grade, dois vizinhos, ocupação fora do recorte e término depois da última data consultada. Diferenças de 15/16 datas e conversão de 7 dias para 10.080 minutos conferidas. Isso verifica coerência do contrato, não DDL, grants, RLS, Rails/SQL ou autorização real; C0 permanece pendente.

**Arquivos previstos:**
- `SPEC-agenda.md`
- `tasks/agenda/plan.md`
- `SPEC-autorizacao.md`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 5, 8, 9, 10, 11 de SPEC-agenda.md; fase P0 do plano.

#### Checkpoint C0a — Contratos

- [x] AG01–AG03 revisadas e aprovadas; limites, catálogo, schema/grants, tempo e contexto limitado decididos. Este checkpoint documental não demonstra provedores entregues.
- [x] Evidências documentais e aprovação explícita registradas em AG01–AG03; provas reais continuam pendentes em AG04/C0.

### AG04 — Validar provedores e ambiente compartilhados

- [ ] Concluir AG04.

**Objetivo:** Registrar evidência dos pré-requisitos reais sem absorver sua implementação.

**Aceite:**
- [ ] Equipe/vínculo/validade e decisão por operação existem e são exercitáveis pelo provedor real, não por flags locais ou titular disfarçado.
- [ ] Base Next.js compartilhada entrega sessão/onboarding, proxy de mesma origem, componentes/tokens e scripts reais; registrar comandos reais e caminhos antes de liberar UI.
- [ ] Banco de teste separado, runtime/migrator segregados e ambiente protegido estão disponíveis; documentar evidências e manter ausências bloqueadas.

**Dependências:** AG03.

**Bloqueio/gate:** o backend de equipe, validade e política por operação foi implementado em `feature/identidade-equipe-autorizacao`; as ABIs `agenda_authorize` e `agenda_context_tenant`, o contexto limitado e o frontend compartilhado permanecem ausentes. A entrega da branch e a verificação específica das ABIs de agenda não são presumidas.

**Verificação e smoke (futuros):**
- Percorrer uma sessão de equipe válida e revogada no provedor e a base frontend real alcançando sessão da API; verificar roles/ambiente sem instalar ou executar containers por inferência.

**Inventário inicial de AG04:** a análise documental anterior não encontrou provedor de equipe/grupos nem frontend. Posteriormente, o backend de equipe/grupos foi implementado na branch citada e exercitado com roles segregadas; ver evidências no [README](../../README.md#identidade-de-equipe-e-grupos). Essa implementação não fornece, por si só, as ABIs nem o contexto limitado contratados pela agenda.

**Ambiente:** a implementação de identidade foi verificada em PostgreSQL e containers isolados não root, com roles segregadas; o ambiente foi descartado após o smoke. O fluxo OAuth Google real não foi exercitado. A disponibilidade futura do ambiente e a base frontend ainda precisam ser comprovadas para AG04.

**Desbloqueio exigido:** entrega e comprovação das ABIs/contexto contratado, base frontend e ambiente de teste; validar a integração do provedor de equipe/autorização com as ABIs da agenda. Não há tarefa de código elegível de P1–P4 enquanto isso faltar. Este inventário não reduz o aceite nem amplia agenda para implementar os provedores.

**Arquivos previstos:**
- `tasks/agenda/todo.md`

**Escopo:** 1 arquivo(s) listado(s), 1 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 9, 11 de SPEC-agenda.md; fase P0 do plano.

#### Checkpoint C0 — Pré-requisitos

- [ ] Contratos aprovados e provedores/ambiente reais comprovados em AG04. Enquanto faltar equipe/autorização, frontend ou limite humano, manter execução dependente bloqueada; nenhum atalho de titular/mocks.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

## P1

### AG05 — Persistir configuração e linha de sincronização

- [ ] Concluir AG05.

**Objetivo:** Criar o agregado mínimo de agenda/configuração/janelas aprovado em AG03.

**Aceite:**
- [ ] Unicidade por advogado/tenant e linha estável funcionam mesmo sem compromissos; configuração ausente difere de configuração com janelas vazias, sem defaults funcionais.
- [ ] DDL aprovada habilita/força RLS, integridade e grants restritos; runtime não recebe DML/SELECT direto nem privilégios indevidos em tenants/lawyers.
- [ ] Fixtures administrativas limitadas preparam duas agendas; runtime tem acesso direto recusado e não ganha acesso por tenant fabricado. Projeções funcionais de configuração serão provadas em AG07, não inventadas nesta etapa.

**Dependências:** AG04.

**Bloqueio/gate:** C0 aprovado; migration somente em banco de teste autorizado, por migrator.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_persistence_test.rb` — em `backend/`, após criação do arquivo previsto.
- No banco de teste autorizado, preparar fixtures administrativas e verificar integridade, políticas/grants e recusa de acesso direto do runtime. Ações funcionais runtime passam por funções em AG07; não usar migrator para executá-las ou alegar projeção ainda inexistente.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_create_agendas_and_agenda_windows.rb`
- `backend/test/integration/agenda_persistence_test.rb`

**Escopo:** 2 arquivos listados, 3 incluindo rastreio. Sem models ActiveRecord novos que só serviriam a DML direto vedado pelo contrato.
**Rastreio:** critérios 4, 6, 11 de SPEC-agenda.md; fase P1 do plano.

### AG06 — Validar configuração explícita

- [ ] Concluir AG06.

**Objetivo:** Implementar validação de entrada conforme contratos e máximos decididos, sem HTTP.

**Aceite:**
- [ ] Recusar campos/tipos inválidos, frações e valores fora dos limites; duração é positiva, intervalo/antecedência admitem zero.
- [ ] Validar janelas e interpretação temporal aprovadas, distinguindo ausência de configuração de lista explicitamente vazia.
- [ ] Retornar erros de domínio estruturados sem inserir defaults, normalizações que alterem regras ou persistência parcial.

**Dependências:** AG05.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/services/agenda_configuration_test.rb` — em `backend/`, após criação do arquivo previsto.
- Invocar validação com dados válidos, zeros permitidos, valores no limite e logo fora dele; observar dados aceitos e erros por campo.

**Arquivos previstos:**
- `backend/app/services/agenda_configuration.rb`
- `backend/test/services/agenda_configuration_test.rb`

**Escopo:** 2 arquivo(s) listado(s), 3 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 1, 2, 3, 4 de SPEC-agenda.md; fase P1 do plano.

#### Checkpoint C1a — Persistência e validação

- [ ] DDL/grants restritos e fronteiras de validação provados; a projeção funcional e seu isolamento serão exercitados via funções em AG07. Checkpoint interno, não entrega de API/UI.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG07 — Aplicar configuração integral sob lock

- [ ] Concluir AG07.

**Objetivo:** Estabelecer a fronteira comum de escrita com comportamento real de configuração, sem stubs de operações futuras.

**Aceite:**
- [ ] Criar/adquirir a linha estável pelo protocolo aprovado e substituir regras/janelas integralmente; erro preserva configuração anterior.
- [ ] Revalidar sessão/vínculo e exclusividade do titular na operação protegida; equipe não configura por ter permissões de compromissos.
- [ ] Toda escrita de configuração participa do mesmo lock e não modifica compromissos legados; primeira configuração concorrente não cria agendas duplicadas.

**Dependências:** AG06.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_configuration_persistence_test.rb` — em `backend/`, após criação do arquivo previsto.
- Salvar/reler configuração, tentar substituição inválida e duas primeiras configurações concorrentes; conferir unicidade, rollback integral e negação à equipe real.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_add_agenda_configuration_functions.rb`
- `backend/app/services/agenda_store.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/test/integration/agenda_configuration_persistence_test.rb`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 4, 8, 9, 11 de SPEC-agenda.md; fase P1 do plano.

### AG08 — Consultar disponibilidade pelo cálculo único

- [ ] Concluir AG08.

**Objetivo:** Implementar predicados temporais e consulta reutilizáveis pela confirmação.

**Aceite:**
- [ ] Aplicar janela integral, duração em tempo decorrido, s>t e s>=t+a, com limites consultáveis definidos em AG01.
- [ ] Aplicar uma única separação, aceitando intervalo zero e igualdade elegível, sem exigir buffer após o último atendimento até o fim da janela.
- [ ] Distinguir configuração ausente, configuração sem horários e falha; não criar grade, expediente ou fonte externa presumidos.

**Dependências:** AG06, AG07.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/services/agenda_availability_test.rb` — em `backend/`, após criação do arquivo previsto.
- Com instantes explícitos, verificar início/fim de janela, antecedência e intervalo zero/positivo. Até AG12 há apenas cálculo determinístico; desconto de ocupações persistidas será integrado e provado lá.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_add_agenda_availability_functions.rb`
- `backend/app/services/agenda_store.rb`
- `backend/app/services/agenda_availability.rb`
- `backend/test/services/agenda_availability_test.rb`

**Escopo:** 4 arquivos listados, 5 incluindo rastreio. Cálculo autoritativo SQL; Ruby apenas valida/parsa a fronteira e apresenta resultado, sem segunda regra de confirmação.
**Rastreio:** critérios 1, 2, 3, 4 de SPEC-agenda.md; fase P1 do plano.

#### Checkpoint C1b — Configuração e cálculo

- [ ] Escrita integral e cálculo temporal exercitados; ainda não alegar desconto de ocupações reais antes de AG12.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG09 — Expor configuração e disponibilidade na API

- [ ] Concluir AG09.

**Objetivo:** Fechar a fronteira HTTP sobre domínio real, mantendo autorização própria de cada ação.

**Aceite:**
- [ ] Salvar/reler configuração e consultar disponibilidade pelos contratos aprovados, com sessão, JSON, Origin/CSRF nas mutações, no-store e envelope existentes.
- [ ] Aplicar autorização de leitura/escrita no servidor; equipe não configura e IDs/tenant recebidos não ampliam acesso.
- [ ] Distinguir ausência de configuração, nenhum horário, entrada inválida, conflito/falha operacional e negação; disponibilidade não expõe ocupantes nem garante confirmação futura.

**Dependências:** AG08.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_configuration_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida: titular configura e consulta, erro conserva dados, equipe e outro tenant são recusados; inspecionar respostas sem simular sucesso de fornecedor.

**Arquivos previstos:**
- `backend/app/controllers/agenda_configurations_controller.rb`
- `backend/app/controllers/agenda_availabilities_controller.rb`
- `backend/config/routes.rb`
- `backend/test/integration/agenda_configuration_http_test.rb`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 4, 9, 11 de SPEC-agenda.md; fase P1 do plano.

### AG10 — Entregar configuração na interface compartilhada

- [ ] Concluir AG10.

**Objetivo:** Fechar a experiência P1 no navegador contra API real.

**Aceite:**
- [ ] Formulário sem defaults salva/rele config/janelas e consulta disponibilidade; fuso explícito e sucesso apenas após persistência.
- [ ] Distinguir carregamento, ausência de configuração, nenhum horário, falha e negação; preservar preenchimento após erro.
- [ ] Controles semânticos, foco/teclado e design system respeitados; provar titular e negação à equipe real, sem frontend paralelo.

**Dependências:** AG09.

**Bloqueio/gate:** Base frontend efetivamente entregue em AG04; ratificar layout e comandos reais antes de criar arquivos.

**Verificação e smoke (futuros):**
- Navegador real: salvar, recarregar, consultar, provocar erro e negação; observar DOM/rede/console e fuso. Não criar teste permanente de wiring ou texto incidental.

**Arquivos previstos:**
- `frontend/app/agenda/configuracao/page.tsx`
- `frontend/components/agenda/agenda-configuration-form.tsx`
- `frontend/components/agenda/agenda-availability.tsx`
- `frontend/lib/agenda-api.ts`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 4, 9, 11 de SPEC-agenda.md; fase P1 do plano.

#### Checkpoint C1 — Experiência de configuração

- [ ] API e navegador salvam/releem regras explícitas com fuso e negação à equipe; revisar antes de iniciar P2.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

## P2

### AG11 — Persistir compromissos e participantes

- [ ] Concluir AG11.

**Objetivo:** Adicionar ocupações com identidade estável, estado atual e integridade de tenant.

**Aceite:**
- [ ] Persistir início/término UTC, modalidade, situação e participantes conforme AG03; preservar duração confirmada.
- [ ] Constraints/FKs e RLS forçada protegem os registros; runtime não recebe acesso direto às tabelas. Provas de ações e projeções runtime ocorrem após as funções em AG12/AG14.
- [ ] Não gravar buffer antigo como autoridade da separação nem criar tabelas/credenciais/filas de fornecedores.

**Dependências:** AG10.

**Bloqueio/gate:** C1 completo, inclusive UI/equipe; migration sequencial e autorizada.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_persistence_test.rb` — em `backend/`, após criação do arquivo previsto.
- Preparar fixtures administrativas e conferir integridade/recusa de acesso direto entre agendas/participantes. A prova funcional de confirmação runtime segue em AG12, sem confundir preparação de fixture com execução da ação.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_create_appointments_and_appointment_participants.rb`
- `backend/test/integration/agenda_persistence_test.rb`

**Escopo:** 2 arquivos listados, 3 incluindo rastreio. Não criar models apenas para DML que o runtime não poderá executar.
**Rastreio:** critérios 1, 6, 10, 11 de SPEC-agenda.md; fase P2 do plano.

### AG12 — Confirmar compromisso pelo domínio único

- [ ] Concluir AG12.

**Objetivo:** Conectar regras temporais e ocupações reais na mesma transação protegida usada pela configuração.

**Aceite:**
- [ ] Sob lock, revalidar contexto/permissão, reler configuração e ocupações e obter tempo autoritativo pós-espera; calcular término e recusar override.
- [ ] Validar janela, duração, antecedência e separação vigente; compromisso/participantes persistem integralmente ou não persistem.
- [ ] Entradas interna e limitada do contrato aprovado usam as mesmas regras sem rede ou cliente como equipe; disponibilidade desconta ocupações reais.

**Dependências:** AG12b. As subfatias dependem de AG11 e formam o trabalho real desta agregadora.

**Bloqueio/gate:** Contexto limitado e resposta da ação fechados em AG03; não usar bypass RLS nem tenant recebido.

**Verificação e smoke (futuros):**
- Concluir as provas reais de AG12a/AG12b abaixo; somente então marcar a agregadora AG12. Não há uma terceira implementação nem teste de forwarding para completar este pai.

**Arquivos previstos:**
- `tasks/agenda/todo.md`

**Escopo:** agregação documental de AG12a/AG12b; um arquivo de rastreio, sem fatia adicional de código. Os arquivos executáveis são enumerados separadamente nas folhas.
**Rastreio:** critérios 1, 2, 3, 5, 11 de SPEC-agenda.md; fase P2 do plano.

#### AG12a — Funções autoritativas de confirmação e ocupação

- [ ] Concluir AG12a.

**Objetivo:** Implementar confirmação no PostgreSQL e integrar ocupações persistidas ao cálculo único da disponibilidade.

**Aceite:**
- [ ] Funções estreitas autorizam contexto interno/limitado real, adquirem lock da agenda, revalidam configuração/relógio pós-espera e confirmam compromisso/participantes integralmente.
- [ ] Cálculo SQL compartilhado desconta ocupações reais, usa intervalo vigente e rejeita duração/término divergentes; runtime não tem caminho alternativo de DML.
- [ ] Conflito/negação/erro conserva estado anterior, sem dados parciais ou vazamento de ocupantes; confirmação online não promete sala/provedor externo.

**Dependências:** AG11.
**Bloqueio/gate:** C0 completo e ABIs reais; não criar função stub ou contexto fictício para testar.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/appointment_confirmation_persistence_test.rb` — em `backend/`, após criação.
- Invocar entradas SQL concedidas com runtime real e parâmetros bindados sob contextos válidos distintos; confirmar, reler disponibilidade autorizada e provocar recusa. Preparação administrativa não executa a ação em teste.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_add_appointment_confirmation_functions.rb`
- `backend/test/integration/appointment_confirmation_persistence_test.rb`

**Escopo:** 2 arquivos listados, 3 incluindo rastreio.
**Rastreio:** critérios 1, 2, 3, 5 e 11; subfatia de AG12/P2.

#### AG12b — Consumidores Ruby da confirmação real

- [ ] Concluir AG12b.

**Objetivo:** Conectar os consumidores do domínio à confirmação e à disponibilidade SQL reais, sem duplicar a autoridade temporal.

**Aceite:**
- [ ] Gateway permite somente entradas fixas e parametrizadas; operações/cálculo Ruby não confirmam por lógica alternativa nem aceitam função, tenant ou permissão arbitrários do request.
- [ ] Consumidores interno e limitado seguem as mesmas regras/contextos reais, distinguindo validação, conflito e falha operacional sem gravar parcialmente.
- [ ] Retorno mínimo e indicação de estado atual correspondem ao commit; não exigir consulta ampla nem alegar links ou fornecedores implementados.

**Dependências:** AG12a.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/services/appointment_confirmation_test.rb` — em `backend/`, após criação.
- Exercitar consumidores contra PostgreSQL real: confirmação válida, duração divergente, conflito e contexto recusado; verificar ocupação/resultados persistidos, não argumentos repassados ou ecos de mocks. Regras de corrida continuam em AG13.

**Arquivos previstos:**
- `backend/app/services/agenda_store.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/app/services/agenda_availability.rb`
- `backend/test/services/appointment_confirmation_test.rb`

**Escopo:** 4 arquivos listados, 5 incluindo rastreio.
**Rastreio:** critérios 1, 2, 3, 5 e 11; subfatia de AG12/P2.


### AG13 — Provar concorrência e relógio pós-espera

- [ ] Concluir AG13.

**Objetivo:** Antecipar a prova de maior risco com conexões independentes no PostgreSQL real.

**Aceite:**
- [ ] Duas confirmações incompatíveis em agenda vazia, inclusive canais distintos, deixam uma confirmação, conflito de domínio e só a ocupação vencedora commitada.
- [ ] Reter lock de A e observar B concluir antes de liberar A, provando independência de agendas, não apenas término eventual de dois pedidos.
- [ ] Pedido elegível antes da espera, mas inelegível ao obter lock, é recusado; timeout/erro de lock permanece falha operacional distinta.

**Dependências:** AG12.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_concurrency_test.rb` — em `backend/`, após criação do arquivo previsto.
- Executar corrida coordenada com filas/barreiras, dados commitados, contexto por conexão, cleanup e falhas propagadas. Provar limites do relógio pelo mecanismo determinístico aprovado, sem tempo do cliente nem sleeps como oráculo.

**Arquivos previstos:**
- `backend/test/integration/agenda_concurrency_test.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/app/services/agenda_availability.rb`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 3, 5, 6 de SPEC-agenda.md; fase P2 do plano.

#### Checkpoint C2a — Ocupação e concorrência

- [ ] Persistência de compromissos, confirmação real e corrida sob lock provadas antes de ampliar HTTP/UI. Não declarar C2 completo.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG14 — Expor criação e consulta autorizadas

- [ ] Concluir AG14.

**Objetivo:** Implementar HTTP de confirmação, lista e detalhe sobre estado persistido e concessões independentes.

**Aceite:**
- [ ] Criar/listar/detalhar pelo contrato aprovado, com sessão/CSRF e envelope reais; mapear validação, conflito, ausência e falha operacional distintamente.
- [ ] Listas/detalhes respeitam tenant e consulta; criação só devolve resultado autorizado, sem exigir GET ou conceder leitura por inferência.
- [ ] Revalidar concessão/validade no ponto protegido; disponibilidade real não oferece ocupação recém-confirmada e nenhum sucesso local promete fornecedores.

**Dependências:** AG13.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/appointments_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida: criar presencial/online, consultar com permissão, provocar conflito/override/ID alheio; equipe com somente criação conclui a ação sem baixar lista/detalhe.

**Arquivos previstos:**
- `backend/app/controllers/appointments_controller.rb`
- `backend/app/controllers/agenda_availabilities_controller.rb`
- `backend/config/routes.rb`
- `backend/test/integration/appointments_http_test.rb`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 1, 2, 3, 5, 9, 11 de SPEC-agenda.md; fase P2 do plano.

### AG15 — Entregar lista e detalhe na interface

- [ ] Concluir AG15.

**Objetivo:** Mostrar somente compromissos autorizados, sem inventar eventos ou disponibilidade.

**Aceite:**
- [ ] Lista/detalhe apresentam início, término, fuso, modalidade, participantes e situação local reais.
- [ ] Carregamento, vazio, falha e negação são distintos; dado protegido não chega ao browser para só então ser ocultado.
- [ ] Controles semânticos, navegação real e foco seguem design system; leitura depende da concessão própria.

**Dependências:** AG14.

**Verificação e smoke (futuros):**
- Navegador real com titular/equipe autorizada e sessão negada; abrir lista e detalhe, recarregar e adulterar referência de outro tenant, observando DOM/rede/console.

**Arquivos previstos:**
- `frontend/app/agenda/page.tsx`
- `frontend/app/agenda/compromissos/[id]/page.tsx`
- `frontend/components/agenda/appointment-list.tsx`
- `frontend/lib/agenda-api.ts`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 6, 9, 11 de SPEC-agenda.md; fase P2 do plano.

### AG16 — Entregar agendamento na interface

- [ ] Concluir AG16.

**Objetivo:** Fechar criação real, inclusive quando o operador não pode consultar lista/detalhe.

**Aceite:**
- [ ] Oferecer início elegível, modalidade e participantes pelo contrato; duração não editável por compromisso e fuso explícito.
- [ ] Revalidar pela API ao confirmar; conflito/validação preservam dados e sucesso só aparece após persistência.
- [ ] Concessão somente de criação permite concluir pelo resultado mínimo autorizado, sem preflight GET protegido ou promessa de Jitsi/Google/e-mail.

**Dependências:** AG15.

**Verificação e smoke (futuros):**
- Criar e reler com sessão autorizada; em outra sessão ocupar horário já exibido e observar recusa; operador somente-criação confirma sem consulta. Usar API e navegador reais.

**Arquivos previstos:**
- `frontend/app/agenda/novo/page.tsx`
- `frontend/components/agenda/appointment-form.tsx`
- `frontend/lib/agenda-api.ts`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 1, 2, 3, 5, 9, 10 de SPEC-agenda.md; fase P2 do plano.

#### Checkpoint C2 — Experiência de agendamento

- [ ] Lista/detalhe/criação reais no navegador, concessões independentes e limites temporais corretos; revisar antes de transições.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

## P3

### AG17 — Remarcar atomicamente no domínio

- [ ] Concluir AG17.

**Objetivo:** Adicionar mudança indivisível de origem/destino ao protocolo comum.

**Aceite:**
- [ ] Sob lock, revalidar permissão, estado futuro, configuração vigente e tempo pós-espera; validar destino sem override de duração.
- [ ] Recusa por conflito/antecedência/autorização ou rollback conserva início/término e ocupação original; sucesso troca ocupação sem liberação intermediária.
- [ ] Preservar referência estável, atualizar indicação de estado atual e não depender de fornecedor nem permitir gestão retroativa.

**Dependências:** AG16.

**Bloqueio/gate:** C2 completo antes de iniciar próxima experiência vertical.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/services/appointment_rescheduling_test.rb` — em `backend/`, após criação do arquivo previsto.
- Invocar domínio com destino ocupado, fora de janela, abaixo da antecedência e válido; conferir origem intacta nas recusas e destino persistido no sucesso.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_add_appointment_rescheduling_function.rb`
- `backend/app/services/agenda_store.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/test/services/appointment_rescheduling_test.rb`

**Escopo:** 4 arquivos listados, 5 incluindo rastreio. Função SQL executa a transição; Ruby não mantém implementação concorrente da regra.
**Rastreio:** critérios 1, 2, 3, 7, 8, 9 de SPEC-agenda.md; fase P3 do plano.

### AG18 — Expor remarcação autorizada

- [ ] Concluir AG18.

**Objetivo:** Conectar contrato HTTP de remarcação à operação real, sem ampliação de acesso.

**Aceite:**
- [ ] Usar concessão própria, sessão, JSON, Origin/CSRF e no-store; repetir contexto/validade na operação protegida.
- [ ] Distinguir recusa de domínio/falha operacional e devolver somente resultado autorizado, sem GET de detalhe obrigatório.
- [ ] Identificador alheio, apenas permissão de criar ou contexto inválido não alteram compromisso ou ocupação.

**Dependências:** AG17.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/appointment_rescheduling_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida: remarcar para destino ocupado e comprovar origem, depois para destino válido; repetir com equipe sem concessão e tenant adulterado, sem alteração.

**Arquivos previstos:**
- `backend/app/controllers/appointments_controller.rb`
- `backend/config/routes.rb`
- `backend/test/integration/appointment_rescheduling_http_test.rb`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 7, 9, 11 de SPEC-agenda.md; fase P3 do plano.

### AG19 — Entregar remarcação na interface

- [ ] Concluir AG19.

**Objetivo:** Fechar esta transição no navegador antes de começar cancelamento.

**Aceite:**
- [ ] Operador com concessão própria opera referência conhecida pelo contrato, sem adquirir consulta implicitamente.
- [ ] Destino recusado mantém preenchimento e estado local original; sucesso só apresenta mudança persistida e fuso correto.
- [ ] Labels, teclado, foco e estados seguem base visual; nenhuma resposta local é apresentada como sala/publicação/envio concluídos.

**Dependências:** AG18.

**Verificação e smoke (futuros):**
- Navegador real: destino ocupado conserva formulário/origem, destino válido altera compromisso; inspecionar rede inclusive sem concessão de consulta.

**Arquivos previstos:**
- `frontend/app/agenda/remarcar/page.tsx`
- `frontend/components/agenda/appointment-reschedule-form.tsx`
- `frontend/lib/agenda-api.ts`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 7, 9, 10 de SPEC-agenda.md; fase P3 do plano.

#### Checkpoint C3a — Remarcação

- [ ] Domínio, API e navegador conservam origem nas recusas e trocam ocupação no sucesso; fechar a experiência antes do cancelamento.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG20 — Cancelar e liberar ocupação no domínio

- [ ] Concluir AG20.

**Objetivo:** Adicionar cancelamento futuro à fronteira comum de escrita.

**Aceite:**
- [ ] Permissão própria e contexto vigentes são exigidos sob lock; antes do início cancelar é permitido mesmo dentro da antecedência de novas reservas.
- [ ] Commit cancela e libera ocupação/separação associada; falha não libera parcialmente nem permite gestão retroativa.
- [ ] Nova confirmação elegível pode ocupar a vaga; ausência/falha externa não impede cancelamento nem reativa o compromisso.

**Dependências:** AG19.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/services/appointment_cancellation_test.rb` — em `backend/`, após criação do arquivo previsto.
- Cancelar compromisso futuro dentro da antecedência para provar regra distinta; em outro caso ainda elegível para nova reserva, cancelar e confirmar novamente a vaga. Conferir estado persistido.

**Arquivos previstos:**
- `backend/db/migrate/<timestamp>_add_appointment_cancellation_function.rb`
- `backend/app/services/agenda_store.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/test/services/appointment_cancellation_test.rb`

**Escopo:** 4 arquivos listados, 5 incluindo rastreio. Cancelamento é uma transição SQL protegida, não DML direto do runtime.
**Rastreio:** critérios 7, 9, 10 de SPEC-agenda.md; fase P3 do plano.

### AG21 — Expor cancelamento autorizado

- [ ] Concluir AG21.

**Objetivo:** Conectar cancelamento HTTP sem usar concessão de criar/remarcar como substituta.

**Aceite:**
- [ ] Usar sessão, JSON, Origin/CSRF, no-store e resultado mínimo aprovado da ação.
- [ ] Negação, validade expirada/revogada, compromisso alheio ou início já ocorrido não produzem liberação parcial.
- [ ] Sucesso reflete estado cancelado persistido sem depender de integração externa; falha mantém verdade anterior.

**Dependências:** AG20.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/appointment_cancellation_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida cancela antes do início, inclusive dentro da antecedência; equipe sem concessão/tenant alheio é recusado. Reconsultar com sessão autorizada e tentar nova reserva elegível.

**Arquivos previstos:**
- `backend/app/controllers/appointments_controller.rb`
- `backend/config/routes.rb`
- `backend/test/integration/appointment_cancellation_http_test.rb`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 7, 9, 10, 11 de SPEC-agenda.md; fase P3 do plano.

### AG22 — Entregar cancelamento na interface

- [ ] Concluir AG22.

**Objetivo:** Fechar a experiência de cancelamento com resultado local inequívoco.

**Aceite:**
- [ ] Concessão própria permite cancelar referência conhecida sem exigir consulta indevida; não ampliar direitos por UI.
- [ ] Processamento, erro e sucesso correspondem à resposta real; não remover compromisso só por otimismo nem alegar comunicação enviada.
- [ ] Ação é operável por teclado com nome/foco/estado acessíveis; recusa preserva estado anterior verdadeiro.

**Dependências:** AG21.

**Verificação e smoke (futuros):**
- Navegador real: cancelar, reler com permissão e confirmar vaga ainda elegível; outra sessão sem concessão não recebe sucesso nem dados negados na rede.

**Arquivos previstos:**
- `frontend/app/agenda/cancelar/page.tsx`
- `frontend/components/agenda/appointment-cancel-form.tsx`
- `frontend/lib/agenda-api.ts`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 7, 9, 10 de SPEC-agenda.md; fase P3 do plano.

#### Checkpoint C3b — Cancelamento

- [ ] Domínio, API e navegador cancelam e liberam ocupação sem antecedência de reserva; vaga liberada só é reutilizada se ainda elegível.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG23 — Provar configuração concorrente e compromissos legados

- [ ] Concluir AG23.

**Objetivo:** Consolidar mudanças de regras sob disputa com confirmação/remarcação.

**Aceite:**
- [ ] Mudar duração/intervalo/janelas preserva instantes e situação de compromissos existentes, mesmo incompatíveis com nova configuração.
- [ ] Forçar ambos os ordenamentos configuração/confirmação e configuração/remarcação; resultados usam uma configuração integral, nunca campos híbridos.
- [ ] Antecedência é reavaliada após espera também na remarcação; recusa conserva origem e ocupação.

**Dependências:** AG22.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_configuration_concurrency_test.rb` — em `backend/`, após criação do arquivo previsto.
- `RAILS_ENV=test ruby bin/rails test test/services/agenda_configuration_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida cria compromisso, altera regras e relê legado intacto; cria/remarca outro com regras novas. Testes coordenados verificam os ordenamentos e commits com relógio de teste aprovado.

**Arquivos previstos:**
- `backend/test/integration/agenda_configuration_concurrency_test.rb`
- `backend/test/services/agenda_configuration_test.rb`
- `backend/app/services/agenda_operations.rb`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 3, 8 de SPEC-agenda.md; fase P3 do plano.

### AG24 — Provar disputas entre transições

- [ ] Concluir AG24.

**Objetivo:** Demonstrar serialização válida entre operações reais, sem estados parciais.

**Aceite:**
- [ ] Criação/remarcação e remarcações de compromissos distintos ao mesmo destino deixam uma ocupação vencedora e preservam origem da remarcação recusada.
- [ ] Remarcação/cancelamento do mesmo compromisso só admitem resultados serializados válidos, sem ressurreição ou ocupação residual; não exigir um único sucesso quando dois sucessos sequenciais são legítimos.
- [ ] Conexões/contextos independentes, barreiras, cleanup e propagação de falhas permitem observar commits; timeout genérico não é conflito de domínio aprovado.

**Dependências:** AG23.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/appointment_transition_concurrency_test.rb` — em `backend/`, após criação do arquivo previsto.
- Executar os interleavings coordenados com PostgreSQL runtime real, conferir respostas e ocupações finais; API smoke repete origem ocupada e liberação elegível sem transação compartilhada de testes.

**Arquivos previstos:**
- `backend/test/integration/appointment_transition_concurrency_test.rb`
- `backend/app/services/agenda_operations.rb`
- `backend/app/services/agenda_availability.rb`

**Escopo:** 3 arquivo(s) listado(s), 4 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 5, 7 de SPEC-agenda.md; fase P3 do plano.

#### Checkpoint C3 — Transições e configuração

- [ ] Corridas adicionais e legados provados sem configuração híbrida, ocupação residual ou ressurreição; revisar antes do aceite consolidado.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

## P4

### AG25 — Consolidar acesso real e isolamento de contexto

- [ ] Concluir AG25.

**Objetivo:** Reunir prova da matriz e de dois tenants, sem postergar proteções já exigidas em cada fatia.

**Aceite:**
- [ ] Grupos reais, concessões isoladas e negação explícita seguem catálogo; sem grupos/monitoramento não autorizam agenda e equipe nunca configura.
- [ ] Expiração/revogação após contexto inicial ou espera bloqueia ação protegida; IDs/referências cruzados, ausência de contexto e tenant adulterado não leem/alteram dados.
- [ ] Role sem ownership/bypass e RLS forçada protegem novas tabelas; pool/savepoints após sucesso/erro/conflito não vazam contexto/cache entre A/B/sem contexto.

**Dependências:** AG24.

**Verificação e smoke (futuros):**
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_authorization_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_tenant_isolation_test.rb` — em `backend/`, após criação do arquivo previsto.
- `RAILS_ENV=test ruby bin/rails test test/integration/agenda_isolation_http_test.rb` — em `backend/`, após criação do arquivo previsto.
- `RAILS_ENV=test ruby bin/rails test test/integration/database_context_test.rb` — em `backend/`, após criação do arquivo previsto.
- API servida com equipe real: conceder só criação, tentar demais ações, acrescentar negação e revogar/expirar em sessão aberta. Em duas agendas, adulterar IDs e alternar a conexão após rollback; não fabricar equipe em fixture.

**Arquivos previstos:**
- `backend/test/integration/agenda_authorization_http_test.rb`
- `backend/test/integration/agenda_tenant_isolation_test.rb`
- `backend/test/integration/agenda_isolation_http_test.rb`
- `backend/test/integration/database_context_test.rb`

**Escopo:** 4 arquivo(s) listado(s), 5 incluindo rastreio; pequeno/médio conforme a fatia.
**Rastreio:** critérios 6, 9, 11 de SPEC-agenda.md; fase P4 do plano.

### AG26 — Provar verdade local perante consumidores

- [ ] Concluir AG26.

**Objetivo:** Exercitar fronteiras reais fornecidas pela agenda sem construir integrações fake.

**Aceite:**
- [ ] Após confirmação commitada, interrupção/falha de consumidor isolado não libera ocupação; outra confirmação incompatível continua recusada.
- [ ] Captura antiga de referência/estado é distinguível do estado atual após remarcação/cancelamento; cancelado não é reativado por retorno externo.
- [ ] UI afirma apenas estado local e consumidor limitado não lê ocupantes nem escolhe tenant; não criar writeback/callback ou provedor fake para sustentar a prova.

**Dependências:** AG25.

**Verificação e smoke (futuros):**
- Smoke descartável contra domínio/API reais: confirmar e parar consumidor após commit; tentar conflito; capturar estado, remarcar/cancelar e reler estado atual. Sem canal de writeback aprovado, não inventá-lo nem criar teste de wiring; registrar limite de que links/Calendar/Jitsi/e-mail não foram exercitados.

**Arquivos previstos:**
- `tasks/agenda/todo.md`

**Escopo:** 1 arquivo(s) listado(s), 1 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 5, 7, 10, 11 de SPEC-agenda.md; fase P4 do plano.

### AG27 — Validar configuração e consulta acessíveis

- [ ] Concluir AG27.

**Objetivo:** Consolidar inspeção real das superfícies de leitura já implementadas, sem criar toda a UI no final.

**Aceite:**
- [ ] Configuração ausente, configurada sem horários, lista vazia, carregamento, falha e negação têm estados distintos; nenhum dado negado chega ao DOM/rede.
- [ ] Horários/fuso, modalidade, participantes e situação correspondem à API; recarregar preserva a verdade persistida.
- [ ] Em 320/768/1024/1440px e texto a 200%, teclado/foco, labels, reflow e contraste seguem design system monocromático de cantos retos.

**Dependências:** AG26.

**Verificação e smoke (futuros):**
- Navegador real contra API: percorrer configuração/lista/detalhe nos estados autorizados e restritos; inspecionar DOM/rede/console e superfícies nas larguras/zoom previstos, sem snapshots de texto incidental.

**Arquivos previstos:**
- `tasks/agenda/todo.md`

**Escopo:** 1 arquivo(s) listado(s), 1 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 4, 6, 9, 11 de SPEC-agenda.md; fase P4 do plano.

#### Checkpoint C4a — Acesso, consumidores e leitura

- [ ] Matriz, isolamento/pool, verdade local e superfícies de leitura exercitados; não substituir OAuth/provedores reais por alegações.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

### AG28 — Validar interação acessível das mutações

- [ ] Concluir AG28.

**Objetivo:** Consolidar prova no navegador de ações já fechadas nas fatias anteriores.

**Aceite:**
- [ ] Criação, conflito, remarcação e cancelamento correspondem à API real; falha conserva preenchimento e sucesso só ocorre após persistência.
- [ ] Ações funcionam com concessões isoladas, sem GET protegido implícito; foco, teclado e anúncio de estado são verificáveis nas larguras/zoom do plano.
- [ ] Nenhum sucesso local promete sala criada, evento publicado ou e-mail entregue; console/rede não revelam erro ou dado protegido ocultado apenas visualmente.

**Dependências:** AG27.

**Verificação e smoke (futuros):**
- No navegador real, executar criar → conflito → remarcar para ocupado → remarcar validamente → cancelar → nova confirmação ainda elegível; conferir persistência e restrições de permissão.

**Arquivos previstos:**
- `tasks/agenda/todo.md`

**Escopo:** 1 arquivo(s) listado(s), 1 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 1, 2, 3, 7, 9, 10 de SPEC-agenda.md; fase P4 do plano.

### AG29 — Executar aceite integrado e submeter conclusão

- [ ] Concluir AG29.

**Objetivo:** Fechar evidências da agenda integral, sem confundir testes com smoke ou autorizar deploy.

**Aceite:**
- [ ] Os 11 critérios possuem evidência exercitada e rastreada; suíte existente sem regressão e build aprovado executado; não dispensar UI/equipe reais.
- [ ] Smoke HTTP e navegador cobrem duas agendas, configuração, criação, conflito, transições, validade e acesso; distinguir sessões preparadas de OAuth Google real.
- [ ] Atualizar documentação do estado implementado e resultados sem segredos; submeter revisão humana antes de integração/deploy e não liberar outros módulos.

**Dependências:** AG28.

**Verificação e smoke (futuros):**
- Executar uma vez suíte completa e build autorizados após provas focadas, depois o cenário real integrado; registrar comandos/resultados/limitações e revisão humana. Ausência de provedor ou frontend mantém C4 pendente, não encerra por plausibilidade.

**Arquivos previstos:**
- `README.md`
- `tasks/agenda/todo.md`

**Escopo:** 2 arquivo(s) listado(s), 2 incluindo rastreio; documental/verificação.
**Rastreio:** critérios 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 de SPEC-agenda.md; fase P4 do plano.

#### Checkpoint C4 — Aceite final

- [ ] 11 critérios, suíte, build e smokes reais documentados. Obter revisão humana final; não liberar deploy nem outros módulos por inferência.
- [ ] Registrar evidências exercitadas e impedimentos; não marcar o gate por plausibilidade.

## Cobertura dos critérios da especificação

| Critério | Tarefas de prova |
|---|---|
| 1 | AG01, AG06, AG08, AG11, AG12, AG14, AG16, AG17, AG28; AG29 consolida o aceite |
| 2 | AG01, AG06, AG08, AG12, AG14, AG16, AG17, AG28; AG29 consolida o aceite |
| 3 | AG01, AG06, AG08, AG12, AG13, AG14, AG16, AG17, AG23, AG28; AG29 consolida o aceite |
| 4 | AG01, AG05, AG06, AG07, AG08, AG09, AG10, AG27; AG29 consolida o aceite |
| 5 | AG03, AG12, AG13, AG14, AG16, AG24, AG26; AG29 consolida o aceite |
| 6 | AG05, AG11, AG13, AG15, AG25, AG27; AG29 consolida o aceite |
| 7 | AG17, AG18, AG19, AG20, AG21, AG22, AG24, AG26, AG28; AG29 consolida o aceite |
| 8 | AG03, AG07, AG17, AG23; AG29 consolida o aceite |
| 9 | AG02, AG03, AG04, AG07, AG09, AG10, AG14, AG15, AG16, AG17, AG18, AG19, AG20, AG21, AG22, AG25, AG27, AG28; AG29 consolida o aceite |
| 10 | AG03, AG11, AG16, AG19, AG20, AG21, AG22, AG26, AG28; AG29 consolida o aceite |
| 11 | AG02, AG03, AG04, AG05, AG07, AG09, AG10, AG11, AG12, AG14, AG15, AG18, AG21, AG25, AG26, AG27; AG29 consolida o aceite |

## Estado para a próxima etapa

Checklist e contrato aprovados; AG01–AG03 concluídas documentalmente e C0a registrado. AG12 subdividida em AG12a/AG12b sem renomear os 29 IDs principais. AG04 bloqueada: provedores de equipe/autorização/ABIs e frontend ausentes no inventário; banco/ambiente runtime ainda sem comprovação. Nenhuma implementação iniciada. C0 e P1–P4 não estão liberados; não substituir dependências por mocks nem enfraquecer critérios.

Este checklist não aprova especificações, planos ou implementação dos outros quatro módulos da iniciativa. Aceite de agenda não é aceite de reserva por link, videochamada, sincronização Calendar ou entrega de e-mails.
