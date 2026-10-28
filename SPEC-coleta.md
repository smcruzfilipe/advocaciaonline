# Especificação proposta: coleta (`coleta`)

**Estado:** proposta para revisão; não declarar aprovada nem iniciar implementação antes da aprovação. Módulo e dependências conforme [mapa de capacidades](CAPABILITIES.md); contratos compartilhados em [especificação geral](docs/especificacao.md) e [intenção confirmada](docs/intent/monitoramento-juridico.md).

## Objetivo

Planejar e executar duas coletas diárias de publicações do DJEN para os tenants e entidades monitoradas, persistindo comunicações distintas e todos os vínculos que levaram a encontrá-las. Cadernos são a fonte principal; a consulta paginada de comunicações é fallback. Não fazer coleta retroativa de dias anteriores.

## Escopo e contratos lógicos

- **Dependências do mapa:** `monitoramentos` (`SPEC-monitoramentos.md`) fornece entidades, seus vínculos e tenant; `escriba` (`SPEC-escriba.md`) recebe marcos append-only do fluxo.
- **Consumidor:** `consulta` (`SPEC-consulta.md`) lê comunicações persistidas e estado de coleta por execução/tribunal.
- A aplicação de planejamento/control plane e as microaplicações ETL são responsabilidades lógicas distintas da aplicação central, conforme o mapa; não se determina aqui se serão processos, serviços ou diretórios separados.
- O contexto autenticado identifica usuário e tenant no servidor. A coleta sempre associa entidade e publicação ao tenant obtido do contrato confiável, nunca ao tenant fornecido pelo cliente como prova de acesso.
- O planejador produz trabalho rastreável por entidade/tenant elegível, execução, fonte e tribunal aplicável. Há duas execuções por dia; horários, fuso, elegibilidade e comportamento após interrupção ainda precisam ser definidos.
- Para cada execução, usar exclusivamente o dia corrente da execução como data de consulta. A fonte principal é o caderno DJEN para tribunal, data corrente e meio aplicável: obter o ZIP, descompactar todos os JSONs e pesquisar correspondências de nome e OAB do advogado, número de processo e nome de parte monitorados.
- Quando houver problema nos cadernos, usar a consulta de comunicações paginada como fallback, enviando `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais ao dia corrente. Percorrer as páginas necessárias segundo o contrato efetivo da fonte. Cadernos e API são caminhos de acesso à mesma fonte lógica, DJEN.
- Normalizar e persistir comunicações, vínculos aos monitoramentos que as encontraram e estado por execução/tribunal. Uma falha persistente deve permanecer distinguível de zero publicações e permitir aviso por tribunal na dashboard. Uma execução posterior no mesmo dia pode recuperar publicações; não há recuperação automática de dias anteriores.
- Após falhas, fazer novas tentativas com backoff. Não estão definidos quantidade de tentativas, intervalos, limites ou condições exatas de parada; nenhum número fica implícito nesta especificação.

## Deduplicação e vínculos

1. A identidade lógica de uma publicação para deduplicação é a combinação **conjunta** de `id` e `hash`, escopada pelo tenant e pela fonte lógica DJEN. Ambos são essenciais; não basta apenas um deles.
2. Uma publicação encontrada em caderno e API, em consultas diferentes ou em execuções diferentes do mesmo tenant não é persistida novamente como outra comunicação quando a combinação conjunta coincide.
3. Cada monitoramento que encontrou a publicação mantém seu vínculo a ela. A deduplicação da comunicação não descarta vínculos adicionais encontrados em outra entidade, consulta ou execução.
4. Valores diferentes de `id` ou `hash` representam chaves diferentes para este contrato; não colapsar publicações apenas por coincidirem em processo ou tribunal.
5. A estabilidade dos identificadores é uma premissa aceita pelo solicitante, não uma conclusão provada globalmente. A referência observada em 28/10/2026 é TJRO/D, `id` **769263947** e `hash` **jlx8NKdwzRKJtohPTKe77wYbD1mrEX**, iguais no caderno e na página 1 da consulta por número de processo. Essa amostra não comprova unicidade ou estabilidade global. Evidências e limites adicionais estão em [especificação geral](docs/especificacao.md#decisões-pendentes-e-evidências).

## Requisitos e critérios observáveis

1. Cada execução planeja trabalho por entidade/tenant elegível e pelos tribunais aplicáveis, com vínculo rastreável à fonte e execução.
2. A coleta principal usa apenas caderno do tribunal, dia corrente e meio aplicável; processa os JSONs do ZIP e busca as entidades monitoradas pelos critérios de nome/OAB/processo/parte.
3. Se o caderno for considerado problemático, o fallback percorre a consulta paginada com início e fim iguais ao dia corrente. Um resultado sem publicações não é apresentado como falha sem evidência de problema técnico.
4. Tentativas subsequentes respeitam uma estratégia de backoff configurada; esgotamento de tentativas e regra de acionamento do fallback dependem de limites e condições ainda pendentes.
5. Uma comunicação do mesmo tenant e DJEN com o mesmo `id` e `hash` aparece uma vez, inclusive quando veio dos dois caminhos ou de execuções diferentes; os vínculos de todos os monitoramentos que a encontraram permanecem consultáveis.
6. Publicações sem igualdade da combinação `id` + `hash` não são fundidas apenas por processo ou tribunal. O comportamento para identificador ausente ou inválido depende de decisão pendente, pois ambos são essenciais.
7. Estado de sucesso/falha é distinguível por execução e tribunal; após falha final a dashboard pode identificar o tribunal falho, sem converter falha em zero publicações.
8. A data inicial e final passada ao fallback é igual à data corrente da execução, e a coleta não consulta automaticamente datas anteriores.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** comandos não existem no repositório e são bloqueantes para implementação. Stack e ferramentas não foram escolhidas; não inventar comandos.
- **Estrutura física:** pendente. O limite lógico reúne planejador/control plane e ETL e mantém esses componentes separados da aplicação central, sem decidir diretórios, deploy ou processos.
- **Estilo de código:** não há implementação ou snippet real para servir de padrão. Linguagem, convenções de nomes/formatação e exemplo devem ser definidos a partir da stack e de código existente quando houver; nenhum estilo fictício é prescrito.

## Estratégia de testes comportamentais proposta

São cenários propostos de contrato, não repetição de teste da fonte externa. Framework, diretório, comandos e cobertura dependem de decisões técnicas ainda bloqueantes. A validação de cadernos/API reais deve ser planejada separadamente; as amostras existentes não devem ser tratadas como prova global.

- Um ZIP contendo JSONs é processado por tribunal, data e meio; correspondências de advogado por nome/OAB, processo e parte por nome são associadas à entidade e ao tenant corretos.
- O fallback consulta mais de uma página quando necessário e envia início/fim iguais ao dia corrente; não inclui dia anterior.
- Falha do caderno sob as condições de fallback acordadas ativa a API paginada; resposta válida sem itens não é falsamente apresentada como falha.
- A mesma combinação `id` + `hash` do tenant em caderno, API e execuções repetidas resulta em uma comunicação, preservando os vínculos dos vários monitoramentos.
- Dois tenants com a mesma combinação mantêm isolamento; no mesmo tenant, mudança em qualquer componente da combinação não é colapsada. Mesmos processo/tribunal sem chave conjunta igual não causam deduplicação.
- Falhas levam a novas tentativas com backoff e, quando esgotadas, a estado de falha identificável por tribunal; não se exige sequência numérica até que limites e política sejam decididos.
- Uma segunda execução no mesmo dia pode recuperar dados; uma execução normal não reprocessa automaticamente uma data anterior.

## Fronteiras

- **Sempre:** restringir a coleta ao dia corrente por execução; planejar por entidade/tenant; usar cadernos ZIP/JSON como caminho principal e API paginada como fallback; enviar datas de fallback iguais; deduplicar por `id` e `hash` conjuntamente, por tenant e fonte lógica DJEN; preservar todos os vínculos; separar falha de zero publicações.
- **Pedir aprovação:** mudar fonte, janela de datas, critérios de correspondência, chave/escopo da deduplicação, retenção/alteração de publicação, número ou limites de execuções/tentativas, política de recuperação histórica ou comportamento para identificadores ausentes.
- **Nunca:** deduplicar só por processo/tribunal ou só por um dos identificadores; tratar API e caderno como fontes lógicas diferentes; confiar tenant enviado pelo cliente; apresentar falha persistente como zero publicações; afirmar que a estabilidade/unicidade global foi provada pela amostra TJRO; coletar e-mail ou outras fontes na primeira entrega.

## Questões abertas e bloqueios

- Quais horários, fuso, configuração e elegibilidade determinam as duas execuções diárias? O que acontece com execução interrompida?
- Quais meios e tribunais são aplicáveis a cada entidade, e como a fonte indica ZIP inválido, indisponível, incompleto ou resposta válida sem itens?
- Quais condições exatas acionam fallback? Quais são a semântica de paginação, limites e disponibilidade efetiva da API? O filtro por processo não foi comprovado de forma geral; evidência inconclusiva está documentada na especificação geral.
- Quais regras de normalização e correspondência resolvem homônimos, acentos, pontuação e variações de nome/OAB/processo sem ampliar indevidamente os resultados?
- Como tratar ausência, alteração ou inconsistência de `id`/`hash` e mudanças posteriores no conteúdo da fonte?
- Quais limites numéricos, intervalos de backoff, critérios de parada e estado de execução parcial devem ser usados?
- Quais métricas/estados são mantidos por execução e tribunal para permitir consulta e aviso sem levar detalhes de erro ao Escriba?
- Stack, estrutura física, comandos, estilo real, framework, localização e cobertura dos testes precisam ser decididos antes de implementar.

## Critérios de sucesso

Duas execuções diárias consultam apenas o dia corrente; cadernos são primários e fallback percorre páginas com as datas corretas; matching e persistência mantêm tenant e vínculos corretos; deduplicação conjunta funciona entre caminhos e execuções sem fundir tenants ou publicações distintas; falhas persistentes permanecem observáveis como falhas. Limites operacionais e bloqueios técnicos devem ser resolvidos antes de implementação.
