# Mapa físico do monorepo para as fatias

Este mapa reúne caminhos existentes e previstos dentro do mesmo repositório; o estado de cada componente está na [estrutura do monorepo](../README.md#estrutura-do-monorepo). `apps/backend/`, `apps/backend/despachante/`, `apps/backend/test/`, `apps/etl/`, `apps/etl/test/` e `apps/web/` existem. Antes de iniciar cada fatia, confirmar os arquivos exatos no checklist e subdividir quando exceder cinco arquivos; geradores, migrations e configuração podem acrescentar arquivos. Nunca marcar uma fatia pronta apenas por criar diretórios.

| IDs | Áreas físicas existentes ou previstas | Responsabilidade |
|---|---|---|
| 4 | `apps/backend/app/models/`, `apps/backend/app/controllers/`, `apps/backend/app/services/`, `apps/web/src/app/` | onboarding, identidade e tenant |
| 5–6 | `apps/backend/app/models/`, `apps/backend/app/services/`, `apps/backend/app/controllers/`, `apps/web/src/app/` | credenciais, grupos e autorização |
| 7–8 | `apps/backend/app/models/`, `apps/backend/app/services/`, `apps/backend/app/controllers/`, `apps/web/src/app/` | monitoramentos, filtros e navegação |
| 9 | `apps/backend/app/models/`, `apps/backend/app/services/`, `apps/backend/db/migrate/` | Escrevente, permissões e retenção |
| 10 | `apps/backend/despachante/`, `apps/backend/app/models/`, `apps/backend/db/migrate/` | planejamento e agenda persistente |
| 11–12 | `apps/etl/`, `apps/backend/app/models/`, `apps/backend/db/migrate/` | DJEN, persistência, deduplicação e vínculos |
| 13 | `apps/backend/despachante/`, `apps/etl/`, `apps/backend/app/models/` | execução, tentativas e estado |
| 14–15 | `apps/backend/app/controllers/`, `apps/backend/app/services/`, `apps/web/src/app/`, `apps/web/src/components/` | consulta, métricas e dashboard |
| 16 | `apps/backend/test/`, `apps/web/`, `apps/etl/test/` | integração e carga |

O mapa não implica que todas as rotas, modelos, migrations ou bibliotecas das fatias estejam implementados. Confirmar os arquivos e comandos de cada componente antes da execução, sem tratar caminhos previstos como existentes. A garantia de isolamento e a análise de impacto são verificadas por fatia, não substituídas por este mapa.

## Migrations iniciais consolidadas

As migrations em `apps/backend/db/migrate/` destinam-se somente à criação de novos bancos de desenvolvimento e definem diretamente o estado final do schema, sem reproduzir alterações intermediárias ou backfills da sequência anterior:

- `20261028000000_create_identity_and_lawyer_profiles.rb`: identidade, vínculos selecionados e contexto de sessão.
- `20261028000003_create_collection_planning.rb`: planejamento, integridade das entidades dos trabalhos, audiência por tenant e estado `interrupted`; integra as antigas migrations 04–06.
- `20261028000004_create_escrevente.rb`: marcos append-only e estado operacional dos trabalhos; substitui a antiga `07_create_escrevente`.
- `20261028000005_create_team_credentials.rb`: credenciais e convites de equipe.
- `20261028000006_create_authorization_groups.rb`: grupos, regras e associações.

Não há rollback destrutivo nem upgrade automático de banco pré-existente. Um banco descartável criado pela sequência anterior precisa ser recriado explicitamente antes de receber o schema inicial atual; o provisionamento e a execução estão descritos no [README](../README.md#imagens-docker-da-api-e-do-despachante).

Evidências de cada alteração e suas limitações estão no [README](../README.md#implementação-e-verificações) e no checklist; resultados anteriores não comprovam versões posteriores das migrations.
