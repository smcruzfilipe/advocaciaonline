# Plano técnico: STF

**Estado:** spec/to-do aprovados pelo solicitante; decisões STF00 abaixo ratificadas para implementação. O [checklist](todo-stf.md) e a [spec](../SPEC-stf.md) governam escopo e aceite. Não constitui evidência de implementação ou autorização de deploy.

## Fonte e atividade

JSON nominal público com paginação completa; conferir nome completo normalizado e `processoEmTramitacao=Sim`. Parte usa `processosEmTramitacao=sim`; advogado também exige filtro local. `processoId` é incidente. Classe/número e CNJ resolvem o detalhe; quando o critério é processo, confirmar a situação pelo JSON de uma parte real lida na aba de partes, exigindo o mesmo incidente/CNJ. Ausência de resultado não prova atividade nem baixa.

Prova observada: incidente `7728350` → aba de partes → `ROBERTO FERREIRA DA SILVA` → JSON `PARTE`, `sim`: HTTP 200, uma página, registro do mesmo incidente e CNJ `0188263-19.2026.1.00.0000`, situação `Sim`. Não demonstra cobertura universal. Nenhuma API JSON de andamentos foi encontrada: obter o fragmento HTML por HTTP e extrair eventos/links do mesmo item, sem browser ou download de peças.

## Contratos ratificados

- Aplicação `apps/stf/`, Ruby/Nokogiri/pg/tzinfo, dependências próprias mínimas. Coletor é a fronteira da fonte; processador executa trabalho confiável. Nenhum serviço HTTP intermediário ou segundo planejador.
- Mesmo mecanismo PostgreSQL de `collection_runs`, `collection_jobs`, concessões, eventos, comunicações e vínculos. Fonte STF, tribunal STF, meio `A` (andamentos); DJEN conserva `DJEN/D`. Extensão dos checks é pareada, não relaxamento geral.
- Planejador cria trabalho STF somente no slot 1 do dia, no `COLETA_HORARIO_1` existente. Não criar nova configuração de horário nem alterar slots DJEN. A audiência e critérios permanecem congelados; o planejamento compartilhado mantém suas falhas identificáveis.
- Catálogo de cadastro/autorização oferece STF como fonte adicional; não criar trabalho DJEN/D para a entrada de portal STF. Filtros explícitos não se ampliam silenciosamente.
- Captura canônica por `(tenant, run, incidente)`, com ID local e ordinal dos itens apenas dentro da captura. Reentrega igual reutiliza itens e acrescenta vínculos; conteúdo de fonte divergente para a mesma chave falha explicitamente. Timestamp de captura não faz parte da igualdade semântica. Dois eventos iguais continuam dois; outra captura não é fundida como identidade nativa.
- `stf_captures` conserva `process_data` (incidente, CNJ, classe/identificação e evidência `Sim`) e `stf_capture_links` conserva os vínculos aos trabalhos mesmo com zero movimentos. Referência/ordinal em comunicações suportam identidade local. Toda comunicação STF permanece `pending`/`possible_duplicate`, com `source_id`, `source_hash` e digest nulos. Não alterar identidade ou métricas DJEN; capturas legadas sem proveniência não recebem backfill inventado.
- Interfaces SQL específicas `stf_processor_next`, `claim_available`, `job`, `renew`, `start`, `commit`, `record_failure`, na schema `app_private`, reaproveitam as roles e os estados atuais. Entradas DJEN recusam jobs STF; entradas STF recusam DJEN. Helpers privados sem grants públicos; SECURITY DEFINER, search_path fixo, RLS/FKs tenant e lease/data verificados no commit.
- `stf_processor_commit(job_uuid, token, processes_json)` recebe lista de processos com `incidente`, `cnj` (20 dígitos canônicos ou JSON null), `classe`, `identificacao`, `publicidade=Público`, `em_tramitacao=Sim`, `capturado_em` ISO8601 e `items`; tenant/run vêm do job confiável. CNJs mascarados são semanticamente equivalentes; timestamps de captura não fazem parte da comparação de conteúdo. `process_data` conserva a primeira captura inclusive vazia e `recorded_at` a primeira persistência, sem inventar instante legado. Resultado contém estado, `source_path=andamentos`, contagens de movimentos pendentes e processos elegíveis. Nenhum elegível difere de processo sem movimentos. Replay terminal não consulta a fonte de novo.
- Fuso `America/Sao_Paulo`; interromper ao perder concessão ou mudar o dia. Sem parâmetro público de retroativo, novos retries ou backoff herdado de DJEN.
- Payload tem projeção explícita para a consulta atual: `siglaTribunal`, `numero_processo`, `nomeClasse`, texto simples e link original; objeto `stf` conserva incidente, identificação, data/título/julgador/observação, URL de coleta, instante de captura e links com URL/rótulo/referência original. O envelope marca source STF; não afirma ser resposta JSON nativa de movimentos.
- UI usa consulta/autorização existentes, aviso de identidade pendente, origem e links seguros, logo preservado. Dashboard continua estritamente DJEN em métricas **e estados**; histórico mostra o trabalho STF real.

