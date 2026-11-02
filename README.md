# Monitoramento jurídico — monorepo

Monorepo da plataforma de monitoramento de publicações judiciais voltada a advogados independentes e suas equipes, reunindo backend Rails API-only e frontend Next.js no mesmo repositório. A fonte inicial é o Diário de Justiça Eletrônico Nacional (DJEN), exclusivamente Diário Eletrônico (`D`), sem coleta de editais (`E`): na primeira coleta, cadernos com fallback paginado; na segunda, API paginada diretamente.

> **Estado atual:** o backend contém identidade, autorização, monitoramentos, coleta, consulta e dashboard. A interface Next.js fica em `apps/web/`; o Swagger UI ainda não está implementado.

## Estrutura do monorepo

A raiz é compartilhada pelo produto inteiro; não é a raiz de uma aplicação Rails nem de uma aplicação Next.js isolada. Cada componente mantém suas dependências, comandos e artefatos de execução.

| Caminho relativo à raiz | Responsabilidade | Situação |
|---|---|---|
| `apps/backend/` | API Rails, domínio, persistência e testes; dependências em `apps/backend/Gemfile` e `apps/backend/Gemfile.lock`. | Existente. |
| `apps/backend/despachante/` | Despachante de coletas, processo Ruby separado da API, com `Gemfile` e lockfile próprios. | Existente; pertence ao backend e ao mesmo monorepo, mas não executa dentro do servidor Rails. |
| `apps/web/` | Interface Next.js com TypeScript e App Router; páginas, componentes e estilos do produto. | Existente. |
| `apps/etl/` | Execução da coleta, em processo separado da API e do despachante. | Existente; processador automático com retomada. |
| `apps/stf/` | Coletor HTTP e processador dos andamentos STF, separados de DJEN/API, com dependências e imagem próprias. | Fonte `STF`, meio `A`; trabalhos duráveis, capturas e vínculos no PostgreSQL compartilhado. |
| `docs/` | Especificação geral, arquitetura, contratos técnicos e direção visual compartilhados. | Existente. |
| `tasks/` | Plano, gates e checklist de implementação do monorepo. | Existente. |
| `SPEC-*.md` e `CAPABILITIES.md` | Contratos funcionais e mapa de capacidades do produto. | Existentes na raiz. |

Frontend e API têm imagens Docker separadas. O despachante tem target próprio `despachante` em `apps/backend/Dockerfile`; o target da API é `runtime`. Processos e imagens separados não significam repositórios separados. PostgreSQL é infraestrutura compartilhada: imagem separada somente para testes locais e instância já existente no deploy.

A [arquitetura](docs/arquitetura.md#estrutura-do-monorepo-e-fronteiras) detalha as fronteiras. O [guia visual](docs/design-system.md#escopo-no-monorepo) orienta a interface de `apps/web/`, não uma aplicação independente deste repositório.

## Escopo funcional

- Login comum com senha e TOTP; painel administrativo em `/admin/convites` para convidar advogados por e-mail ou copiar o link. Cadastro de advogado exclusivamente por convite, sem confirmação adicional de caixa postal; equipe exige convite e confirmação real do e-mail.
- Isolamento por tenant do advogado, autorização por grupos e tribunal, monitoramentos de advogados/partes/processos e consulta de comunicações.
- Duas coletas diárias do DJEN, somente Diário Eletrônico (`D`), sem editais (`E`): cadernos e fallback paginado na primeira execução, API paginada diretamente na segunda e deduplicação pela combinação de `id` e `hash`.
- Acompanhamento STF: descoberta JSON de processos explicitamente em tramitação, extração HTTP dos andamentos da data corrente em Brasília e persistência de dados/origem/links. Contrato próprio em [SPEC-stf.md](SPEC-stf.md), sem deduplicação fictícia por ID de documento.
- Dashboard e registros append-only do fluxo de coleta.

O mapa de módulos e a ordem de dependências estão em [`CAPABILITIES.md`](CAPABILITIES.md). Requisitos detalhados: [`docs/especificacao.md`](docs/especificacao.md) e as seis especificações `SPEC-*.md` na raiz.

## Stack definida

- API central: Ruby on Rails, exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).

O projeto é um monorepo. As imagens de frontend e backend são separadas; a imagem PostgreSQL do Compose é exclusiva da validação local. No deploy, a aplicação usará a instância PostgreSQL já existente no servidor. A criação do banco da aplicação e as migrations nessa instância dependem das permissões e do procedimento de deploy, ainda não definidos. Os processos dos containers locais executam sem root, conforme [`AGENTS.md`](AGENTS.md).

Versões de referência e limites da decisão: [`docs/stack.md`](docs/stack.md). Estrutura e ferramentas propostas para os demais componentes estão em [`docs/arquitetura.md`](docs/arquitetura.md).

## Execução local pela Tailscale

O `compose.yaml` é **somente local**, não um procedimento de deploy. Sobe PostgreSQL isolado, migration de execução única, API Rails, frontend Next.js standalone e ingresso Nginx HTTPS. Não inicia despachante nem processador de coletas, não cria dados demonstrativos e não oferece bypass de login.

Pré-requisitos: Docker com Compose v2.24 ou superior, OpenSSL, Tailscale conectado com MagicDNS/HTTPS habilitados e permissão para `tailscale cert` (ou sudo). A chave TLS precisa ser legível pelo UID 1000 do ingresso; nesta máquina o usuário local também tem UID 1000.

```bash
bash bin/local-up apps-contabo.tail519952.ts.net 3001
```

Acesso nesta máquina: **https://apps-contabo.tail519952.ts.net:3001/login**. Abra pelo nome DNS em outra máquina da mesma tailnet; o certificado não cobre o IP numérico. A porta HTTPS é publicada em **`0.0.0.0:3001`**, inclusive nas interfaces externas, sujeita ao firewall; isso não restringe o acesso à Tailscale. API e PostgreSQL não publicam portas. O frontend escuta internamente em `0.0.0.0:3000`, acessível externamente apenas pelo ingresso HTTPS.

O script gera segredos aleatórios uma única vez em `.local/compose.env`, arquivo privado ignorado pelo Git. Não apague esse arquivo ao reiniciar: as senhas precisam continuar correspondendo ao volume existente. O PostgreSQL inicializa diretamente como UID/GID `70:70` com SCRAM para conexões de rede; o volume `advocacia-local_postgres` herda as permissões preparadas na imagem. API e migration recebem somente suas próprias credenciais. Os demais containers executam como `1000:1000`, sem capabilities e sem escalada de privilégios.

Para cadastro, redefinição de senha e convites, forneça as cinco variáveis `SMTP_*` documentadas abaixo em `.local/integrations.env`. Proteja o arquivo com `chmod 600 .local/integrations.env`; não versione nem publique seus valores. Sem SMTP, a confirmação do e-mail, a recuperação de senha e o envio de convites não funcionam.

