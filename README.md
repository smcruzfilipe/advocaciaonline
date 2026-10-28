# Monitoramento jurídico

Plataforma de monitoramento de publicações judiciais voltada a advogados independentes e suas equipes. A fonte inicial prevista é o Diário de Justiça Eletrônico Nacional (DJEN), com consulta a cadernos como caminho principal e à API paginada de comunicações como fallback.

> **Estado atual:** o backend contém onboarding, cadastros de monitoramento e geração de planos de coleta. Frontend, equipe/grupos, Escriba, execução da coleta, dashboard e Swagger UI ainda não estão implementados.

## Escopo funcional

- Login Google para advogado e equipe; o contrato de identidade não prevê senha local para usuários da aplicação.
- Isolamento por tenant do advogado, autorização por grupos e tribunal, monitoramentos de advogados/partes/processos e consulta de comunicações.
- Coleta diária do DJEN, com cadernos como fonte principal, API paginada como fallback e deduplicação pela combinação de `id` e `hash`.
- Dashboard e registros append-only do fluxo de coleta.

O mapa de módulos e a ordem de dependências estão em [`CAPABILITIES.md`](CAPABILITIES.md). Requisitos detalhados: [`docs/especificacao.md`](docs/especificacao.md) e as seis especificações `SPEC-*.md` na raiz.

## Stack definida

- API central: Ruby on Rails, exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).

O projeto é um monorepo. As imagens de frontend e backend serão separadas; a imagem PostgreSQL será usada somente para testes locais. No deploy, a aplicação usará a instância PostgreSQL já existente no servidor. A criação do banco da aplicação e as migrations nessa instância dependem das permissões e do procedimento de deploy, ainda não definidos. Todas as imagens deverão ser mínimas e executar sem root, conforme [`AGENTS.md`](AGENTS.md).

Versões de referência e limites da decisão: [`docs/stack.md`](docs/stack.md). Estrutura e ferramentas propostas para os demais componentes estão em [`docs/arquitetura.md`](docs/arquitetura.md).

## Swagger UI e acesso à documentação

