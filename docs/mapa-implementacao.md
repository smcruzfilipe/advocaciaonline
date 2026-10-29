# Mapa físico do monorepo para as fatias

Este mapa reúne caminhos existentes e previstos dentro do mesmo repositório; o estado de cada componente está na [estrutura do monorepo](../README.md#estrutura-do-monorepo). `backend/`, `backend/despachante/` e `backend/test/` já existem; `frontend/` e `etl/` ainda são previstos. Testes do backend e do despachante ficam em `backend/test/`; testes futuros de frontend e ETL estão previstos em `frontend/tests/` e `etl/test/`. Antes de iniciar cada fatia, confirmar os arquivos exatos no checklist e subdividir quando exceder cinco arquivos; geradores, migrations e configuração podem acrescentar arquivos. Nunca marcar uma fatia pronta apenas por criar diretórios.

| IDs | Áreas físicas existentes ou previstas | Responsabilidade |
|---|---|---|
| 4 | `backend/app/models/`, `backend/app/controllers/`, `backend/app/services/`, `frontend/app/` | onboarding, identidade e tenant |
| 5–6 | `backend/app/models/`, `backend/app/services/`, `backend/app/controllers/`, `frontend/app/` | credenciais, grupos e autorização |
| 7–8 | `backend/app/models/`, `backend/app/services/`, `backend/app/controllers/`, `frontend/app/` | monitoramentos, filtros e navegação |
| 9 | `backend/app/models/`, `backend/app/services/`, `backend/db/migrate/` | Escrevente, permissões e retenção |
| 10 | `backend/despachante/`, `backend/app/models/`, `backend/db/migrate/` | planejamento e agenda persistente |
| 11–12 | `etl/`, `backend/app/models/`, `backend/db/migrate/` | DJEN, persistência, deduplicação e vínculos |
| 13 | `backend/despachante/`, `etl/`, `backend/app/models/` | execução, tentativas e estado |
| 14–15 | `backend/app/controllers/`, `backend/app/services/`, `frontend/app/`, `frontend/components/` | consulta, métricas e dashboard |
| 16 | `backend/test/`, `frontend/tests/`, `etl/test/` | integração e carga |

O mapa não implica que todas as rotas, modelos, migrations ou bibliotecas das fatias estejam implementados. Confirmar os arquivos e comandos de cada componente antes da execução, sem tratar caminhos previstos como existentes. A garantia de isolamento e a análise de impacto são verificadas por fatia, não substituídas por este mapa.

## Migrations iniciais consolidadas

As migrations em `backend/db/migrate/` destinam-se somente à criação de novos bancos de desenvolvimento e definem diretamente o estado final do schema, sem reproduzir alterações intermediárias ou backfills da sequência anterior:

- `20261028000000_create_identity_and_lawyer_profiles.rb`: identidade, vínculos selecionados e contexto de sessão.
- `20261028000003_create_collection_planning.rb`: planejamento, integridade das entidades dos trabalhos, audiência por tenant e estado `interrupted`; integra as antigas migrations 04–06.
- `20261028000004_create_escrevente.rb`: marcos append-only e estado operacional dos trabalhos; substitui a antiga `07_create_escrevente`.
- `20261028000005_create_team_credentials.rb`: credenciais e convites de equipe.
- `20261028000006_create_authorization_groups.rb`: grupos, regras e associações.

Não há rollback destrutivo nem upgrade automático de banco pré-existente. Um banco descartável criado pela sequência anterior precisa ser recriado explicitamente antes de receber o schema inicial atual; o provisionamento e a execução estão descritos no [README](../README.md#imagens-docker-da-api-e-do-despachante).

Evidências de cada alteração e suas limitações estão no [README](../README.md#implementação-e-verificações) e no checklist; resultados anteriores não comprovam versões posteriores das migrations.