## Inventário de consumidores

| Superfície | Decisão |
|---|---|
| `apps/backend/db/migrate/` | Migration incremental após as existentes, com ABI e capturas STF; não reescrever histórico |
| `apps/backend/despachante/collection_despachante.rb` | Planejar STF uma vez por dia, fonte/meio próprios, preservar snapshot e concessões |
| `apps/backend/app/services/court_catalog.rb` | Oferecer STF explicitamente, distinguindo sua origem de DJEN no planejamento |
| `apps/etl/` | ABI/seleção SQL conserva DJEN; não importar nem mover processamento para outro app |
| `apps/stf/` | Novo runtime de fonte, processamento e entrada worker/UUID, imagem própria não root |
| `communication_query.rb` e endpoints existentes | Reusar DTO, RLS e autorização; adição explícita do objeto STF, sem novo login/API paralela |
| `dashboard_snapshot.rb` e estados SQL | Filtrar fonte DJEN onde necessário, sem alterar fórmula, máscara ou janelas |
| Histórico de coletas | Exibir fonte/meio e contagens/resultado STF distinguíveis |
| Comunicações web e CourtSymbol | Dados, links, rótulos e marca STF; não nova tela administrativa |
| README e CI | Comandos reais, configuração e gates agregados na mesma mudança que introduz variáveis |
| Identidade, TOTP, SMTP, convites, agenda | Intencionalmente inalterados: não pertencem ao escopo |
| Compose local e banco persistente | Intencionalmente inalterados: preservar teste do usuário; usar recursos descartáveis próprios |

## Decomposição e verificação

Os IDs canônicos STF00–STF10 permanecem no checklist. Subdivisões de implementação abaixo têm até quatro arquivos funcionais mais rastreio; nomes adicionais só após ratificação antes da edição. Migrations grandes devem ser separadas por responsabilidade, sem criar arquivos sem consumidor.

| Folha interna | Arquivos/área ratificados | Aceite e prova |
|---|---|---|
| STF01.A | Migration de checks/capturas e teste SQL STF | Fonte pareada, RLS/tenant e multiplicidade reais |
| STF01.B | Migration de ABIs e teste SQL STF | Claims exclusivos, lease, commit, replay e concorrência |
| STF02.A | Gemfile/lockfile, HTTP e teste | HTTPS hosts permitidos, timeout/bytes, sem retry ou bypass |
| STF02.B | Discovery e teste | Paginação, matching, filtro `Sim`, falha tardia |
| STF03.A | Lookup, parser e testes correspondentes | CNJ/classe, atividade, datas, links e multiplicidade |
| STF04.A | Processor, store SQL e testes | Fonte → filtro diário → entrega transacional |
| STF04.B | Entradas e Dockerfile | Execução real worker/UUID e usuário não root |
| STF05 | Evidências e PR draft | Uma rodada focada agregada, smoke positivo/zero/falha |
| STF06.A | Planejador, catálogo e testes correspondentes | Slot 1 STF, slot 2 DJEN, filtros/snapshot preservados |
| STF07.A | Consulta/estados e testes HTTP correspondentes | Tenant/tribunal, estado STF e métricas DJEN isolados |
| STF08.A | Apresentação de detalhe/tipos/helpers/testes | Links seguros e dados do movimento sem executar HTML |
| STF08.B | Marca/rótulos e consumidores necessários | Superfície real e histórico sem reclassificar `A` como `D` |
| STF09.A | Workflow e README | Checks reais, imagens e variáveis documentadas |
| STF10 | Checklist, docs e correções de review | Smoke definitivo, limpeza posterior, CI terminal verde |

