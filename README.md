# Monitoramento jurídico — monorepo

Monorepo da plataforma de monitoramento de publicações judiciais voltada a advogados independentes e suas equipes, reunindo backend Rails API-only e frontend Next.js no mesmo repositório. A fonte inicial é o Diário de Justiça Eletrônico Nacional (DJEN), exclusivamente Diário Eletrônico (`D`), sem coleta de editais (`E`): na primeira coleta, cadernos com fallback paginado; na segunda, API paginada diretamente.

> **Estado atual:** o backend contém identidade, autorização, monitoramentos, coleta, consulta e dashboard. A interface Next.js fica em `apps/web/`; o Swagger UI ainda não está implementado.

## Estrutura do monorepo

A raiz é compartilhada pelo produto inteiro; não é a raiz de uma aplicação Rails nem de uma aplicação Next.js isolada. Cada componente mantém suas dependências, comandos e artefatos de execução.

| Caminho relativo à raiz | Responsabilidade | Situação |
|---|---|---|
| `backend/` | API Rails, domínio, persistência e testes; dependências em `backend/Gemfile` e `backend/Gemfile.lock`. | Existente. |
| `backend/despachante/` | Despachante de coletas, processo Ruby separado da API, com `Gemfile` e lockfile próprios. | Existente; pertence ao backend e ao mesmo monorepo, mas não executa dentro do servidor Rails. |
| `apps/web/` | Interface Next.js com TypeScript e App Router; páginas, componentes e estilos do produto. | Existente. |
| `etl/` | Execução da coleta, em processo separado da API e do despachante. | Existente; processador automático com retomada. |
| `docs/` | Especificação geral, arquitetura, contratos técnicos e direção visual compartilhados. | Existente. |
| `tasks/` | Plano, gates e checklist de implementação do monorepo. | Existente. |
| `SPEC-*.md` e `CAPABILITIES.md` | Contratos funcionais e mapa de capacidades do produto. | Existentes na raiz. |

Frontend e API terão imagens Docker separadas. O despachante já tem target próprio `despachante` em `backend/Dockerfile`; o target da API é `runtime`. Processos e imagens separados não significam repositórios separados. PostgreSQL é infraestrutura compartilhada: imagem separada somente para testes locais e instância já existente no deploy.

A [arquitetura](docs/arquitetura.md#estrutura-do-monorepo-e-fronteiras) detalha as fronteiras. O [guia visual](docs/design-system.md#escopo-no-monorepo) orienta a interface de `apps/web/`, não uma aplicação independente deste repositório.

## Escopo funcional

- Login Google para advogado e equipe; o contrato de identidade não prevê senha local para usuários da aplicação.
- Isolamento por tenant do advogado, autorização por grupos e tribunal, monitoramentos de advogados/partes/processos e consulta de comunicações.
- Duas coletas diárias do DJEN, somente Diário Eletrônico (`D`), sem editais (`E`): cadernos e fallback paginado na primeira execução, API paginada diretamente na segunda e deduplicação pela combinação de `id` e `hash`.
- Dashboard e registros append-only do fluxo de coleta.

O mapa de módulos e a ordem de dependências estão em [`CAPABILITIES.md`](CAPABILITIES.md). Requisitos detalhados: [`docs/especificacao.md`](docs/especificacao.md) e as seis especificações `SPEC-*.md` na raiz.

## Stack definida

- API central: Ruby on Rails, exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).

O projeto é um monorepo. As imagens de frontend e backend serão separadas; a imagem PostgreSQL será usada somente para testes locais. No deploy, a aplicação usará a instância PostgreSQL já existente no servidor. A criação do banco da aplicação e as migrations nessa instância dependem das permissões e do procedimento de deploy, ainda não definidos. Todas as imagens deverão ser mínimas e executar sem root, conforme [`AGENTS.md`](AGENTS.md).

Versões de referência e limites da decisão: [`docs/stack.md`](docs/stack.md). Estrutura e ferramentas propostas para os demais componentes estão em [`docs/arquitetura.md`](docs/arquitetura.md).

## Interface web em desenvolvimento

`apps/web/` usa Node.js 24, npm e Next.js App Router. A API precisa estar disponível em uma rede Docker compartilhada; os comandos abaixo usam `advocacia-local`, com um proxy HTTPS à frente do frontend. Configure `APP_ORIGIN`, `RAILS_API_ORIGIN` e `AUTH_INGRESS_SECRET` no ambiente protegido antes de executar. O exemplo usa a imagem Node para desenvolvimento, não uma imagem de deploy do produto.

```bash
mkdir -p apps/web/node_modules apps/web/.next
docker run --rm -it --name advocacia-web --network advocacia-local \
  --user "$(id -u):$(id -g)" \
  --mount "type=bind,source=$PWD/apps/web,target=/workspace" \
  --tmpfs "/workspace/node_modules:exec,uid=$(id -u),gid=$(id -g),mode=0775" \
  --tmpfs "/workspace/.next:uid=$(id -u),gid=$(id -g),mode=0775" \
  --tmpfs /tmp:mode=1777 -w /workspace -e HOME=/tmp \
  -e APP_ORIGIN -e RAILS_API_ORIGIN -e AUTH_INGRESS_SECRET \
  node:24.22.1-alpine \
  sh -c 'npm ci --ignore-scripts && npm run dev -- --hostname 0.0.0.0'
```

Enquanto o container estiver ativo, `docker exec advocacia-web npm run format:check`, `docker exec advocacia-web npm run lint`, `docker exec advocacia-web npm run typecheck`, `docker exec advocacia-web npm test` e `docker exec advocacia-web npm run build` executam as verificações. O diretório de dependências e o build usam tmpfs; não são instalados no host.

O ingresso público deve terminar TLS, encaminhar a mesma origem ao Next.js e **substituir**, não concatenar nem confiar nos valores do navegador, os cabeçalhos `X-Advocacia-Client-IP` pelo endereço IP real do cliente e `X-Advocacia-Ingress-Secret` pelo valor protegido de `AUTH_INGRESS_SECRET` nas requisições a `/auth/google`. O segredo deve ser acessível somente ao ingresso e ao processo Next.js; impedir acesso público direto ao Next.js e à API. O Next.js envia o IP autenticado ao Rails para preservar a limitação por cliente; a conexão interna deve vir de uma rede de proxy confiável para a configuração Rails. Se houver balanceador anterior, o ingresso só pode usar o IP repassado por ele depois de validar sua cadeia de confiança.

Não registrar query strings do callback OAuth nem os cabeçalhos internos em logs de ingresso ou observabilidade. O login requer cliente Google registrado e o convite requer SMTP configurado. A API e o frontend compartilham `APP_ORIGIN`; cookies `Secure` e CSRF exigem HTTPS também no desenvolvimento. Leituras e mutações exigem um navegador com Web Locks em contexto seguro para coordenar sessões e vínculos entre abas. O relay aceita até 1 MiB de corpo por requisição e impõe prazo de 20 segundos; configure também limites de corpo e tempo no ingresso HTTPS. Se uma mutação perder a confirmação, consulte o estado antes de repeti-la.

