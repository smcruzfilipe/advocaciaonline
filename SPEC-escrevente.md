# Especificação: Escrevente (`escrevente`)

**Estado:** base funcional aprovada pelo solicitante e implementada no backend Rails com interface SQL controlada para o processador. A fronteira renomeada foi verificada em PostgreSQL isolado com roles reais; o processo em `etl/` executa trabalhos já planejados. **ID:** `escrevente`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Manter um registro imutável e consultável do fluxo de coleta, com os marcos de início e término e os dados relevantes disponíveis para rastrear o trabalho por tenant, execução, entidade e tribunal. O Escrevente não é trilha de auditoria de ações de usuários nem repositório de erros técnicos.

## Escopo e contratos lógicos

- **Responsabilidade:** aceitar e acrescentar registros do fluxo de coleta; não os alterar nem excluir.
- **Dependência do mapa:** `identidade`. Chamadas humanas usam usuário e tenant autenticados no servidor; o worker usa identidade de serviço com privilégios mínimos e deriva o tenant de trabalho persistido, reivindicado por interface controlada, nunca de parâmetro externo isolado. A transação estabelece esse tenant antes de gravar; trabalho inexistente ou inconsistente é recusado. RLS complementa, mas não substitui autorização ou contexto confiável.
- **Consumidor lógico:** `coleta` (`SPEC-coleta.md`). A fronteira não exige serviço, processo, armazenamento ou transporte independente.
- **Dados mínimos:** cada marco usa instante de registro confiável e, quando disponíveis, execução, tenant, fonte lógica, referência interna da entidade/monitoramento, advogado, tribunal e processos associados. Não registrar nomes, números de OAB ou de processo em claro, conteúdo da comunicação, e-mail, segredo ou dado desnecessário.
- **Acréscimo e retenção:** marcos não são sobrescritos ou removidos por operações normais. Por decisão do solicitante, não há prazo automático de retenção ou expurgo nesta etapa; não presumir exclusão de registros ou cópias por tempo.
- **Cópias:** backup, restauração e acesso seguem os controles de segurança e isolamento do ambiente. A ausência de prazo automático não implica que dados públicos deixem de ser dados pessoais nem determina sua situação jurídica.
- **Consulta:** apenas o advogado titular pode consultar marcos do próprio tenant; não há acesso de equipe nem concessão por grupo nesta entrega. Listas, detalhes e agregações aplicam o mesmo controle server-side, inclusive para referências sem tribunal.

## Requisitos e critérios observáveis

1. Cada marco de início ou término ocorrido é acrescentado com instante de registro e dados mínimos de rastreio disponíveis; nenhum marco anterior é sobrescrito.
2. Tenant é derivado do contexto confiável no servidor. Tenant enviado pelo cliente não autoriza nem desloca um registro.
3. Uma vez gravado, o registro não pode ser editado ou removido por operações normais do produto. RLS não basta para assegurar append-only; operações e permissões capazes de alterar/remover exigem proteção própria (ver [stack](docs/stack.md)).
4. Registros não contêm ações de usuários, conteúdo de comunicações, identificadores pessoais diretos ou detalhes técnicos de erro. Referências internas necessárias podem constituir dados pessoais e permanecem protegidas.
5. Marco sem término permanece sem término; o estado de falha é mantido separadamente, sem inferência retroativa nem inclusão de detalhe de erro no Escrevente.
6. Nenhum prazo automático de expurgo é exigido para os marcos nesta etapa; acessos e cópias permanecem sujeitos a controle de tenant e segurança.

## Comandos, estrutura e estilo

