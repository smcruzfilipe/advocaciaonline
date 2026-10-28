# Mapa físico previsto para as fatias

Os caminhos abaixo são uma proposta de alocação, não arquivos já existentes. Testes ficam nos caminhos correspondentes sob `backend/test/`, `frontend/tests/`, `planner/test/` e `etl/test/`. Antes de iniciar cada fatia, confirmar os arquivos exatos no checklist e subdividir quando exceder cinco arquivos; geradores, migrations e configuração podem acrescentar arquivos. Nunca marcar uma fatia pronta apenas por criar esses diretórios.

| IDs | Áreas físicas previstas | Responsabilidade |
|---|---|---|
| 4 | `backend/app/models/`, `backend/app/controllers/`, `backend/app/services/`, `frontend/app/` | onboarding, identidade e tenant |
| 5–6 | `backend/app/models/`, `backend/app/services/`, `backend/app/controllers/`, `frontend/app/` | credenciais, grupos e autorização |
| 7–8 | `backend/app/models/`, `backend/app/services/`, `backend/app/controllers/`, `frontend/app/` | monitoramentos, filtros e navegação |
| 9 | `backend/app/models/`, `backend/app/services/`, `backend/db/migrate/` | Escriba, permissões e retenção |
| 10 | `planner/`, `backend/app/models/`, `backend/db/migrate/` | planejamento e agenda persistente |
| 11–12 | `etl/`, `backend/app/models/`, `backend/db/migrate/` | DJEN, persistência, deduplicação e vínculos |
| 13 | `planner/`, `etl/`, `backend/app/models/` | execução, tentativas e estado |
| 14–15 | `backend/app/controllers/`, `backend/app/services/`, `frontend/app/`, `frontend/components/` | consulta, métricas e dashboard |
| 16 | `backend/test/`, `frontend/tests/`, `planner/test/`, `etl/test/` | integração e carga |

As rotas, nomes de modelos, migrations e bibliotecas ainda não foram gerados. Por isso não se afirma que estes caminhos ou comandos existam, nem se presume o conjunto final de arquivos por fatia. A garantia de isolamento e a análise de impacto para uma fatia são verificadas antes de implementá-la, não substituídas por este mapa.
