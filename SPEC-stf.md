# Especificação: acompanhamento de processos do STF (`stf`)

**Estado:** especificação criada por autorização expressa do solicitante na branch `stf`; descreve a entrega a implementar, não uma funcionalidade já disponível. A autorização para escrever esta spec e o [to-do](tasks/todo-stf.md) não é evidência de execução, aprovação técnica dos gates ou CI. A fonte STF é uma extensão separada: não substitui nem altera o contrato DJEN de [coleta](SPEC-coleta.md).

## Objetivo e escopo confirmado

Pesquisar diariamente processos públicos do STF associados ao advogado do tenant, a uma parte cadastrada ou a um processo monitorado. Considerar **somente processos em tramitação**, obter seus andamentos no portal, selecionar os que tenham a **data corrente da execução** e persistir os dados, a origem e os links associados para consulta em comunicações.

As três modalidades são alternativas independentes; não exigir nome de advogado para monitorar diretamente um processo nem criar vínculo advogado–parte inexistente. O acompanhamento nominal não afirma que toda comunicação do processo foi dirigida ao advogado pesquisado.

### Decisões recebidas do solicitante

- Aplicação STF separada da API e do ETL DJEN, no mesmo monorepo; coletor e processador têm fronteiras próprias e são coordenados pelo planejador.
- Busca de processos por JSON; para localizar o processo no portal, usar a identificação por classe/número, incluindo `Rcl`, e/ou o número CNJ. `Rcl` é exemplo, não filtro universal.
- Coletar somente andamentos da data da execução, sem busca retroativa de dias anteriores.
- Guardar o endereço original da página do STF e todos os links associados ao andamento, inclusive PDFs, publicações e links externos.
- Usar a marca oficial do STF em comunicações; o arquivo já existente é `apps/web/src/assets/courts/STF.png`, com procedência em `sources.json` no mesmo diretório. Sua existência não significa suporte funcional ao tribunal.

## Fontes de verdade e precedência