Requisito registrado: a documentação interativa da API será publicada com Swagger UI e protegida por login e senha. O contrato proposto usa autenticação HTTP Basic separada do login Google, exclusivamente por HTTPS, conforme [`docs/arquitetura.md`](docs/arquitetura.md#identidade-convites-e-documentação). O Swagger UI ainda não existe; não há usuário ou senha padrão, nem credenciais versionadas.

## Variáveis de ambiente

As variáveis abaixo são lidas pelo backend ou configuradas em sua imagem. Forneça valores sem default pelo gerenciador de segredos ou ambiente do deploy; não versione credenciais nem URLs contendo senhas. As credenciais Google exigem um cliente OAuth web registrado externamente, com URI de redirecionamento exatamente `APP_ORIGIN/auth/google/callback`.

| Variável | Default | Obrigatória? | Finalidade |
|---|---|---|---|
| `DATABASE_URL` | Nenhum | Sim, para API e testes | Conexão PostgreSQL com a role `advocacia_runtime`, sem propriedade das tabelas nem bypass de RLS. |
| `MIGRATION_DATABASE_URL` | Nenhum | Sim, para migration e teste administrativo de sessão; não fornecer à API web | Conexão com `advocacia_migrator`, separada da role de execução. |
| `PLANNER_DATABASE_URL` | Nenhum | Sim, no planejador e nos testes do planejador; não fornecer à API web | Conexão PostgreSQL da role `advocacia_planner`, exclusiva do processo confiável de planejamento. |
| `COLETA_HORARIO_1` | Nenhum | Sim, no planejador | Primeiro horário diário em `HH:MM`, fuso `America/Sao_Paulo`, a partir de `04:00`; fornecer pela configuração do processo. |
| `COLETA_HORARIO_2` | Nenhum | Sim, no planejador | Segundo horário diário em `HH:MM`, posterior ao primeiro; fornecer pela configuração do processo. |
| `APP_ORIGIN` | Nenhum | Sim, para API, migration e testes Rails; não é usada pelo planejador | Origem pública HTTPS da API, sem caminho ou credenciais; valida origem de operações mutáveis e compõe o callback Google. |
| `GOOGLE_CLIENT_ID` | Nenhum | Sim, para autenticação Google | Identificador do cliente OAuth web. |
| `GOOGLE_CLIENT_SECRET` | Nenhum | Sim, para autenticação Google | Segredo do cliente OAuth web; fornecer por mecanismo de segredos. |
| `SECRET_KEY_BASE` | Nenhum | Sim, para API, migration e testes Rails; não é usada pelo planejador | Segredo Rails usado para proteção de tentativas de autenticação; gerar e fornecer externamente. |
| `RAILS_ENV` | `production` na imagem runtime; `test` na imagem de testes | Não | Seleciona o ambiente Rails. |
| `RAILS_LOG_LEVEL` | `info` | Não | Nível de logging. |
| `PORT` | `3000` | Não | Porta do servidor Puma. |
| `RAILS_MAX_THREADS` | `5` | Não | Número de threads Puma e tamanho do pool de conexões PostgreSQL. |
| `BUNDLE_PATH` | `/bundle` na imagem | Não | Diretório das gems na imagem. |
| `BUNDLE_FROZEN` | `true` na imagem | Não | Impede alteração do lockfile pelo Bundler. |
| `BUNDLE_DEPLOYMENT` | `true` na imagem | Não | Ativa o modo de implantação do Bundler. |
| `BUNDLE_WITHOUT` | `test` no runtime; vazio no target de testes | Não | Exclui as dependências de testes da imagem de execução. |
| `BUNDLE_GEMFILE` | `/app/planner/Gemfile` na imagem do planejador; caminho do `Gemfile` da API no boot Rails | Não | Seleciona o manifesto próprio de dependências de cada processo. |
| `HOME` | `/home/app` na imagem | Não | Diretório inicial do usuário não root da imagem. |

Configurações futuras, ainda não implementadas: `COLETA_TENTATIVAS_POR_CAMINHO` terá default `3`, `COLETA_BACKOFF_APOS_FALHA_1_SEGUNDOS` default `60` e `COLETA_BACKOFF_APOS_FALHA_2_SEGUNDOS` default `300`, conforme [`SPEC-coleta.md`](SPEC-coleta.md). Não há prazo automático de retenção do Escriba nesta etapa. As configurações de SMTP e Swagger permanecem por nomear.

**Regra de manutenção:** toda variável de ambiente introduzida ou alterada em uma implementação deve ser registrada nesta seção do README no mesmo conjunto de mudanças. Para cada variável, informe nome exato, valor default (ou `Nenhum` se não houver), se é obrigatória e para que serve. Quando não existir default, documente também como fornecer o valor sem incluir segredos. Atualize a tabela ao remover variáveis.

## Documentação do projeto

- [Especificação geral](docs/especificacao.md)
- [Stack e versões de referência](docs/stack.md)
- [Arquitetura e contratos técnicos propostos](docs/arquitetura.md)
- [Mapa de capacidades](CAPABILITIES.md)
- [Plano de implementação e gates](tasks/plan.md)
- [Checklist de implementação](tasks/todo.md)
- [Contrato OpenAPI do DJEN consultado](docs/contrato-djen.md)

## Implementação e verificações

### API de onboarding

| Método e caminho | Comportamento |
|---|---|
| `GET /auth/google` | Inicia autenticação Google por authorization code com PKCE. |
| `GET /auth/google/callback` | Valida o retorno Google e cria sessão; sucesso devolve JSON, falha devolve `401`. |
| `GET /api/session` | Informa se há sessão autenticada, se o onboarding foi concluído e, quando autenticada, o token CSRF. |
| `POST /api/onboarding` | Cria perfil e tenant do advogado autenticado. Exige `Origin` igual a `APP_ORIGIN` e `X-CSRF-Token` da sessão. |
| `GET /api/onboarding` | Retorna o perfil, inscrições e tenant associados à sessão, sem aceitar seleção de tenant pelo cliente. |

O corpo do POST contém `full_name`, `primary_oab` com `number` e `uf`, `secondary_oabs` como lista e `office_name` opcional. A OAB principal é obrigatória; as secundárias podem ser uma lista vazia. O número é textual para preservar zeros e sufixos. Não se confunde escritório com tenant.

### API de monitoramentos

As operações abaixo exigem sessão válida; alterações exigem também `Origin` e `X-CSRF-Token`. O tenant vem da sessão, nunca do corpo ou da query. Por enquanto, só existem sessões do advogado titular: antes de habilitar usuários de equipe, estas rotas precisam integrar as regras de autorização por grupos.

| Método e caminho | Comportamento |
|---|---|
| `GET /api/courts` | Consulta o catálogo atual de tribunais do DJEN; falha da fonte retorna `503`, sem substituir o catálogo por lista inventada. |
| `GET /api/monitorings/lawyer` | Retorna o perfil e as OABs do advogado titular como entidade monitorada, sem duplicar seu cadastro. |
| `GET`, `POST /api/monitorings/parties` | Lista ou cadastra partes do tenant. |
| `GET`, `PATCH /api/monitorings/parties/:id` | Lê, edita, desativa ou reativa uma parte do tenant. |
| `GET`, `POST /api/monitorings/processes` | Lista ou cadastra processos do tenant. |
| `GET`, `PATCH /api/monitorings/processes/:id` | Lê, edita, desativa ou reativa um processo do tenant. |

No cadastro de parte, `name` é obrigatório e sua chave de equivalência ignora caixa, diacríticos e espaços excedentes, mantendo pontuação significativa. A chave canônica aceita até 2.000 bytes; entradas maiores retornam `422`, evitando exceder o limite do índice PostgreSQL. No cadastro de processo, `number` aceita 20 dígitos ASCII ou a máscara CNJ; a resposta preserva os 20 dígitos e zeros iniciais. Duplicatas no mesmo tenant geram conflito mesmo quando desativadas. `courts` ausente ou `null` significa todos os tribunais disponíveis; uma lista explícita deve ser não vazia e conter somente códigos do catálogo atual. A seleção salva não é ampliada se um tribunal deixar de estar disponível.

### Planejamento de coleta

O planejador é um processo separado da API: usa uma conexão PostgreSQL exclusiva, consulta o catálogo DJEN e registra uma execução por data de Brasília e horário configurado. Para cada advogado, parte e processo elegível, fixa os critérios e gera trabalhos por tribunal e meio `D`/`E`. Editar ou desativar um cadastro posteriormente não altera o plano já registrado. A leitura da API é limitada ao tenant autenticado:

| Método e caminho | Comportamento |
|---|---|
| `GET /api/collection-runs` | Lista as execuções cuja audiência inclui o tenant da sessão. |
| `GET /api/collection-runs/:id/jobs` | Lista os trabalhos do tenant para uma execução autorizada. |

`planned` indica planejamento concluído; `no_work` indica que não houve trabalho elegível; `planning_failed` indica falha do planejamento; `interrupted` identifica planejamento não recuperado após a virada da data local. Nenhum desses estados significa que uma coleta de publicações foi executada ou que ela encontrou zero resultados. Os trabalhos são criados como `pending`; o ETL e a execução da coleta ainda não estão implementados.

### Imagem e banco

Construa a imagem com `docker build --target runtime -t advocacia-backend:local backend`. A imagem usa Ruby 4.0.9 sobre Alpine 3.23; as ferramentas de compilação ficam no estágio de build. O processo web inicia como UID/GID `1000:1000` e não executa migrations automaticamente. Neste ambiente, o build precisou de `--network host` para resolver dependências devido ao DNS da rede Docker.

Use a instância PostgreSQL já existente no servidor de deploy. Um administrador deve executar [`backend/db/provision.sql`](backend/db/provision.sql) e [`backend/db/provision_planner.sql`](backend/db/provision_planner.sql), nessa ordem, no banco da aplicação e configurar credenciais SCRAM fora do repositório. A role `advocacia_migrator` é proprietária das tabelas migradas e executa migrations; `advocacia_runtime` executa a API; `advocacia_planner` pertence somente ao processo confiável de planejamento e pode ler os monitoramentos dos tenants para gerar o trabalho. Runtime e planner não são donos das tabelas; nenhuma das três roles possui `BYPASSRLS`. A API não recebe a credencial do planejador nem a de migration. O provisionamento e a criação do banco no servidor dependem das permissões e do procedimento de deploy.

Forneça as variáveis por arquivos de ambiente protegidos ou pelo gerenciador de segredos do ambiente. Em uma rede Docker que alcance o PostgreSQL, execute `docker run --rm --env-file <arquivo-de-migration> --entrypoint ruby advocacia-backend:local bin/migrate` separadamente; o arquivo de migration deve conter `MIGRATION_DATABASE_URL` e as demais variáveis necessárias ao boot. Inicie a API com `docker run --rm --env-file <arquivo-da-api> -p 3000:3000 advocacia-backend:local`, fornecendo apenas a URL da role runtime. Coloque a API atrás de terminação HTTPS compatível com `APP_ORIGIN`; nunca exponha `MIGRATION_DATABASE_URL` ao processo web.

Construa o processo separado com `docker build --target planner -t advocacia-planner:local backend` e inicie-o com `docker run --rm --env-file <arquivo-do-planejador> advocacia-planner:local` em uma rede que alcance o PostgreSQL e o DJEN. O arquivo deve fornecer `PLANNER_DATABASE_URL`, `COLETA_HORARIO_1` e `COLETA_HORARIO_2`; não forneça credenciais da API, do Google ou de migration. O processo reconcilia os dois horários do dia local e registra falha do catálogo; após indisponibilidade, espera pelo menos 60 segundos antes de nova requisição. Configure um supervisor de implantação para reiniciar o processo caso ele termine por erro inesperado.

O PostgreSQL local de teste é separado e não se destina ao deploy. Para verificá-lo nesta máquina, foi iniciada a imagem `postgres:18.6-alpine3.23` diretamente como UID 70, com diretório de dados previamente preparado; uma linha persistiu após parada e reinício.

Durante o desenvolvimento, as requisições ao DJEN utilizam o nó de saída Tailscale `100.118.186.77`. Em produção, Tailscale não é requisito: o tráfego usa a saída normal da infraestrutura de deploy.

### Verificações desta fatia

- As migrations foram executadas no PostgreSQL de teste com a role de migration. A suíte completa da imagem de testes passou com roles reais separadas: **247 testes, 6.865 assertions, sem falhas, erros ou skips**.
- A imagem runtime iniciou o Puma como UID 1000. Um smoke HTTP real verificou negação anônima, criação e leitura de dois perfis com tenants distintos, OAB principal sem secundárias e resistência a tenant adulterado. As sessões foram criadas diretamente para o teste; isso não é um teste de login Google real.
- Tamanhos locais: imagem da API **263.210.704 bytes**, imagem do planejador **176.460.240 bytes**, base `ruby:4.0.9-alpine3.23` **147.221.451 bytes**, PostgreSQL de teste `postgres:18.6-alpine3.23` **429.615.951 bytes**. Alpine reduz a base mantendo compatibilidade Ruby e nativa; compiladores ficam fora das imagens finais. O planejador possui manifesto e bundle próprios, sem as gems Rails da API.
- O fluxo Google com credenciais reais e a URI HTTPS registrada ainda não foi exercitado: depende de configuração OAuth externa. Os testes automatizados usam tokens assinados de teste e substituem apenas a comunicação externa do provedor.
- A imagem runtime consultou por HTTPS as chaves públicas reais do Google e recebeu duas chaves RSA; essa verificação de conectividade não substitui a autenticação com credenciais reais.
- Os testes focados de catálogo e projeção do advogado passaram com 24 testes; partes, com 47; processos, com 63. Um smoke HTTP na imagem runtime consultou o catálogo DJEN real e criou, leu, editou e desativou ambos os tipos em dois tenants, negando acesso cruzado. As sessões desse smoke foram preparadas para teste, sem login Google real.
- Em 28/10/2026, o catálogo real retornou 93 códigos validados. A [OpenAPI do DJEN](https://comunicaapi.pje.jus.br/swagger/djen.yml) descreve uma lista plana, enquanto a resposta observada agrupa instituições por UF; o cliente aceita ambos os formatos e rejeita resposta parcial inválida.
- Em banco local separado, o planejador da imagem final consultou o DJEN real e gerou os dois slots do dia. A API confirmou, para dois tenants, trabalhos de advogado, parte e processo com meios `D`/`E`, critérios fixados e isolamento cruzado. Os processos web e planner executaram como UID 1000 e o PostgreSQL como UID 70. Isso verifica planejamento, não execução da coleta.
