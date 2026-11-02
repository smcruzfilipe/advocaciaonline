# Contexto vinculante de deploy — Advocacia Online

## Autorização e responsabilidade

O solicitante autorizou a implantação pelo control plane/API Dokploy. Validação funcional, aceite e decisão/execução de recuperação pertencem ao solicitante. A automação acompanha somente a conclusão técnica de builds, provisionamento, migrations e deployments; não cria dados de prova, testa login/e-mail ou executa rollback por iniciativa própria.

## Infraestrutura confirmada por consultas à API

- Control plane: `https://vmi3631516.contaboserver.net`.
- Autenticação: chave Dokploy existente na configuração protegida do operador. Nunca registrar o valor em documentos, Git, imagens ou logs.
- Destino: **apps-contabo**, cadastrado como **Servidor de Aplicações - SSH**; IP `161.97.138.127`; `serverId=MCtn5oDI73kjE8Cmumg_N`.
- O servidor de agentes/build `173.249.24.22` não é destino de execução das aplicações.
- PostgreSQL existente: **Vertice - Infraestrutura → production → PostgreSQL compartilhado**; `postgresId=utnOfYkn40zt37GpTTFS6`; serviço/DNS `postgres-synthesize-primary-panel-jbxggh`; imagem atual `postgres:18`; sem porta externa publicada.
- Rede existente confirmada: **dokploy-network**, conectada ao PostgreSQL. Reutilizar como externa; não criar substituta.
- Domínio de produção: **painel.alessandraguinosa.adv.br**, registro A para `161.97.138.127`.
- `APP_ORIGIN=https://painel.alessandraguinosa.adv.br`.

## Contratos de implantação

- Criar projeto **Advocacia Online**, ambiente **production**, pelo Dokploy; reutilizar os recursos próprios caso a execução seja retomada.
- Publicar o repositório `smcruzfilipe/advocaciaonline` pela branch **main**, nunca `dev`.
- Configurar integração GitHub, evento `push`, `autoDeploy=true` e `watchPaths` por aplicação.
- Agenda de produção definida pelo solicitante: **segunda a sexta, às 04h00 e 16h00**, fuso `America/Sao_Paulo`. `COLETA_HORARIO_1=04:00`, `COLETA_HORARIO_2=16:00`, `COLETA_DIAS_SEMANA=1,2,3,4,5`; STF somente no primeiro slot. A aplicação deve respeitar os dias, não apenas o fuso do servidor.
- Cinco aplicações permanentes, uma réplica inicial cada: web, API, despachante, processador DJEN e processador STF.
- O Traefik existente encaminha HTTPS diretamente ao frontend. O frontend aceita apenas o IP exato do Traefik em `TRUSTED_PROXY_IP`, valida o IP encaminhado e gera os cabeçalhos internos de autenticação. Não copiar certificados Tailscale nem o Compose local.
- API/web/workers/banco não ganham portas públicas que contornem o Traefik.
- Jobs de provisionamento e migration são temporários e sequenciais; não são outra instância PostgreSQL.
- Criar somente o banco **advocacia_online** e as roles previstas nos scripts do projeto: `advocacia_migrator`, `advocacia_runtime`, `advocacia_despachante`, `advocacia_processador`.
- Não alterar configuração, volumes, senhas, roles ou bancos de outras aplicações; não recriar/reiniciar o PostgreSQL compartilhado.
- Gerar segredos criptográficos e senhas na primeira implantação, persistir na configuração protegida do Dokploy e reutilizar entre redeploys. Nunca gerar novas chaves automaticamente em cada push.
- Conexão administrativa somente no job de provisionamento; migrator somente no job de migration; cada aplicação recebe apenas suas credenciais necessárias.
- Aplicar migrations antes das aplicações correspondentes. A ABI `collection_court_states(uuid,text)` exige atualização coordenada; filtros de observação não ordenam migrations.
- Não modificar a saída de rede por causa do DJEN: o solicitante informou que o acesso brasileiro já funciona.

## Divisão histórica da implantação inicial

O integrador é o único responsável pelas operações mutantes remotas e pelo manuseio dos segredos. Workers recebem contexto sem credenciais, investigam e produzem artefatos independentes; não fazem chamadas privadas, SSH, alterações Git, Docker ou deploy remoto. Builds/verificações agregadas ficam com o integrador, respeitando a validação funcional reservada ao solicitante.

1. **Ingresso original:** Dockerfile e configuração Nginx que antecederam a substituição pelo encaminhamento direto do Traefik.
2. **Banco:** bootstrap PostgreSQL específico e instruções de migration, baseados em `apps/backend/db/provision*.sql`, `apps/backend/bin/migrate` e README. Sem senhas embutidas; sem alterações em terceiros.
3. **API Dokploy:** schemas e operações oficiais de projeto/ambiente/aplicações/GitHub/build/env/rede/domínio/deployment, incluindo jobs de execução única e acompanhamento técnico.

Artefatos de trabalho temporários desses slices podem ficar fora do Git. Este contexto e o [checklist de deploy](deploy-checklist.md) permanecem no repositório; não devem ser removidos como scaffolding de prova.

## Fontes de verdade

- [Checklist de deploy](deploy-checklist.md).
- [README](../README.md): variáveis, roles, provisionamento, administração e ABI STF.
- [Regras YAGNI](../YAGNI.md).
- [API oficial Dokploy](https://docs.dokploy.com/docs/api).
- Dockerfiles existentes em `apps/backend`, `apps/web`, `apps/etl` e `apps/stf`; scripts de provisionamento em `apps/backend/db/`.

As consultas iniciais ao control plane foram somente leitura. Estados efetivamente implantados, IDs e resultados devem ser registrados após observação; o plano não substitui evidência de execução.
