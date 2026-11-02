# Briefing de deploy — Advocacia Online / Dokploy

**Estado:** plano de implantação; nenhum recurso de produção criado ou alterado nesta preparação. Validação funcional, aceite e decisão/execução de recuperação pertencem ao solicitante.

## 1. Destino confirmado e limites

- [x] Identificar o control plane pela configuração existente no `.bashrc`, sem imprimir a chave: `https://vmi3631516.contaboserver.net`.
- [x] Consultar a API Dokploy: servidor de aplicações `161.97.138.127`, cadastrado como **Servidor de Aplicações - SSH**, `serverId=MCtn5oDI73kjE8Cmumg_N`; destino denominado **apps-contabo** pelo solicitante.
- [x] Distinguir do servidor de agentes/build `173.249.24.22`: ele NÃO será o destino de execução da aplicação.
- [x] Identificar **Vertice - Infraestrutura → production → PostgreSQL compartilhado**, `postgresId=utnOfYkn40zt37GpTTFS6`, serviço `postgres-synthesize-primary-panel-jbxggh`, imagem atual `postgres:18`, no servidor de aplicações, sem porta externa publicada.
- [x] Identificar a rede já conectada ao PostgreSQL: **dokploy-network**. Reutilizá-la como rede externa; não criar uma rede substituta nem outra instância PostgreSQL.
- [x] Confirmar existência da branch **main** no repositório `smcruzfilipe/advocaciaonline`.
- [ ] Realizar todas as criações/configurações e acionamentos pelo control plane/API Dokploy. Não subir produção pelo Docker local nem fazer deploy avulso por SSH.
- [ ] Não parar, atualizar, recriar ou alterar volumes, credenciais e bancos das outras aplicações ou do PostgreSQL compartilhado.

## 2. Projeto, aplicações e quantidade de containers

- [ ] Criar o projeto **Advocacia Online**, ambiente **production**, e associar os recursos executáveis ao `serverId` confirmado, sem duplicar projeto caso a execução seja retomada.
- [ ] Criar **seis aplicações permanentes**, inicialmente com uma réplica cada. Traefik/Dokploy e PostgreSQL existentes não entram nessa contagem. Jobs de provisionamento e migration são temporários, sequenciais e não são novos servidores PostgreSQL.

| Aplicação | Código/contexto de build | Target ou configuração | Caminhos observados em main |
|---|---|---|---|
| ingresso | `docker/production/ingress/` — a preparar | Nginx mínimo não root, atrás do ingresso HTTPS do Dokploy | `docker/production/ingress/**` |
| web | `apps/web/` | Imagem Next.js standalone de produção | `apps/web/**` |
| api | `apps/backend/` | Dockerfile, target `runtime` | `apps/backend/**` |
| despachante | `apps/backend/` | Dockerfile, target `despachante` | `apps/backend/**` |
| processador-djen | `apps/etl/` | Dockerfile, target `runtime` | `apps/etl/**` |
| processador-stf | `apps/stf/` | Dockerfile, target `runtime` | `apps/stf/**` |

Os dois serviços de backend observam o mesmo diretório porque compartilham Dockerfile e código do catálogo. Filtros são relativos à raiz do repositório. A configuração de ingresso de produção ainda será preparada; não copiar certificados, variáveis locais ou o Compose local para produção.

- [ ] Reutilizar as redes existentes necessárias, incluindo `dokploy-network`, com nomes de serviço exclusivos. Não publicar portas próprias para API, PostgreSQL, despachante ou processadores.
- [ ] Configurar `painel.alessandraguinosa.adv.br` no roteamento HTTPS do Dokploy, com DNS A para `161.97.138.127`. O Nginx permanece como adaptador dos cabeçalhos confiáveis de autenticação exigidos pela aplicação, não como outro control plane/proxy público independente.
- [ ] Preservar IP real do cliente somente a partir do proxy confiável; sobrescrever os cabeçalhos internos, nunca aceitar os enviados pelo navegador. Manter API/web sem rotas públicas que contornem esse ingresso.
- [ ] Executar os novos containers da aplicação como não root, usando imagens de runtime e sem credenciais de build/migration desnecessárias.

## 3. Banco e segredos automáticos

