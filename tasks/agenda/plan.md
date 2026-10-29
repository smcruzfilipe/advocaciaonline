# Plano de implementação: agenda

**Estado:** aprovado pelo solicitante, incluindo ordem das fatias, lock transacional por agenda e contrato técnico de schema, ABIs, HTTP e funções restritas ratificado em AG03. **Módulo:** `agenda`. Base: [SPEC-agenda.md](../../SPEC-agenda.md) e [mapa](../../CAPABILITIES.md#agenda-e-atendimento-online). AG01–AG03 concluídas documentalmente; AG04/C0 permanece bloqueio de entrega real dos provedores e ambiente.

**Destino autorizado:** este plano e [checklist](todo.md), ambos aprovados. Selecionar explicitamente `tasks/agenda/plan.md` e `tasks/agenda/todo.md`, preservando os defaults ocupados por monitoramento jurídico. A aprovação dos contratos não substitui AG04/C0; nenhuma implementação de agenda foi iniciada.

## Objetivo e limites

Implementar a agenda do advogado com configuração explícita, consulta, confirmação sem sobreposição, remarcação atômica e cancelamento. As regras de duração única, intervalo e antecedência são iguais para operações internas e confirmações solicitadas pelo consumidor externo. Entregar interface real para advogado/equipe autorizada, além dos contratos da API/domínio; backend isolado não encerra o aceite integral.

Não implementar aqui links de cliente, sala Jitsi, Google Calendar, e-mails, lembretes, recorrência, catálogo de serviços, administração genérica de equipe/grupos ou um frontend compartilhado alternativo. Esses componentes possuem capacidades ou pré-requisitos próprios. Compromisso online na agenda é modalidade de ocupação local, não prova de sala criada.

## Base existente e dependências externas

| Área | Evidência atual | Consequência para o plano |
|---|---|---|
| Rails e persistência | `backend/app/`, `backend/config/routes.rb`, `backend/db/`; Ruby 4.0.9, Rails 8.1.4, PostgreSQL/RLS | Reutilizar stack, contexto e padrões; agenda ainda não tem implementação |
| Sessão e contexto | `ApplicationController`, `IdentityStore`, `DatabaseContext.with_session` | Reutilizar cookie, Origin/CSRF, no-store e resolução de tenant por sessão; não substituir por tenant recebido |
| Equipe e autorização | Provedor real de equipe/grupos ainda ausente; catálogo de agenda incorporado documentalmente por AG02 | Dependência externa de vínculo/validade e decisão por operação; RLS não substitui permissão |
| Frontend | `frontend/` ainda previsto; arquitetura define Next.js/TypeScript/App Router e proxy de mesma origem | Dependência externa de base compartilhada, sessão/onboarding, proxy e ferramentas reais; manter aceites visuais, sem inventar comandos npm |
| Testes | Rails/Minitest, integração HTTP e PostgreSQL com roles separadas; precedente de corrida em `session_validity_test.rb` | Reutilizar testes de fronteira, contexto, RLS e conexões independentes |
| Limites operacionais | Solicitante decidiu máximos de duração 120 minutos, intervalo 60 minutos, antecedência 10.080 minutos e consulta 15 dias por requisição | Sem defaults; precisão/representação das janelas e consulta ainda exigem ratificação no contrato técnico AG01/AG03 |

Dependências externas conservam seus próprios donos e gates. A referência às tarefas 5–6 do [plano de monitoramento](../plan.md) identifica trabalho de equipe/autorização já previsto; não o move, conclui ou replaneja. A base frontend também precisa de entrega compartilhada autorizada, não de um atalho exclusivo para agenda.

O login Google de identidade exige configuração OAuth externa para prova real. Ele é distinto da integração Google Calendar, que não bloqueia ocupação local. Sessões preparadas para smoke permitem exercitar agenda, mas não comprovam login Google real.

## Decisões técnicas aprovadas no plano

### Domínio e persistência

- Um agregado de agenda por advogado/tenant contém configuração explícita, janelas e compromissos. Configuração ausente e agenda sem disponibilidade são situações distintas. O mecanismo de exclusão mútua precisa existir mesmo antes do primeiro compromisso.
- Manter instantes absolutos em UTC; interpretar janelas e apresentar horários em `America/Sao_Paulo`. Duração, intervalo e antecedência em minutos inteiros conforme spec. Não usar fuso do navegador como autoridade.
- Preservar início/término dos compromissos confirmados ao alterar configuração. Novas confirmações e remarcações usam uma configuração vigente integral. Aumentar intervalo não obriga a reescrever ocupações históricas nem a cancelar compromissos legados.
- Referências de compromisso e participantes devem impedir associação cruzada de tenant. Novas tabelas seguem RLS habilitada/forçada, `USING` e `WITH CHECK`, constraints e privilégios mínimos. Migration usa a role separada; runtime nunca recebe propriedade ou bypass de RLS.
- Fornecer identidade estável e indicação de estado atual do compromisso aos consumidores. Não criar filas, processos, tabelas de entrega externa ou armazenamento de credenciais Calendar dentro da agenda.

### Exclusão mútua e transições

**Escolha aprovada:** lock transacional em uma linha estável própria da agenda, uma por advogado, obtido por todas as mutações de configuração/ocupação. Após adquirir o lock, reler configuração e ocupações e obter o instante autoritativo do servidor para validar antecedência. Não usar relógio capturado antes de uma espera pelo lock nem relógio de início de transação como prova de que a antecedência ainda vale.

Confirmar, remarcar, cancelar e configurar compartilham o mesmo protocolo de escrita e ordem de aquisição. Não bloquear linha de `tenants`/`lawyers` por suposição: o runtime atual não tem automaticamente todos os privilégios necessários para isso. A linha própria da agenda e seus grants precisam ser definidos e aprovados no contrato de persistência.

O lock é cooperativo: comprovar que todos os escritores autorizados passam pela mesma fronteira; revisar grants e acessos diretos, sem deixar outro caminho de mutação que ignore a regra. Se não for possível garantir essa participação, rever o mecanismo antes de implementar, preservando o contrato funcional. Não usar mutex de processo Ruby nem apenas bloquear compromissos existentes, pois uma agenda vazia não contém linha de ocupação para bloquear.

Não adotar inicialmente exclusão GiST com buffer gravado no compromisso: um intervalo antigo persistido pode divergir da regra vigente, e reescrevê-lo pode rejeitar mudanças que devem preservar compromissos legados. A alternativa também pode exigir extensão/opclass e permissões não comprovadas. Só reconsiderá-la se demonstrar equivalência com a spec e aprovar suas dependências.

Remarcação altera ocupação de origem/destino na mesma transação; erro conserva origem. Cancelamento libera ocupação local sem esperar fornecedor. Nenhuma chamada de rede participa da transação de reserva. Tratar timeout/erro de lock como falha operacional, não como confirmação nem prova de conflito de domínio bem tratado.

### HTTP, autorização e apresentação

- Reutilizar envelope `{ error: { code, message, details } }`, autenticação, validação de JSON, Origin/CSRF e no-store. Mapear conflito, validação, ausência de recurso e falha operacional de forma coerente com os controllers existentes; contrato exato será fechado no gate técnico.
- A autorização deve preceder consulta/mutação e ser revalidada na operação protegida; não depender apenas do contexto memoizado do controller. Equipe usa concessões por operação, com negação explícita prevalente; ausência de grupos e permissão de monitoramento não concedem acesso à agenda.
- Só titular configura a agenda. Consulta, criação, remarcação e cancelamento de equipe são concessões independentes; conceder criação não autoriza baixar lista ou detalhe por conveniência da UI.
- Domínio único recebe contexto interno ou contexto limitado reconhecido no servidor para consumidor externo, sem duplicar cálculo de disponibilidade. O contrato externo não cria vínculo de equipe; sua implementação real depende de `reservas-clientes`.
- UI usa a base Next.js compartilhada e o [design system](../../docs/design-system.md): estados verdadeiros, controles semânticos, foco/teclado e mensagens em português. Conflito preserva preenchimento; sucesso só após persistência. Não prometer sala, evento Google ou e-mail entregue a partir da confirmação local.

## Sequência de entrega e checkpoints

As fases abaixo são unidades do plano aprovado, **não tarefas de implementação já liberadas**. O [checklist](todo.md), também aprovado, detalha fatias com até cinco arquivos, no máximo três critérios de aceite e verificação própria; contratos técnicos e provedores C0 continuam bloqueantes. Depois dos pré-requisitos compartilhados, fechar cada experiência antes de iniciar a seguinte, sem acumular toda a UI no final.

### P0 — Fechar contratos e pré-requisitos

Limites e representação temporal ratificados: duração até 120 minutos, intervalo até 60 minutos, antecedência até 10.080 minutos e consulta de até 15 datas locais por requisição, sem defaults. AG02 incorporou o catálogo canônico, com disponibilidade mínima por cadastro/remarcação. AG01–AG03 concluídas documentalmente; falta demonstrar os provedores compartilhados e ambiente em AG04.

O [contrato técnico aprovado](../../SPEC-agenda.md#contrato-técnico-aprovado--ag01-e-ag03) define janelas absolutas, conjuntos contínuos de inícios, datas locais, schema/RLS, funções restritas, ABIs e HTTP. O checklist adapta os arquivos e subdivide AG12 em AG12a/AG12b, preservando os IDs principais e até cinco arquivos por fatia. Isso não autoriza migrations antes de AG04/C0.

Confirmar entrega real de equipe/validade/autorização e frontend compartilhado, além das ABIs/contexto limitado já contratados. Não implementar links ou cadastrar cliente como equipe para contornar ausências. Fontes oficiais sustentam o contrato; sua execução e segurança exigem provas reais.

**Checkpoint C0:** contratos e limites aprovados, dependências externas identificadas e sua entrega demonstrada para liberar as fatias dependentes. Nenhum aceite é dispensado por indisponibilidade de equipe ou UI. Lógica isolada pode ser organizada antes, mas não equivale a caminho executável completo nem autoriza contornar esse gate.

### P1 — Titular configura e consulta disponibilidade

Entregar fatia de persistência, domínio, API e UI para titular salvar e consultar janelas, duração única, intervalo e antecedência, sem defaults. Equipe não configura. Distinguir configuração ausente, configurada sem horários, erro e ausência de permissão. Estabelecer a linha estável de sincronização e a leitura consistente da configuração desde esta fatia.

**Checkpoint C1:** salvar/reler configuração pela API e pelo navegador, com banco real; provar limites inválidos, zero nos campos permitidos, UTC/fuso explícito e negação à equipe. Alteração conserva compromissos existentes quando estes forem exercitados nas fases seguintes.

### P2 — Operador autorizado agenda e consulta compromissos

Entregar lista/detalhe e criação de compromisso com modalidade e participantes, duração calculada e validação de janela, separação e antecedência. Fechar a experiência correspondente na UI sem ampliar concessões. O resultado de consulta de disponibilidade não garante a reserva; confirmar novamente sob proteção transacional.

Provar cedo o risco principal: confirmações incompatíveis concorrentes na mesma agenda deixam uma única ocupação; dois canais de entrada do domínio obedecem às mesmas regras. Usar consumidor de teste isolado para a fronteira externa, sem alegar reserva real por link implementada.

**Checkpoint C2:** API/UI persistem e apresentam dados reais, rejeitam duração divergente e horário que acabou de ser ocupado. Executar limites temporais da spec. Provar exclusão mútua com conexões reais e ausência de bloqueio entre agendas distintas. Concessão de criar não permite consulta por inferência.

### P3 — Operador autorizado remarca e cancela

Entregar remarcação e cancelamento como fatias verticais distintas no futuro checklist. Remarcação revalida destino/configuração vigente e antecedência; falha preserva origem. Cancelamento antes do início não aplica antecedência de reserva, libera horário e não depende de confirmação externa. Não acrescentar gestão retroativa de compromissos passados.

**Checkpoint C3:** API e navegador exercitam destino ocupado, remarcação válida e cancelamento; nova confirmação elegível usa o horário liberado. Provar disputas criação/remarcação, remarcação/remarcação, remarcação/cancelamento e configuração/confirmação sem estado parcial, dupla ocupação ou configuração híbrida. Comprovar preservação de compromissos legados após mudança de duração/intervalo/janelas.

### P4 — Validar isolamento, consumidores e experiência integral

Consolidar prova de titular e equipe real com concessões independentes, negações, expiração e revogação em sessão aberta. Verificar lista/detalhe/mutações entre dois tenants e reutilização do pool após erro/rollback. Provar que indisponibilidade ou retorno atrasado de consumidor externo não decide ocupação local; não criar implementação fake desses serviços para declarar integrações prontas.

**Checkpoint C4 final:** todos os critérios da spec cobertos; suíte existente sem regressão; smoke pela API realmente servida e pela UI real; DOM/rede/console e acessibilidade verificados. Os checkpoints C1–C3 não transferem segurança para o final: cada fatia já exige autorização, RLS e regressões pertinentes. Não concluir a agenda integralmente enquanto UI/equipe estiverem ausentes. Obter revisão humana final antes de integrar ou liberar deploy.

## Dependências e paralelização

| Fase | Pré-requisitos diretos | Paralelismo seguro |
|---|---|---|
| P0 | Spec aprovada; decisões humanas; contratos dos provedores compartilhados | Pesquisa de contrato de persistência e avaliação de UI/equipe podem ocorrer em paralelo, sem mutação compartilhada |
| P1 | P0 e base frontend/autorização disponíveis | API e UI após congelar o contrato; um único dono integra schema e áreas compartilhadas |
| P2 | P1 | Lista/detalhe e apresentação podem ser preparados em paralelo à confirmação após acordar os contratos; todas as escritas compartilham protocolo |
| P3 | P2 | UI por ação e provas isoladas podem avançar após contrato; mutações do mesmo domínio/migrations devem ser integradas por um dono |
| P4 | P1, P2, P3 e provedores reais | Provas por lente podem ser divididas, sem concorrência acidental sobre o mesmo banco de teste |

Migrations e mudanças de privilégios são sequenciais. Não executar suites independentes que limpem as mesmas fixtures ou disputar edição de rotas, catálogo de autorização e services centrais. A implementação ocorre na base `dev` em feature própria conforme o fluxo vigente, não no branch documental por inferência de aprovação.

## Rastreabilidade do aceite

Referências numéricas são os itens de [critérios observáveis](../../SPEC-agenda.md#critérios-de-sucesso-observáveis), não novos IDs de tarefa.

| Critérios da spec | Fases/checkpoints responsáveis |
|---|---|
| 1 — duração única | P1, P2 / C1, C2 |
| 2 — intervalo e limites | P1, P2 / C1, C2 |
| 3 — antecedência, inclusive instante limite | P2, P3 / C2, C3 |
| 4 — configuração ausente | P1 / C1 |
| 5 — concorrência na mesma agenda | P2, P3 / C2, C3 |
| 6 — agendas independentes e isolamento | P2, P4 / C2, C4 |
| 7 — remarcação/cancelamento | P3 / C3 |
| 8 — configurações e compromissos legados | P1, P2, P3 / C3 |
| 9 — matriz de equipe e validade | P0, todas as fatias / C1–C4 |
| 10 — independência de fornecedores | P2, P3, P4 / C4 |
| 11 — contexto confiável | P0, todas as fatias / C1–C4 |

## Índice do checklist

O [checklist de agenda](todo.md) detalha as 29 fatias abaixo e foi aprovado pelo solicitante; critérios, dependências, arquivos e verificações são mantidos somente nele. Aprovação não equivale a execução das tarefas nem libera os bloqueios C0.

| Fase | IDs do checklist |
|---|---|
| P0 — Contratos e pré-requisitos | AG01–AG04 |
| P1 — Configuração e disponibilidade | AG05–AG10 |
| P2 — Compromissos e concorrência | AG11–AG16 |
| P3 — Transições e configurações concorrentes | AG17–AG24 |
| P4 — Acesso, consumidores e aceite real | AG25–AG29 |


## Estratégia de verificação

- Regras temporais determinísticas: antes/exatamente/depois dos limiares, intervalo zero/positivo, duração por tempo decorrido e configuração ausente. Sem sleeps como prova.
- Banco real com `advocacia_runtime`, sem ownership, superusuário ou bypass de RLS; migrator somente para preparar/migrar banco autorizado. Testes de concorrência usam dados commitados, uma conexão e contexto próprios por worker e barreiras explícitas; não compartilhar a transação de teste que esconderia corridas.
- Observar estado persistido depois dos commits. Timeout ou erro genérico não substitui conflito de domínio correto. Para provar independência entre agendas, manter uma transação de A retida e demonstrar B concluindo antes da liberação de A, não apenas dois pedidos terminando depois.
- Respeitar tamanho do pool e timeouts existentes; o coordenador não pode ocupar todas as conexões nem criar barreira inalcançável. Testes futuros precisam de cleanup e propagação de falhas dos workers.
- HTTP com sessão, Origin/CSRF e envelope reais; sessão preparada para smoke não comprova OAuth Google real. Registrar separadamente essa limitação e o resultado de login real quando credenciais/HTTPS estiverem disponíveis.
- UI com navegador real e chamadas reais à API: configuração, criar/listar/detalhar, conflito, remarcação e cancelamento; estados de vazio/falha/acesso negado; fuso visível, teclado, foco, labels, reflow e texto a 200%. Verificar larguras 320, 768, 1024 e 1440px conforme direção visual existente. Não adicionar teste permanente de texto incidental ou wiring.
- Após cada fatia, executar uma vez os checks pertinentes e smoke da superfície mudada; no checkpoint final, suíte completa, build e smoke integrado. Resultados são futuros, não evidências produzidas por este plano.

### Comandos existentes para a execução futura

Diretório de trabalho `backend/`, Ruby/gems do lockfile e ambiente já fornecido por mecanismo protegido:

| Finalidade | Comando suportado |
|---|---|
| Suíte Rails | `RAILS_ENV=test ruby bin/rails test` |
| Precedente de teste de concorrência existente | `RAILS_ENV=test ruby bin/rails test test/integration/session_validity_test.rb` |
| API para smoke autorizado | `bundle exec puma -C config/puma.rb` |
| Migration em banco de teste previamente autorizado | `RAILS_ENV=test ruby bin/migrate` |

Da raiz, build da API existente: `docker build --target runtime -t advocacia-backend:local backend`. Não executar build, migration, instalação ou container por este documento. A suíte exige banco de teste separado/provisionado/migrado, URLs segregadas por role e variáveis de boot registradas no README. No deploy, usar somente o PostgreSQL já existente; nenhuma nova instância ou inicialização root é autorizada.

Comandos de testes focados da agenda e de build/lint/testes do frontend serão registrados no checklist quando os respectivos arquivos/scripts existirem ou forem explicitamente previstos como criação da fatia. Não anunciar comandos npm, testes ou assets inexistentes como verificados. Qualquer variável criada/alterada na implementação deve ser documentada no README no mesmo conjunto de mudanças.

## Riscos e mitigação

| Risco | Mitigação/gate |
|---|---|
| Equipe/grupos e frontend inexistentes | Dependências externas explícitas em P0; não substituir por flags/mocks nem declarar titular/API como entrega completa |
| TOCTOU em reserva ou antecedência vencida enquanto espera lock | Lock por agenda, configuração e tempo relidos no ponto protegido; testes de corrida reais |
| Escritor ignora lock ou privilégios impedem adquiri-lo | Dono único de mutações, linha própria, revisão dos grants e prova dos caminhos de escrita em C0/C2 |
| Buffer histórico contraria configuração nova | Calcular separação pela configuração vigente sem redimensionar compromissos legados; regressão de mudança de configuração |
| Remarcação libera origem prematuramente | Uma transação protegida, rollback integral e testes de interleavings |
| Vazamento de contexto em pool/savepoints | Reutilizar DatabaseContext e provar restauração/cache em sucesso e erro com dois tenants |
| Limite de consulta aplicado incorretamente | Máximos confirmados; ratificar datas locais e fronteiras em AG01/AG03 e testar 15 datas versus 16, sem criar horizonte de reserva |
| Estado local apresentado como integração concluída | Contratos e UI distinguem ocupação de sala/publicação/envio; validar sem alegar fornecedores reais |
| Plano atual perdido ou comando seleciona arquivo errado | Destino isolado autorizado; registrar caminhos no mapa/spec; manter arquivos originais intactos |

## Questões abertas e próximo gate

1. Plano, checklist e contrato técnico aprovados; AG01–AG03 concluídas documentalmente. AG04/C0 ainda exige comprovação real de provedores e ambiente.
2. Aplicar os máximos confirmados (120 minutos, 60 minutos, 10.080 minutos e 15 dias por consulta), sem convertê-los em defaults ou horizonte de agendamento.
3. Registrar evidência de equipe/autorização, frontend e ambiente, incluindo implementação das ABIs e contexto limitado. Esses gates não autorizam ampliar a agenda para implementar os provedores ausentes.

As aprovações humanas do plano e do checklist foram registradas em turnos posteriores às respectivas elaborações. A implementação só começa após os bloqueios C0 serem resolvidos. As outras quatro capacidades da iniciativa ainda dependem de especificações próprias; estas aprovações não as liberam.

**Verificação desta etapa:** pesquisa documental e de fontes locais, com análises paralelas de backend/concorrência e frontend/verificação. Não foram executados testes, build, lint, migrations, containers ou smoke de aplicação. Nenhum resultado histórico foi promovido a prova atual.