## Swagger UI e acesso à documentação

Requisito registrado: a documentação interativa da API será publicada com Swagger UI e protegida por login e senha. O contrato proposto usa autenticação HTTP Basic separada do login Google, exclusivamente por HTTPS, conforme [`docs/arquitetura.md`](docs/arquitetura.md#identidade-convites-e-documentação). O Swagger UI ainda não existe; não há usuário ou senha padrão, nem credenciais versionadas.

## Variáveis de ambiente

As variáveis abaixo são lidas pelos componentes, seus testes ou processos indicados; a conexão do processador é exclusiva dessa fronteira. Forneça valores sem default pelo gerenciador de segredos ou ambiente protegido do deploy; não versione credenciais nem URLs contendo senhas. As credenciais Google exigem um cliente OAuth web registrado externamente, com URI de redirecionamento exatamente `APP_ORIGIN/auth/google/callback`.

| Variável | Default | Obrigatória? | Finalidade |
|---|---|---|---|
| `DATABASE_URL` | Nenhum | Sim, para API e testes | Conexão PostgreSQL com a role `advocacia_runtime`, sem propriedade das tabelas nem bypass de RLS. |
| `MIGRATION_DATABASE_URL` | Nenhum | Sim, para migration e teste administrativo de sessão; não fornecer à API web | Conexão com `advocacia_migrator`, separada da role de execução. |
| `DESPACHANTE_DATABASE_URL` | Nenhum | Sim, no despachante e nos testes do despachante; não fornecer à API web | Conexão PostgreSQL isolada com a role `advocacia_despachante`, exclusiva do processo confiável de planejamento; fornecer externamente por ambiente protegido ou gerenciador de segredos. |
| `PROCESSADOR_DATABASE_URL` | Nenhum | Sim, no processador e nos testes de fronteira do Escrevente; não fornecer à API nem ao despachante | Conexão PostgreSQL exclusiva com a role `advocacia_processador`, provisionada administrativamente por `backend/db/provision_processador.sql` antes da migration do Escrevente. Fornecer credencial e URL externamente por ambiente protegido ou gerenciador de segredos, sem registrar segredo no repositório. |
| `POSTGRES_DB` | `POSTGRES_USER` da imagem PostgreSQL; `postgres` quando este não é definido | Não na imagem; o CI define `advocacia_test` | Nome do banco criado na primeira inicialização do PostgreSQL descartável do CI; não configura o banco de deploy. |
| `POSTGRES_HOST_AUTH_METHOD` | `scram-sha-256` na imagem PostgreSQL 18; `trust` no CI | Não na imagem; o CI define `trust` para o banco descartável sem senha | Método de autenticação para conexões de rede na inicialização do banco de teste; `trust` é usado exclusivamente na rede interna descartável do CI, nunca no deploy. |
| `COLETA_HORARIO_1` | Nenhum | Sim, no despachante | Primeiro horário diário em `HH:MM`, fuso `America/Sao_Paulo`, a partir de `04:00`; fornecer pela configuração do processo. |
| `COLETA_HORARIO_2` | Nenhum | Sim, no despachante | Segundo horário diário em `HH:MM`, posterior ao primeiro; fornecer pela configuração do processo. |
| `COLETA_TENTATIVAS_POR_CAMINHO` | `3` | Não | Número máximo de tentativas de cada caminho, inteiro de 1 a 3; qualquer mudança requer aprovação. |
| `COLETA_BACKOFF_APOS_FALHA_1_SEGUNDOS` | `60` | Não | Espera em segundos após a primeira falha, inteiro positivo; alterações requerem aprovação. |
| `COLETA_BACKOFF_APOS_FALHA_2_SEGUNDOS` | `300` | Não | Espera em segundos após a segunda falha, inteiro positivo; alterações requerem aprovação. |
| `PROCESSADOR_TEST_ADMIN_DATABASE_URL` | Nenhum | Sim, apenas na integração do processador em banco descartável | Conexão administrativa usada exclusivamente para preparar e remover dados sintéticos do teste; fornecer no ambiente protegido de teste, nunca no processo de produção ou com acesso a banco real. |
| `APP_ORIGIN` | Nenhum | Sim, para frontend, API, migration e testes Rails; não é usada pelo despachante | Origem pública HTTPS compartilhada, sem caminho ou credenciais; forneça pelo ambiente protegido. A API valida origens de operações mutáveis e compõe o callback Google; o proxy web usa seu host canônico para contatar a API. |
| `RAILS_API_ORIGIN` | Nenhum | Sim, no frontend | Origem interna da API Rails, acessível somente ao servidor Next.js; forneça pela configuração protegida do ambiente, sem expô-la ao navegador. |
| `AUTH_INGRESS_SECRET` | Nenhum | Sim, no frontend para iniciar login Google | Segredo compartilhado com o proxy HTTPS confiável para autenticar o IP do cliente encaminhado à limitação de login. Gere pelo menos 32 bytes aleatórios e forneça ao Next.js e ao proxy por um gerenciador de segredos; nunca o exponha ao navegador nem registre seu valor. Sem ele ou sem os cabeçalhos confiáveis, o login falha fechado. |
| `GOOGLE_CLIENT_ID` | Nenhum | Sim, para autenticação Google | Identificador do cliente OAuth web. |
| `GOOGLE_CLIENT_SECRET` | Nenhum | Sim, para autenticação Google | Segredo do cliente OAuth web; fornecer por mecanismo de segredos. |
| `SMTP_HOST` | Nenhum | Sim, para enviar convites | Host do servidor SMTP; fornecer pela configuração protegida do ambiente. |
| `SMTP_PORT` | Nenhum | Sim, para enviar convites | Porta TCP do servidor SMTP com STARTTLS obrigatório; fornecer pela configuração protegida do ambiente. |
| `SMTP_USERNAME` | Nenhum | Sim, para enviar convites | Usuário de autenticação SMTP; fornecer pela configuração protegida do ambiente. |
| `SMTP_PASSWORD` | Nenhum | Sim, para enviar convites | Senha de autenticação SMTP; fornecer por gerenciador de segredos, sem versioná-la. |
| `SMTP_FROM` | Nenhum | Sim, para enviar convites | Endereço remetente autorizado no servidor SMTP; fornecer pela configuração protegida do ambiente. |
| `SECRET_KEY_BASE` | Nenhum | Sim, para API, migration e testes Rails; não é usada pelo despachante | Segredo Rails usado para proteção de tentativas de autenticação; gerar e fornecer externamente. |
| `RAILS_ENV` | `production` na imagem runtime; `test` na imagem de testes | Não | Seleciona o ambiente Rails. |
| `RAILS_LOG_LEVEL` | `info` | Não | Nível de logging. |
| `PORT` | `3000` | Não | Porta do servidor Puma. |
| `RAILS_MAX_THREADS` | `5` | Não | Número de threads Puma e tamanho do pool de conexões PostgreSQL. |
| `BUNDLE_PATH` | `/bundle` na imagem | Não | Diretório das gems na imagem. |
| `BUNDLE_FROZEN` | `true` na imagem | Não | Impede alteração do lockfile pelo Bundler. |
| `BUNDLE_DEPLOYMENT` | `true` na imagem | Não | Ativa o modo de implantação do Bundler. |
| `BUNDLE_WITHOUT` | `test` no runtime; vazio no target de testes | Não | Exclui as dependências de testes da imagem de execução. |
| `BUNDLE_GEMFILE` | `/app/despachante/Gemfile` na imagem do despachante; caminho do `Gemfile` da API no boot Rails | Não | Seleciona o manifesto próprio de dependências de cada processo. |
| `HOME` | `/home/app` na imagem | Não | Diretório inicial do usuário não root da imagem. |

Não há prazo automático de retenção do Escrevente nesta etapa. As configurações de Swagger permanecem por nomear.

**Regra de manutenção:** toda variável de ambiente introduzida ou alterada em uma implementação deve ser registrada nesta seção do README no mesmo conjunto de mudanças. Para cada variável, informe nome exato, valor default (ou `Nenhum` se não houver), se é obrigatória e para que serve. Quando não existir default, documente também como fornecer o valor sem incluir segredos. Atualize a tabela ao remover variáveis.

## Documentação do projeto

- [Especificação geral](docs/especificacao.md)
- [Stack e versões de referência](docs/stack.md)
- [Arquitetura e contratos técnicos propostos](docs/arquitetura.md)
- [Direção visual: UI, tipografia e cores](docs/design-system.md)
- [Mapa de capacidades](CAPABILITIES.md)
- [Plano de implementação e gates](tasks/plan.md)
- [Checklist de implementação](tasks/todo.md)
- [Contrato OpenAPI do DJEN consultado](docs/contrato-djen.md)

## Implementação e verificações

**Interface web:** em containers não root, `npm run format:check`, `npm run lint`, `npm run typecheck` e `npm test` passaram; o runner executou **33 testes**, sem falhas ou skips. `npm run build` gerou o build Next.js de produção. No Chromium headless, o build foi exercitado com Rails e PostgreSQL descartável: onboarding, troca de vínculo entre abas, operações de monitoramento e equipe, grupos, dashboard parcial e mascarada, comunicações independentes e HTML da fonte como texto. A 320 px não houve transbordamento horizontal.

Um SMTP descartável com STARTTLS e certificado de teste recebeu criação e reemissão de convite; o link efetivamente entregue foi aberto e aceito pela interface com sessão sintética. Também foi exercitada a falha de SMTP sem perder a credencial. Não houve login Google nem entrega em servidor SMTP externos. A consulta ao catálogo real do DJEN retornou 503 na API, após a fonte responder 403 neste ambiente; o fluxo de seleção bem-sucedida de tribunal real continua sem comprovação. O checklist detalhado está em [`apps/web/endpoints.md`](apps/web/endpoints.md).

Os registros históricos a seguir são anteriores à renomeação para processador e não comprovam, por si só, a configuração renomeada.

O histórico da consolidação anterior registra 276 testes e 7.678 assertions, comparação de catálogo e smoke de onboarding; esses resultados não comprovam as alterações posteriores de identidade e autorização.

**Identidade e autorização:** em PostgreSQL 18.6 isolado, as migrations atuais foram aplicadas com roles segregadas e a suíte passou com **382 testes e 9.242 assertions**, sem falhas, erros ou skips. Smoke HTTP em processo não root criou e listou grupo, enviou convite por SMTP local com STARTTLS, aceitou-o numa sessão preparada, confirmou leitura de equipe sem grupos, negou administração à equipe e bloqueou a sessão após revogação. O smoke não usou Google OAuth nem servidor SMTP externos.

As decisões de transação e privilégios seguem as referências oficiais de [funções PostgreSQL seguras](https://www.postgresql.org/docs/18/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY), [RLS](https://www.postgresql.org/docs/18/ddl-rowsecurity.html) e [travas de advisory](https://www.postgresql.org/docs/18/explicit-locking.html#ADVISORY-LOCKS). O transporte usa o [SMTP da biblioteca Mail](https://github.com/mikel/mail/blob/2.9.1/lib/mail/network/delivery_methods/smtp.rb).

### API de onboarding

| Método e caminho | Comportamento |
|---|---|
| `GET /auth/google` | Inicia autenticação Google por authorization code com PKCE. |
| `GET /auth/google/callback` | Valida o retorno Google e cria sessão; sucesso devolve JSON, falha devolve `401`. |
| `GET /api/session` | Informa se há sessão autenticada, se o onboarding foi concluído e, quando autenticada, o token CSRF. |
| `POST /api/onboarding` | Cria perfil e tenant do advogado autenticado. Exige `Origin` igual a `APP_ORIGIN` e `X-CSRF-Token` da sessão. |
| `GET /api/onboarding` | Retorna o perfil, inscrições e tenant associados à sessão, sem aceitar seleção de tenant pelo cliente. |

O corpo do POST contém `full_name`, `primary_oab` com `number` e `uf`, `secondary_oabs` como lista e `office_name` opcional. A OAB principal é obrigatória; as secundárias podem ser uma lista vazia. O número é textual para preservar zeros e sufixos. Não se confunde escritório com tenant.

### Identidade de equipe e grupos

A identidade Google pode ter vínculos em vários tenants. `GET /api/session` informa os vínculos disponíveis; `PATCH /api/session/membership` seleciona um `membership_id` validado pelo servidor e `DELETE /api/session` encerra a sessão. Uma credencial de equipe exige `validity_days` explícito: `null` para sem expiração ou inteiro positivo, contado em períodos de 24 horas desde a criação ou renovação. Alterar a escolha não altera o vencimento até a renovação; revogação é imediata e não é revertida por renovação.

O titular administra credenciais em `GET`/`POST /api/team/credentials`, `PATCH`/`DELETE /api/team/credentials/:id`, `POST /api/team/credentials/:id/renewal` e `POST /api/team/credentials/:id/invitation`. A criação recebe `email`, `validity_days` e `group_ids` opcional. O convite é enviado por SMTP após o commit: se a entrega não for confirmada, a credencial permanece criada e o titular pode reemitir o convite. A reemissão invalida o link anterior sem reiniciar a validade. O link usa fragmento `#token=...`; a interface preserva o token durante o login e o envia a `POST /api/team/invitations/accept`, com sessão Google, `Origin` e CSRF. Não registrar o token nem o conteúdo do convite.

O titular administra grupos, regras e associações em `/api/authorization/groups`, suas rotas `/:id/rules` e `/:id/memberships/:membership_id`; `GET /api/authorization/catalog` lista as operações. Uma regra contém `operation`, `effect` (`allow` ou `deny`) e `court` (`null` para escopo geral). Sem grupos, equipe recebe as leituras padrão; com grupos, concessões se somam e negação explícita prevalece. Escritas exigem concessões distintas. A consulta e a dashboard aplicam a política por tribunal e operação no servidor.

### API de monitoramentos

As operações abaixo exigem sessão válida; alterações exigem também `Origin` e `X-CSRF-Token`. O tenant vem da sessão, nunca do corpo ou da query. A equipe depende da autorização específica por grupo; o titular opera por propriedade. Sem permissão de consulta, uma alteração autorizada retorna somente o identificador, não o detalhe do monitoramento.

| Método e caminho | Comportamento |
|---|---|
| `GET /api/courts` | Consulta o catálogo atual de tribunais do DJEN; falha da fonte retorna `503`, sem substituir o catálogo por lista inventada. |
| `GET /api/monitorings/lawyer` | Retorna o perfil e as OABs do advogado titular como entidade monitorada, sem duplicar seu cadastro. |
| `GET`, `POST /api/monitorings/parties` | Lista ou cadastra partes do tenant. |
| `GET`, `PATCH /api/monitorings/parties/:id` | Lê, edita, desativa ou reativa uma parte do tenant. |
| `GET`, `POST /api/monitorings/processes` | Lista ou cadastra processos do tenant. |
| `GET`, `PATCH /api/monitorings/processes/:id` | Lê, edita, desativa ou reativa um processo do tenant. |

No cadastro de parte, `name` é obrigatório e sua chave de equivalência ignora caixa, diacríticos e espaços excedentes, mantendo pontuação significativa. A chave canônica aceita até 2.000 bytes; entradas maiores retornam `422`, evitando exceder o limite do índice PostgreSQL. No cadastro de processo, `number` aceita 20 dígitos ASCII ou a máscara CNJ; a resposta preserva os 20 dígitos e zeros iniciais. Duplicatas no mesmo tenant geram conflito mesmo quando desativadas. `courts` ausente ou `null` significa todos os tribunais disponíveis; uma lista explícita deve ser não vazia e conter somente códigos do catálogo atual. A seleção salva não é ampliada se um tribunal deixar de estar disponível.

### API de comunicações e dashboard

As rotas exigem sessão válida e tenant selecionado no servidor. Não aceitam tenant nem escopo fornecidos pelo cliente; respostas protegidas usam `Cache-Control: no-store`.

| Método e caminho | Resposta |
|---|---|
| `GET /api/communications` | `{ courts: [{ court, communications: [...] }] }`, com publicações independentes, `id`, `source`, `identity_status`, `warning` e `process_number` quando fornecido pela fonte. |
| `GET /api/communications/:id` | Detalhe, `payload` da primeira versão persistida e `links` dos monitoramentos em tribunais legíveis. Identificador inválido, inexistente ou não autorizado retorna `404`. |
| `GET /api/dashboard` | Estado, tribunais legíveis, avisos e métricas de comunicações e processos para hoje, semana civil e últimos sete dias de calendário. |

A identidade incompleta aparece com `identity_status: "pending"` e `warning: "possible_duplicate"`; essas comunicações não entram nas métricas. O corpo JSON escapa caracteres HTML, mas o JSON decodificado continua contendo texto da fonte: **o consumidor deve renderizar como texto e escapar todos os campos**, inclusive conteúdo de caderno preservado; não inserir HTML bruto. Campos ausentes não são inventados. A origem é o tribunal do vínculo mais antigo da comunicação; se houver empate entre tribunais diferentes, a origem é ambígua e o registro não é exposto. Uma sigla de tribunal válida conflitante no payload exige autorização também para essa sigla. Vínculos posteriores não concedem acesso à primeira versão.

A dashboard usa `America/Sao_Paulo`, `as_of` e `periods` com `today`, `week` e `last_seven_days`; cada período contém `start`, `end`, `communications` e `processes`. O início é inclusivo e o fim exclusivo. Uma comunicação completa é contada na primeira persistência; processos usam CNJ canônico válido e são distintos por janela. A agregação considera somente tribunais autorizados cujo trabalho esteja integralmente concluído. `state` distingue `succeeded`, `partial`, `running`, `failed`, `no_work`, `unavailable` e `masked`; sem tribunal concluído, números são `null`, não zero. Sem permissão de dashboard, cada número é `*`, sem valor subjacente na resposta.

Para o estado corrente de cada tribunal usa-se o último slot relevante do dia; um planejamento posterior falho, interrompido ou sem trabalho não herda o sucesso anterior. Avisos de falhas persistentes incluem apenas tribunais legíveis e permanecem até sucesso integral em slot posterior do mesmo dia. Falhas não recuperadas em dias anteriores continuam sinalizadas sem iniciar coleta retroativa. As telas correspondentes estão em `apps/web/`.

**Verificação:** em PostgreSQL 18.6 descartável, com roles segregadas, `ruby bin/rails test test/integration/communications_http_test.rb test/integration/dashboard_http_test.rb` executou 47 testes e 691 assertions; `ruby bin/rails test` executou 460 testes e 10.503 assertions, sem falhas, erros ou skips. No smoke HTTP em servidor Rails não root, o processador persistiu comunicação e pendência, registrou falha de tribunal e recuperou no segundo slot; a API retornou estado parcial, máscara para equipe restrita e contagens de 2 comunicações e 2 processos após a recuperação. O smoke usou fonte controlada e sessões preparadas, não Google OAuth real.

Referências: [Rails API-only 8.1](https://guides.rubyonrails.org/v8.1/api_app.html), [escape JSON Rails 8.1](https://api.rubyonrails.org/v8.1.4/classes/ActiveSupport/JSON.html#method-c-encode), [RLS PostgreSQL 18](https://www.postgresql.org/docs/18/ddl-rowsecurity.html) e [agregações PostgreSQL 18](https://www.postgresql.org/docs/18/functions-aggregate.html).

Não houve alteração de schema nem novas variáveis nesta fatia. A implantação continua condicionada ao procedimento de atualização do banco existente descrito abaixo; reverter o código da API remove os endpoints sem modificar dados de coleta.

### Planejamento de coleta

O despachante é um processo separado da API: usa uma conexão PostgreSQL exclusiva, consulta o catálogo DJEN e registra uma execução por data de Brasília e horário configurado. Para cada advogado, parte e processo elegível, fixa os critérios e gera trabalhos por tribunal somente no meio `D`; não planeja coleta de editais (`E`). Editar ou desativar um cadastro posteriormente não altera o plano já registrado. A leitura da API é limitada ao tenant autenticado:

| Método e caminho | Comportamento |
|---|---|
| `GET /api/collection-runs` | Lista as execuções cuja audiência inclui o tenant da sessão. |
| `GET /api/collection-runs/:id/jobs` | Lista os trabalhos do tenant para uma execução autorizada. |
| `GET /api/collection-runs/:id/events` | Retorna `{ events: [...] }` com os marcos do tenant: `id`, `job_id`, `event_type` (`started` ou `completed`), `recorded_at`, `entity_type`, `entity_id`, `source`, `court` e `medium`, ordenados por `recorded_at` e `id`. |
| `GET /api/collection-runs/:id/execution` | Retorna `{ jobs: [...] }` com `job_id`, `court`, `medium` e `state` operacional (`pending`, `running`, `succeeded` ou `failed`), ordenados por `job_id`. |

`planned` indica planejamento concluído; `no_work` indica que não houve trabalho elegível; `planning_failed` indica falha do planejamento; `interrupted` identifica planejamento não recuperado após a virada da data local. Nenhum desses estados significa que uma coleta de publicações foi executada ou que ela encontrou zero resultados. Os trabalhos do plano mantêm `collection_jobs.status = pending`; o estado operacional fica separadamente em `collection_job_executions`.

**Verificação histórica dos contratos 10a/10b, anterior à renomeação para processador:** com as migrations então vigentes em PostgreSQL 18.6 isolado e roles separadas, `ruby bin/rails test test/integration/collection_planning_test.rb test/integration/despachante_execution_test.rb test/services/collection_schedule_test.rb test/integration/collection_runs_http_test.rb` passou com 72 testes e 1.248 assertions, sem falhas, erros ou skips. O teste de perfil sem OAB principal verifica falha integral do planejamento, ausência de trabalhos parciais e recuperação da mesma execução após restauração do perfil. A suíte completa passou com 383 testes e 9.267 assertions, sem falhas, erros ou skips.

**Smoke histórico, anterior à restrição ao meio D:** na imagem final do despachante então vigente, usou catálogo TJAC controlado e dois tenants: os dois slots terminaram em `planned`, com advogado, parte e processo, meios D/E, critérios e vínculos conferidos para cada tenant. Repetir a execução reutilizou os mesmos slots; o despachante executou como UID/GID `1000:1000` e o PostgreSQL como `70:70`. Não houve coleta de publicações. Esse registro preserva a evidência anterior, não autoriza trabalhos E na regra vigente.

O workflow `.github/workflows/backend.yml` constrói as imagens da API, do despachante e do processador e executa as suítes contra PostgreSQL descartável em rede isolada; também exercita a imagem final do despachante com catálogo controlado. O smoke seleciona uma data posterior aos planos globais deixados pelas suítes, sem reutilizar um slot criado antes do advogado de teste. O banco e os processos das imagens iniciam sem root; a autenticação `trust` é restrita à rede de teste descartável e não é configuração de produção. A verificação automatizada não comprova login Google real nem cobertura global do DJEN.

### Processador DJEN

O processo em `etl/` consome continuamente os trabalhos planejados com a role exclusiva `advocacia_processador`. Para uma imagem construída por `docker build -t advocacia-processador etl`, execute `docker run --rm --network <rede> -e PROCESSADOR_DATABASE_URL advocacia-processador`, fornecendo a URL pelo ambiente protegido. Sem trabalho disponível, o processo consulta novamente após cinco segundos; ele deve permanecer em execução, separado do despachante, e ser reiniciado pelo supervisor após uma falha fatal. Também é possível executar um trabalho específico informando seu UUID como argumento.

O banco seleciona e concede cada trabalho atomicamente, sem fornecer acesso direto às tabelas ao processador. Instâncias concorrentes ignoram trabalhos bloqueados ou com concessão ativa. Após interrupção, uma concessão expirada permite retomar o progresso persistido; trabalhos concluídos ou com falha não são coletados novamente. Trabalhos pendentes de dias anteriores são marcados como interrompidos sem consultar o DJEN. Como a função de seleção foi adicionada à migration inicial existente, bancos que já a executaram não recebem essa função automaticamente: sua atualização deve integrar o procedimento de deploy antes de iniciar o novo processador.

Após uma tentativa frustrada, o processador libera a concessão enquanto aguarda o backoff ou `Retry-After` persistido; outros trabalhos elegíveis podem avançar sem antecipar a próxima tentativa. O prazo informado pela fonte é compartilhado entre executores para o mesmo tribunal, data, meio e caminho. Uma resposta bem-sucedida com `Retry-After` entre páginas mantém o trabalho atual na instância até a espera terminar; instâncias adicionais podem consumir outros trabalhos.

Cada trabalho consulta somente Diário Eletrônico (`D`) no dia corrente de `America/Sao_Paulo`. Na primeira coleta, valida integralmente o ZIP do caderno e, após esgotar as tentativas, percorre a API paginada até a primeira página vazia válida; na segunda, inicia diretamente pela API, sem caderno. Contadores, etapa e espera são persistidos; falha posterior não publica páginas parciais. Somente para resultados da API, Loofah converte o campo `texto` em texto simples, removendo HTML, scripts e estilos e decodificando entidades; cadernos são persistidos sem essa sanitização. Como a primeira versão é preservada na deduplicação, uma comunicação inicialmente obtida de caderno pode continuar contendo HTML mesmo se também aparecer na API. Todo texto da fonte deve ser escapado pelo consumidor na renderização.

`collection_communications`, `collection_communication_links`, `collection_job_results` e `collection_job_failures` armazenam resultados, vínculos e falhas fora dos marcos do Escrevente. A função `app_private.collection_court_states(uuid)` agrega o estado do tribunal sob a sessão autenticada; contagens ficam `NULL` quando o tribunal não terminou integralmente. A consulta está integrada à interface em `apps/web/`.

Para os testes de integração isolados, forneça também `PROCESSADOR_TEST_ADMIN_DATABASE_URL` de um PostgreSQL descartável e execute `docker run --rm --network <rede-de-teste> -e PROCESSADOR_DATABASE_URL -e PROCESSADOR_TEST_ADMIN_DATABASE_URL <imagem-de-teste-do-processador>`. A conexão administrativa é exclusiva da preparação de dados sintéticos; não deve ser fornecida ao processador de produção.

**Verificação histórica, anterior à API direta na segunda coleta e à restrição ao meio D:** em PostgreSQL 18.6 isolado, `ruby bin/rails test` passou com 402 testes e 9.775 assertions; a imagem de teste do processador passou com 98 testes e 1.004 assertions, sem falhas, erros ou skips. No smoke controlado anterior, seis trabalhos planejados concluíram por caderno e fallback e geraram uma comunicação com seis vínculos. O comando definitivo consultou o caderno TJAC/D real e terminou com zero correspondências; isso não comprova cobertura global nem verifica as decisões vigentes.

**Verificação do contrato vigente:** em PostgreSQL 18.6 descartável com migrations recriadas, a suíte Rails executou 405 testes e 9.648 assertions; a suíte do processador executou 103 testes e 1.030 assertions, ambas sem falhas, erros ou skips. Os testes incluem rejeição de edital, paginação direta no segundo slot e sanitização somente da API.

No smoke definitivo, o despachante planejou seis trabalhos `D` em dois slots para advogado, parte e processo no TJAC. A imagem final executou o trabalho do advogado no segundo slot contra a API DJEN real pelo exit node informado: `succeeded`, zero correspondências, uma tentativa da API e nenhuma do caderno. A amostra não comprova cobertura global.

**Verificação das tarefas 10a, 10b, 12a e 12b:** em PostgreSQL 18.6 descartável, o despachante planejou dois slots para dois tenants, cada um com advogado, parte e processo no TJAC/D. O processador percorreu 12 trabalhos com fonte DJEN controlada: seis por caderno e seis pela API. Foram persistidas duas comunicações, uma por tenant, cada qual com seis vínculos e a primeira versão em HTML preservada. A imagem final do despachante confirmou dois slots distintos e idempotentes; a entrada final do processador confirmou o estado concluído após expiração simulada da concessão no banco descartável.

**Verificação das tarefas 13a e 13b:** com PostgreSQL 18.6 descartável e roles isoladas, `ruby bin/rails test` passou com 413 testes e 9.812 assertions; a suíte completa do processador passou com 128 testes e 1.200 assertions, sem falhas, erros ou skips. Os testes focados incluem 64 casos de integração do processador, com 457 assertions, e 58 casos Rails, com 1.493 assertions.

No smoke controlado com os processos das imagens finais, o despachante planejou dois slots idempotentes para Guilherme Curcelli Guimarães em TJAC/D: o primeiro falhou sem resultado parcial e o segundo recuperou uma comunicação e um vínculo pela API. No caminho definitivo sem UUID, a imagem final consultou a API DJEN real pelo exit node informado e terminou `succeeded` com zero correspondências, uma tentativa da API e nenhuma do caderno. A amostra não comprova cobertura global ou capacidade de produção.

A imagem runtime do processador mediu 202.001.204 bytes e executou com UID/GID 1000:1000; a base `ruby:4.0.9-alpine3.23` mediu 147.221.451 bytes e foi escolhida por compartilhar a versão Ruby do projeto com runtime Alpine enxuto. PostgreSQL local executou com UID/GID 70:70; a persistência após reinicialização foi verificada anteriormente. A imagem final não inclui ferramentas de compilação ou testes.


As consultas do Escrevente exigem sessão válida e onboarding do advogado titular, sem acesso de equipe nesta entrega. O tenant vem da sessão, nunca de parâmetro do cliente. UUID inválido, execução inexistente ou fora da audiência do tenant retorna `404` sem revelar dados; uma execução visível sem trabalhos retorna listas vazias, não eventos nem sucesso fabricados. `pending` significa trabalho ainda não iniciado, `running` processamento iniciado, `succeeded` conclusão bem-sucedida confirmada e `failed` falha operacional. Esses estados, isoladamente, não informam quantidade de publicações, sucesso vazio ou resultado parcial; a ausência de término não permite inferir falha.

O Escrevente é implementado no backend Rails, com marcos append-only em `collection_events`. A interface do executor é SQL, no schema `app_private`, acessível somente pela role `advocacia_processador` entre as roles normais de execução; não é uma API HTTP de escrita:

| Função SQL | Retorno e efeito |
|---|---|
| `processor_claim(uuid)` | Retorna `token`, `expires_at` e `state` do trabalho reivindicado; reserva uma lease de 15 minutos, preservando o estado atual e sem registrar início. |
| `processor_renew(uuid,text)` | Recebe UUID do trabalho e token vigente; retorna `expires_at`, renovando a lease por 15 minutos a partir do horário do banco sem alterar estado ou marcos, inclusive em `failed` e `succeeded`. |
| `processor_start(uuid,text)` | Retorna `id` e `recorded_at` do marco `started`; acrescenta o início e muda `pending` ou `failed` para `running` atomicamente, ou confirma o marco já persistido sem duplicá-lo. Em `succeeded`, apenas recupera o início anterior, sem regredir o estado. |
| `processor_finish(uuid,text)` | Retorna `id` e `recorded_at` do marco `completed`; exige início e acrescenta o término junto da transição para `succeeded`, ou confirma o término já persistido. |
| `processor_fail(uuid,text)` | Retorna `state = failed`, libera a reivindicação e não acrescenta término nem recebe texto técnico de erro. |

O token é segredo sigiloso vinculado ao trabalho: o banco persiste apenas seu digest SHA-256. Não o registre em logs, URLs ou respostas da API. Operações exigem reivindicação vigente; em trabalho longo, renove antes de expirar. Após falha, um novo claim preserva `failed` até `processor_start`; renovar a lease não apaga a falha. Após expiração ou perda de confirmação, reivindicar um trabalho `succeeded` serve apenas para recuperar a confirmação dos marcos existentes: não reexecute a coleta, não crie outros marcos nem faça o estado regredir. Uma lease ativa impede reivindicação concorrente.

O tenant e as referências dos marcos derivam do trabalho persistido, não de tenant ou contexto enviado pelo processador. Bloqueio do estado por trabalho, unicidade de `(job_id, event_type)` e transação conjunta de marco e estado sustentam a atomicidade e a idempotência da fronteira; falha ou interrupção não vira término. RLS forçado e privilégios explícitos protegem contra operações normais de leitura cruzada, inserção direta, alteração, exclusão e `TRUNCATE`; não prometem imutabilidade contra o proprietário de migration ou superusuários. A role do processador usa somente as funções controladas, sem acesso direto às tabelas.

**Verificação histórica do Escrevente, anterior à consolidação:** em PostgreSQL 18.6 isolado, a migration então vigente e seu rollback foram exercitados com roles reais separadas. Os testes específicos passaram com **29 testes e 813 assertions**; a suíte completa passou com **276 testes e 7.678 assertions**, sem falhas, erros ou skips. Um smoke SQL e HTTP na imagem final da API confirmou marcos de início/término no sucesso, início sem término na falha, estado separado e negação de acesso cruzado. A API executou como UID/GID `1000:1000`, o PostgreSQL como `70:70`; a imagem final da API mediu **263.242.962 bytes**. As chamadas de coleta foram controladas para teste: não comprovam execução de ETL ou consulta real ao DJEN. O rollback citado pertence à migration anterior, não à estrutura consolidada.

### Imagens Docker da API e do despachante

As duas imagens já são definidas no mesmo [`backend/Dockerfile`](backend/Dockerfile), por targets independentes. Não existe um Dockerfile separado em `backend/despachante/`; ele não é necessário para gerar uma imagem exclusiva do despachante.

| Componente | Target | Base final | Usuário final | Comando da imagem |
|---|---|---|---|---|
| API Rails | `runtime` | `ruby:4.0.9-alpine3.23` | `1000:1000` | `bundle exec puma -C config/puma.rb` |
| Despachante | `despachante` | `ruby:4.0.9-alpine3.23` | `1000:1000` | `ruby despachante/run.rb` |

Os builds são multi-stage: o despachante usa os estágios `despachante_base` e `despachante_dependencies` antes do target final `despachante`. A instalação de pacotes de compilação ocorre nos estágios de build, sem levar compiladores para as imagens finais. O uso de root durante a construção não é um entrypoint privilegiado: ambas as imagens iniciam diretamente como usuário não root, sem instalar pacotes, corrigir permissões ou executar migrations no startup.

Construa a API, a partir da raiz do monorepo, com `docker build --target runtime -t advocacia-backend:local backend`. Neste ambiente, o build precisou de `--network host` para resolver dependências devido ao DNS da rede Docker. O comando de build do despachante está abaixo; nenhum deles depende de um frontend implementado.

**Migrations iniciais consolidadas — banco inicial vazio:** `20261028000000_create_identity_and_lawyer_profiles.rb` define o schema atual de identidade; `20261028000005_create_team_credentials.rb` e `20261028000006_create_authorization_groups.rb` acrescentam credenciais e grupos. `20261028000003_create_collection_planning.rb` integra as antigas migrations 04–06; `20261028000004_create_escrevente.rb` substitui a antiga 07. O deploy futuro continua condicionado ao procedimento próprio e às permissões necessárias.

Essas migrations não oferecem rollback destrutivo nem upgrade automático de banco pré-existente. Um banco descartável de desenvolvimento criado pela sequência anterior precisa ser recriado explicitamente antes de receber a sequência consolidada; não aplique as migrations consolidadas sobre o schema antigo nem use os relatos históricos de `db:rollback` abaixo como instrução atual. O uso futuro da instância PostgreSQL do servidor de deploy continua condicionado a um procedimento próprio, ainda não definido.

Para um banco inicial vazio, um administrador deve executar [`backend/db/provision.sql`](backend/db/provision.sql), [`backend/db/provision_despachante.sql`](backend/db/provision_despachante.sql) e [`backend/db/provision_processador.sql`](backend/db/provision_processador.sql), nessa ordem, no banco da aplicação, antes das migrations, e configurar credenciais SCRAM fora do repositório. A role `advocacia_migrator` é proprietária das tabelas migradas e executa migrations; `advocacia_runtime` executa a API; `advocacia_despachante` pertence somente ao processo confiável de planejamento e pode ler os monitoramentos dos tenants para gerar o trabalho; `advocacia_processador` é exclusiva do executor e dos testes de fronteira, sem membros, memberships ou acesso direto às tabelas. Runtime, despachante e processador não são donos das tabelas; nenhuma das quatro roles possui `BYPASSRLS`. A API não recebe as credenciais do despachante, do processador ou de migration; o despachante nunca recebe `PROCESSADOR_DATABASE_URL`.

**Registro histórico do corte de nomes (anterior à consolidação; não é procedimento atual de instalação ou upgrade):**

1. O componente antigo (`planner`/planejador) era parado, com reinício pelo supervisor impedido. A versão antiga não podia executar junto com o despachante.
2. Antes de publicar a release daquela entrega ou executar suas migrations, o procedimento exigia que um administrador executasse [`backend/db/rename_despachante.sql`](backend/db/rename_despachante.sql) no banco da aplicação. A conexão administrativa precisava dos privilégios de gerenciamento da role e das políticas exigidos pelo script, sem usar a credencial da API nem a do despachante. A role é global ao cluster, mas as políticas pertencem a cada banco; o corte abrangia cada banco da aplicação que compartilhasse essa role.
3. O script renomeava `advocacia_planner` para `advocacia_despachante` e o prefixo de políticas `collection_planner_` para `collection_despachante_`, preservando o OID e as permissões da role. Se as duas roles já existissem, nenhuma existisse ou houvesse colisão de nomes de políticas na mesma tabela, o script abortava sem aplicar mudanças parciais e exigia resolução administrativa do conflito antes de repetir o corte.
4. O roteiro exigia atualizar o login da URL de conexão para `advocacia_despachante`, substituir `PLANNER_DATABASE_URL` por `DESPACHANTE_DATABASE_URL` e atualizar os arquivos de ambiente protegidos e o gerenciador de segredos. Uma senha SCRAM existente podia ser mantida. Credenciais MD5 antigas dependem do nome da role e são invalidadas pelo PostgreSQL ao renomeá-la; a orientação era convertê-las para SCRAM externamente antes do corte ou redefini-las externamente antes de reiniciar o processo, sem registrar senhas no repositório.
5. Só então se aplicavam as migrations vigentes naquela entrega e se iniciava o despachante com target, imagem, caminhos e configuração novos, removendo as referências antigas de automações e supervisores. Não havia variável alternativa, alias de classe, target de compatibilidade ou caminho legado. Esse passo histórico não autoriza aplicar a sequência consolidada a um banco pré-existente.

O corte de nomes trocou o módulo `escriba`/Escriba por `escrevente`/Escrevente e moveu `SPEC-escriba.md` para [`SPEC-escrevente.md`](SPEC-escrevente.md), sem arquivo de redirecionamento ou alias. Naquela entrega, o Escrevente era apenas documental. Posteriormente foi implementado no backend Rails, sem ações de usuários nem detalhes de erros, com as verificações históricas descritas acima.


Forneça as variáveis por arquivos de ambiente protegidos ou pelo gerenciador de segredos do ambiente. Em uma rede Docker que alcance o PostgreSQL, execute `docker run --rm --env-file <arquivo-de-migration> --entrypoint ruby advocacia-backend:local bin/migrate` separadamente; o arquivo de migration deve conter `MIGRATION_DATABASE_URL` e as demais variáveis necessárias ao boot. Inicie a API com `docker run --rm --env-file <arquivo-da-api> -p 3000:3000 advocacia-backend:local`, fornecendo apenas a URL da role runtime. Coloque a API atrás de terminação HTTPS compatível com `APP_ORIGIN`; nunca exponha `MIGRATION_DATABASE_URL` ao processo web.

Construa o processo separado com `docker build --target despachante -t advocacia-despachante:local backend` e inicie-o com `docker run --rm --env-file <arquivo-do-despachante> advocacia-despachante:local` em uma rede que alcance o PostgreSQL e o DJEN. O arquivo deve fornecer `DESPACHANTE_DATABASE_URL`, `COLETA_HORARIO_1` e `COLETA_HORARIO_2`; não forneça credenciais da API, do Google ou de migration. O processo reconcilia os dois horários do dia local e registra falha do catálogo; após indisponibilidade, espera pelo menos 60 segundos antes de nova requisição. Configure um supervisor de implantação para reiniciar o processo caso ele termine por erro inesperado.

O PostgreSQL local de teste é separado e não se destina ao deploy. Para verificá-lo nesta máquina, foi iniciada a imagem `postgres:18.6-alpine3.23` diretamente como UID 70, com diretório de dados previamente preparado; uma linha persistiu após parada e reinício.

Durante o desenvolvimento, as requisições ao DJEN utilizam o nó de saída Tailscale `100.118.186.77`. Em produção, Tailscale não é requisito: o tráfego usa a saída normal da infraestrutura de deploy.

### Verificações da renomeação para despachante e Escrevente

Estas evidências pertencem à entrega de renomeação, anterior à consolidação das migrations; não são resultados desta alteração.

- Os targets `runtime`, `despachante` e `test` foram construídos com os caminhos novos. A suíte completa executou com `DESPACHANTE_DATABASE_URL` e a role real `advocacia_despachante`: **247 testes, 6.865 assertions, sem falhas, erros ou skips**.
- Em PostgreSQL descartável, o corte de um esquema legado preservou o OID e os atributos da role, os OIDs/alvos/expressões das 12 políticas e uma execução sentinela. Roles ambíguas e colisão de política abortaram com rollback integral; a credencial de migration foi recusada no script administrativo. Reaplicar o corte sobre o estado novo não alterou dados.
- As migrations vigentes naquela entrega também foram aplicadas a um banco sem tabelas. Os quatro down paths afetados foram exercitados com `db:rollback STEP=4`, seguidos de `db:migrate`, usando a role de migration e sem alterar dados de produção. Esse registro não descreve os down paths da sequência consolidada, que não suporta rollback destrutivo.
- A imagem final do despachante executou `CollectionDespachante` contra PostgreSQL, com catálogo local explicitamente fornecido, e persistiu dois slots `no_work` em banco sem entidades. O CMD real `ruby despachante/run.rb` iniciou como PID 1 com UID/GID `1000:1000` e reutilizou os slots concluídos sem carregar Rails. Isso verifica planejamento e execução independente, não ETL nem conectividade DJEN.
- A imagem final da API iniciou Puma em produção como UID/GID `1000:1000`; uma requisição HTTP no loopback do próprio container a `GET /api/session` retornou `200` com `authenticated: false` e `onboarded: false`. Nos dois runtimes não foram encontrados `gcc`, `g++`, `cc`, `make`, arquivos de cache de gems ou `/app/test`.
- Limites desta verificação: uma tentativa de smoke com catálogo DJEN real excedeu 90 segundos e foi encerrada; o acesso HTTP pela porta publicada no host também excedeu o timeout. Não se declara conectividade externa nem acesso pela porta publicada como aprovados nesta revisão. O smoke HTTP aprovado ocorreu dentro do container; o smoke de planejamento aprovado usou catálogo local explícito.
- A especificação passou a ser `SPEC-escrevente.md`, com ID `escrevente`; seus links e os links novos do despachante foram verificados naquela entrega. Na entrega de renomeação, o Escrevente permanecia documental, sem implementação de runtime; essa evidência histórica não abrange a implementação atual em andamento.

| Imagem verificada | Tamanho local em bytes |
|---|---|
| `advocacia-backend:local` | 263.216.146 |
| `advocacia-despachante:local` | 176.460.209 |
| Base `ruby:4.0.9-alpine3.23` | 147.221.451 |

A base Alpine continua escolhida pelo tamanho reduzido com suporte ao Ruby e às dependências nativas utilizadas; os compiladores ficam somente nos estágios de build, e a imagem do despachante mantém bundle próprio sem Rails.

### Verificações históricas anteriores à renomeação

As evidências abaixo foram registradas antes da renomeação dos componentes e da consolidação das migrations. Elas preservam o histórico, mas não comprovam a sequência consolidada, o build, os tamanhos nem a execução dos artefatos renomeados; esses pontos exigem nova verificação em Docker.

- As migrations foram executadas no PostgreSQL de teste com a role de migration. A suíte completa da imagem de testes passou com roles reais separadas: **247 testes, 6.865 assertions, sem falhas, erros ou skips**.
- A imagem runtime iniciou o Puma como UID 1000. Um smoke HTTP real verificou negação anônima, criação e leitura de dois perfis com tenants distintos, OAB principal sem secundárias e resistência a tenant adulterado. As sessões foram criadas diretamente para o teste; isso não é um teste de login Google real.
- Tamanhos históricos, medidos antes da renomeação: imagem da API **263.210.704 bytes**, imagem do processo separado de planejamento **176.460.240 bytes**, base `ruby:4.0.9-alpine3.23` **147.221.451 bytes**, PostgreSQL de teste `postgres:18.6-alpine3.23` **429.615.951 bytes**. Alpine reduz a base mantendo compatibilidade Ruby e nativa; compiladores ficam fora das imagens finais. O despachante possui manifesto e bundle próprios, sem as gems Rails da API.
- Na revisão anterior à renomeação, a reinspeção das duas imagens locais confirmou os tamanhos históricos acima, usuário configurado `1000:1000` e comandos distintos. Um smoke em containers descartáveis, com filesystem somente leitura, `/tmp` temporário, sem rede, sem capabilities e com `no-new-privileges`, confirmou UID/GID reais `1000:1000`, carregamento de Rails/Puma na API e do runner Ruby com `pg` no processo separado de planejamento então vigente. Não foram encontrados `gcc`, `g++`, `cc`, `make`, arquivos no cache de gems ou `/app/test`; o bundle desse processo não continha Rails. Esse smoke não iniciou o servidor HTTP nem executou planejamento contra banco ou DJEN, e não exercitou `DespachanteRunner` nem a imagem renomeada.
- O fluxo Google com credenciais reais e a URI HTTPS registrada ainda não foi exercitado: depende de configuração OAuth externa. Os testes automatizados usam tokens assinados de teste e substituem apenas a comunicação externa do provedor.
- A imagem runtime consultou por HTTPS as chaves públicas reais do Google e recebeu duas chaves RSA; essa verificação de conectividade não substitui a autenticação com credenciais reais.
- Os testes focados de catálogo e projeção do advogado passaram com 24 testes; partes, com 47; processos, com 63. Um smoke HTTP na imagem runtime consultou o catálogo DJEN real e criou, leu, editou e desativou ambos os tipos em dois tenants, negando acesso cruzado. As sessões desse smoke foram preparadas para teste, sem login Google real.
- Em 28/10/2026, o catálogo real retornou 93 códigos validados. A [OpenAPI do DJEN](https://comunicaapi.pje.jus.br/swagger/djen.yml) descreve uma lista plana, enquanto a resposta observada agrupa instituições por UF; o cliente aceita ambos os formatos e rejeita resposta parcial inválida.
- Antes da renomeação, em banco local separado, o processo de planejamento da imagem final então vigente consultou o DJEN real e gerou os dois slots do dia. A API confirmou, para dois tenants, trabalhos de advogado, parte e processo com meios `D`/`E`, critérios fixados e isolamento cruzado. Os processos web e de planejamento executaram como UID 1000 e o PostgreSQL como UID 70. Isso verificou planejamento, não execução da coleta nem a imagem renomeada.
