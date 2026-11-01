# Tarefas: acompanhamento de processos do STF

**Estado:** spec, to-do e continuidade one-shot aprovados expressamente pelo solicitante. Planejamento STF00 concluído documentalmente; implementação iniciará pelos contratos do [plano técnico](plan-stf.md). Issue própria: [#20](https://github.com/smcruzfilipe/advocaciaonline/issues/20). Fonte normativa: [SPEC-stf.md](../SPEC-stf.md), critérios C1–C9. Preservar os planos de DJEN, primeiro acesso e agenda. O workflow exige um único PR; não abrir um PR de scaffold ou apenas de marca como se fosse a feature.

## Fontes, execução e rastreio

- O escopo é o da spec, não uma cópia da coleta DJEN. Aplicação independente em `apps/`; `apps/stf/` e os nomes novos abaixo são **propostos**, a ratificar em STF00. Não criar arquivos só porque aparecem neste planejamento.
- Cada folha exige aceite, dependências, arquivos ratificados e verificação focada. Se uma alteração ultrapassar cinco arquivos por folha, incluindo este checklist, subdividir antes de editar. Não omitir callers, testes ou README para cumprir o limite.
- Antes de concluir cada folha de implementação, cumprir as seções Correção e Qualidade da [Definition of Done](../.agents/references/definition-of-done.md), incluindo comportamento em runtime e regressões aplicáveis, com evidência ou justificativa de não aplicação. Verificações agregadas no gate não autorizam carregar dívida entre folhas; não adicionar nova aprovação humana intermediária.
- Documentação acompanha a mudança que altera o contrato. Toda variável criada/alterada entra no README na mesma folha, com nome, default ou `Nenhum`, obrigatoriedade e finalidade; nenhuma variável foi criada por esta autoria.
- Reusar contratos SQL, PostgreSQL/RLS, autorização, registro operacional e consulta existentes quando compatíveis. Campos e funções hoje exclusivos DJEN exigem migração explícita; não afrouxar o contrato DJEN nem migrar toda a arquitetura como refatoração lateral.
- Desenvolvimento/testes não usam banco persistente do usuário, credenciais reais de teste em commits nem a instância de deploy. Containers de prova são descartáveis e não root. Não parar a aplicação local que o usuário está testando.
- O planejador fornece contexto confiável. Nenhum parâmetro de tenant enviado pelo cliente concede acesso. Não criar cadastro/modelo paralelo de usuário, perfil profissional ou vínculo advogado–parte no produto para fazer a prova passar. Fixtures sintéticas de identidade nos bancos descartáveis de prova são permitidas para exercitar os contratos reais de autenticação/isolamento; não são contas reais, bypass de runtime nem dependência do produto.
- Evidência registra comando/cenário, resultado observado e artefato. Resultado zero e dados de relógio controlado devem ser descritos como tais. HTTP 401/403, página de login ou bloqueio não significam zero movimentos.
- Sem retries, abstração de fontes, mensageria, agendamento genérico, MNI, backfill, downloader de documentos, alertas ou infra de deploy “aproveitando” a tarefa.

## Fases e gates

| Fase | Folhas | Entregável | Gate de saída |
|---|---|---|---|
| Planejamento | STF00.A–C | Plano técnico revisável na issue STF, contratos e handoff | Busca reproduzível, atividade, data, persistência, identidade, rollout e integrações definidos; questão externa real identificada com tentativas e impacto, sem alegar gate aprovado |
| Execução inicial | STF01–STF05 | Mesmo fluxo de coleta/persistência funcional e único PR draft | Trabalho STF percorre JSON/HTML, filtra tramitação/data e persiste dados/links; teste focado e smoke com banco real de prova; prova positiva controlada, zero e falha distinguíveis |
| Refinamento | STF06–STF09 | Mesmo PR draft integrado ao planejador e superfícies aplicáveis | Entrada definitiva em execução controlada termina e produz resultados canônicos; PostgreSQL Docker local descartável, consulta autorizada, links seguros e isolamento comprovados |
| Finalização | STF10.A–C | Mesmo PR aberto fora de draft | C1–C9, checklist e Definition of Done completos; smoke definitivo antes da limpeza, verificações afetadas repetidas, reviews resolvidas e CI terminal verde |

A fase seguinte só começa depois do gate anterior observado e registrado. Pendência técnica corrigível é trabalho da fase, não motivo de declarar `blocked`. Acesso/credencial ou decisão externa realmente ausente deve indicar o que falta, o que foi tentado e a entrada exata necessária. A autoria desta spec/to-do não satisfaz o gate Planejamento.

## Planejamento

### STF00.A — Consolidar autoridade, issue e interfaces

- [x] Confirmar spec, este checklist e escopo na issue própria STF; não reutilizar issue #16, de primeiro acesso. Publicar plano/handoff com referências, sem copiar relatórios extensos ou segredos.
- [x] Inventariar os consumidores afetados: planejador, SQL de trabalhos/resultados/comunicações, roles/RLS, coletor/processador, consulta API, histórico, dashboard e frontend. Para cada um, indicar mudança ou `intencionalmente inalterado`, com motivo e prova requerida.
- [x] Fixar responsabilidades e contrato de trabalho/captura entre planejador, coletor e processador. Ambos são coordenados pelo planejador; não presumir pipeline obrigatório nem executar STF dentro do Rails ou do worker DJEN.
- [x] Ratificar caminhos, símbolos, comandos STF, dependências mínimas e folhas de até cinco arquivos; nenhum comando proposto pode ser apresentado como existente ou executado.

**Aceite:** spec e issue correspondem; fronteiras e inventário permitem implementar sem segunda convenção. **Dependências:** nenhuma. **Arquivos:** `SPEC-stf.md`, este checklist e referências dos contratos existentes; issue/handoff externos. **Verificação:** revisão documental contra arquitetura, implementação e pedido; registrar URLs e conflitos, se houver. **Critérios:** C1, C9.

### STF00.B — Resolver contratos de fonte, tempo e identidade

- [x] Definir paginação completa e validação do JSON; confirmar `processosEmTramitacao=sim` para parte e filtro local `Sim` para advogado, sem prometer filtro remoto não demonstrado.
- [x] Validar o caminho direto de processo CNJ e classe/número, inclusive como comprovar tramitação. Não considerar ausência de baixa prova de atividade nem encerrar essa modalidade sem entregá-la.
- [x] Fixar data corrente `America/Sao_Paulo`, cadência diária no planejador, virada, concessões e limites reais de acesso; não alterar os dois slots DJEN por inferência.
- [x] Definir schema/persistência transacional, chave durável de captura/entrega, retomada e concorrência. Preservar dois eventos iguais ou com mesma peça; ausência de ID nativo segue pendente, sem deduplicação enganosa entre capturas nem contagem indevida na dashboard.
- [x] Registrar política de acesso recorrente ao portal diante de `robots.txt`; não executar ciência MNI ou contornar restrições. Se uma autorização externa for indispensável e ausente, documentar o bloqueio da ativação diária e concluir todo trabalho independente alcançável.

**Aceite:** busca, elegibilidade, data, identidade e persistência têm regras implementáveis e limites de evidência explícitos. **Dependências:** STF00.A. **Arquivos:** `SPEC-stf.md`, este checklist; caminhos de contrato compartilhado somente se necessários e ratificados antes da edição. **Verificação:** GETs de fonte descoberta e cenários de contrato, sem baixar intimações ou fingir varredura das 393 ocorrências. **Critérios:** C2–C6, C8.

### STF00.C — Rollout, provas e handoff de implementação

- [x] Definir ativação e parada do processo STF sem afetar DJEN, migrações/roles e rollback que preserve dados; sem deploy ou nova instância PostgreSQL.
- [x] Definir extensão fonte STF e payload de consulta; separar identidade local, identidade nativa e deduplicação DJEN. Manter métricas DJEN e mascaramento intactos salvo alteração explicitamente contratada.
- [x] Fixar provas positivas determinísticas e smoke da entrada definitiva. Fonte real sem movimentos hoje prova sucesso vazio, não persistência positiva; não habilitar parâmetro público de data histórica para fabricar o smoke.
- [x] Publicar handoff final da fase com entregáveis, arquivos/símbolos, slices independentes, não objetivos, comandos e gates. Registrar conclusão somente após observação.

**Aceite:** gate Planejamento revisável, publicado e sem dúvida arquitetural bloqueante. **Dependências:** STF00.B. **Arquivos:** spec, checklist e índice de capacidades quando necessário; issue/handoff. **Verificação:** conferir o inventário e os nove critérios da spec contra cada folha seguinte. **Critérios:** C1–C9.

## Execução inicial

### STF01 — Persistência e concessão STF isoladas

- [x] Implementar migrations incrementais e interfaces SQL STF de trabalhos/capturas/resultados/vínculos conforme STF00, com contexto confiável, roles restritas, RLS e unicidade atômica da entrega.
- [x] Preservar restrições DJEN, histórico e dados existentes; impedir que processadores reclamem trabalhos da fonte errada. Commit e estado de resultado devem refletir conclusão real.
- [x] Provar dois tenants, falta de contexto, concorrência, perda de concessão e replay da mesma entrega; persistir eventos distintos sem usar ID de peça como identidade.

**Aceite:** escrita/leitura real isolada e transacional, sem bypass ou colapso de eventos. **Dependências:** STF00.C. **Arquivos prováveis:** novas migrations e testes em `apps/backend/`, provisionamento de role quando necessário; subdividir schema/concessão/commit antes de exceder o limite. **Verificação:** testes SQL/integração e smoke em PostgreSQL descartável com as roles reais. **Critérios:** C1, C6.

### STF02 — Coletor JSON de processos elegíveis

- [x] Implementar acesso HTTP e descoberta nominal paginada, validação da resposta e conferência do nome completo pelo contrato de monitoramentos.
- [x] Filtrar tramitação afirmativa, preservar todas as associações e distinguir nenhum elegível de pesquisa falha/parcial. Não truncar em primeira página ou no limite visual do portal.
- [x] Cobrir páginas cheias/parciais, erro tardio, metadados inconsistentes, nomes não exatos, homônimos, processo arquivado e situação desconhecida.

**Aceite:** lista de candidatos elegíveis e vínculos completos para a captura, sem aceitar `id`/`pessoaId` como incidente. **Dependências:** STF00.C; contrato STF01 definido antes da integração. **Arquivos propostos:** `apps/stf/lib/stf/discovery.rb`, `apps/stf/lib/stf/http.rb`, `apps/stf/test/discovery_test.rb`, dependências/documentação se necessárias. **Verificação:** Minitest focado com respostas controladas e consulta pública limitada declarada; não confundir amostra com varredura integral. **Critérios:** C2.

### STF03 — Resolução de processo e extração da aba

- [x] Resolver classe/número ou CNJ, confirmar identidade e tramitação conforme STF00.B, reutilizar incidente vindo do JSON quando disponível e rejeitar identificações contraditórias.
- [x] Extrair cada andamento com data, título e opcionais reais. Conservar URL original/aba, âncoras relativas/absolutas e URLs em texto do próprio item; não usar hints genéricos como observação.
- [x] Cobrir dois itens iguais, peça compartilhada, ausência opcional, URL externa, caracteres escapados, data inválida, HTML incompleto e shell de bloqueio/login.

**Aceite:** resultados estruturados fielmente à fonte, sem browser obrigatório, peça executada ou link atribuído ao evento errado. **Dependências:** STF00.C. **Arquivos propostos:** `apps/stf/lib/stf/process_lookup.rb`, `apps/stf/lib/stf/andamentos.rb`, testes correspondentes; subdividir transporte se tocar arquivo de STF02. **Verificação:** testes focados e comparação de uma captura real declarada com os itens do HTML, sem tratar histórico como resultado do dia. **Critérios:** C3, C5.

### STF04 — Processador: somente hoje e entrega transacional

- [x] Consumir trabalho confiável do planejador, executar busca/obtenção pelos contratos ratificados e filtrar por data do andamento, não autuação ou data citada em observação.
- [x] Interromper na virada/perda de concessão; entregar os dados e vínculos na interface SQL STF. Retomada preserva captura/identidade e não reaplica a mesma entrega.
- [x] Registrar terminal, sucesso vazio, sem elegíveis, falha e parcial corretamente; não criar tentativas/backoff extras fora da decisão de STF00.

**Aceite:** caminho completo fonte → filtro → PostgreSQL, com dados e links positivos, zero e falha distinguíveis. **Dependências:** STF01–STF03. **Arquivos ratificados:** `apps/stf/lib/stf/processor.rb`, `apps/stf/lib/stf/store.rb`, `apps/stf/lib/stf/worker.rb`, `apps/stf/bin/processador` e `apps/stf/test/processor_test.rb`, subdivididos conforme o plano. **Verificação:** teste focado e smoke executando a entrada real contra banco descartável; relógio controlado somente no ambiente de teste. **Critérios:** C4–C6, C8.

### STF05 — Gate inicial e PR draft

- [x] Integrar fatias com uma única rodada agregada dos checks necessários, corrigindo causas e repetindo somente verificações afetadas.
- [x] Registrar comandos e contagens observadas, resultado da execução e dados/vínculos persistidos; assegurar ausência de alterações em dados reais ou credenciais.
- [x] Publicar a branch e um único PR draft com escopo, issue, evidências e limitações reais. Não marcar C1–C9 ou o gate final como completos pela abertura do PR.

**Aceite:** gate Execução inicial demonstrado e feature no PR draft. **Dependências:** STF04. **Arquivos:** conjunto implementado e este checklist, sem nova camada funcional. **Verificação:** smoke e checks agregados correspondentes ao escopo inicial. **Critérios:** C8, C9.

## Refinamento

### STF06 — Integração diária ao planejador

- [ ] Planejar critérios do perfil/partes/processos elegíveis e fonte STF respeitando filtros e cadência diária ratificada, sem duplicar o planejador ou alterar DJEN.
- [ ] Integrar coletor/processador ao mecanismo durável, seleção/concessão corretas por fonte e retomada do dia; manter alterações/desativações aplicáveis apenas aos próximos planos.
- [ ] Provar acionamento definitivo sem UUID digitado como único caminho, concorrência de executores, reinício e virada; execução antiga não consulta data anterior.

**Aceite:** trabalho diário vai a estado terminal pelos processos reais e preserva os contratos congelados. **Dependências:** STF05. **Arquivos prováveis:** integração no planejador, interface SQL, entrada STF e testes próprios; subdividir antes da edição conforme STF00. **Verificação:** cenário controlado em PostgreSQL Docker descartável com processos independentes e observação de estados/linhas. **Critérios:** C1, C4, C6, C8.

### STF07 — Consulta API e estado operacional

- [ ] Estender lista/detalhe e histórico aplicáveis para reconhecer STF e o payload ratificado sem supor campos DJEN; conservar origem, dados, links e identidade pendente.
- [ ] Aplicar autorização por tenant/tribunal e não revelar resultados por IDs, agregações ou cache. Falha não pode virar zero; pendentes não entram como comunicações deduplicadas nas métricas DJEN.
- [ ] Migrar callers/testes afetados no mesmo conjunto da mudança de contrato, preservando consulta DJEN e máscara `*`.

**Aceite:** dados STF persistidos são consultáveis somente pelo escopo correto e os estados são honestos. **Dependências:** STF06. **Arquivos existentes a avaliar:** `apps/backend/app/services/communication_query.rb`, `apps/backend/app/services/dashboard_snapshot.rb`, controladores e testes de integração; cada folha deve explicitar os realmente afetados antes de editar. **Verificação:** chamadas HTTP reais com dois tenants, tribunal negado, identidade pendente e falha; regressões DJEN afetadas. **Critérios:** C6–C8.

### STF08 — Comunicações web, links e marca STF

- [ ] Apresentar andamentos STF individualmente na superfície existente, com origem navegável, documentos/links externos rotulados e aviso de identidade quando aplicável.
- [ ] Integrar a marca oficial preservada e sua procedência; escapar conteúdo e aceitar somente links navegáveis seguros, sem download automático, HTML executado ou nova tela administrativa.
- [ ] Provar detalhes, fonte sem links e com múltiplos links, negação e estados de erro no navegador headless; não transmitir dados sintéticos a destinos externos para provar clique.

**Aceite:** usuário autorizado lê os dados e consegue abrir origem/links corretos, sem quebra de DJEN ou vazamento. **Dependências:** STF07. **Arquivos:** consumidores existentes em `apps/web/src/` identificados por referências em STF00; usar `apps/web/src/assets/courts/STF.png` e `sources.json`, não duplicar asset. **Verificação:** superfície real integrada à API/banco de prova, lint/typecheck/build e testes existentes afetados; não criar testes que só confiram cópia de texto ou wiring. **Critérios:** C5, C7.

### STF09 — Runtime, CI e prova integrada terminal

- [ ] Entregar a imagem própria mínima STF, somente runtime/dependências/artefatos necessários, com build multi-stage quando necessário e processos não root; não adicionar outra instância PostgreSQL de deploy.
- [ ] Integrar os comandos/testes reais ao CI, com banco descartável e roles de verdade. Registrar tamanho/base/usuário e execução efetiva, sem afirmar conformidade apenas pela instrução `USER`.
- [ ] Executar cenário definitivo com planejador e processos STF, persistência e consulta: resultado positivo controlado, sucesso vazio, falha, duplicata de entrega, dois eventos iguais, isolamento e virada. Registrar também os limites da consulta à fonte real.

**Aceite:** gate Refinamento demonstrado no mesmo PR draft, sem serviço falso, fonte trocada ou teste enfraquecido. **Dependências:** STF06–STF08. **Arquivos propostos:** `apps/stf/Dockerfile`, dependências/lockfile e workflow necessário; README atualizado junto às variáveis, com folhas separadas se preciso. **Verificação:** comandos ratificados, usuários/processos observados, saída terminal e leitura SQL/HTTP reais. **Critérios:** C1–C8.

## Finalização

### STF10.A — Caminho definitivo e pronto integral

- [ ] Provar primeiro a entrada definitiva, a persistência e a consulta com a configuração final da feature; não usar somente script auxiliar ou fixture inicial como gate.
- [ ] Conferir C1–C9, todos os callers e cada item da Definition of Done. Registrar evidência ou justificativa de não aplicação ligada ao escopo, sem encerrar item só por existir comando ou arquivo.
- [ ] Atualizar documentação de operação, fonte, limites, variáveis, segurança e rollback. Remover afirmações históricas que passem a contradizer os contratos alterados, sem reescrever a história de outras features.

**Aceite:** contrato final e smoke aprovados tecnicamente com evidência revisável. **Dependências:** STF09. **Arquivos:** README, contratos afetados, spec e checklist conforme alterações reais. **Verificação:** matriz C1–C9 e pronto transversal, com resultados do ambiente final de prova. **Critérios:** C1–C9.

### STF10.B — Limpeza após prova definitiva

- [ ] Remover somente fixtures/scripts/configurações usados exclusivamente na prova inicial, depois de STF10.A; preservar testes permanentes de comportamento e dados/artefatos do usuário.
- [ ] Reexecutar as verificações afetadas pela limpeza e confirmar que a entrada definitiva não dependia desses artefatos.

**Aceite:** nenhum artefato exclusivo da prova é necessário ao produto, sem remoção de cobertura útil. **Dependências:** STF10.A. **Arquivos:** somente os comprovadamente exclusivos da prova. **Verificação:** smoke final e checks afetados após limpeza. **Critérios:** C8, C9.

### STF10.C — Reviews, CI e PR pronto

- [ ] Resolver todos os achados e threads aplicáveis, esperar reviews e CI em estado terminal; `pending`, cancelado ou thread aberta não equivalem a aprovação.
- [ ] Confirmar checklist sem item `agora`/`fase posterior`, com todos os concluídos ligados à evidência e todos os não aplicáveis justificados. Não marcar tarefas de outros planos como concluídas.
- [ ] Atualizar o mesmo PR com evidências e riscos, retirar draft apenas após todos os gates e entregar o link. Não fazer merge/deploy nem parar o ambiente local sem autorização.

**Aceite:** único PR aberto, fora de draft, CI verde e reviews resolvidas, sem pendência mascarada. **Dependências:** STF10.B. **Arquivos:** checklist/handoff e correções estritamente necessárias aos achados. **Verificação:** estado remoto de checks/reviews/threads e smoke definitivo registrado. **Critério:** C9.

## Handoff e evidências

Issue e plano publicados: [#20](https://github.com/smcruzfilipe/advocaciaonline/issues/20); decisões, inventário, subdivisões e comandos em [plan-stf.md](plan-stf.md). Prova de fonte STF00.B: aba de partes do incidente `7728350` e API pública `PARTE/sim` retornaram o mesmo incidente/CNJ em tramitação, HTTP 200, uma página. Não é prova de execução da implementação. Próximas evidências e PR serão registrados aqui sem segredos.

| Artefato | Estado |
|---|---|
| Spec STF | Criada em `SPEC-stf.md` |
| Checklist STF | Este documento; itens de execução não realizados permanecem abertos |
| Issue e plano/handoff publicado | [#20](https://github.com/smcruzfilipe/advocaciaonline/issues/20), [plano técnico](plan-stf.md); gate documental STF00 concluído |
| PR STF | [#21](https://github.com/smcruzfilipe/advocaciaonline/pull/21), draft; execução inicial publicada no commit `2e1c8c8` |
| Testes/smoke de execução inicial | Gate corrigido: aplicativo STF **50 testes/201 assertions**, SQL STF **16 testes/192 assertions**, sem falhas/erros/skips. CLI real preserva dois movimentos/links e proveniência mesmo vazia; HTML truncado agora termina `invalid_source`, não sucesso vazio. Rodadas anteriores e correções constam abaixo. |
| Ativação diária/deploy | Não realizada; depende dos gates e condições de acesso |

### Evidências da execução inicial

- Migrations incrementais `20261102000006` e `20261102000007` aplicadas no PostgreSQL Docker descartável com roles reais. Timestamps inicialmente futuros foram corrigidos antes da aplicação; não foi desabilitada a proteção Rails.
- `docker run --rm --network advocacia-stf-ci -e PROCESSADOR_DATABASE_URL -e PROCESSADOR_TEST_ADMIN_DATABASE_URL advocacia-stf:test`: **46 testes, 185 assertions, zero falhas/erros/skips**.
- Caso de processo arquivado: regressão primeiro falhou (`inactive` esperado, `nil` recebido); consulta de situação passou a usar `sim` e depois `nao` quando necessário. Descoberta focada: **13 testes/35 assertions**, sem falhas.
- A suíte backend inicial executou **571 testes/12.085 assertions**, com uma falha apenas na exigência incidental do nome antigo da constraint; essa assertion foi removida sem repinar nome nem remover a prova de rejeição de editais. Reexecução afetada: **1 teste/10 assertions**, sem falhas. Na prova de FK entre tenants, o ordinal da fixture foi corrigido para não colidir antes da checagem de FK; assertion de `ForeignKeyViolation` preservada e aprovada.
- Smoke da imagem runtime pela entrada `bin/processador JOB_UUID`, com fonte controlada externa ao produto: positivo `succeeded`, 2 movimentos pendentes; processo sem andamentos `succeeded`, 0 movimentos/1 elegível; nenhum elegível `succeeded`, 0/0; falha `source_unavailable`, exit1. Dados lidos pela role `advocacia_runtime`, 2 links por movimento e UID1000.
- HTTP real do aplicativo: JSON por parte confirmou `Rcl 101463` em tramitação; HTML retornou zero andamentos da data corrente da execução, corretamente. Nenhuma peça foi aberta; não é prova positiva de movimentos reais do dia.
- Runtime Alpine: 186.008.247 bytes não comprimidos, UID1000 observado, sem testes, gcc ou cache de gems. Fonte e SQL não exigiram novas variáveis; usos STF das conexões existentes documentados no README.

### Correções observadas no gate inicial

- Consulta direta de situação só confirma atividade depois de validar todas as páginas. Regressão falhou antes e passou depois; descoberta focada: 14 testes/36 assertions. A busca de inativos permanece explícita por `nao`, sem inferir baixa por ausência.
- Política de fixture esclarecida: a proibição é cadastro/modelo paralelo no produto ou bypass; identidades sintéticas em banco descartável exercitam autenticação e RLS reais e não são dependência do produto.
- Comparação do parser implementado com um HTML real: 9 itens históricos e URLs coincidem item a item, incluindo uma peça compartilhada por dois movimentos. Diagnóstico da biblioteca sem persistência/backfill, não movimento de hoje.
- RLS sem contexto: teste PostgreSQL real provou zero capturas/comunicações sem sessão, somente o tenant correto com sessão válida e zero após rollback/reutilização ou hash inválido: 1 teste/9 assertions.
- Migration incremental `20261102000008` conserva CNJ, classe/identificação, evidência `Sim` e vínculo ao trabalho mesmo quando não há movimentos; não fabrica proveniência para capturas legadas. SQL STF completo: **16 testes/192 assertions**, com replay, divergência, concorrência, dois tenants, vazio e ausência de contexto.
- A resposta 200 truncada `<div class='processo-andamentos'><ul>` foi reproduzida como sucesso vazio incorreto na CLI anterior. Parser corrigido usa estrutura/diagnóstico HTML5 da versão Nokogiri fixada, mantém extração HTML4 para markup legado, limita erros e preserva os nove movimentos reais. Aplicativo: **50 testes/201 assertions**, sem falhas/erros/skips.
- Smoke da CLI em imagem sem código montado, somente conexão de processador no runtime: positivo 2 movimentos, processo vazio 0/1 elegível, nenhum elegível 0/0, falha de fonte e HTML truncado terminam respectivamente `source_unavailable`/`invalid_source` com exit1. Leitura de captura vazia por `advocacia_runtime` comprovou metadados e vínculo preservados.
