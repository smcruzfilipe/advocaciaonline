# Especificação: agenda

**Estado:** base funcional, limites, matriz de operações e contrato técnico AG01/AG03 aprovados pelo solicitante. **ID:** `agenda`. Referências: [mapa](CAPABILITIES.md#agenda-e-atendimento-online) e [ideia](docs/ideas/agenda-atendimento-online.md). AG01–AG03 concluídas documentalmente. Plano/checklist estão aprovados, mas a entrega real dos provedores e o gate AG04/C0 ainda impedem implementação. O plano de monitoramento jurídico permanece inalterado.

## Objetivo

Permitir que o advogado e sua equipe autorizada mantenham compromissos presenciais e online na mesma agenda, com disponibilidade confiável, reserva sem sobreposição e regras iguais para agendamento interno e reserva externa. O sucesso deste módulo é confirmar, consultar, remarcar e cancelar compromissos corretamente, sem depender de Jitsi, Google ou entrega de e-mail para preservar a ocupação local.

O cliente é consumidor indireto por `reservas-clientes`, não usuário de equipe. O fluxo completo de atendimento só estará concluído após os demais módulos e suas verificações próprias.

## Decisões confirmadas

Decisões explícitas do solicitante:

- Uma duração configurada pelo advogado vale para todos os compromissos, sem duração diferente por atendimento, modalidade ou canal.
- O intervalo entre atendimentos é configurável por advogado, inclusive zero.
- A antecedência mínima para novas reservas é configurável por advogado. Não há exceção automática para advogado ou secretária.
- Reserva do cliente é direta, por link individual sem cadastro; convidados online não precisam de conta e aguardam admissão. Esses acessos pertencem aos módulos consumidores.
- Google recebe alterações da plataforma, sem consulta de ocupação nem importação de alterações.

Convenções adicionais aprovadas pelo solicitante na revisão desta especificação:

1. Usar minutos inteiros: duração positiva; intervalo e antecedência não negativos. Não fornecer valores padrão. Exigir configuração explícita antes de oferecer ou confirmar horários.
2. Usar `America/Sao_Paulo` como fuso da agenda nesta entrega, mantendo instantes absolutos em UTC na persistência e fuso explícito na apresentação; não usar o fuso do navegador como autoridade.
3. Interpretar intervalo como uma única separação mínima entre término de um compromisso e início do próximo, sem somar dois buffers. Com intervalo zero, o próximo pode começar exatamente no término do anterior.
4. Validar novas confirmações e remarcações contra a configuração vigente. Mudanças de configuração não movem, redimensionam ou cancelam compromissos já confirmados; estes conservam os instantes e duração confirmados. A duração única aplica-se às confirmações sob a mesma configuração, não como reescrita retroativa.
5. Aplicar antecedência mínima ao novo início na remarcação, não ao cancelamento. Permitir cancelamento por operador autorizado antes do início, sem criar outra antecedência mínima. Gestão retroativa de compromissos passados fica fora desta entrega.
6. Remarcar de forma indivisível: só liberar o horário original quando o destino estiver confirmado. Cancelamento efetivado libera a ocupação local, inclusive o intervalo associado, independentemente do estado das integrações.

Valores de configuração são dados do advogado, não novas variáveis de ambiente. Os limites abaixo foram escolhidos explicitamente pelo solicitante e não são defaults: duração de 1 a 120 minutos; intervalo de 0 a 60 minutos; antecedência de 0 a 10.080 minutos (7 × 24 horas); consulta de até 15 dias por requisição. A consulta não limita o horizonte futuro de agendamento. Precisão, representação e fronteiras da consulta/janelas serão ratificadas no contrato técnico AG03, concluindo a parte restante de AG01.

## Escopo e dono dos contratos

Agenda é dona da disponibilidade, das configurações de horário, dos compromissos e da prevenção de sobreposição. Disponibilidade é informada pelo advogado em janelas explícitas; não inventar expediente padrão. Recorrência de compromissos, catálogo de serviços, bloqueios temporários de reserva e negociação de horário entre convidados não integram esta entrega. A representação das janelas não implica autorização para criar um motor de recorrência.

Contratos lógicos fornecidos aos consumidores, sem fixar endpoints, tabelas ou transporte:

- **Configuração e disponibilidade:** identificar a agenda no contexto confiável, consultar regras vigentes e obter apenas horários reserváveis; distinguir configuração ausente de agenda sem horários livres. O cliente externo não recebe detalhes dos compromissos ocupantes.
- **Confirmar compromisso:** receber início pretendido, modalidade presencial/online e participantes informados pelo organizador; calcular término pela duração configurada e revalidar disponibilidade, intervalo e antecedência no momento da confirmação. Um horário anteriormente listado pode deixar de estar disponível.
- **Consultar compromisso:** fornecer ao operador autorizado início, término, fuso, modalidade, participantes e situação local. Lista e detalhe respeitam o mesmo tenant e autorização.
- **Remarcar ou cancelar:** produzir novo estado local coerente, sem depender de resposta de fornecedor externo. Falha de remarcação conserva o compromisso original.
- **Referência para integrações:** fornecer identidade estável do compromisso e informação que permita distinguir seu estado atual de uma publicação/envio referente a estado anterior. Formato técnico será definido no contrato de implementação.

`reservas-clientes` resolve o acesso individual e chama estas mesmas regras. `reunioes-online` cria e controla o acesso à sala. `integracao-google-agenda` mantém a cópia no Google. `convites-reuniao` compõe e envia comunicações. Nenhum deles confirma horário por uma regra alternativa. A apresentação pode compor estados desses módulos sem tornar o domínio agenda dependente deles.

## Requisitos funcionais e temporais

1. Cada agenda pertence ao tenant do advogado. Um identificador fornecido pelo cliente nunca comprova acesso ao tenant ou ao compromisso.
2. O advogado configura disponibilidade, duração, intervalo e antecedência. A equipe opera compromissos apenas mediante autorização explícita; poder operar não concede poder configurar a agenda ou administrar usuários/grupos.
3. Compromissos presenciais e online ocupam a mesma disponibilidade e seguem duração única. Não aceitar término ou duração divergente enviados por um canal alternativo.
4. Um compromisso deve caber integralmente em uma janela disponível e começar no futuro. Pela convenção proposta, o intervalo separa compromissos; não exige que exista uma margem vazia após o último atendimento até o fim da janela.
5. Para início `s`, duração `d` e término `e`, `e = s + d` em tempo decorrido. Com intervalo `i`, dois compromissos são compatíveis somente se o início do posterior for maior ou igual ao término do anterior mais `i`.
6. Para instante de confirmação do servidor `t` e antecedência `a`, aceitar somente `s > t` e `s >= t + a`. Igualdade com o limiar positivo é admitida; com antecedência zero, início no instante presente continua inválido. Revalidar no servidor mesmo que a tela tenha listado o horário anteriormente.
7. Aplicar as regras a criação interna, confirmação solicitada pelo módulo externo e remarcação, inclusive sob concorrência. Nenhum operador autorizado pode ignorar conflito ou antecedência nesta entrega.
8. Duas solicitações incompatíveis concorrentes na mesma agenda não podem ambas confirmar. Agendas de advogados distintos não se bloqueiam mutuamente por esse mecanismo; não se verifica disponibilidade dos convidados.
9. Remarcação que falhe por conflito, antecedência ou autorização não altera início, término ou ocupação originais. Disputas entre remarcação, cancelamento e reserva não podem produzir dupla ocupação ou perda parcial do compromisso.
10. Cancelamento efetivado deixa de ocupar disponibilidade. Uma falha de publicação ou envio não reativa o compromisso cancelado. Uma falha externa tampouco desfaz um compromisso confirmado ou libera seu horário.
11. Não exibir sucesso completo das integrações a partir do estado local da agenda. A ausência de evento Google ou de e-mail não significa que um horário esteja livre.
12. Uma alteração de configuração não pode invalidar silenciosamente uma confirmação concorrente: o resultado deve corresponder integralmente a uma configuração válida, não a uma combinação de duração, intervalo e antecedência de versões diferentes.

## Identidade e autorização

Reutilizar [identidade](SPEC-identidade.md), [autorização](SPEC-autorizacao.md) e o isolamento de [arquitetura](docs/arquitetura.md). Sessão válida, vínculo, expiração e revogação são revalidados no servidor. Aplicar RLS com a role real de runtime; não fabricar usuário de equipe nem usar bypass de RLS para atender ao cliente externo.

A matriz abaixo é uma **extensão funcional aprovada**, incorporada ao catálogo canônico de SPEC-autorizacao.md por AG02, ainda não implementada:

| Operação lógica da agenda | Advogado titular no próprio tenant | Equipe |
|---|---|---|
| Consultar lista e detalhes | Permitida | Exige concessão específica por grupo |
| Criar compromisso | Permitida, respeitando regras de horário | Exige concessão específica por grupo |
| Remarcar compromisso | Permitida, respeitando regras de horário | Exige concessão específica por grupo |
| Cancelar compromisso | Permitida, respeitando regras de cancelamento | Exige concessão específica por grupo |
| Configurar disponibilidade, duração, intervalo e antecedência | Exclusiva do titular | Não concedida por gestão de compromissos |
| Consultar apenas horários livres para criar/remarcar | Permitida | Permitida como parte de criação ou remarcação concedida; não autoriza lista/detalhe de compromissos ou identificação dos ocupantes. |

Conceder criação não concede consulta de compromissos, remarcação ou cancelamento por inferência; o conjunto necessário à experiência da secretária deve ser concedido explicitamente. A concessão de criar ou remarcar autoriza somente consulta de disponibilidade mínima para a ação, sem compromissos/ocupantes. Composição por grupos e precedência de negação seguem o contrato existente. Ausência de grupos ou permissão de monitoramentos não concede acesso à agenda. A extensão aprovada está incorporada em `SPEC-autorizacao.md`, sem alterar as regras dos módulos anteriores. Cada mutação responde com referência do compromisso, início, término, modalidade, situação local e marcador do estado resultante, sem exigir GET de lista/detalhe nem retornar dados alheios.

A autorização limitada de reservas-clientes é distinta desta matriz de operadores internos. Seu contexto deve resolver a agenda no servidor e conceder somente a ação prevista no link; formato e ciclo pertencem à especificação desse provedor de acesso.

## Contrato técnico aprovado — AG01 e AG03

**Estado desta seção:** aprovado explicitamente pelo solicitante. AG01 e AG03 concluídas documentalmente, incluindo representação temporal, schema, privilégios, ABIs e HTTP. Não há tabelas, funções ou rotas de agenda implementadas; a aprovação não demonstra provedores de AG04 nem libera C0.

### Instantes, janelas e consulta

- Janelas são intervalos absolutos explícitos `{starts_at, ends_at}`, com início anterior ao fim e sem recorrência. A cobertura disponível é a união das janelas; sobreposições ou adjacências não criam uma pausa artificial. A confirmação deve caber integralmente nessa cobertura contínua. Não criar expediente, grade de horários, arredondamento ou passo de duração implícitos.
- Instantes HTTP são RFC3339 completos, com data, hora e `Z` ou offset explícito; respostas usam UTC com `Z` e `time_zone: "America/Sao_Paulo"`. Persistir em `timestamptz(6)`; aceitar até seis casas decimais de segundo, sem truncar silenciosamente precisão excedente. Duração, intervalo e antecedência são minutos inteiros multiplicados por 60 segundos. O offset enviado representa o instante, não um novo fuso da agenda.
- Consulta recebe `start_date` e `end_date` em `YYYY-MM-DD`: início inclusivo e fim exclusivo, interpretados como fronteiras de datas em `America/Sao_Paulo`. Exigir diferença de datas entre 1 e 15 dias civis e converter cada fronteira local a UTC separadamente. `2026-11-01` a `2026-11-16` consulta 15 datas; até `2026-11-17` excede o limite. Não transformar 15 datas em um horizonte de reserva nem impor que reservas ocorram em até 7 dias.
- O recorte da disponibilidade seleciona possíveis inícios, não exige que o compromisso termine antes da fronteira final da consulta. Se uma janela cobrir a passagem da meia-noite, um início na última data pode terminar no dia seguinte. Ocupações iniciadas fora do recorte ainda entram no cálculo quando afetam os candidatos por duração/separação.
- Sem grade aprovada, responder conjuntos contínuos de inícios elegíveis em `start_ranges`: cada item tem `starts_at`, `ends_at`, `start_inclusive` e `end_inclusive`. São limites de INÍCIOS, não duração do compromisso. Uma janela livre de 10h–11h com duração de 30 minutos admite inícios de 10h até 10h30, ambos inclusivos. Um único início elegível tem limites iguais inclusivos; limite inferior igual ao relógio corrente é aberto se antecedência for zero. Intersectar os conjuntos com o recorte `[Q0,Q1)`.
- Para cada janela coberta `[w0,w1)`, candidato `s` satisfaz `s >= w0`, `s + d <= w1`, `s > t` e `s >= t + a`. Para cada compromisso confirmado `[b,e)` diferente do próprio alvo de remarcação, exigir `s + d + i <= b` OU `s >= e + i`. Usar intervalo vigente e instantes históricos preservados; cancelados não ocupam. Não exigir margem extra até o fim da janela.
- Disponibilidade retorna `configured`, `time_zone`, `computed_at` e `start_ranges`; quando configurada inclui `duration_minutes`. Ausência de configuração é `configured: false`, não falha disfarçada de vazio. Não retornar janelas brutas, ocupantes, seus IDs, participantes, contagens ou motivos de indisponibilidade nessa projeção. Conhecer horários livres permite inferir ausência de disponibilidade; não prometer impedir essa inferência admitida pelo produto.
- Para remarcar, a consulta pode receber `appointment_id` do alvo, condicionado à autorização de remarcação e resolução do alvo no tenant confiável. Excluir somente a ocupação desse compromisso no cálculo, sem liberá-lo de verdade antes do commit. Não aceitar um `exclude_id` genérico para ignorar compromisso arbitrário.

### Esquema e privilégios

Nomes ratificados no contrato técnico, ainda não implementados. Um tenant pertence a um advogado; não criar tenant por escritório nem duplicar essa identidade.

| Objeto | Campos/constraints relevantes |
|---|---|
| `public.agendas` | `id uuid` estável, `tenant_id uuid` com FK e unicidade por tenant; chave única `(tenant_id,id)`. Linha de sincronização persistente. `configured_at` nulo indica ausência de configuração e exige os três parâmetros nulos; quando configurada, duração 1–120, intervalo 0–60 e antecedência 0–10080, todos inteiros obrigatórios. `configuration_version` inteiro crescente identifica configuração completa, não um valor default de atendimento. |
| `public.agenda_windows` | `id uuid`, `tenant_id`, `agenda_id`, `starts_at`, `ends_at`; FK composta ao mesmo tenant/agenda, instantes finitos e início anterior ao fim. A substituição integral das janelas acompanha a configuração na mesma transação. |
| `public.appointments` | `id uuid` estável, `tenant_id`, `agenda_id`, `starts_at`, `ends_at`, `modality` (`in_person`/`online`), `status` (`confirmed`/`cancelled`) e `state_version` crescente. FK composta ao tenant/agenda; início anterior ao fim e duração confirmada de 1–120 minutos inteiros. Não recalcular fim antigo usando configuração nova nem persistir buffer histórico como autoridade. |
| `public.appointment_participants` | `id uuid`, `tenant_id`, `appointment_id`, `name`, `email`; FK composta ao mesmo tenant/compromisso. Dados informados pelo organizador, sem conta de equipe, tabela de clientes ou nova categoria de conteúdo jurídico. Não introduzir edição avulsa de participantes nesta entrega. |

Indexar janelas e compromissos pela agenda/tenant e início para consultas delimitadas, preservando as chaves necessárias às FKs. Nenhuma extensão GiST, Redis, novo processo ou novo banco é requerida por esta proposta.

Todas as tabelas novas têm `ENABLE` e `FORCE ROW LEVEL SECURITY`, com `USING` e `WITH CHECK` vinculados ao tenant resolvido por prova válida. Owner é a role de migration existente, sem superusuário/BYPASSRLS; `FORCE` também precisa valer quando funções executam como esse owner. Não usar política ampla para viabilizar acesso externo.

Runtime, PUBLIC e despachante não recebem `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES` ou `TRIGGER` diretamente sobre tabelas da agenda. O runtime recebe somente `USAGE` de schema e `EXECUTE` nas entradas necessárias de leitura/mutação; helpers internos não são executáveis por ele. Leituras completas e disponibilidade mínima passam por funções distintas com projeções autorizadas. Não copiar o grant de INSERT dos cadastros atuais para compromissos, pois permitiria ignorar o protocolo.

Entradas de agenda em `app_private` usam funções restritas `SECURITY DEFINER`, com objetos qualificados, `search_path` fixo em schemas confiáveis e `pg_temp` por último; criação e revogação de EXECUTE de PUBLIC ocorrem na mesma transação da migration. Revisar grants efetivos, inclusive herança, não apenas um REVOKE nominal. Não conceder ao runtime associação à role migrator ou propriedade das tabelas. Autoridade administrativa continua uma fronteira de confiança separada; esta garantia se refere aos escritores de runtime.

### Fronteira única de escrita e contexto

`AgendaOperations` e `AgendaAvailability` validam/parsam a fronteira e chamam funções parametrizadas por um gateway concreto, `AgendaStore`, seguindo o padrão de chamadas estreitas de `IdentityStore`. Não expor SQL arbitrário, aceitar nomes de funções do request ou duplicar a regra temporal autoritativa entre Ruby e PostgreSQL. As funções de consulta e mutação compartilham o mesmo cálculo temporal no banco; Ruby pode apresentar os resultados, mas não confirmar por cálculo alternativo.

As únicas mutações de domínio são configuração/substituição de janelas, confirmação, remarcação e cancelamento. Participantes são gravados junto da confirmação. As funções mutadoras são `VOLATILE` e usam comandos internos separados para lock e releituras; não embutir espera e consulta de ocupações numa única CTE com snapshot antigo.

Protocolo aprovado:

1. Resolver prova interna/limitada e ação inicial em transação `READ COMMITTED`, sem confiar em tenant, identidade ou booleano de permissão recebidos.
2. Se necessário, inserir a linha sentinela da agenda com unicidade e `ON CONFLICT DO NOTHING`; em outro comando adquirir `FOR UPDATE` dessa linha. Isso protege primeira configuração/reserva sem depender de haver compromissos. Ausência de configuração nunca gera parâmetros presumidos; recusa desfaz também o bootstrap realizado pela operação.
3. Depois da espera, capturar `t = clock_timestamp()` e reavaliar sessão/vínculo/validade/permissão. Em comandos posteriores ao lock reler configuração completa, janelas e ocupações. Preservar ordem de locks: agenda antes dos seus filhos. Não mover compromisso entre agendas nesta entrega.
4. Aplicar a regra temporal única e gravar integralmente estado/participantes ou nova configuração. Remarcação conserva ID e só troca ocupação se destino for válido; cancelamento exige `t < starts_at`, muda status e libera ocupação. Incrementar `state_version` em transição efetiva; registro já cancelado ou iniciado não pode ser remarcado/cancelado por este contrato. Não adicionar writeback externo.
5. Commit da transação externa antes de anunciar sucesso persistido. Falha/negação faz rollback integral; erro SQL não pode ser engolido deixando a transação PostgreSQL abortada ou serializando objeto Ruby alterado como sucesso. `requires_new` sob transação externa é savepoint, não commit independente. Nenhuma rede ou fornecedor participa do trecho protegido.

Pré-flight memoizado no controller não basta. O helper atual `session_context` é `STABLE` e usa `statement_timestamp()`; chamá-lo dentro do mesmo SELECT que esperou pelo lock não comprova validade pós-espera. O provedor de identidade/autorização deverá expor reavaliação temporal pelo instante do servidor pós-lock, com releitura de revogação/concessões em snapshot adequado. Não modificar globalmente esse helper às cegas nem declarar que ele já satisfaz o contrato.

**Contrato obrigatório do provedor, ainda sem implementação:** resolver uma prova opaca para tenant/ator ou contexto externo limitado; vincular ações ao alvo; decidir propriedade/concessões/negações; validar expiração/revogação no instante autoritativo e negar sem fallback. ABI privada aprovada: `app_private.agenda_authorize(operation text, appointment_id uuid, evaluated_at timestamptz)` retorna contexto autorizado com `tenant_id`, `agenda_id`, `actor_kind` e `identity_id`; agenda pode ainda não existir no primeiro cadastro de configuração, e identidade é nula para prova externa. O alvo nulo só vale para ações sem compromisso existente. A função não é executável pelo runtime: entradas estreitas escolhem a operação e fornecem o instante capturado no banco, nunca um horário/permissão do request. O provedor mantém sua política canônica, não uma cópia dentro da agenda.

ABI aprovada da política RLS: `app_private.agenda_context_tenant()` resolve o tenant de uma prova ativa no contexto transacional e retorna nulo se ausente/inválida. Não recebe tenant como parâmetro nem permite duas provas ativas ambíguas. Interno reutiliza o hash de sessão delimitado por `DatabaseContext`; externo usa prova opaca limitada cujo ciclo/resolução pertencem a reservas-clientes. Armazenar um valor em GUC não o torna confiável: o provedor deve conferir a prova persistida, validade, ação e alvo. Helpers de contexto/autorização precisam de snapshots e relógio que não reutilizem validade anterior à espera. `current_user` dentro do definer é a role owner, não o ator humano; a asserção de runtime fica na fronteira de conexão externa, não como substituto da identidade dentro da função.

Essas ABIs são contratos aprovados para os donos dos provedores, não funções stub a criar agora. AG03 ratificou as interfaces antes da implementação dos provedores; AG04 exige demonstrar sua entrega real e integração à RLS para liberar C0. Não publicar função/endpoint externo como utilizável antes dessa entrega; não inventar usuário de equipe, aceitar hash arbitrário como autorização ou usar bypass RLS.

### HTTP aprovado

As rotas abaixo foram aprovadas para implementação futura na mesma origem, sem `tenant_id`/`agenda_id` autorizativos no corpo ou query. Mutação exige JSON, sessão válida, Origin e CSRF existentes; respostas têm no-store. O endpoint externo de link não integra este módulo.

| Método/caminho aprovado | Entrada e autorização | Resposta de sucesso |
|---|---|---|
| `GET /api/agenda/configuration` | Titular da agenda | 200, `configured` e fuso; se configurada, parâmetros e janelas |
| `PUT /api/agenda/configuration` | Titular; `{duration_minutes, interval_minutes, minimum_notice_minutes, windows}` com todos os campos explícitos | 200, configuração completa persistida e sua versão |
| `GET /api/agenda/availability` | `start_date`, `end_date`, alvo opcional de remarcação; propriedade, consulta ou ação criar/remarcar permitida conforme o alvo | 200, projeção mínima de inícios elegíveis descrita acima |
| `GET /api/appointments` | `consultar_agenda`, período de datas de até 15 dias | 200, `{appointments: [...]}` com compromissos que intersectam o período, ordenados por início/ID |
| `GET /api/appointments/:id` | `consultar_agenda` e alvo no tenant | 200, detalhe autorizado |
| `POST /api/appointments` | `cadastrar_compromisso`; `{starts_at, modality, participants: [{name,email}]}` | 201, resultado mínimo da própria ação |
| `PATCH /api/appointments/:id/schedule` | `remarcar_compromisso`; `{starts_at}` | 200, resultado mínimo da própria ação |
| `POST /api/appointments/:id/cancellation` | `cancelar_compromisso`; objeto JSON vazio, sem motivo novo obrigatório | 200, resultado mínimo da própria ação |

Resultado mínimo da mutação: `{id, starts_at, ends_at, time_zone, modality, status, state_version}`. Não exige GET e não ecoa participantes, tenant ou dados do ocupante conflitante. Lista/detalhe incluem os participantes previstos no contrato, além desses metadados, somente com consulta autorizada. Não aceitar término ou duração por compromisso. O limite da consulta não se aplica à extensão total da configuração nem altera a antecedência do agendamento.

Erros preservam `{error: {code, message, details?}}`: JSON inválido 400 `invalid_json`; tipo de conteúdo inválido 415 `invalid_content_type`; sessão inválida 401 `authentication_required`; CSRF 403 `invalid_csrf`; ação negada 403 `agenda_operation_forbidden`; alvo ausente ou fora do tenant visível 404 `appointment_not_found`; entrada/data/limite inválido 422 `invalid_agenda_input`; configuração ausente para mutação 409 `agenda_not_configured`; destino indisponível 409 `appointment_unavailable`; transição não permitida 409 `appointment_state_conflict`. Não revelar compromisso causador ou motivo detalhado da indisponibilidade a quem só pode operar. Timeout/indisponibilidade de lock/banco, depois de rollback, é falha operacional 503 `agenda_unavailable`, não conflito de horário, sucesso ou retentativa automática.

### Fontes e verificação do contrato

- [PostgreSQL 18 — locks de linha](https://www.postgresql.org/docs/18/explicit-locking.html#LOCKING-ROWS): `FOR UPDATE` protege linhas recuperadas até o fim da transação; consulta vazia não fornece sentinela.
- [PostgreSQL 18 — Read Committed](https://www.postgresql.org/docs/18/transaction-iso.html#XACT-READ-COMMITTED): comandos sucessivos podem ver commits novos; `DO NOTHING` pode conflitar com linha invisível ao snapshot do mesmo comando. Separar bootstrap, lock e releituras.
- [PostgreSQL 18 — volatilidade](https://www.postgresql.org/docs/18/xfunc-volatility.html): `VOLATILE` obtém snapshot novo por query interna; `STABLE` usa snapshot do comando chamador.
- [PostgreSQL 18 — relógio](https://www.postgresql.org/docs/18/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT): `now()` é início da transação, `statement_timestamp()` início do comando e `clock_timestamp()` acompanha o instante corrente.
- [PostgreSQL 18 — RLS](https://www.postgresql.org/docs/18/ddl-rowsecurity.html): `FORCE` sujeita owner, mas superusuário/BYPASSRLS continuam exceções; RLS não protege TRUNCATE/REFERENCES nem substitui grants/autorização.
- [PostgreSQL 18 — definer seguro](https://www.postgresql.org/docs/18/sql-createfunction.html#SQL-CREATEFUNCTION-SECURITY): restringir search_path e EXECUTE de PUBLIC na mesma transação da criação.
- [PostgreSQL 18 — timestamps](https://www.postgresql.org/docs/18/datatype-datetime.html#DATATYPE-DATETIME-INPUT-TIME-STAMPS) e [ranges](https://www.postgresql.org/docs/18/rangetypes.html#RANGETYPES-INCLUSIVITY): instantes absolutos e inclusividade são distintos de uma grade de negócio; o nome IANA precisa ser explícito, não recuperado do offset armazenado.
- [Rails 8.1.4 — RFC3339](https://api.rubyonrails.org/v8.1.4/classes/ActiveSupport/TimeZone.html#method-i-rfc3339): exige data, hora e zona; parse permissivo não comprova contrato lexical.
- [Rails 8.1.4 — transações](https://api.rubyonrails.org/v8.1.4/classes/ActiveRecord/Transactions/ClassMethods.html): transações por conexão, savepoints, rollback e limites de restauração dos objetos Ruby.

Revisão de contrato cobre primeiro bootstrap concorrente, releitura pós-lock, limite inclusivo de início, candidato único, quinze datas, ocupação que afeta o recorte apesar de começar fora dele e mutação sem GET. Fontes verificam semântica, não comprovam DDL, grants, RLS, autorização ou concorrência da futura implementação. As provas reais de AG04/P1–P4 permanecem exigidas.

Representação temporal de AG01 e contrato técnico de AG03 aprovados pelo solicitante. O checklist mantém AG01–AG29 e subdivide AG12 em AG12a/AG12b para implementar funções e integração sem exceder cinco arquivos por fatia; as previsões de AG05/AG07/AG08/AG11/AG17/AG20 refletem grants restritos e gateway. A comprovação de execução permanece em AG04/C0 e P1–P4; não criar stubs ou usar credenciais administrativas para executar ações de runtime.

## Stack e estrutura do projeto

Base existente: Ruby **4.0.9**, Rails **8.1.4** API-only, `pg` **1.7.0** e Puma **7.2.1**, conforme `backend/Gemfile`. PostgreSQL com RLS; versão de referência **18.6** em [stack](docs/stack.md). Não introduzir outra infraestrutura para a agenda por presunção.

| Caminho | Uso e estado |
|---|---|
| `backend/app/services/`, `backend/app/models/` | Domínio e persistência existentes; futuros elementos de agenda seguem essas áreas |
| `backend/app/controllers/`, `backend/config/routes.rb` | Fronteira HTTP existente; rotas de agenda aprovadas em AG03, ainda não implementadas |
| `backend/db/migrate/` | Migrations existentes; schema de agenda aprovado, execução condicionada a AG04/C0 e ambiente autorizado |
| `backend/test/services/`, `backend/test/integration/` | Testes de regras, HTTP, segurança e banco; testes de agenda ainda inexistentes |
| `frontend/` | Next.js/TypeScript previstos, ainda não criados; sem comando de UI executável nesta etapa |
| `SPEC-agenda.md`, `CAPABILITIES.md`, `docs/ideas/` | Especificação, índice e origem das decisões |

Não criar serviço de agenda no despachante de coleta nem usar Escrevente como auditoria genérica. Nenhuma biblioteca de calendário, mecanismo de execução externa ou novo processo é escolhido por esta especificação.

## Comandos

Comandos suportados pela base existente, **não executados nesta etapa documental**. Executar comandos locais com diretório de trabalho `backend/`, Ruby/gems do lockfile disponíveis e ambiente protegido já fornecido:

| Finalidade | Comando |
|---|---|
| Suíte Rails existente | `RAILS_ENV=test ruby bin/rails test` |
| Exemplo de teste de service existente | `RAILS_ENV=test ruby bin/rails test test/services/onboarding_profile_test.rb` |
| Servidor API existente | `bundle exec puma -C config/puma.rb` |
| Migration em banco de teste previamente autorizado | `RAILS_ENV=test ruby bin/migrate` |

Da raiz do monorepo, o build existente da API é `docker build --target runtime -t advocacia-backend:local backend`. Sua documentação não autoriza executar containers ou builds nesta etapa.

Testes exigem PostgreSQL de teste separado e previamente provisionado/migrado. `DATABASE_URL` deve usar `advocacia_runtime`; a suíte completa também usa `MIGRATION_DATABASE_URL` e `DESPACHANTE_DATABASE_URL` em verificações específicas. Boot exige `APP_ORIGIN` e `SECRET_KEY_BASE`; fornecer valores externamente, conforme [README](README.md#variáveis-de-ambiente). Migration usa exclusivamente o script com `MIGRATION_DATABASE_URL`; nunca executar contra deploy sem procedimento/permissão aprovados. Não fornecer credenciais administrativas ao processo web.

Não há comando específico de agenda, frontend ou lint estabelecido nesta mudança; não anunciar `npm test`, RuboCop ou testes de agenda inexistentes como ferramentas prontas.

## Estilo de código

Seguir classes concretas, nomes de classes em CamelCase e métodos em snake_case; dois espaços de indentação e aspas duplas, conforme o backend existente. Validação na fronteira e mensagens de domínio em português. Não introduzir uma hierarquia abstrata de services apenas para esta capacidade.

Trecho real de `backend/app/services/onboarding_profile.rb:15–22`, como referência de estilo, não implementação de agenda:

```ruby
  def validate_input
    @registrations = []
    unless @input.is_a?(Hash) && (@input.keys - FIELDS).empty?
      errors.add(:base, "Envie somente os campos do perfil profissional.")
      return
    end
    @full_name = normalized_name(@input["full_name"])
    errors.add(:full_name, "Informe seu nome completo.") if @full_name.blank?
```

O trecho termina antes do fechamento do método original. Código novo deve reutilizar os contratos de erro e contexto existentes, sem copiar campos ou mensagens deste exemplo para a agenda.

## Estratégia de testes

- **Framework e locais:** Minitest/Rails, `ActiveSupport::TestCase` e `ActionDispatch::IntegrationTest`; helpers em `backend/test/test_helper.rb`. Manter convenções dos testes existentes.
- **Regras determinísticas:** testar duração única, configuração ausente/inválida, janelas, intervalo zero/positivo e fronteiras de antecedência com instantes explícitos; não depender de espera real.
- **HTTP e segurança:** sessões reais de teste, Origin/CSRF, titular, equipe com/sem concessão e acesso cruzado entre dois tenants. Dados não podem vazar por lista, detalhe ou adulteração de IDs.
- **Persistência e concorrência:** PostgreSQL real e role runtime sem bypass de RLS, conexões independentes e coordenação determinística. Não provar exclusão mútua com mocks de banco nem transação compartilhada que esconda a corrida. Há precedente de threads/conexões em `backend/test/integration/session_validity_test.rb`.
- **Transições:** remarcação recusada conserva origem; cancelamento libera ocupação; disputa entre operações não deixa estado parcial; configuração não altera silenciosamente compromissos existentes conforme a política aprovada.
- **Fronteiras externas:** demonstrar, por consumidores de teste isolados, que falha de integração não modifica a verdade local. Não transformar testes de simples encaminhamento em prova de entrega Google/e-mail ou de funcionamento Jitsi.
- **Cobertura:** cobrir os critérios observáveis abaixo; não introduzir percentual arbitrário nem enfraquecer a suíte existente.
- **Smoke futuro obrigatório:** exercer criação, conflito, remarcação e cancelamento pela API real, com duas agendas/tenants e sem fornecedor externo. Quando houver frontend, verificar também a superfície real no navegador. Nenhuma dessas provas foi executada agora.

## Critérios de sucesso observáveis

Exemplos numéricos abaixo são dados de teste, **não defaults**.

1. Com duração configurada de 30 minutos, compromissos presenciais e online, internos e solicitados pelo consumidor externo terminam 30 minutos após o início. Uma duração divergente não é aceita como override.
2. Com compromisso de 10h a 10h30 e intervalo zero, outro pode começar às 10h30 se couber na janela e cumprir antecedência; início às 10h29 é recusado. Com intervalo de 15 minutos, 10h44 é recusado e 10h45 é elegível pelas regras de separação.
3. Com relógio de confirmação em 08h e antecedência de 60 minutos, 08h59 é recusado e 09h é elegível para titular, equipe e consumidor externo. Os exemplos pressupõem janela livre e duração compatível. Com antecedência zero, um início igual ao instante de confirmação é recusado.
4. Configuração ausente não gera horários presumidos. Diferenciar ausência de configuração de configuração válida sem disponibilidade.
5. Para duas confirmações concorrentes incompatíveis na mesma agenda, no máximo uma confirma e apenas a ocupação vencedora permanece. Testar também concorrência entre canais interno e externo.
6. Duas agendas de tenants distintos podem confirmar o mesmo intervalo sem se bloquear; nenhum dos operadores lê ou altera a agenda alheia.
7. Remarcar para destino indisponível conserva a origem. Remarcar com sucesso troca a ocupação sem permitir dupla confirmação intermediária. Cancelamento efetivado libera o horário para outra confirmação elegível.
8. Sob a política de configuração aprovada, alteração de duração não redimensiona compromissos existentes. Novas confirmações usam integralmente a configuração vigente; testes cobrem alteração concorrente à confirmação.
9. Equipe sem concessão específica não consulta nem gerencia agenda; criação concedida não concede remarcação/cancelamento. Expiração ou revogação bloqueia novas operações protegidas em sessão já aberta.
10. Falha de Google/e-mail não libera compromisso confirmado. Cancelamento local não é revertido por uma integração atrasada, e o estado local não implica sucesso externo.
11. Consultas e alterações usam contexto de tenant reconhecido no servidor. Dados externos de tenant e permissão de monitoramentos não ampliam acesso.

As convenções e os critérios acima foram aprovados funcionalmente. Não representam comportamento já implementado ou verificado em execução.

## Fronteiras

- **Sempre:** usar regras únicas no servidor, contexto confiável e autorização/RLS; preservar instantes e fuso; distinguir estado local de integrações; testar limites, concorrência e isolamento com a role real; manter documentação e registrar qualquer variável nova ou alterada no README na mesma implementação.
- **Pedir aprovação antes:** alterar duração única, intervalo, antecedência ou permissões; acrescentar dependências, processos ou alterações de esquema; definir política diferente para configurações já aplicadas; ampliar o escopo ou liberar execução contra deploy. Plano, tarefas e implementação continuam sujeitos a gates separados.
- **Nunca:** criar defaults silenciosos; delegar administração de usuários/grupos por permissão de agenda; tratar cliente como equipe; confiar em tenant recebido para autorizar; desabilitar RLS para fluxo externo; fazer disponibilidade depender de Google; adicionar recorrência, gravação, lembretes, coleta ou auditoria genérica nesta capacidade; versionar segredos.

## Pendências e gates seguintes

1. As seis convenções temporais e a matriz de operações foram aprovadas pelo solicitante e incorporadas ao catálogo canônico em SPEC-autorizacao.md. AG02 foi concluída documentalmente, incluindo a decisão explícita de consultar apenas horários livres como parte de criação/remarcação; o provedor ainda não está implementado.
2. Limites e representação temporal aprovados: duração até 120 minutos, intervalo até 60 minutos, antecedência até 10.080 minutos e consulta de até 15 datas locais por requisição, início inclusivo/fim exclusivo. Não são defaults nem horizonte máximo de agendamento.
3. Política aprovada para mudanças de disponibilidade/intervalo: preservar compromissos existentes sem alteração automática e aplicar as novas regras a novas confirmações. Uma incompatibilidade de compromissos antigos com a nova configuração não autoriza remarcá-los ou cancelá-los silenciosamente.
4. [Plano](tasks/agenda/plan.md) e [checklist](tasks/agenda/todo.md) aprovados, preservando os arquivos padrão de monitoramento jurídico. AG01–AG03 concluídas documentalmente; AG04 exige entrega real dos provedores e ambiente antes de C0. Selecionar explicitamente os caminhos da agenda e não iniciar código pelo simples aceite dos contratos.

Links individuais, remarcação/cancelamento pelo cliente, hospedagem Jitsi, anfitrião, consentimento Calendar e provedor de e-mail permanecem questões dos respectivos módulos, não impedindo revisar a responsabilidade da agenda. Seus contratos precisam ser aprovados antes de usar o fluxo completo.

A revisão humana desta especificação foi concluída com aprovação em turno posterior à sua elaboração. Planejamento, tarefas e implementação continuam sujeitos aos próprios gates. Esta mudança registra somente documentação; não comprova funcionamento de agenda nem executa as verificações futuras descritas acima.