- [ ] Gerar, na primeira execução, com gerador criptograficamente seguro: `SECRET_KEY_BASE` (64 bytes aleatórios), `AUTH_INGRESS_SECRET` (pelo menos 32 bytes) e quatro senhas independentes das roles PostgreSQL da aplicação.
- [ ] Persistir os valores na configuração protegida do Dokploy, por API, antes de usá-los no provisionamento. Reutilizar valores existentes em retomadas/redeploys: não rotacionar chaves, resetar senhas ou recriar contas em cada push.
- [ ] Executar job operacional temporário no apps-contabo, usando a conexão administrativa já cadastrada do PostgreSQL compartilhado, para criar somente o banco **advocacia_online** e as roles `advocacia_migrator`, `advocacia_runtime`, `advocacia_despachante` e `advocacia_processador`, conforme os scripts existentes em `apps/backend/db/` e autenticação SCRAM.
- [ ] Se nomes já existirem, conferir associação e permissões antes de reutilizar; não tomar posse, sobrescrever senha ou modificar recursos de outra aplicação. As roles são globais ao cluster, embora o banco seja específico.
- [ ] Retirar a conexão administrativa do job após provisionamento. Distribuir somente a conexão correspondente a cada processo: runtime na API; despachante no planejador; processador nos workers; migrator exclusivamente no job de migration.
- [ ] Configurar `APP_ORIGIN=https://painel.alessandraguinosa.adv.br`, `RAILS_API_ORIGIN` e a agenda **segunda a sexta, 04h00 e 16h00 de Brasília**: `COLETA_HORARIO_1=04:00`, `COLETA_HORARIO_2=16:00`, `COLETA_DIAS_SEMANA=1,2,3,4,5`. STF somente no primeiro slot. Demais variáveis conforme README; nunca fornecer variáveis administrativas de testes à produção.
- [ ] Reutilizar a credencial externa Resend disponível, por SMTP/STARTTLS e remetente autorizado; ela não é uma chave que possamos inventar/gerar localmente. Não criar outra integração ou variável `RESEND_API_KEY`.
- [ ] Caso a administração inicial ainda não exista no banco novo, provisioná-la pelo procedimento protegido do README, com senha forte gerada uma única vez e entrega protegida. Não copiar a senha nem o autenticador do ambiente local; a configuração do TOTP pelo QR code cabe ao usuário no primeiro acesso.
- [ ] Não colocar segredos em Git, imagens, argumentos visíveis, respostas de entrega ou logs. Preservar as chaves de cifragem entre releases.

## 4. Publicação inicial pelo control plane

- [ ] Vincular o repositório GitHub ao projeto/aplicações, reutilizando a integração cadastrada no Dokploy; selecionar **main**, nunca `dev`.
- [ ] Fixar o SHA de main para a primeira publicação e configurar os contextos/targets reais das imagens.
- [ ] Criar o banco/roles e executar migration em processo temporário antes de iniciar as aplicações correspondentes; não executar migration automaticamente no startup do servidor web.
- [ ] Aplicar somente a sequência compatível com o banco específico da aplicação. Não executar migrations consolidadas sobre schema legado nem alterar o banco `postgres` ou bancos de terceiros.
- [ ] Respeitar a ABI `collection_court_states(uuid,text)`: nenhuma API antiga pode continuar atendendo durante uma troca incompatível de schema/assinatura.
- [ ] Iniciar ingresso, web, API, despachante e os dois processadores pelo Dokploy, com configuração persistente e sem duplicar supervisores ou agendadores.
- [ ] Registrar a conclusão técnica dos builds, jobs e deployments pela API e entregar IDs, URLs, SHA e logs sem segredos. Isso não substitui validação funcional ou aceite do solicitante.

## 5. Auto-deploy de main

- [ ] Em cada aplicação, configurar o provedor GitHub com `branch=main`, `triggerType=push`, `autoDeploy=true` e `watchPaths` conforme a matriz acima.
- [ ] Garantir que o evento de push chegue pela integração/webhook do Dokploy e que cada build use o contexto/target correspondente. Não criar um webhook concorrente que cause deployments duplicados.
- [ ] Push/merge que altere os caminhos observados deve disparar rebuild/redeploy; mudanças fora desses caminhos não devem reconstruir aplicações sem relação com a alteração. Eventos de `dev` não publicam produção.
- [ ] Manter os segredos e o banco entre redeploys. Auto-deploy de código não significa recriação de banco, migrations destrutivas ou geração de novas credenciais.
- [ ] Para futuras releases com migration incompatível, usar publicação coordenada de migration/API/workers, em vez de deixar deploys independentes correrem em paralelo. Os filtros de observação não constituem um mecanismo de ordenação de migrations.

## 6. Entrega e responsabilidades

- [ ] Entregar ao solicitante: URL pública, links dos recursos no Dokploy, SHA publicado, aplicações implantadas e localização protegida das credenciais.
- [ ] **Solicitante:** realizar validação funcional, aceitar a publicação e decidir/executar recuperação ou rollback. Não iniciar testes de negócio, cadastrar dados de prova, enviar e-mails de teste ou restaurar banco por iniciativa do agente.
- [ ] **Agente/automação:** provisionar/configurar/publicar conforme o plano e acompanhar o estado técnico das operações. Em falha, registrar e informar; não improvisar recuperação, substituir a fonte ou alterar infraestrutura compartilhada.
- [ ] Não modificar a saída de rede atual por causa do DJEN: o solicitante informou que o acesso brasileiro já funciona. Não transportar a saída francesa do servidor de agentes como requisito ou configuração do apps-contabo.

**Domínio de produção definido pelo solicitante:** `painel.alessandraguinosa.adv.br`. Registro na zona `alessandraguinosa.adv.br`: tipo A, nome `painel`, destino `161.97.138.127`. A definição do hostname não comprova propagação DNS ou emissão do certificado; essas operações ainda não foram executadas nesta preparação.

## Referências

- Repositório: `README.md` (variáveis, provisionamento, administração e ABI STF), `tasks/plan.md`, `apps/backend/db/provision*.sql`, `docker/local/nginx.conf.template` (contrato atual de cabeçalhos; não configuração de produção).
- [API Dokploy](https://docs.dokploy.com/docs/api), [aplicações e filtros GitHub](https://docs.dokploy.com/docs/api/application), [servidores](https://docs.dokploy.com/docs/api/server), [PostgreSQL](https://docs.dokploy.com/docs/api/postgres).
- Inventário desta preparação: GET `server.all`, `server.one`, `project.all`, `docker.getContainers`, `docker.getConfig` e `postgres.one`. Somente leitura; nenhum POST de criação/deploy executado.