| Assunto | Referência |
|---|---|
| Escopo STF e critérios específicos | Esta spec e [tasks/todo-stf.md](tasks/todo-stf.md) |
| Fases, dependências e gates STF | [Fases e gates](tasks/todo-stf.md#fases-e-gates) |
| Arquitetura, isolamento e organização | [docs/arquitetura.md](docs/arquitetura.md#estrutura-do-monorepo-e-fronteiras) |
| Identidade, elegibilidade e equivalência dos alvos | [SPEC-monitoramentos.md](SPEC-monitoramentos.md#contratos-lógicos) e [SPEC-autorizacao.md](SPEC-autorizacao.md) |
| Consulta, autorização e identidade pendente | [SPEC-consulta.md](SPEC-consulta.md#escopo-e-contratos-lógicos), sem modificar suas métricas DJEN implicitamente |
| Requisitos finais e pronto transversal | [Critério de pronto](#critério-de-pronto) e [Definition of Done](.agents/references/definition-of-done.md) |
| Estilo e implementação vigente | `apps/etl/`, `apps/backend/despachante/` e contratos SQL em `apps/backend/db/migrate/` |

Os planos de primeiro acesso, agenda e DJEN continuam com seus próprios escopos. A nova fonte exige extensão explícita dos contratos afetados; o código atual tem fonte `DJEN` e meio `D` fixos em vários pontos. Não remover esses checks indiscriminadamente nem representar um andamento STF como publicação DJEN para fazê-lo passar.

## Busca reproduzível e limites da fonte

### Descoberta nominal — JSON público

`GET https://digital.stf.jus.br/integracoes-processos/api/public/partes/processos`

| Parâmetro | Uso |
|---|---|
| `nome` | Nome completo do alvo, com codificação de query string |
| `tipoPesquisa` | `ADVOGADO` ou `PARTE` |
| `processosPorPagina` | `20`, tamanho observado na investigação |
| `pagina` | Começa em `1`; percorrer a resposta paginada sem limite local silencioso |
| `processosEmTramitacao` | `sim` na pesquisa de parte, onde o parâmetro é obrigatório; não alegar filtro remoto de advogado sem verificá-lo |

A resposta observada contém `totalDePaginas`, `totalDeRegistros` e `partes`. Cada registro informa `pessoaNome`, `processoId`, `processoIdentificacao`, `processoNumeroUnico`, `processoDataAutuacao` e `processoEmTramitacao`, entre outros campos.

1. Validar estrutura e tipos na fronteira. Considerar candidato somente quando `processoEmTramitacao` declarar `Sim`; ausência ou valor desconhecido não prova atividade. Rejeitar arquivados/baixados antes de buscar seus andamentos. Para advogado, aplicar esse filtro localmente mesmo que seja enviado parâmetro adicional.
2. A busca aceita nomes não exatos: conferir `pessoaNome` pela igualdade de nome completo normalizado de monitoramentos antes de vincular o resultado. Não inventar OAB no retorno nem desambiguar homônimos.
3. Percorrer todas as páginas indicadas por metadados válidos. Processar página parcial; não encerrar apenas porque tem menos de 20 registros. Página repetida, metadados inconsistentes ou erro após páginas válidas não comprovam pesquisa completa e não autorizam sucesso vazio. A fonte não garante uma fotografia imutável entre páginas: registrar a captura e não prometer completude global além da resposta observada.
4. `processoId` identifica o `incidente` usado no portal; `id` e `pessoaId` não são substitutos. `processoDataAutuacao` não é data do andamento.
5. Um processo encontrado por vários critérios mantém todos os vínculos autorizados; não precisa ser consultado repetidamente na mesma captura do tenant.

### Localização por classe/número ou CNJ

- Classe/número: `https://portal.stf.jus.br/processos/listarProcessos.asp?classe=Rcl&numeroProcesso=101463`.
- Número CNJ: `https://portal.stf.jus.br/processos/listarProcessos.asp?numeroUnico=01882631920261000000`.
- Detalhe conhecido: `https://portal.stf.jus.br/processos/detalhe.asp?incidente=7728350`.

Os números são exemplos da investigação, não alvos fixos do produto. Validar o CNJ conforme monitoramentos, preservando zeros. Classe e número STF são uma identificação adicional da fonte: não substituir a chave CNJ dos cadastros existentes nem aceitar número abreviado como CNJ válido. Confirmar a identidade do processo resolvido antes de persistir. Se duas identificações fornecidas discordarem, registrar falha de resolução, sem escolher silenciosamente uma delas.

O JSON nominal informa `processoEmTramitacao` por registro; somente o valor `Sim` comprova a situação afirmativa observada. **Não foi comprovada uma API pública de situação para um processo arbitrário encontrado apenas por classe/CNJ.** STF00.B deve validar uma indicação inequívoca de tramitação nesse caminho; até isso ocorrer, não presumir elegibilidade por ausência de baixa nem declarar esse caminho implementado. Essa verificação é condição de aceite da modalidade direta, não autorização para omiti-la.

### Andamentos — HTML público

`GET https://portal.stf.jus.br/processos/abaAndamentos.asp?incidente={processoId}&imprimir=`

O portal carrega esse fragmento por HTTP. Não é uma API JSON de movimentos; solicitar JSON no header continuou retornando HTML. A leitura validada não requer browser headless. Cada `.andamento-item` contém data (`.andamento-data`), título (`.andamento-nome`), julgador e observação opcionais e links do próprio item. `.hint-msg` é explicação genérica, não observação do evento. Não associar links de um item a outro nem confundir shell de login, bloqueio ou página incompleta com lista vazia.

Na amostra do incidente `7728350`, foram observados nove movimentos de 20 a 22/10/2026. A busca nominal de Benoni Canellas Rossi informou 393 registros em 20 páginas; apenas a primeira foi lida na investigação. Esses resultados **não provam movimentos de hoje, varredura completa ou estabilidade futura**.

## Contrato de execução e componentes

- O planejador deriva tenant, alvo, filtros e data de contexto confiável e congela o trabalho. O processador recebe esse trabalho; o coletor é a fronteira de acesso à fonte. A comunicação de ambos com o planejador deve reaproveitar o mecanismo durável vigente, sem executar coleta dentro da requisição Rails nem criar outro planejador.
- A implementação pertence a uma aplicação própria sob `apps/`, conforme arquitetura. `apps/stf/` é o caminho proposto, a ratificar em STF00 antes de criar código. Não impor um pipeline obrigatório coletor → processador nem introduzir broker, serviço HTTP ou camada genérica sem necessidade do contrato real.
- Usar `America/Sao_Paulo`, coerente com planejamento e consulta existentes. A data é obtida do relógio de execução, não de parâmetro público de retroativo. Congelar a data do trabalho e interrompê-lo se deixar de ser a data corrente antes de novas consultas ou do commit; não misturar dois dias numa execução.
- Comparar a data estruturada do andamento em `DD/MM/AAAA` com essa data. Datas na observação, na publicação citada ou na autuação não a substituem. Não persistir movimentos de ontem/amanhã como resultados de hoje.
- A cadência solicitada é diária. Horário, encaixe na agenda e concessões STF devem ser registrados em STF00 sem mudar a frequência DJEN nem criar variáveis especulativas. Não herdar automaticamente os dois slots ou retries DJEN como decisão STF.
- Sucesso requer descoberta e consultas elegíveis concluídas. Distinguir sucesso sem andamentos do dia, nenhum processo elegível, execução pendente, resultado parcial e falha. Erros HTTP, JSON/HTML inválido, situação não verificável, concessão perdida e virada de data não viram zero.

## Dados persistidos, links e identidade

Persistir no PostgreSQL compartilhado existente, com migrations incrementais, roles restritas e RLS por tenant. Não criar nova instância de deploy. O banco de prova deve ser PostgreSQL Docker descartável, separado dos dados locais do usuário.

| Grupo | Dados mínimos |
|---|---|
| Proveniência | Fonte lógica STF, tribunal STF, execução/trabalho, tenant confiável, alvos que encontraram o processo, instante de captura e primeira persistência |
| Processo | Incidente STF, identificação classe/número, CNJ quando fornecido e evidência de que estava em tramitação na captura |
| Andamento | Data do evento, título, julgador e observação quando existentes; ausência opcional não deve gerar conteúdo inventado |
| Origem navegável | URL original `detalhe.asp?incidente=...` e URL da aba efetivamente consultada |
| Links | URL resolvida, referência original e rótulo quando existente, provenientes de âncoras e URLs escritas na observação do mesmo item |
| Identidade | ID local e estado de identidade da fonte; identificador nativo somente se efetivamente fornecido e verificado |

Resolver links relativos contra a página de coleta. Guardar PDFs, RTF, publicações e outros destinos externos HTTP(S), preservando query strings; não presumir que todo link seja PDF. Conteúdo e URLs são dados não confiáveis: escapar texto/atributos, não tornar `javascript:` ou `data:` executáveis, não seguir links automaticamente para redes privadas, nem baixar ou executar peças para concluir a coleta.

Não foi observado ID estável de movimento. Dois movimentos podem compartilhar a mesma peça e até data/título/texto; portanto, **ID de documento, posição no HTML e hash de conteúdo não são, isoladamente, identidade processual**. Preservar a multiplicidade observada. A mesma entrega de uma captura deve ser idempotente, sem duplicar gravações na retomada; isso não prova identidade entre capturas diferentes. Sem chave nativa confiável, conservar registros como identidade pendente, com aviso de possível duplicidade, sem fundir eventos e sem inventar o par DJEN `id` + `hash`. STF00 deve definir a chave durável de captura/entrega e a política de reencontro, incluindo concorrência e falha no commit, antes do código.

Comunicações STF devem ficar disponíveis na consulta autorizada, com seus links e marca oficial. Resultados pendentes não entram nas métricas deduplicadas existentes; não alterar a semântica da dashboard DJEN. Autorização por tribunal, mascaramento e isolamento continuam no servidor, não apenas na tela.

## Runtime, comandos, estilo e verificação

Reaproveitar o runtime Ruby e as bibliotecas necessárias já usadas no repositório, sem novo framework: `apps/etl/Gemfile` fixa Ruby 4.0.9, Nokogiri 1.19.4, pg 1.7.0, tzinfo 2.0.6 e Minitest 5.27.0. Isso é referência existente, não ordem para copiar dependências de ZIP/DJEN para STF.

Exemplo de estilo real em `apps/etl/lib/processador/runner.rb`: `TIMEZONE = TZInfo::Timezone.get("America/Sao_Paulo")`, dependências explícitas e validação na entrada. Respeitar limites entre apps: código realmente compartilhado tem uma implementação fora das aplicações; não migrar todo o DJEN como refatoração adjacente.

Comandos **existentes de referência**, não execução STF: em `apps/etl/`, `bundle exec ruby bin/processador JOB_UUID` executa um trabalho **DJEN**; em `apps/backend/`, `bundle exec ruby bin/rails test` executa a suíte Rails no ambiente de teste preparado. Não usar o processador DJEN para provar STF. Entradas STF, comandos focados, build e CI serão fixados com os caminhos reais em STF00/STF02 e documentados no README na implementação. Esta autoria não cria comando nem variável de ambiente.

Testes permanentes devem cobrir filtro de atividade, paginação, nomes, resolução de processo, data local/virada, HTML malformado, links, multiplicidade, retomada, concorrência, isolamento e distinção falha/zero. Usar relógio e fonte controlados para casos determinísticos, sem habilitar retroativo em produção. O smoke definitivo deve executar o caminho real com PostgreSQL e consultar os registros persistidos por role de runtime; uma fonte real sem movimentos de hoje pode provar sucesso vazio, mas não substitui a prova positiva controlada de persistência e links.

## Fronteiras e condições de acesso

- **Sempre:** apenas escopo confirmado; preservar DJEN e trabalho preexistente; tenant confiável/RLS/RBAC; validar dados externos; manter vínculos, origem e links; registrar evidência observada em cada gate; atualizar README para toda variável criada ou alterada.
- **Pedir decisão externa somente quando necessário:** credencial/acesso efetivamente ausente, conflito com contrato vigente ou escolha de produto/arquitetura não resolúvel pelas fontes. Decisões técnicas delegadas devem ser resolvidas pelo repositório e registradas, não tratadas como novos pedidos genéricos de aprovação.
- **Nunca:** coleta retroativa, escopo fixo em Rcl, reclassificar STF como DJEN, ampliar filtros/autorização, usar MNI autenticado como leitura inofensiva, executar ciência de comunicação, contornar bloqueio/captcha/autenticação, enviar alertas por WhatsApp/e-mail, baixar peças automaticamente, criar infraestrutura de deploy ou alterar credenciais do usuário.

O [robots.txt do portal](https://portal.stf.jus.br/robots.txt) declara `Disallow: /processos`. A leitura técnica observada não comprova permissão para operação recorrente. STF00 deve registrar as condições de acesso aplicáveis; se dependerem de autorização externa ausente, isso bloqueia a ativação diária, sem justificar bypass ou substituir a fonte. A [integração MNI](https://portal.stf.jus.br/textos/verTexto.asp?servico=processoIntegracaoInformacaoGeral&pagina=mni) exige adesão institucional; não é fallback automático desta entrega.

## Critérios de aceite

- **C1:** planejador entrega trabalho STF rastreável para advogado, parte ou processo do tenant elegível; aplicação é separada e DJEN permanece funcionando.
- **C2:** descoberta nominal percorre todas as páginas válidas, confere nome completo e conserva somente processos explicitamente em tramitação, sem perder vínculos.
- **C3:** classe/número e CNJ resolvem o processo correto, confirmam tramitação e chegam à aba pelo incidente correto; ausência de confirmação não é sucesso.
- **C4:** somente a data corrente de Brasília é persistida; datas em observações não confundem o filtro, e a virada interrompe o trabalho sem retroativo.
- **C5:** cada movimento conserva dados opcionais reais, URL original STF, URL de coleta e todos os links associados; dois itens distintos continuam dois.
- **C6:** persistência e entrega são transacionais e rastreáveis, retomada não duplica a mesma entrega, tenant é isolado e identidade de fonte não comprovada permanece explícita.
- **C7:** consulta autorizada apresenta comunicações STF e links seguros, usa a marca oficial e mantém aviso de identidade pendente, sem alterar métricas DJEN indevidamente.
- **C8:** execução controlada chega a estado terminal em PostgreSQL Docker descartável; prova positiva, zero, falha, concorrência e isolamento têm resultados observados, sem inventar movimentos reais do dia.
- **C9:** único PR fica draft até os gates finais; smoke definitivo precede limpeza, documentação/variáveis e contratos afetados são atualizados, reviews são resolvidas e CI termina verde.

## Critério de pronto

Todos os critérios C1–C9 e todas as folhas aplicáveis do to-do têm evidência revisável; nenhum item atual ou posterior desaparece do checklist. Aplicam-se integralmente os itens da Definition of Done. Comandos, resultados, limitações de fonte e riscos externos devem estar no handoff/PR, sem segredos. Não declarar implementação concluída com spec, logo, fixture ou scaffold. Não há autorização de deploy, troca de banco persistente ou encerramento dos outros planos do repositório.