- **Build e testes:** o backend e seus comandos estão no [README](README.md#implementação-e-verificações). Os testes de fronteira estão em `backend/test/integration/escrevente_processor_test.rb` e `backend/test/integration/escrevente_http_test.rb`. Historicamente, a suíte completa passou com roles reais após a consolidação das migrations, antes desta renomeação; esse resultado não comprova a configuração renomeada.
- **Estrutura física:** o Escrevente fica dentro do backend Rails, não como componente independente. A migration `backend/db/migrate/20261028000004_create_escrevente.rb` define `collection_events` e `collection_job_executions`, substituindo a antiga `07_create_escrevente`; `backend/app/controllers/escrevente_controller.rb` oferece leitura autenticada por tenant. O processador em `etl/` é separado da API e do despachante.
- **Schema inicial:** as migrations consolidadas criam diretamente o estado final em banco inicial vazio, sem upgrade automático de banco pré-existente nem rollback destrutivo. O planejamento e as antigas migrations 04–06 ficam em `backend/db/migrate/20261028000003_create_collection_planning.rb`; um banco descartável criado pela sequência anterior precisa ser recriado explicitamente antes de receber a sequência consolidada.
- **Estilo de código:** seguir os serviços e testes existentes em `backend/app/` e `backend/test/`; as funções SQL controladas ficam no schema `app_private`.

## Estratégia de testes comportamentais

Os cenários abaixo devem ser exercitados com testes de integração Rails e PostgreSQL usando roles reais separadas. Os resultados históricos desta implementação são anteriores à consolidação das migrations e não foram repetidos nesta alteração; não comprovam a sequência consolidada.

- Iniciar e concluir uma coleta produz marcos acrescentados com os dados de contexto e rastreio disponíveis, sem nomes/OAB/processos em claro, conteúdo de comunicações, ações de usuário ou detalhes de erro.
- Uma tentativa normal de alterar ou excluir registro não muda nem remove seu conteúdo; não há expurgo automático por tempo nesta etapa.
- O contexto de tenant autenticado no servidor prevalece; enviar outro tenant pelo cliente não desloca o registro.
- Uma execução sem marco de término permanece sem término registrado, em vez de receber evento fabricado; estado de falha consultável permanece fora do Escrevente.
- Claim concorrente, token ausente, incorreto, de outro trabalho ou expirado não permitem escrita; renovação de lease vigente e retomada após expiração preservam a autorização e os marcos já confirmados.
- Reivindicar novamente um trabalho `failed` conserva a falha até `processor_start`; reivindicar `succeeded` permite somente recuperar a confirmação, sem reexecução, regressão de estado ou novos marcos. Renovação não altera esses estados.
- Marco e transição operacional são atômicos sob concorrência e rollback; concluir sem início é recusado. Planejamento, falha e execução visível sem trabalhos não fabricam término ou sucesso.
- A API devolve os campos documentados, recusa sessão anônima/revogada e execução fora do tenant, e não expõe token, digest, lease ou erro técnico. Runtime e despachante não executam as funções do processador nem assumem sua role.

Exemplos verificáveis da política 2c:

| Caso | Decisão |
|---|---|
| Marco existente após 90 dias | Permanece disponível ao titular autorizado; não existe expurgo automático por tempo. |
| Tentativa normal de editar ou excluir marco | Negada; o conteúdo permanece inalterado. |

## Fronteiras

- **Sempre:** acrescentar registros do fluxo; manter apenas referências mínimas; usar tenant confiável; não registrar ações de usuários, conteúdo, identificadores pessoais diretos, segredos ou detalhes de erro.
- **Pedir aprovação:** alterar dados ou granularidade dos marcos, instituir expurgo ou tornar obrigatório dado hoje apenas disponível.
- **Nunca:** editar ou apagar registros por operação normal; registrar ações de usuários, conteúdo de comunicações, identificadores pessoais diretos, segredos ou detalhes de erro; aceitar tenant informado pelo cliente como autorização.

## Contrato técnico implementado — granularidade aprovada

**Estado:** o solicitante aprovou um marco de início e um de término por trabalho. A fronteira SQL e as consultas HTTP foram verificadas em ambiente de teste isolado; o processador usa essa fronteira para trabalhos planejados.

### Unidade e comportamento

- Há um par de tipos de marco, `started` (início) e `completed` (término), para cada trabalho de coleta identificado por `collection_jobs.id`: a unidade já fixa tenant, execução, entidade, fonte, tribunal e meio. O planejamento de um trabalho pelo despachante não constitui início ou término de coleta.
- O início representa o início efetivo do processamento; o término representa sua conclusão efetiva bem-sucedida. Tentativas e retomadas de um mesmo trabalho não fabricam novos inícios ou términos. Falha final ou interrupção não fabrica término; eventual recuperação bem-sucedida pode acrescentá-lo posteriormente conforme as regras de retomada da coleta.
- `collection_events` conserva somente `id`, `job_id`, `tenant_id`, `event_type` e `recorded_at`, com instante confiável do banco. O contexto de execução, fonte, entidade, tribunal e meio é obtido do trabalho persistido, preservando os vínculos congelados; advogado e processos associados são referenciados somente quando efetivamente disponíveis. Não copiar critérios JSON, nomes, números, conteúdo, e-mail ou detalhes de erro para os marcos.
- A persistência impede duplicação do mesmo tipo de marco para um trabalho, inclusive sob concorrência. Repetir uma operação já confirmada não cria segundo marco; conclusão sem início é recusada. A gravação e a transição operacional correspondente devem ser atômicas, sem transformar falha de gravação em sucesso.

### Fronteiras e segurança

- A consulta é exclusiva do advogado titular, derivada da sessão válida no servidor e limitada ao seu tenant. Identificadores fornecidos pelo cliente não criam autorização; referência inexistente ou de outro tenant não revela dados.
- A gravação é restrita à role de serviço `advocacia_processador`, separada de runtime web, migration e despachante, sem membros ou memberships e sem acesso direto às tabelas. O executor deve comprovar uma reivindicação válida do trabalho persistido; o tenant e o contexto são derivados desse trabalho, nunca de tenant isolado ou de variável de sessão informada pelo chamador. Trabalho inexistente, inconsistente, não reivindicado ou reivindicação inválida é recusado.
- O registro é append-only para operações normais: RLS habilitado e forçado, política por tenant e privilégios mínimos explícitos; runtime e executor não recebem `UPDATE`, `DELETE` ou `TRUNCATE` nos marcos. O proprietário de migration e superusuários mantêm poderes administrativos inerentes, portanto essa proteção não é imutabilidade contra administradores.
- As funções SQL usam `SECURITY DEFINER`, proprietário `advocacia_migrator` e `search_path = pg_catalog, pg_temp`, com objetos qualificados. `EXECUTE` é revogado de `PUBLIC`, runtime e despachante; somente o processador recebe as cinco entradas do Escrevente e as entradas específicas de resultados e tentativas entre as roles normais de execução. RLS não protege `TRUNCATE`, e funções recebem `EXECUTE` para `PUBLIC` por padrão: ver [RLS PostgreSQL 18](https://www.postgresql.org/docs/18/ddl-rowsecurity.html) e [privilégios PostgreSQL 18](https://www.postgresql.org/docs/18/ddl-priv.html). A proteção é contra operações normais, não contra o proprietário de migration ou superusuários.
- Estado de processamento e falha pertence à coleta, em `collection_job_executions`, separado dos marcos e de `collection_jobs.status`, que continua `pending` no plano. Os estados operacionais disponíveis são `pending`, `running`, `succeeded` e `failed`. Resultados, contagens e falhas ficam nas tabelas próprias da coleta, não nos marcos; agregados por tribunal não podem ser inferidos apenas do Escrevente.

### Contrato SQL para processadores e consulta

A interface do processador é SQL no schema `app_private`, não uma rota HTTP de escrita. A fronteira renomeada e o processamento controlado foram exercitados com as roles reais em PostgreSQL isolado.

| Função | Entrada | Retorno e efeito |
|---|---|---|
| `processor_claim(uuid)` | UUID do trabalho persistido | `token text`, `expires_at timestamptz`, `state text`; cria uma reivindicação com lease de 15 minutos, preservando o estado operacional atual e sem registrar início. |
| `processor_renew(uuid,text)` | UUID do trabalho e token vigente | `expires_at timestamptz`; renova a lease por 15 minutos a partir do horário do banco, sem alterar estado ou marcos, inclusive em `failed` e `succeeded`. |
| `processor_start(uuid,text)` | UUID do trabalho e token vigente | `id uuid`, `recorded_at timestamptz` do marco `started`; acrescenta o início e muda `pending` ou `failed` para `running` na mesma transação, ou confirma o marco existente. Em `succeeded`, apenas recupera o início confirmado, sem regressão de estado. |
| `processor_finish(uuid,text)` | UUID do trabalho e token vigente | `id uuid`, `recorded_at timestamptz` do marco `completed`; exige início, acrescenta o término e muda `running` para `succeeded` na mesma transação. Em `succeeded`, apenas recupera o término já confirmado. |
| `processor_fail(uuid,text)` | UUID do trabalho e token vigente | `state text = failed`; registra falha operacional de trabalho `pending` ou `running` e libera a reivindicação, sem acrescentar término ou receber texto técnico de erro. |

- O token é segredo sigiloso vinculado ao trabalho e à reivindicação: o banco persiste apenas o digest SHA-256. Não registrar token em logs, URLs, respostas HTTP ou marcos; não confundir esse segredo com a credencial de conexão do processador. UUID, tenant, nome de serviço ou variável de sessão do chamador não bastam como prova.
- Uma lease ativa impede outro claim do mesmo trabalho. O executor deve renovar antes de expirar durante processamento longo; token vencido ou incorreto é recusado. Novo claim após expiração conserva o estado existente e invalida o token anterior. Após falha, re-claim e renew preservam `failed` até o próximo `processor_start`, sem duplicar o início anterior.
- `state` retornado por claim orienta a retomada. Se for `succeeded`, a reivindicação serve somente para recuperar a confirmação de `started`/`completed`, inclusive após perda da resposta anterior; o executor não deve reexecutar a coleta. Nenhuma chamada pode regredir esse sucesso nem fabricar novos marcos.
- A leitura do trabalho e a verificação da reivindicação ocorrem em contexto confiável, com bloqueio por trabalho. O tenant é derivado do trabalho persistido; os vínculos compostos `(tenant_id, job_id)` e a unicidade `(job_id, event_type)` protegem consistência e deduplicação. A gravação do marco e sua transição operacional são atômicas: falha de gravação não pode virar sucesso.
- `processor_finish` sem início confirmado é recusado. Entrada inválida, token ausente, inválido ou expirado, trabalho inexistente ou fora da reivindicação e transição incompatível não gravam marco. A recusa é genérica, sem revelar a existência do trabalho fora da autorização, segredos ou detalhes técnicos. Indisponibilidade ou resultado incerto não é confirmação; o processador deve resolver o estado antes de declarar sucesso.
- `tenant_id`, dados pessoais, conteúdo de publicação, critérios de busca, texto livre e erro técnico não fazem parte da entrada. Falha ou interrupção nunca fabrica `completed`; a ausência desse marco não permite concluir falha. Repetições autorizadas recuperam o mesmo `id` e `recorded_at`, sem duplicatas.

As consultas HTTP exigem sessão válida e onboarding do advogado titular; o tenant vem da sessão, não do cliente. Não há acesso de equipe nesta entrega. Execução inexistente, UUID inválido ou execução fora da audiência do tenant retorna `404` com `collection_run_not_found`, sem revelar dados.

| Endpoint | Campos e comportamento |
|---|---|
| `GET /api/collection-runs/:id/events` | `{ events: [...] }`, com `id`, `job_id`, `event_type` (`started` ou `completed`), `recorded_at`, `entity_type`, `entity_id`, `source`, `court` e `medium`; ordenação por `recorded_at` e `id`. Só os marcos do tenant são retornados. |
| `GET /api/collection-runs/:id/execution` | `{ jobs: [...] }`, com `job_id`, `court`, `medium` e `state`; ordenação por `job_id`. `pending` é trabalho ainda não iniciado; `running`, processamento iniciado; `succeeded`, conclusão bem-sucedida confirmada; `failed`, falha operacional mantida fora dos marcos. |

Execução visível sem trabalhos retorna listas vazias, não sucesso ou término fabricado. Nenhum dos endpoints expõe token, digest, lease, detalhes de erro ou contagens de publicações. O estado operacional não é agregado pela presença ou ausência de marcos.

### Pré-requisitos e verificação

- Em banco novo de desenvolvimento, antes das migrations consolidadas, um administrador deve seguir a ordem `backend/db/provision.sql`, `backend/db/provision_despachante.sql` e `backend/db/provision_processador.sql` indicada no README. Esse provisionamento não é procedimento de upgrade de um banco pré-existente. A role `advocacia_processador` usa credencial SCRAM exclusiva, configurada externamente, sem segredo versionado.
- `PROCESSADOR_DATABASE_URL` não tem default (`Nenhum`) e é obrigatória para o processador e os testes de fronteira. Fornecer a URL externamente por ambiente protegido ou gerenciador de segredos; nunca entregá-la à API ou ao despachante. A variável está registrada na tabela de ambiente do README.
- **Evidência histórica anterior à consolidação:** a dependência 4b foi verificada em PostgreSQL isolado, com testes de sessão/tenant e smoke HTTP com tenant adulterado; os resultados estão em `tasks/todo.md`. Login OAuth real é verificação independente.
- **Evidência histórica anterior à consolidação:** os testes específicos passaram com 29 testes e 813 assertions, incluindo duas sessões/tenants, claims inválidas, leases, concorrência, falha sem término, imutabilidade e atomicidade. A suíte completa passou com 276 testes e 7.678 assertions. Smoke HTTP e SQL na imagem final confirmou sucesso, falha e negação cruzada; veja [README](README.md#planejamento-de-coleta). Essas verificações históricas não comprovam alterações posteriores.

## Questões abertas e bloqueios

- O processador executa trabalho já planejado e preserva início, conclusão e falha fora dos marcos; o acionamento automático dos trabalhos continua na tarefa 13.
- O solicitante dispensou prazo automático de retenção e expurgo nesta etapa. Dados públicos podem conter dados pessoais; a aplicação deve preservar isolamento e avaliar obrigações legais aplicáveis antes do uso em produção.

## Critérios de sucesso

O fluxo acrescenta marcos mínimos, sem alteração ou exclusão por operação normal e sem prazo automático de expurgo. Ações de usuários, identificadores diretos, conteúdo e erros técnicos ficam fora do Escrevente; isolamento e segurança devem ser verificados.