Comandos STF serão os executáveis reais do aplicativo, via Bundler/Minitest nos targets test/runtime da imagem, com PostgreSQL 18 descartável e roles provisionadas. A rodada de cada gate será registrada no handoff com contagens observadas; scripts auxiliares não substituem a entrada definitiva. Fonte/relógio controlados provam positividade, erros e virada; leitura real pode terminar validamente com zero eventos do dia. Não apresentar essa leitura como prova positiva.

## Fases, integração e rollout

A ordem e gates são os de [todo-stf.md](todo-stf.md#fases-e-gates). SQL e fonte/runtime podem ser implementados em paralelo após este contrato. Planejador e superfície de consulta entram no Refinamento, depois do primeiro gate e do PR draft. Pai integra e executa verificações; workers não rodam suites/build/lint/formatter.

Ativar worker STF é operação separada do deploy desta mudança. Antes de uso recorrente, conferir condições da fonte: `robots.txt` exclui `/processos`; a leitura observada não prova autorização institucional. Não contornar restrições nem iniciar crawler contínuo contra o portal nesta máquina. A integração e provas controladas devem funcionar sem depender dessa ativação operacional. Para parar/rollback, encerrar o worker STF e preservar dados; DJEN continua, sem downgrade destrutivo ou nova instância PostgreSQL.

## Handoff

Issue, PR, comandos e resultados observados serão registrados em [todo-stf.md](todo-stf.md#handoff-e-evidências). Não há alegação de gate concluído sem prova. A aprovação recebida libera a implementação deste escopo sem novos checkpoints genéricos; conflito normativo ou acesso externo ausente deve ser descrito exatamente, após concluir o trabalho independente alcançável.

## Comandos ratificados para a implementação

Executar na raiz do monorepo. As entradas e targets abaixo serão implementados nos slices; não são alegados como já disponíveis ou verificados no gate documental.

```bash
docker build --target test -t advocacia-stf:test apps/stf
docker build --target runtime -t advocacia-stf:runtime apps/stf
docker run --rm --network advocacia-stf-ci \
  -e PROCESSADOR_DATABASE_URL -e PROCESSADOR_TEST_ADMIN_DATABASE_URL advocacia-stf:test
docker run --rm --network advocacia-stf-ci \
  -e PROCESSADOR_DATABASE_URL advocacia-stf:runtime bundle exec ruby bin/processador --once
docker run --rm --network advocacia-stf-ci \
  -e PROCESSADOR_DATABASE_URL advocacia-stf:runtime bundle exec ruby bin/processador JOB_UUID
```

`apps/stf/bin/processador` sem argumentos executa o worker contínuo; `--once` seleciona pela fila e termina após um ciclo, permitindo prova controlada da mesma seleção automática, e UUID executa um trabalho específico. Nenhum modo aceita data histórica. O target `test` executa os testes Minitest em `apps/stf/test/` por Bundler; o comando focado de descoberta será `bundle exec ruby -Itest test/discovery_test.rb`, condicionado à criação do arquivo na implementação. As duas variáveis de conexão são contratos já existentes, fornecidas somente no ambiente protegido do teste/processador e nunca ao navegador.