Para [Resend via SMTP](https://resend.com/docs/send-with-smtp), use `SMTP_HOST=smtp.resend.com`, `SMTP_PORT=587` (STARTTLS), `SMTP_USERNAME=resend` e **a chave de API como `SMTP_PASSWORD`**. `SMTP_FROM` deve ser um remetente autorizado no domínio verificado do Resend, independentemente do e-mail de login ou do destinatário. No ambiente local, o remetente é `contato@informacao.verticesolucoes.tec.br`, cujo subdomínio foi confirmado como verificado no provedor. Não é preciso outro login/senha do provedor, SDK ou variável `RESEND_API_KEY`; mantenha a chave apenas na configuração protegida.

O link de confirmação deve ser aberto no mesmo navegador usado para iniciar o cadastro. Senhas podem ser redefinidas por **Esqueci minha senha**, em `/reset-password`: o link enviado por e-mail expira em 30 minutos, é de uso único e uma nova solicitação invalida o anterior. A confirmação encerra sessões e desafios de login anteriores; não cria sessão nem modifica o autenticador. A recuperação do autenticador administrativo está no login comum, em **Perdi meu autenticador administrativo**, usando a API descrita abaixo; não há recuperação do autenticador de contas comuns. A perda de `SECRET_KEY_BASE` impede decifrar os segredos dos autenticadores já cadastrados; preserve esse segredo fora do repositório.

```bash
# Recriar a API após fornecer/alterar as integrações:
docker compose --env-file .local/compose.env up -d --no-deps --force-recreate api
# Consultar o estado ou parar sem apagar o banco:
docker compose --env-file .local/compose.env ps
docker compose --env-file .local/compose.env stop
```

Execute novamente `bin/local-up` para reiniciar/atualizar e renovar o certificado quando necessário; a emissão Tailscale é consultada em cada execução. Depois de uma renovação sem recriação do ingresso, use `docker compose --env-file .local/compose.env restart ingress` para carregar o certificado novo. Nunca use `down -v` como reinício: isso elimina o banco local. Este ambiente não muda os checkpoints funcionais nem autoriza deploy.

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

O ingresso público deve terminar TLS, encaminhar a mesma origem ao Next.js e **substituir**, não concatenar nem confiar nos valores do navegador, os cabeçalhos `X-Advocacia-Client-IP` pelo endereço IP real do cliente e `X-Advocacia-Ingress-Secret` pelo valor protegido de `AUTH_INGRESS_SECRET` nas requisições de autenticação. O segredo deve ser acessível somente ao ingresso, Next.js e API; impedir acesso público direto ao Next.js e à API. Se houver balanceador anterior, o ingresso só pode usar o IP repassado por ele depois de validar sua cadeia de confiança.

Não registrar tokens, senhas, códigos TOTP nem os cabeçalhos internos em logs de ingresso ou observabilidade. A API e o frontend compartilham `APP_ORIGIN`; cookies `Secure` e CSRF exigem HTTPS também no desenvolvimento. Leituras e mutações exigem um navegador com Web Locks em contexto seguro para coordenar sessões e vínculos entre abas. O relay aceita até 1 MiB de corpo por requisição e impõe prazo de 20 segundos; configure também limites de corpo e tempo no ingresso HTTPS. Se uma mutação perder a confirmação, consulte o estado antes de repeti-la.

## Swagger UI e acesso à documentação

Requisito registrado: a documentação interativa da API será publicada com Swagger UI e protegida por login e senha. O contrato proposto usa autenticação HTTP Basic separada da aplicação, exclusivamente por HTTPS, conforme [`docs/arquitetura.md`](docs/arquitetura.md#identidade-convites-e-documentação). O Swagger UI ainda não existe; não há usuário ou senha padrão, nem credenciais versionadas.

## Variáveis de ambiente

As variáveis abaixo são lidas pelos componentes, seus testes ou processos indicados; a conexão do processador é exclusiva dessa fronteira. Forneça valores sem default pelo gerenciador de segredos ou ambiente protegido do deploy; não versione credenciais nem URLs contendo senhas.

| Variável | Default | Obrigatória? | Finalidade |
|---|---|---|---|
| `DATABASE_URL` | Nenhum | Sim, para API e testes | Conexão PostgreSQL com a role `advocacia_runtime`, sem propriedade das tabelas nem bypass de RLS. |
| `MIGRATION_DATABASE_URL` | Nenhum | Sim, para migrations e testes PostgreSQL protegidos; não fornecer à API web | Conexão com `advocacia_migrator`, separada da role de execução. |
| `DESPACHANTE_DATABASE_URL` | Nenhum | Sim, no despachante e nos testes do despachante; não fornecer à API web | Conexão PostgreSQL isolada com a role `advocacia_despachante`, exclusiva do processo confiável de planejamento; fornecer externamente por ambiente protegido ou gerenciador de segredos. |
| `PROCESSADOR_DATABASE_URL` | Nenhum | Sim, nos processadores DJEN/STF e nos testes de fronteira; não fornecer à API nem ao despachante | Conexão PostgreSQL exclusiva com a role `advocacia_processador`, provisionada administrativamente por `apps/backend/db/provision_processador.sql`. As ABIs de seleção/execução separam fontes DJEN e STF; a conexão não dá acesso direto às tabelas. Fornecer credencial e URL externamente por ambiente protegido ou gerenciador de segredos, sem registrar segredo no repositório. |
| `POSTGRES_DB` | `POSTGRES_USER` da imagem PostgreSQL; `postgres` quando este não é definido; `advocacia_local` no Compose local | Não na imagem; Compose e CI fornecem um nome | Banco criado na primeira inicialização do PostgreSQL local/descartável; o CI usa `advocacia_test`. Não configura o banco de deploy. |
| `POSTGRES_HOST_AUTH_METHOD` | `scram-sha-256` na imagem PostgreSQL 18; `trust` no CI | Não na imagem; o CI define `trust` para o banco descartável sem senha | Método de autenticação para conexões de rede na inicialização do banco; o Compose local mantém SCRAM. `trust` é exclusivo da rede interna descartável do CI, nunca do deploy. |
| `POSTGRES_PASSWORD` | Nenhum | Sim, no PostgreSQL local | Senha administrativa, recebida de `LOCAL_POSTGRES_PASSWORD` pelo Compose. Não é fornecida à API. |
| `LOCAL_APP_HOST` | Nenhum | Sim, no ambiente local | Nome DNS Tailscale com certificado HTTPS; fornecido pelo primeiro argumento de `bin/local-up` e guardado em `.local/compose.env`. |
| `LOCAL_HTTPS_PORT` | `3001` | Não | Porta HTTPS local publicada em `0.0.0.0`; segundo argumento de `bin/local-up` na primeira execução. |
| `LOCAL_POSTGRES_PASSWORD` | Nenhum | Sim, no Compose local | Senha administrativa gerada por `bin/local-up` e preservada no arquivo privado `.local/compose.env`. |
| `LOCAL_RUNTIME_PASSWORD` | Nenhum | Sim, no Compose local | Senha SCRAM da role `advocacia_runtime`, gerada no mesmo arquivo privado; compõe somente a URL da API. |
| `LOCAL_MIGRATOR_PASSWORD` | Nenhum | Sim, no Compose local | Senha SCRAM da role `advocacia_migrator`, gerada no mesmo arquivo privado; compõe somente a URL do processo de migration. |
| `COLETA_HORARIO_1` | Nenhum | Sim, no despachante | Primeiro horário diário em `HH:MM`, fuso `America/Sao_Paulo`, a partir de `04:00`; também agenda o trabalho STF diário no slot 1. Fornecer pela configuração do processo; não há um segundo horário STF. |
| `COLETA_HORARIO_2` | Nenhum | Sim, no despachante | Segundo horário diário em `HH:MM`, posterior ao primeiro; fornecer pela configuração do processo. |
| `COLETA_TENTATIVAS_POR_CAMINHO` | `3` | Não | Número máximo de tentativas de cada caminho, inteiro de 1 a 3; qualquer mudança requer aprovação. |
| `COLETA_BACKOFF_APOS_FALHA_1_SEGUNDOS` | `60` | Não | Espera em segundos após a primeira falha, inteiro positivo; alterações requerem aprovação. |
| `COLETA_BACKOFF_APOS_FALHA_2_SEGUNDOS` | `300` | Não | Espera em segundos após a segunda falha, inteiro positivo; alterações requerem aprovação. |
| `PROCESSADOR_TEST_ADMIN_DATABASE_URL` | Nenhum | Sim, apenas na integração dos processadores DJEN/STF em banco descartável | Conexão administrativa usada exclusivamente para preparar e remover dados sintéticos do teste; fornecer no ambiente protegido de teste, nunca no processo de produção ou com acesso a banco real. |
| `APP_ORIGIN` | Nenhum | Sim, para frontend, API, migration e testes Rails; não é usada pelo despachante | Origem pública HTTPS compartilhada, sem caminho ou credenciais; forneça pelo ambiente protegido. A API valida origens de operações mutáveis e compõe links de confirmação; o proxy web usa seu host canônico para contatar a API. |
| `RAILS_API_ORIGIN` | Nenhum; `http://api:3000` no Compose local | Sim, no frontend | Origem interna da API Rails, acessível somente ao servidor Next.js; forneça pela configuração protegida do ambiente, sem expô-la ao navegador. |
| `AUTH_INGRESS_SECRET` | Nenhum | Sim, no ingresso, frontend e API para autenticação | Segredo compartilhado para autenticar o IP do cliente encaminhado à limitação de autenticação. Gere pelo menos 32 bytes aleatórios e forneça por gerenciador de segredos; nunca exponha ao navegador nem registre seu valor. Sem ele ou sem os cabeçalhos confiáveis, a autenticação falha fechada. |
| `SMTP_HOST` | Nenhum | Sim, para cadastro, recuperação de senha e convites | Host do servidor SMTP; fornecer pela configuração protegida do ambiente. |
| `SMTP_PORT` | Nenhum | Sim, para cadastro, recuperação de senha e convites | Porta TCP do servidor SMTP com STARTTLS obrigatório; fornecer pela configuração protegida do ambiente. |
| `SMTP_USERNAME` | Nenhum | Sim, para cadastro, recuperação de senha e convites | Usuário de autenticação SMTP; fornecer pela configuração protegida do ambiente. |
| `SMTP_PASSWORD` | Nenhum | Sim, para cadastro, recuperação de senha e convites | Senha de autenticação SMTP; fornecer por gerenciador de segredos, sem versioná-la. |
| `SMTP_FROM` | Nenhum | Sim, para cadastro, recuperação de senha e convites | Endereço remetente autorizado no servidor SMTP; fornecer pela configuração protegida do ambiente. |
| `SECRET_KEY_BASE` | Nenhum | Sim, para API, migration e testes Rails; não é usada pelo despachante | Segredo Rails para proteção de tentativas, fatores de autenticação e cópia cifrada dos convites de primeiro acesso com derivação/propósito próprios; gerar e fornecer externamente. Preservar entre reinícios. |
| `RAILS_ENV` | `production` na imagem runtime; `test` na imagem de testes | Não | Seleciona o ambiente Rails. |
| `RAILS_LOG_LEVEL` | `info` | Não | Nível de logging. |
| `PORT` | `3000` nas imagens API e web | Não | Porta interna do servidor Puma ou Next.js; a publicação HTTPS local é controlada por `LOCAL_HTTPS_PORT`. |
| `HOSTNAME` | `0.0.0.0` na imagem web | Não | Endereço de escuta do servidor Next.js standalone dentro do container. |
| `NODE_ENV` | `production` na imagem web | Não | Seleciona o runtime otimizado Next.js. |
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
- [STF: especificação](SPEC-stf.md), [plano técnico](tasks/plan-stf.md) e [checklist](tasks/todo-stf.md)

## Implementação e verificações

**Estado atual — tribunais, navegação e marca:** comunicações são apresentadas em accordions independentes por tribunal, inicialmente abertos, com os mesmos cartões de processo mascarado/órgão, sem “Fonte” repetida e com “Ver íntegra” para abrir o detalhe. Os símbolos das 93 instituições do catálogo DJEN foram pesquisados com Tinyfish e armazenados em `apps/web/src/assets/courts/`; a procedência exata está em [`sources.json`](apps/web/src/assets/courts/sources.json). Não há blocos de fundo nos símbolos; variantes originalmente brancas são apresentadas em monocromia escura para contraste, sem substituir suas formas por ícones genéricos. Novas siglas ainda não presentes no acervo continuam identificadas textualmente, sem marca inventada. A marca do header foi reconstruída em SVG horizontal com autorização do usuário, porque o arquivo anterior incorporava um quadriculado; não é uma reprodução tipográfica exata. O favicon fornecido permanece inalterado.

No mobile, o menu sanduíche substitui as abas; no desktop as abas permanecem. O menu mantém a tela ativa, as mesmas restrições por perfil, fechamento com Escape e após selecionar um destino. A navegação usa “Execuções de Monitoramento”, preservando a rota `/coletas`; o novo rótulo e a navegação foram conferidos também no menu de 320px. No detalhe da comunicação, foi removido o campo “Fonte — DJEN”, mantendo “Tribunal de origem” e os demais metadados; o payload/API não foi alterado. Foram removidos o bloco “Operações do catálogo” e o aviso “Datas em UTC; validade escolhida e vencimento vigente são independentes.” da equipe. No Chromium, foram carregados os 93 símbolos, aberto/fechado um accordion com teclado e conferidos cartões sem “Fonte”; o acesso “Ver íntegra” foi restaurado e exercitado depois. Em 320px, o menu ficou contido na tela, respondeu a Enter/Escape e navegou até coletas, fechando depois; em 1440px as abas continuaram visíveis. A marca foi conferida também em 768 e 1024px. Os smokes utilizaram sessão e respostas de API controladas, sem alterar grupos/credenciais reais. Passaram lint, tipos, formatação, 12 testes de apresentação de comunicação e build de produção do frontend.

**Catálogo DJEN neste servidor:** a fonte bloqueava a saída normal por país (HTTP 403), convertido pela API em 503 `court_catalog_unavailable`. Com autorização explícita, este servidor passou a usar o exit node brasileiro Tailscale `vertice` (`100.127.34.127`), com acesso à rede local habilitado. Essa escolha muda a saída de internet do servidor inteiro; não é proxy isolado da aplicação. A consulta real de `CourtCatalog.fetch` dentro do container da API retornou 93 instituições após a mudança. Nenhum fallback estático foi introduzido; o catálogo e a validação de regras continuam dependendo da fonte atual. Nenhuma variável de ambiente foi criada ou alterada.

**Hiperlinks das publicações:** a ingestão normal preserva destinos HTTP(S) seguros em `texto_parts`, mantendo o texto sanitizado da API ou o HTML original do caderno; neste último caso, acrescenta também `texto_plain` para apresentação segura. A UI constrói nós React, nunca executa HTML e só aceita segmentos que reconstituem exatamente o texto esperado. A suíte ETL passou em PostgreSQL descartável: 134 testes, 1.247 asserções, sem falhas, erros ou skips. A compilação ETL passou após substituir `postgresql-dev` por `libpq-dev` e usar cache externo de APK no estágio de build: mantém os headers de cliente necessários e evita ferramentas LLVM do servidor; compiladores e testes continuam fora do runtime, observado como UID/GID 1000:1000.

Na revisão pré-PR, uma regressão confirmou que `texto_parts` enviado pela fonte sem `texto` provocava `KeyError` no caminho de caderno. O sanitizador passou a descartar metadados de apresentação não confiáveis antes de tratar texto ausente/não textual, preservando os demais campos. Depois da correção, passaram os 10 testes de sanitização (69 asserções), e um smoke na imagem runtime confirmou descarte desses metadados com UID 1000. A suíte completa de 134 testes acima foi executada antes dessa correção pontual.


Com autorização explícita, foi acrescentado somente `texto_parts` à comunicação `f2b0f307-4892-4c57-904e-b76c0f79e7d3` (fonte 713732282), a partir do arquivo bruto original com tenant, tribunal, id, hash e payload completo conferidos em transação. Nenhum campo anterior, identidade, texto, data ou vínculo foi alterado. É uma exceção aditiva pontual aprovada; a ingestão normal continua preservando o primeiro payload nas duplicatas. Os 40 registros importados foram comparados aos originais: apenas esse tinha um destino de âncora recuperável; rótulos sem `href` permanecem texto. O Chromium seguiu “Ver íntegra”, exibiu o rótulo original do material de apoio como link e abriu o PDF real em nova aba; o destino retornou HTTP 206 `application/pdf` e assinatura `%PDF-`. A tela também foi conferida em 320px sem transbordamento. O smoke da UI usou sessão/respostas controladas com o payload reparado relido do banco; não foi um novo login real. A imagem ETL atualizada foi construída, sem iniciar um trabalhador contínuo de coleta.

**Assets da toolbar e favicon:** `header.svg` foi movido da raiz para `apps/web/src/assets/header.svg` e substitui a marca textual no cabeçalho, com altura de 40px e largura proporcional, sem modificar a arte. `icone.ico` foi movido para `apps/web/src/app/favicon.ico`, convenção de favicon do Next.js. O nome do titular aparece em vermelho (`text-error`) no desktop e no celular. A legenda de coletas contém somente “Execuções visíveis no contexto atual.”. Build, tipos, lint e formatação passaram; o Chromium confirmou carregamento e proporção da marca em 320, 768, 1024 e 1440px, favicon HTTP 200 idêntico ao arquivo fornecido e, com respostas de API controladas, nome vermelho e legenda em desktop/celular sem transbordamento da página. Nenhuma variável de ambiente foi alterada.

**Listagem, cabeçalho e rótulos:** a listagem de comunicações apresenta a sigla do tribunal em “Fonte”, o órgão no lugar do UUID visível e o processo com máscara. A API mantém `source: DJEN` e acrescenta os campos opcionais `organ_name` e `process_number_masked`, extraídos somente de strings da primeira versão persistida, sem expor o payload integral na lista nem ampliar permissões. O cabeçalho mostra o nome cadastrado do titular, consultado no perfil autorizado, sem avatar; respostas de outra sessão/tenant não reaproveitam o nome anterior. A UI utiliza “Painel” em vez de “Dashboard”, preservando rotas e operações técnicas. A linha de atualização não exibe mais o sufixo “— America/Sao_Paulo”; a formatação do horário continua no fuso de Brasília. Em coletas, foram removidos a coluna “Consulta” e os links “Ver trabalhos e marcos”; a descrição é “Execuções e trabalhos. Consulta exclusiva do advogado titular.”.

Passaram os testes HTTP da API (21 execuções, 521 asserções, sem falhas), em PostgreSQL descartável separado, os 37 testes Node e as verificações de tipos, lint, formatação e build de produção do frontend. O Chromium conferiu a listagem com payload real lido do banco e respostas/sessão controladas, além do cabeçalho, coletas e Painel em desktop e celular de 320px: nome sem avatar, menu contido na tela, rótulos novos e horário preservado sem o sufixo. Esses smokes visuais não substituem login autenticado real; os contratos e o isolamento foram exercitados nos testes HTTP. API e web locais foram atualizadas, sem mudança de schema ou variáveis de ambiente.

**Detalhe da comunicação:** a identificação apresenta o número mascarado fornecido por `numeroprocessocommascara` (com fallback CNJ textual), DJEN, órgão, classe, tipo, data de disponibilização e link HTTP(S) da fonte sem credenciais. Foram removidos o identificador interno, o JSON/“Todos os campos recebidos da fonte”, o aviso sobre marcação e os UUIDs de trabalho, execução e monitoramento nessa tela. O texto permanece somente em “Conteúdo da publicação”, escapado e com quebras preservadas; os links de monitoramentos continuam funcionais. Passaram 37 testes Node, tipos, lint, formatação e build de produção. No Chromium, o payload da publicação real foi lido do banco e servido à tela com sessão/respostas controladas exclusivamente para o smoke: conferidos os metadados, as remoções, o link, texto inerte e ausência de transbordamento em 320px e 1440px. URL `javascript:` não gerou link e texto com `<script>` não executou. Backend, dados persistidos e variáveis de ambiente não foram alterados; o frontend local foi reconstruído e atualizado.


**Refatoração visual Banani (`refactor/frontend`):** as 14 telas selecionadas em “Central de Processos”, seus componentes e tokens estão preservados, sem alterações, em [`docs/banani/byZqYk7YE568/`](docs/banani/byZqYk7YE568/). A aplicação real em `apps/web/` agora usa esse desenho: cabeçalho com abas em vez da sidebar, IBM Plex Sans servida localmente, Lucide, Tailwind CSS 4 e os tokens exportados. O [contrato visual](docs/design-system.md) registra a integração aprovada: senha/TOTP em vez do Google ilustrado, inputs funcionais, dados reais e estados condicionais; nomes, resumos e datas ausentes na API não são inventados. A exportação original foi comparada com `export.json`, sem divergências.

Passaram os 30 testes Node, tipos, lint, formatação e o build Next.js de produção executado pelo Dockerfile. `npm audit --omit=dev` retornou zero vulnerabilidades; a instalação completa reportou 15 vulnerabilidades moderadas na árvore que inclui ferramentas de desenvolvimento, sem aplicar atualizações forçadas. A imagem web mantém a base Node 24.22.1 Alpine e o runtime standalone, com processo observado como UID/GID 1000:1000. Nenhuma variável de ambiente foi criada ou alterada.

No Chromium, contra Rails e PostgreSQL locais, foram exercitados login com senha/TOTP e saída, onboarding com OAB secundária, erro de nome associado ao input, seleção de vínculo, cadastro de parte/processo com zeros preservados, edição e desativação/reativação de parte, alteração de validade com persistência, criação de grupo e associação de credencial. O modal foi conferido com Escape, restauração e contenção de foco, inclusive a 320px. Comunicações sintéticas persistidas exibiram identidade completa/pendente; o `<script>` do payload apareceu como texto e não foi inserido nem executado. Também foram abertos histórico/detalhe operacional, recuperação de senha, confirmação de e-mail e a tela de convite com preservação/remoção do fragmento e descarte.

Dashboard, monitoramentos, parte, comunicações, detalhe, equipe, grupos e vínculos foram conferidos em 320, 768, 1024 e 1440px, sem transbordamento horizontal. O histórico apresentou transbordamento a 320px; o posicionamento da região rolável foi corrigido e o smoke posterior confirmou sua contenção, inclusive no detalhe operacional. Foram capturadas telas de desktop e celular e conferidos IBM Plex Sans carregada, título de login de 22px, borda `#d4d4d4` e largura desktop de onboarding de 576px. Isso não constitui certificação WCAG nem comparação automatizada pixel a pixel.

O catálogo real de tribunais retornou HTTP 503; não houve seleção bem-sucedida de tribunais nem comprovação das regras dependentes desse catálogo. Este smoke não enviou e-mails nem comprovou entrega/aceite de convite por SMTP ou redefinição completa de senha; esses fluxos mantêm os contratos existentes. As duas contas, o tenant e os registros sintéticos foram removidos, assim como o navegador temporário. Apenas o frontend local foi reconstruído e atualizado; `/login` respondeu HTTP 200 na URL HTTPS existente. Backend, banco de deploy e gates humanos não foram alterados.


**Redefinição de senha:** suíte Rails em PostgreSQL descartável com roles segregadas: 480 testes, 10.711 assertions, sem falhas, erros ou skips. Passaram também os 30 testes Node, tipos, lint, formatação e build web. Na URL HTTPS da aplicação, Chromium exercitou redefinição com conta sintética, rejeição de senha antiga, exigência do autenticador já cadastrado e login com a nova senha e TOTP. A tela de recuperação foi conferida em 390px, sem transbordamento horizontal. Um pedido real para o endereço autorizado pelo Resend retornou 202 após aceitação SMTP; recebimento na caixa de entrada depende do destinatário. A fixture foi removida, sem alterar a senha da conta real. Os containers da aplicação foram atualizados e permanecem ativos.

**Senha e TOTP:** em PostgreSQL descartável com roles segregadas, as migrations foram aplicadas e os testes focados de autenticação passaram: 11 testes, 96 assertions. A suíte Rails completa passou com 459 testes e 10.477 assertions. Um smoke HTTP no processo Rails verificou cadastro, confirmação de e-mail, recusa antes do segundo fator, login com TOTP e recusa de reutilização do código; o envio SMTP foi simulado. No frontend, passaram os 30 testes Node, verificação de tipos, lint, formatação e build; o servidor Next retornou `/login` e sessão anônima com HTTP 200. O navegador não pôde ser iniciado neste ambiente, portanto a interação visual não foi verificada. Os containers locais permaneceram parados. A entrega por SMTP externo não foi verificada.

**Containerização local pela Tailscale:** builds das quatro imagens concluídos; verificação HTTP sem navegador confirmou certificado Let's Encrypt válido, `/login` com HTTP 200, sessão anônima real e dashboard protegida com HTTP 401. A API conectou como `advocacia_runtime`, sem credenciais administrativas, e leu sete migrations. Após reiniciar somente o PostgreSQL, as sete migrations permaneceram no volume. Processos reais de API, web e ingresso executaram com UID/GID 1000:1000; processos PostgreSQL com 70:70. As quatro roles da aplicação não possuem superuser nem BYPASSRLS. Google OAuth e SMTP não estão configurados neste ambiente; não houve teste no navegador nem comprovação dessas integrações externas.

Tamanhos locais descompactados medidos com `docker image inspect`:

| Imagem | Tamanho (MiB) | Base e motivo |
|---|---:|---|
| `advocacia-web:local` | 289,4 | Node 24.22.1 Alpine; build separado, somente saída standalone e assets, incluindo fontes e símbolos locais, sem npm/yarn no runtime. |
| `advocacia-backend:local` | 251,2 | Ruby 4.0.9 Alpine 3.23; compiladores e dependências de teste ficam fora do target runtime existente. |
| `advocacia-processador:local` | 192,6 | Ruby 4.0.9 Alpine 3.23; compatível com as gems nativas musl do projeto, com bundle de produção separado, sem compiladores, código de teste ou cache APK no runtime. |
| `advocacia-postgres:local` | 409,7 | PostgreSQL 18.6 Alpine 3.23; imagem oficial menor que a variante Debian disponível, com diretórios preparados no build para inicialização não root. Exclusiva do ambiente local. |
| `advocacia-ingress:local` | 68,8 | Nginx 1.28.0 Alpine; TLS e substituição dos cabeçalhos confiáveis, sem ferramentas adicionais. |

Referências: [Next.js standalone](https://nextjs.org/docs/app/api-reference/config/next-config-js/output), [dependências e healthchecks Compose](https://docs.docker.com/reference/compose-file/services/), [entrypoint oficial PostgreSQL](https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh).

**Interface web:** em containers não root, `npm run format:check`, `npm run lint`, `npm run typecheck` e `npm test` passaram; o runner executou **33 testes**, sem falhas ou skips. `npm run build` gerou o build Next.js de produção. No Chromium headless, o build foi exercitado com Rails e PostgreSQL descartável: onboarding, troca de vínculo entre abas, operações de monitoramento e equipe, grupos, dashboard parcial e mascarada, comunicações independentes e HTML da fonte como texto. A 320 px não houve transbordamento horizontal.

Um SMTP descartável com STARTTLS e certificado de teste recebeu criação e reemissão de convite; o link efetivamente entregue foi aberto e aceito pela interface com sessão sintética. Também foi exercitada a falha de SMTP sem perder a credencial. Não houve login Google nem entrega em servidor SMTP externos. A consulta ao catálogo real do DJEN retornou 503 na API, após a fonte responder 403 neste ambiente; o fluxo de seleção bem-sucedida de tribunal real continua sem comprovação. O checklist detalhado está em [`apps/web/endpoints.md`](apps/web/endpoints.md).

Os registros históricos a seguir são anteriores à renomeação para processador e não comprovam, por si só, a configuração renomeada.

O histórico da consolidação anterior registra 276 testes e 7.678 assertions, comparação de catálogo e smoke de onboarding; esses resultados não comprovam as alterações posteriores de identidade e autorização.

**Identidade e autorização:** em PostgreSQL 18.6 isolado, as migrations atuais foram aplicadas com roles segregadas e a suíte passou com **382 testes e 9.242 assertions**, sem falhas, erros ou skips. Smoke HTTP em processo não root criou e listou grupo, enviou convite por SMTP local com STARTTLS, aceitou-o numa sessão preparada, confirmou leitura de equipe sem grupos, negou administração à equipe e bloqueou a sessão após revogação. O smoke não usou Google OAuth nem servidor SMTP externos.

As decisões de transação e privilégios seguem as referências oficiais de [funções PostgreSQL seguras](https://www.postgresql.org/docs/18/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY), [RLS](https://www.postgresql.org/docs/18/ddl-rowsecurity.html) e [travas de advisory](https://www.postgresql.org/docs/18/explicit-locking.html#ADVISORY-LOCKS). O transporte usa o [SMTP da biblioteca Mail](https://github.com/mikel/mail/blob/2.9.1/lib/mail/network/delivery_methods/smtp.rb).

### Provisionamento protegido da administradora

A capacidade administrativa da plataforma é única e distinta da titularidade de um tenant. Sua criação usa exclusivamente uma conexão `advocacia_migrator` em processo operacional protegido, nunca a credencial da API. O operador fornece e-mail e senha reais sem defaults; não colocar entradas em argumentos, histórico, arquivos, logs ou sessões gravadas. O primeiro login permanece no mecanismo comum, com senha e confirmação inicial do autenticador.

Em um terminal protegido, use `ruby bin/rails runner` para executar o bloco abaixo como uma única unidade, não colando expressões individuais em IRB/console Rails (que pode imprimir seus resultados). Configure `DATABASE_URL` exclusivamente com a conexão migrator, `APP_ORIGIN` e `SECRET_KEY_BASE` legítimos pelo ambiente protegido; desative gravação do terminal. Não há nova variável ou executável. Para validação, usar somente banco descartável e endereço sintético; isto não autoriza operação em produção.

```ruby
begin
require "io/console"
ActiveRecord::Base.logger = nil
console = IO.console or abort "Terminal protegido obrigatório"
db = ApplicationRecord.connection
abort "Role incorreta" unless db.select_value("SELECT current_user") == "advocacia_migrator"
console.print "E-mail: "
email = console.noecho(&:gets)&.chomp
console.puts
console.print "Senha: "
password = console.noecho(&:gets)&.chomp
console.puts
email = TeamInvitationMailer.normalize_recipient!(email)
abort "Senha inválida" unless password.is_a?(String) && password.valid_encoding? &&
  password.length.between?(12, 128) && password.bytesize <= 512
codes = PasswordAuthentication.new_recovery_codes
db.transaction do
  db.execute("SELECT 1")
  pg = db.raw_connection
  identity = pg.exec_params(
    "INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [email]
  ).getvalue(0, 0)
  pg.exec_params(
    "INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret) VALUES ($1,$2,$3)",
    [identity, PasswordAuthentication.password_hash(password),
      PasswordAuthentication.encrypt(PasswordAuthentication.new_secret)]
  )
  pg.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [identity])
  codes.each do |code|
    pg.exec_params(
      "INSERT INTO app_private.platform_recovery_codes(identity_id,code_hash) VALUES ($1,$2)",
      [identity, PasswordAuthentication.recovery_code_hash(code)]
    )
  end
end
console.puts "Guarde os códigos fora da plataforma; esta é sua única exibição:"
codes.each { |code| console.puts code }
rescue StandardError
  abort "Provisionamento não concluído; confira somente o estado sanitizado."
end
```

A transação é materializada antes das chamadas PostgreSQL parametrizadas: erro ou segunda administradora fazem rollback integral, sem substituir a conta existente. Não imprimir exceções ou seus parâmetros; consultar somente o estado sanitizado. Os códigos só são exibidos após commit e persistidos como hashes. Guarde-os fora da plataforma e preserve `SECRET_KEY_BASE`.

Senha e código de recuperação consumido uma única vez habilitam apenas reinscrição do autenticador; não criam sessão nem autorizam convites. Confirmar o novo TOTP precede o acesso; sessões, desafios e códigos antigos são invalidados. Redefinição de senha mantém TOTP e não autentica automaticamente. Sem autenticador e sem códigos, não há recuperação por e-mail, suporte ou bypass operacional. A administradora entra pelo login comum e usa `/admin/convites` para emitir, enviar, copiar e reemitir links.

### Recuperação administrativa e sessão comum

| Método e caminho | Entrada JSON | Resposta de sucesso |
|---|---|---|
| `POST /api/admin/auth/recovery` | `email`, `password`, `recovery_code` | `200`: `challenge`, `secret`, `otpauth_uri` para preparar o novo autenticador; invalida sessões e desafios de login anteriores. |
| `POST /api/admin/auth/recovery/confirm` | `token` com o challenge recebido, `code` com o novo TOTP | `200`: `recovery_codes` exibidos somente após commit; substitui o fator e os códigos antigos. |

Essas respostas não criam sessão nem cookie; após a confirmação, entrar pelo login comum com senha e novo TOTP. O desafio expira em dez minutos e não pode ser reutilizado. Fatores ausentes, malformados, incorretos, vencidos ou repetidos retornam o mesmo envelope `422`, com `error.code=admin_recovery_invalid`, sem identificar o fator recusado.

As duas rotas exigem JSON, `Origin` igual a `APP_ORIGIN` e o ingresso/IP confiáveis já usados no login. A limitação compartilhada permanece em 20 tentativas por 15 minutos, por IP e, quando aplicável, conta/desafio; `429` traz `Retry-After: 900`. Se houver sessão válida, também é obrigatório seu `X-CSRF-Token`; cookie antigo inválido não equivale a sessão autenticada. Origem, ingresso ou CSRF inválidos retornam `403`. `token`, `code`, `recovery_code`, senha e segredo usam a filtragem existente; consumidores não devem registrar requisições ou respostas sensíveis.

O login concluído por `POST /api/auth/totp` e a consulta autenticada `GET /api/session` incluem `platform_admin` booleano, resolvido no servidor a cada consulta. A capacidade não depende de tenant nem dos papéis owner/member e não pode ser concedida por campos enviados pelo cliente. A consulta anônima mantém `authenticated: false` e `onboarded: false`. Para proteger uma operação administrativa, usar `require_platform_administration` e, nas mutações, `verify_csrf`, revalidando com `authorize_platform_administration!` junto da operação. A guarda usa a sessão comum: sessão ausente/inválida recebe `401`, identidade sem capacidade recebe `403`. Não há segundo cookie, sessão administrativa separada ou nova variável de ambiente.

No login comum, **Perdi meu autenticador administrativo** pede e-mail, senha e um código de recuperação; a etapa seguinte confirma o novo TOTP e exibe os novos códigos para guarda fora da plataforma. Senha, chave, desafio e códigos permanecem somente na memória da tela, nunca em URL ou armazenamento do navegador. O sucesso não entra na conta: depois de guardar os códigos, é necessário novo login com senha e autenticador. Os códigos continuam visíveis até a confirmação de guarda, mesmo se outra aba trocar a conta ou a revalidação da sessão falhar; atualizar/fechar a página descarta essa memória.

A administradora entra por `/login` e segue a `/admin`, sem precisar de tenant. A própria página consulta a sessão real no servidor antes de renderizar; o relay não concede capacidade. Não depender de layout como fronteira de autorização: [layouts Next não revalidam em toda navegação nem impedem a execução/RSC dos filhos](https://nextjs.org/docs/app/guides/authentication#layouts-and-auth-checks). A leitura server-side usa [`cookies()` assíncrono](https://nextjs.org/docs/app/api-reference/functions/cookies), sem outro cookie/provider. Controles de troca de tenant ficam fora do ambiente administrativo; quem também tem vínculo profissional pode acessar seu ambiente existente, sem perder a capacidade administrativa. O provider não trata fragmentos em `/admin` como convites de equipe.

**Verificação PA03:** 44 testes Node aprovados; tipos, lint sem warnings, formatação e build Next de produção aprovados. `npm audit --omit=dev` retornou zero vulnerabilidades; a instalação completa apontou 15 moderadas já presentes na árvore de desenvolvimento, sem atualização forçada. HTTP real verificou origem/ingresso/método, negação a owner/member, CSRF e ausência de CSRF no RSC. Chromium 149 **headless**, em container descartável não root e HTTPS local, verificou login/recuperação, fatores inválidos, expiração, cookie revogado, preservação dos códigos entre contas/erro de rede e navegação de conta com papel duplo. Menu, teclado e foco conferidos a 320 px; ausência de overflow conferida a 320, 768, 1024 e 1440 px. Eventos de foco foram controlados no headless, sem janela gráfica. Não houve SMTP, conta real, deploy ou alteração de dependências/env. Web standalone: 303.629.026 bytes; ingresso existente: 72.190.907 bytes; ambos observados como UID/GID 1000:1000.

### Convites administrativos de primeiro acesso

| Método e caminho | Entrada | Resposta de sucesso |
|---|---|---|
| `GET /api/admin/invitations` | Sessão comum autorizada | `200 { invitations: [{ id, email, created_at, expires_at }] }`, somente ativos e sem segredo. |
| `POST /api/admin/invitations` | JSON com `email` | `201 { id, email, created_at, expires_at }`; normaliza o e-mail, não cria tenant nem substitui convite ativo. |
| `GET /api/admin/invitations/:id/link` | Identificador do convite ativo | `200 { link, expires_at }`; link opaco em `/primeiro-acesso#token=...`, sem renovar o prazo. |
| `POST /api/admin/invitations/:id/reissue` | JSON `{}` | `201` com novos metadados; substitui convite/preparação anteriores atomicamente e reinicia as 24 horas. |
| `POST /api/admin/invitations/:id/email` | JSON `{}` | `200 { accepted, message }` significa aceitação pelo SMTP, não entrega na caixa postal; reenvia o mesmo link sem prorrogar. Falha `503` mantém o convite copiável; timeout informa resultado desconhecido. |

Todas revalidam sessão e capacidade administrativa no PostgreSQL; owner/member comuns não são administradores. Mutações exigem JSON, `Origin` igual a `APP_ORIGIN` e CSRF da sessão atual. Leituras aceitam essa origem ou, sem `Origin`, `Sec-Fetch-Site: same-origin`; origem explícita indevida sempre é recusada. Não há cookie ou variável nova nessas rotas. Respostas usam `no-store`; não registrar seus corpos sensíveis. Sessão ausente/revogada retorna `401`; falta de capacidade, origem ou CSRF retorna `403`; duplicidade ou identidade desativada/titular com tenant retorna `409`; e-mail inválido retorna `422`; identificador sem convite ativo retorna `404`.

Há no máximo um convite ativo por e-mail, com prazo absoluto de 24 horas. Cópia retorna sempre o mesmo token e prazo; somente reemissão explícita substitui ambos. O banco guarda digest e cópia cifrada autenticada, nunca o token em claro. Consumo, substituição e expurgo removem convite e preparação; a liberação consumida permanece vinculada à identidade. Listar/emitir/copiar/resgatar executam expurgo oportunista, sem tarefa agendada: sem atividade, não há promessa de prazo físico de remoção.

No painel, **Enviar convite por e-mail** cria o convite e chama o envio; sucesso significa aceitação pelo SMTP, não recebimento. SMTP ausente/inválido retorna `503 invitation_email_unconfigured` com orientação explícita; o convite permanece copiável. Preencha `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` e `SMTP_FROM` no arquivo local ignorado `.local/integrations.env` com a configuração do provedor antes de iniciar a aplicação; não use a senha de login administrativo como senha SMTP.

**Compartilhar no WhatsApp** exige o telefone com país e DDD, por exemplo `+55 11 99266-9299`. Abre `https://api.whatsapp.com/send/` com número normalizado, mensagem e o mesmo link ativo, `type=phone_number` e `app_absent=0`; o envio final é confirmado no WhatsApp. O telefone não é salvo, não é exigido no envio por e-mail e serve também aos convites ativos. Copiar/compartilhar não renova o prazo; popup bloqueado é informado.

A mensagem usa a [formatação nativa do WhatsApp](https://faq.whatsapp.com/539178204879377): título e seções em negrito, subtítulo e aviso de uso único em itálico, blocos separados por linhas em branco e link intacto em linha própria. Não usa HTML nem links Markdown; destinatário, token e validade permanecem os mesmos.

Inscrição inicial e recuperação do autenticador mostram somente QR code local pelo pacote `qrcode@1.5.4`, sem enviar `otpauth_uri` a terceiros e sem exibir chave manual. Falha na geração informa o erro, sem alternativa textual. Login com TOTP já inscrito continua pedindo seu código, não outro QR.

Em `/primeiro-acesso#token=...`, o formulário captura o segredo apenas em memória e remove o fragmento. Preparar senha/autenticador não cria identidade, sessão, reset ou liberação. A confirmação inicial de TOTP conclui conta, liberação, consumo e sessão comum numa transação, seguindo diretamente ao perfil sem novo login/TOTP. Conta existente usa sua sessão MFA do mesmo e-mail sem alterar credenciais. Perfil/tenant são outra transação; falha nessa etapa não reabre convite consumido. A capacidade server-side `can_create_tenant` permite retomar `/onboarding`, inclusive quando já há vínculo de equipe, e nunca substitui a guarda SQL.

**Restore:** antes de reabrir o tráfego, a operação protegida deve executar `DELETE FROM app_private.first_access_invitations` na instância restaurada com a role de migration. Isso invalida todos os convites restaurados e elimina suas preparações por FK; não apagar identidades nem `app_private.first_access_grants`. A role da API não pode executar esse DELETE; não existe endpoint ou função runtime de manutenção. Preserve `SECRET_KEY_BASE`; não tentar recuperar links antigos com outra chave.

**Verificação PA04/PA05:** foco com 27 testes e 288 assertions e suíte Rails completa com 536 testes e 11.710 assertions, sem falhas, erros ou skips, em PostgreSQL Docker descartável com roles segregadas. `zeitwerk:check` aprovado. HTTP real em Puma de produção não root comprovou senha/TOTP comuns, emissão/cópia/duplicidade/reemissão e negações; o instante de 24 horas devolveu `404` e removeu o segredo. Consumo via store exigiu a sessão MFA da mesma identidade; restore protegido eliminou os convites/preparações e preservou a liberação consumida. Isso não antecipa a prova do cadastro público de conta nova, prevista em PA09, nem SMTP/UI de convites.

### Apresentação dos e-mails

Os próximos envios de convite de equipe, convite de primeiro acesso, confirmação de e-mail, redefinição de senha e aviso de senha alterada usam o visual exportado do Banani em `docs/banani/byZqYk7YE568/emails-export.json`, adaptado para a marca Advocacia Online e os dados/links reais de cada fluxo. A mudança não reenvia mensagens anteriores nem cria notificações de comunicações judiciais.

`apps/backend/app/services/email_template.rb` monta `multipart/alternative` com o texto original e uma versão HTML UTF-8: cabeçalho escuro, conteúdo central, botão de ação, link copiável e rodapé. O HTML usa tabelas de apresentação e estilos inline, com ajuste de espaçamento para celular e sem fontes remotas, imagens de rastreamento, contatos fictícios ou links jurídicos ilustrativos. Valores dinâmicos são escapados; URLs e tokens continuam nos mesmos destinos e fragmentos. Assuntos, destinatários, prazos, STARTTLS e tratamento de erros foram preservados. Nenhuma variável de ambiente foi adicionada.

Verificação local: **594 testes e 12.345 asserções**, sem falhas, erros ou skips, em PostgreSQL descartável; build do runtime e `zeitwerk:check` aprovados. Os cinco formatos atravessaram um SMTP local com STARTTLS, apenas com destinatários e tokens sintéticos. O HTML recebido foi exercitado no Chromium headless não root em 320, 768, 1024 e 1440 px, sem overflow horizontal e com acesso ao botão por teclado. Não houve envio externo, reenvio de mensagens reais ou deploy. Essa prova não equivale a validação em Gmail, Outlook ou Apple Mail.

### API de onboarding

| Método e caminho | Comportamento |
|---|---|
| `POST /api/auth/first-access/inspect` | JSON com `token`; consulta e-mail fixado, expiração e necessidade de login, sem consumir. |
| `POST /api/auth/first-access` | Token e senha/`password_confirmation` preparam conta nova; retorna challenge, segredo TOTP e URI, sem sessão. Conta existente autenticada resgata com token e CSRF, sem alterar credenciais. |
| `POST /api/auth/first-access/confirm` | Token, challenge e `code` confirmam primeiro TOTP e criam sessão comum somente após commit. |
| `POST /api/auth/team-register` | Convite de equipe no token, e-mail correspondente e senha iniciam confirmação real; não concedem titularidade. Conta existente autenticada pode confirmar seu e-mail nesse contexto sem redefinir credenciais. |
| `POST /api/auth/verify-email` | Confirmação vinculada ao convite de equipe e ao navegador; não há cadastro público genérico nem alias de `/api/auth/register`. |
| `POST /api/auth/login` | Valida senha e inicia o desafio TOTP, sem criar sessão. |
| `POST /api/auth/totp` | Valida o código do autenticador e cria sessão somente após sucesso. |
| `POST /api/auth/password-reset` | Recebe `email` e responde `202` genérico após o envio das instruções; não revela existência da conta. |
| `POST /api/auth/password-reset/confirm` | Recebe `token` e `password`; responde `204` após alterar a senha, sem autenticar. Token inválido, expirado ou consumido retorna `422`. |
| `GET /api/session` | Informa se há sessão autenticada, se o onboarding foi concluído e, quando autenticada, o token CSRF. |
| `POST /api/onboarding` | Cria perfil e tenant do advogado autenticado. Exige `Origin` igual a `APP_ORIGIN` e `X-CSRF-Token` da sessão. |
| `GET /api/onboarding` | Retorna o perfil, inscrições e tenant associados à sessão, sem aceitar seleção de tenant pelo cliente. |

O corpo do POST contém `full_name`, `primary_oab` com `number` e `uf`, `secondary_oabs` como lista e `office_name` opcional. A OAB principal é obrigatória; as secundárias podem ser uma lista vazia. O número é textual para preservar zeros e sufixos. Não se confunde escritório com tenant.

A redefinição segue a [orientação OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html): token aleatório de 256 bits armazenado apenas como hash, prazo de 30 minutos, consumo atômico e revogação de sessões/desafios. O link usa fragmento em `/reset-password#token=...`, removido da barra pelo frontend; o segredo fica somente em memória até a submissão. A solicitação usa a mesma operação SMTP e resposta genérica para endereços válidos, inclusive sem conta; somente identidades confirmadas e ativas recebem token utilizável. Falha de envio retorna `503` e invalida aquele token. Após a alteração é enviado um aviso; falha desse aviso registra `password_reset_notification_delivery_failed`, sem reverter a senha já alterada. Os limites de autenticação e a exigência de Origin/ingresso confiável continuam vigentes.

### Identidade de equipe e grupos

A identidade pode ter vínculos em vários tenants. `GET /api/session` informa os vínculos disponíveis; `PATCH /api/session/membership` seleciona um `membership_id` validado pelo servidor e `DELETE /api/session` encerra a sessão. Uma credencial de equipe exige `validity_days` explícito: `null` para sem expiração ou inteiro positivo, contado em períodos de 24 horas desde a criação ou renovação. Alterar a escolha não altera o vencimento até a renovação; revogação é imediata e não é revertida por renovação.

O titular administra credenciais em `GET`/`POST /api/team/credentials`, `PATCH`/`DELETE /api/team/credentials/:id`, `POST /api/team/credentials/:id/renewal` e `POST /api/team/credentials/:id/invitation`. A criação recebe `email`, `validity_days` e `group_ids` opcional. O convite é enviado por SMTP após o commit: se a entrega não for confirmada, a credencial permanece criada e o titular pode reemitir o convite. A reemissão invalida o link anterior sem reiniciar a validade. O link usa fragmento `#token=...`; a interface preserva o token durante o login e o envia a `POST /api/team/invitations/accept`, com sessão autenticada, `Origin` e CSRF. Não registrar o token nem o conteúdo do convite.

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

O processo em `apps/etl/` consome continuamente os trabalhos planejados com a role exclusiva `advocacia_processador`. Para uma imagem construída por `docker build -t advocacia-processador apps/etl`, execute `docker run --rm --network <rede> -e PROCESSADOR_DATABASE_URL advocacia-processador`, fornecendo a URL pelo ambiente protegido. Sem trabalho disponível, o processo consulta novamente após cinco segundos; ele deve permanecer em execução, separado do despachante, e ser reiniciado pelo supervisor após uma falha fatal. Também é possível executar um trabalho específico informando seu UUID como argumento.

O banco seleciona e concede cada trabalho atomicamente, sem fornecer acesso direto às tabelas ao processador. Instâncias concorrentes ignoram trabalhos bloqueados ou com concessão ativa. Após interrupção, uma concessão expirada permite retomar o progresso persistido; trabalhos concluídos ou com falha não são coletados novamente. Trabalhos pendentes de dias anteriores são marcados como interrompidos sem consultar o DJEN. Como a função de seleção foi adicionada à migration inicial existente, bancos que já a executaram não recebem essa função automaticamente: sua atualização deve integrar o procedimento de deploy antes de iniciar o novo processador.

Após uma tentativa frustrada, o processador libera a concessão enquanto aguarda o backoff ou `Retry-After` persistido; outros trabalhos elegíveis podem avançar sem antecipar a próxima tentativa. O prazo informado pela fonte é compartilhado entre executores para o mesmo tribunal, data, meio e caminho. Uma resposta bem-sucedida com `Retry-After` entre páginas mantém o trabalho atual na instância até a espera terminar; instâncias adicionais podem consumir outros trabalhos.

Cada trabalho consulta somente Diário Eletrônico (`D`) no dia corrente de `America/Sao_Paulo`. Na primeira coleta, valida integralmente o ZIP do caderno e, após esgotar as tentativas, percorre a API paginada até a primeira página vazia válida; na segunda, inicia diretamente pela API, sem caderno. Contadores, etapa e espera são persistidos; falha posterior não publica páginas parciais. Somente para resultados da API, Loofah converte o campo `texto` em texto simples, removendo HTML, scripts e estilos e decodificando entidades; cadernos são persistidos sem essa sanitização. Como a primeira versão é preservada na deduplicação, uma comunicação inicialmente obtida de caderno pode continuar contendo HTML mesmo se também aparecer na API. Todo texto da fonte deve ser escapado pelo consumidor na renderização.

`collection_communications`, `collection_communication_links`, `collection_job_results` e `collection_job_failures` armazenam resultados, vínculos e falhas fora dos marcos do Escrevente. A função `app_private.collection_court_states(uuid,text)` agrega o estado sob a sessão autenticada: `NULL` inclui as fontes autorizadas; `'DJEN'` isola o painel. Contagens ficam `NULL` quando o tribunal não terminou integralmente. A consulta está integrada à interface em `apps/web/`.

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

As duas imagens já são definidas no mesmo [`apps/backend/Dockerfile`](apps/backend/Dockerfile), por targets independentes. Não existe um Dockerfile separado em `apps/backend/despachante/`; ele não é necessário para gerar uma imagem exclusiva do despachante.

| Componente | Target | Base final | Usuário final | Comando da imagem |
|---|---|---|---|---|
| API Rails | `runtime` | `ruby:4.0.9-alpine3.23` | `1000:1000` | `bundle exec puma -C config/puma.rb` |
| Despachante | `despachante` | `ruby:4.0.9-alpine3.23` | `1000:1000` | `ruby despachante/run.rb` |

Os builds são multi-stage: o despachante usa os estágios `despachante_base` e `despachante_dependencies` antes do target final `despachante`. A instalação de pacotes de compilação ocorre nos estágios de build, sem levar compiladores para as imagens finais. O uso de root durante a construção não é um entrypoint privilegiado: ambas as imagens iniciam diretamente como usuário não root, sem instalar pacotes, corrigir permissões ou executar migrations no startup.

Construa a API, a partir da raiz do monorepo, com `docker build --target runtime -t advocacia-backend:local apps/backend`. Neste ambiente, o build precisou de `--network host` para resolver dependências devido ao DNS da rede Docker. O comando de build do despachante está abaixo; nenhum deles depende de um frontend implementado.

**Migrations iniciais consolidadas — banco inicial vazio:** `20261028000000_create_identity_and_lawyer_profiles.rb` define o schema atual de identidade; `20261028000005_create_team_credentials.rb` e `20261028000006_create_authorization_groups.rb` acrescentam credenciais e grupos. `20261028000003_create_collection_planning.rb` integra as antigas migrations 04–06; `20261028000004_create_escrevente.rb` substitui a antiga 07. O deploy futuro continua condicionado ao procedimento próprio e às permissões necessárias.

Essas migrations não oferecem rollback destrutivo nem upgrade automático de banco pré-existente. Um banco descartável de desenvolvimento criado pela sequência anterior precisa ser recriado explicitamente antes de receber a sequência consolidada; não aplique as migrations consolidadas sobre o schema antigo nem use os relatos históricos de `db:rollback` abaixo como instrução atual. O uso futuro da instância PostgreSQL do servidor de deploy continua condicionado a um procedimento próprio, ainda não definido.

Para um banco inicial vazio, um administrador deve executar [`apps/backend/db/provision.sql`](apps/backend/db/provision.sql), [`apps/backend/db/provision_despachante.sql`](apps/backend/db/provision_despachante.sql) e [`apps/backend/db/provision_processador.sql`](apps/backend/db/provision_processador.sql), nessa ordem, no banco da aplicação, antes das migrations, e configurar credenciais SCRAM fora do repositório. A role `advocacia_migrator` é proprietária das tabelas migradas e executa migrations; `advocacia_runtime` executa a API; `advocacia_despachante` pertence somente ao processo confiável de planejamento e pode ler os monitoramentos dos tenants para gerar o trabalho; `advocacia_processador` é exclusiva do executor e dos testes de fronteira, sem membros, memberships ou acesso direto às tabelas. Runtime, despachante e processador não são donos das tabelas; nenhuma das quatro roles possui `BYPASSRLS`. A API não recebe as credenciais do despachante, do processador ou de migration; o despachante nunca recebe `PROCESSADOR_DATABASE_URL`.

**Registro histórico do corte de nomes (anterior à consolidação; não é procedimento atual de instalação ou upgrade):**

1. O componente antigo (`planner`/planejador) era parado, com reinício pelo supervisor impedido. A versão antiga não podia executar junto com o despachante.
2. Antes de publicar a release daquela entrega ou executar suas migrations, o procedimento exigia que um administrador executasse [`apps/backend/db/rename_despachante.sql`](apps/backend/db/rename_despachante.sql) no banco da aplicação. A conexão administrativa precisava dos privilégios de gerenciamento da role e das políticas exigidos pelo script, sem usar a credencial da API nem a do despachante. A role é global ao cluster, mas as políticas pertencem a cada banco; o corte abrangia cada banco da aplicação que compartilhasse essa role.
3. O script renomeava `advocacia_planner` para `advocacia_despachante` e o prefixo de políticas `collection_planner_` para `collection_despachante_`, preservando o OID e as permissões da role. Se as duas roles já existissem, nenhuma existisse ou houvesse colisão de nomes de políticas na mesma tabela, o script abortava sem aplicar mudanças parciais e exigia resolução administrativa do conflito antes de repetir o corte.
4. O roteiro exigia atualizar o login da URL de conexão para `advocacia_despachante`, substituir `PLANNER_DATABASE_URL` por `DESPACHANTE_DATABASE_URL` e atualizar os arquivos de ambiente protegidos e o gerenciador de segredos. Uma senha SCRAM existente podia ser mantida. Credenciais MD5 antigas dependem do nome da role e são invalidadas pelo PostgreSQL ao renomeá-la; a orientação era convertê-las para SCRAM externamente antes do corte ou redefini-las externamente antes de reiniciar o processo, sem registrar senhas no repositório.
5. Só então se aplicavam as migrations vigentes naquela entrega e se iniciava o despachante com target, imagem, caminhos e configuração novos, removendo as referências antigas de automações e supervisores. Não havia variável alternativa, alias de classe, target de compatibilidade ou caminho legado. Esse passo histórico não autoriza aplicar a sequência consolidada a um banco pré-existente.

O corte de nomes trocou o módulo `escriba`/Escriba por `escrevente`/Escrevente e moveu `SPEC-escriba.md` para [`SPEC-escrevente.md`](SPEC-escrevente.md), sem arquivo de redirecionamento ou alias. Naquela entrega, o Escrevente era apenas documental. Posteriormente foi implementado no backend Rails, sem ações de usuários nem detalhes de erros, com as verificações históricas descritas acima.


Forneça as variáveis por arquivos de ambiente protegidos ou pelo gerenciador de segredos do ambiente. Em uma rede Docker que alcance o PostgreSQL, execute `docker run --rm --env-file <arquivo-de-migration> --entrypoint ruby advocacia-backend:local bin/migrate` separadamente; o arquivo de migration deve conter `MIGRATION_DATABASE_URL` e as demais variáveis necessárias ao boot. Inicie a API com `docker run --rm --env-file <arquivo-da-api> -p 3000:3000 advocacia-backend:local`, fornecendo apenas a URL da role runtime. Coloque a API atrás de terminação HTTPS compatível com `APP_ORIGIN`; nunca exponha `MIGRATION_DATABASE_URL` ao processo web.

Construa o processo separado com `docker build --target despachante -t advocacia-despachante:local apps/backend` e inicie-o com `docker run --rm --env-file <arquivo-do-despachante> advocacia-despachante:local` em uma rede que alcance o PostgreSQL e o DJEN. O arquivo deve fornecer `DESPACHANTE_DATABASE_URL`, `COLETA_HORARIO_1` e `COLETA_HORARIO_2`; não forneça credenciais da API, do Google ou de migration. O processo reconcilia os dois horários do dia local e registra falha do catálogo; após indisponibilidade, espera pelo menos 60 segundos antes de nova requisição. Configure um supervisor de implantação para reiniciar o processo caso ele termine por erro inesperado.

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

## Primeiro acesso controlado — verificação integrada

Entrega no [PR #17](https://github.com/smcruzfilipe/advocaciaonline/pull/17), sem deploy. O CI do backend executou **560 testes/11.949 assertions**, e o processador **135 testes/1.253 assertions**, sem falhas, erros ou skips; o smoke da imagem final do despachante persistiu dois planos distintos e idempotentes. Web: **47 testes** e gates de tipos, lint, formatação, build e auditoria de produção aprovados.

Chromium headless, em HTTPS local e PostgreSQL Docker descartável, exercitou emissão/SMTP STARTTLS/cópia/reemissão, clipboard permitido/negado e cópia após indisponibilidade SMTP. O advogado preparou senha/TOTP sem conta ativa, confirmou primeiro TOTP e concluiu perfil/tenant sem segundo login; o e-mail permaneceu sem falsa prova de caixa. A equipe criou conta sob convite, confirmou o e-mail recebido pelo SMTP e autenticou/aceitou; não conseguiu administrar ou criar tenant sem grant. Após liberação administrativa, um membro retomou o perfil interrompido sem query ou novo convite e preservou seu vínculo anterior. Painel e dashboard foram conferidos a 320 px sem overflow e com foco de teclado.

Instalação vazia e upgrade desde a imagem anterior foram ensaiados: credenciais, sessões e titulares preservados; identidade sem tenant não recebeu grant; pendência pública invalidada. Restore protegido removeu todos os convites/preparações, inclusive ativos, preservando identidades, liberações e tenants. Uma mutação temporária que invertia o fator TOTP foi detectada pelo teste consumidor; produção ficou intacta.

API, web e ingresso executaram de fato com UID1000; PostgreSQL com UID70. Imagens finais: API **263.103.711 bytes**, web **303.898.522 bytes**, ingresso **72.190.907 bytes**. Bases Ruby4.0.9-Alpine3.23 e Node24.22.1-Alpine já vigentes, multi-stage, sem ferramentas de build/testes nos runtimes. SMTP sintético autenticado com TLS não comprova recebimento externo. Nenhum segredo real, dado persistente, novo job, dependência ou variável foi necessário.

## Processos e andamentos STF

Contrato: [SPEC-stf.md](SPEC-stf.md). Plano/checklist: [tasks/plan-stf.md](tasks/plan-stf.md) e [tasks/todo-stf.md](tasks/todo-stf.md); acompanhamento na [issue #20](https://github.com/smcruzfilipe/advocaciaonline/issues/20).

`apps/stf/` é uma aplicação Ruby independente do Rails e do ETL DJEN. O coletor consulta JSON de processos e HTML de andamentos por HTTPS; o processador consome trabalhos PostgreSQL confiáveis, filtra a data corrente em `America/Sao_Paulo` e persiste movimentos com origem e links. Não abre PDFs, não usa MNI e não aceita argumento de data histórica. A busca nominal confere nome completo, publicidade pública e situação `Sim`; processo direto confirma atividade/publicidade pelo JSON de uma parte real do detalhe, com o mesmo incidente e CNJ quando fornecido. Classe/número continua utilizável sem CNJ, mas CNJ não vazio malformado é recusado. Situação ou publicidade não comprovadas são erro verificável, nunca presunção de elegibilidade.

Fonte STF e meio `A` são distintos de DJEN/D. Capturas têm chave local tenant/execução/incidente e ordinal interno dos itens; itens iguais continuam distintos. Reentrega da mesma captura é idempotente e conserva vínculos; dados divergentes para a mesma chave são recusados. Isso não é identidade nativa STF: movimentos permanecem pendentes, com aviso de possível duplicidade, fora das métricas deduplicadas DJEN.

### Build e execução

Na raiz do monorepo:

```bash
docker build --target test -t advocacia-stf:test apps/stf
docker build --target runtime -t advocacia-stf:runtime apps/stf
```

O runtime lê somente `PROCESSADOR_DATABASE_URL`, fornecida por ambiente protegido para a role existente `advocacia_processador`. Sem argumentos, `bundle exec ruby bin/processador` executa o worker contínuo; `--once` seleciona pela fila e termina após um ciclo; um UUID executa um trabalho específico. O worker não é iniciado pelo Compose local. Não fornecer conexão administrativa, de migration ou de despachante ao processo STF.

No ambiente descartável de prova já provisionado, com a rede `advocacia-stf-ci` e as URLs protegidas configuradas:

```bash
docker run --rm --network advocacia-stf-ci \
  -e PROCESSADOR_DATABASE_URL -e PROCESSADOR_TEST_ADMIN_DATABASE_URL advocacia-stf:test
docker run --rm --network advocacia-stf-ci \
  -e PROCESSADOR_DATABASE_URL advocacia-stf:runtime bundle exec ruby bin/processador --once
```

O teste usa a conexão administrativa exclusivamente para dados sintéticos de PostgreSQL descartável; nunca executar essa suíte contra o banco persistente local ou de deploy. Aplicar antes as migrations incrementais STF pela role migrator, após o provisionamento normal das três roles existentes.

### Imagem e provas

A base `ruby:4.0.9-alpine3.23` mantém o runtime Ruby vigente com `libpq` e dados de fuso, sem Rails/Node/dependências ZIP. Builds multi-stage separam compiladores e testes. Runtime STF medido com **186.017.830 bytes** não comprimidos, usuário configurado `1000:1000` e execução efetiva não root; sem testes, gcc ou cache de gems. Na integração, API, frontend, ingresso e planejador executaram com UID 1000 e PostgreSQL descartável com UID 70.

A suíte STF final executou **94 testes/309 assertions**, SQL STF **21/245**, DJEN **135/1.253** e web **52 testes**, sem falhas, erros ou skips. Tipos, lint, formatação, build web e auditoria de produção passaram, com zero vulnerabilidades de produção. O CI integrado registrou **590 testes/12.294 assertions** de backend aprovados. A fixture não transacional que reutilizava e-mail passou a usar identidade única, sem mudar assertions.

O planejador real, com catálogo controlado, criou nove trabalhos STF/A no slot 1 e nenhum no slot 2. Processos separados executaram `--once` até oito sucessos, uma falha explícita e fila vazia. Quatro movimentos foram persistidos: dois iguais distintos, cada qual vinculado ao advogado, à parte e ao processo, mais casos sem documentos e sem CNJ. Fonte positiva é sintética; não representa movimentos reais de hoje. A comparação histórica real preservou nove eventos e documentos, sem backfill.

Chromium headless acessou API e PostgreSQL reais por HTTPS: lista/detalhe, marca oficial, data do andamento, origem/PDF/URL Unicode, referências, identidade pendente e classe/número sem CNJ. Verificou os dois estados vazios e a falha no histórico, ausência de transbordamento em 320/768/1024/1440px e negação de detalhe entre tenants (404), sem abrir destinos externos nem erros JavaScript. A dashboard permaneceu DJEN, `no_work`, sem métricas inventadas ou avisos pela falha STF.

O catálogo preserva se STF veio também da fonte DJEN, sem criar trabalho DJEN fictício para a entrada exclusiva do portal nem remover DJEN realmente oferecido. A integração mantém a falha explícita do catálogo compartilhado: na prova pontual deste ambiente o provedor DJEN respondeu HTTP 403; não foi comprovado agendamento recorrente com a fonte real disponível nem se alterou a rota de rede do servidor.

O transporte conserva a URL validada após redirecionamentos como origem da coleta e base dos links relativos. CNJ informado deve ser confirmado: resultado restrito sem identidade comprovada falha explicitamente, sem consultar outra parte para sobrepor a restrição. As regressões falharam antes e passaram após as correções. Na prova final, dois trabalhos novos do planejador executaram a entrada CLI com HTTP controlado: nominal antes da limpeza e CNJ depois da remoção dos arquivos exclusivos, sem código da aplicação montado. Cada trabalho persistiu dois movimentos; a role `advocacia_runtime` confirmou quatro novas comunicações e duas capturas, CNJ do JSON ausente no HTML, URL final de coleta e link relativo Unicode/query. O replay sem preload comprovou separadamente idempotência, não substituiu a coleta nova.

### Contratos de consulta

`GET /api/communications` e `GET /api/communications/:id` oferecem `process_identification` quando disponível, permitindo apresentar classe/número sem inventar CNJ. O histórico `GET /api/collection-runs/:id/execution` fornece, por trabalho, `source_path`, `eligible_process_count`, `matched_count` e `pending_identity_count`; ausência de resultado é `null`, não sucesso com zero. Autorização, isolamento por tenant e aviso de identidade pendente permanecem obrigatórios.

### Condições de operação e rollback

O portal não oferece um contrato público validado de API JSON de movimentos e seu `robots.txt` exclui `/processos`. Conferir as condições de acesso com o STF antes de ativar coleta recorrente; não contornar autenticação, captcha ou bloqueios. A entrega não inicia crawler contínuo nem autoriza deploy. Para parar/rollback operacional, encerrar o worker STF e preservar as capturas; não apagar histórico ou criar outra instância PostgreSQL. DJEN mantém seu contrato e processo próprios.

A migration `20261102000011` substitui a assinatura SQL de `collection_court_states` por `(uuid,text)` e exige aplicação e API correspondentes: parar a API antiga, aplicar com a role migrator e iniciar a imagem atualizada. Não aplicar essa troca de ABI com a API antiga atendendo nem presumir compatibilidade de rollback para binário antigo. Esse procedimento está documentado; não foi executado deploy.
