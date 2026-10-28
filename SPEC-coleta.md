# Especificação proposta: coleta (`coleta`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `coleta`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Planejar e executar duas coletas diárias de publicações do DJEN para os tenants e entidades monitoradas, persistindo comunicações distintas e todos os vínculos que levaram a encontrá-las. Cadernos são a fonte principal; a consulta paginada de comunicações é fallback. Não fazer coleta retroativa de dias anteriores.

## Escopo e contratos lógicos

- **Dependências do mapa:** `monitoramentos` (`SPEC-monitoramentos.md`) fornece entidades, seus vínculos e tenant; `escriba` (`SPEC-escriba.md`) recebe marcos append-only do fluxo.
- **Consumidor:** `consulta` (`SPEC-consulta.md`) lê comunicações persistidas e estado de coleta por execução/tribunal.
- A aplicação de planejamento/control plane e as microaplicações ETL são responsabilidades lógicas distintas da aplicação central, conforme o mapa. A stack da aplicação central está definida em [docs/stack.md](docs/stack.md), mas não determina se esses componentes serão processos, serviços ou diretórios separados nem sua tecnologia; não se presume Ruby/Rails para planejador ou ETL.
- O contexto autenticado identifica usuário e tenant no servidor. A coleta sempre associa entidade e publicação ao tenant obtido do contrato confiável, nunca ao tenant fornecido pelo cliente como prova de acesso. PostgreSQL RLS é uma camada adicional e não substitui a derivação server-side do tenant nem autorização/RBAC.
- O planejador produz trabalho rastreável por entidade/tenant elegível, execução, fonte e tribunal aplicável. Há duas execuções por dia; os dois horários devem ser fornecidos por variáveis de ambiente, sem valores padrão. O fuso é fixo em Brasília (`America/Sao_Paulo`) tanto para a agenda quanto para determinar a data corrente enviada à fonte, independentemente do fuso do servidor. Nomes e formato das variáveis e critérios de elegibilidade ainda precisam ser definidos.
- Para cada execução, usar exclusivamente o dia corrente da execução como data de consulta. A fonte principal é o caderno DJEN para tribunal, data corrente e meio aplicável: obter o ZIP, descompactar todos os JSONs e pesquisar correspondências de nome e OAB do advogado, número de processo e nome de parte monitorados.
- Meios aprovados pelo solicitante: **Diário Eletrônico (`D`) e Edital (`E`)**, em ambas as coletas diárias, para os tribunais monitorados. Não adicionar configuração de meios por advogado.
- Se o problema no caderno persistir após esgotar as tentativas do caminho principal, usar a consulta de comunicações paginada como fallback, enviando `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais ao dia corrente. Percorrer as páginas necessárias segundo o contrato efetivo da fonte. Cadernos e API são caminhos de acesso à mesma fonte lógica, DJEN. O limite de tentativas e os intervalos de backoff são definidos por variáveis de ambiente; nomes, unidades, formato e validações permanecem pendentes.
- ZIP inválido ou divergência entre metadados e conteúdo caracteriza falha do caderno: não aceitar conteúdo parcial como coleta completa. Repetir o caminho principal e, esgotadas as tentativas, acionar o fallback; não registrar essa falha como zero publicações. A identificação precisa das divergências verificáveis ainda depende do contrato efetivo da fonte.
- Normalizar e persistir comunicações, vínculos aos monitoramentos que as encontraram e estado por execução/tribunal. Uma falha persistente deve permanecer distinguível de zero publicações e permitir aviso por tribunal na dashboard. Uma execução posterior no mesmo dia pode recuperar publicações; não há recuperação automática de dias anteriores.
- Após falhas, fazer novas tentativas com backoff. Valores iniciais aprovados: até três tentativas por caminho, incluindo a primeira; aguardar um minuto após a primeira falha e cinco minutos após a segunda. Limite e intervalos são configuráveis por variáveis de ambiente; nomes, formato e validações permanecem pendentes do contrato técnico.
- Após reinício do worker ou interrupção, retomar automaticamente as pendências da data corrente em `America/Sao_Paulo`, preservando planejamento, vínculos e deduplicação. Pendências de datas anteriores não são retomadas automaticamente.

## Deduplicação e vínculos

1. A identidade lógica de uma publicação para deduplicação é a combinação **conjunta** de `id` e `hash`, escopada pelo tenant e pela fonte lógica DJEN. Ambos são essenciais; não basta apenas um deles.
2. Uma publicação encontrada em caderno e API, em consultas diferentes ou em execuções diferentes do mesmo tenant não é persistida novamente como outra comunicação quando a combinação conjunta coincide.
3. Cada monitoramento que encontrou a publicação mantém seu vínculo a ela. A deduplicação da comunicação não descarta vínculos adicionais encontrados em outra entidade, consulta ou execução.
4. Valores diferentes de `id` ou `hash` representam chaves diferentes para este contrato; não colapsar publicações apenas por coincidirem em processo ou tribunal.
5. A estabilidade dos identificadores é uma premissa aceita pelo solicitante, não uma conclusão provada globalmente. A referência observada em 28/10/2026 é TJRO/D, `id` **769263947** e `hash` **jlx8NKdwzRKJtohPTKe77wYbD1mrEX**, iguais no caderno e na página 1 da consulta por número de processo. Essa amostra não comprova unicidade ou estabilidade global. Evidências e limites adicionais estão em [especificação geral](docs/especificacao.md#decisões-pendentes-e-evidências).
6. Publicação sem `id` ou `hash` válido deve ser guardada separadamente e exibida na consulta do tenant como pendente, com aviso de possível duplicidade, sem presumir deduplicação confiável. Manter o aviso; não criar mecanismo de resolução nesta entrega.

## Requisitos e critérios observáveis

1. Cada execução planeja trabalho por entidade/tenant elegível e pelos tribunais aplicáveis, com vínculo rastreável à fonte e execução.
2. A coleta principal usa apenas caderno do tribunal, dia corrente e meio aplicável; processa os JSONs do ZIP e busca advogados por igualdade do nome completo normalizado **ou** pela igualdade do par `número OAB` + `UF` em qualquer inscrição principal ou secundária. Partes são buscadas por igualdade do nome completo normalizado. A normalização de nomes ignora maiúsculas/minúsculas e acentos, remove espaços excedentes (incluindo espaços nas extremidades e sequências repetidas) e exige igualdade exata após normalização; não equipara abreviações nem usa correspondência aproximada. Nomes iguais não provam identidade única: homônimos não são desambiguados por regra adicional.
   Para processos, comparar os dígitos do número sem máscara, mantendo zeros iniciais e sem conversão para inteiro. Para OAB, comparar número e UF separadamente e preservar possíveis sufixos, sem inventar sua remoção. Parte ou processo sem filtro monitora todos os tribunais disponíveis na fonte; com filtro, somente os selecionados. A autorização de leitura continua independente desse alcance.
3. Se o caderno for considerado problemático, o fallback percorre a consulta paginada com início e fim iguais ao dia corrente. Um resultado sem publicações não é apresentado como falha sem evidência de problema técnico.
4. Por padrão, cada caminho tem até três tentativas, com espera de um minuto após a primeira falha e cinco minutos após a segunda; os valores são configuráveis. Após esgotar o caderno, acionar o fallback.
5. Uma comunicação do mesmo tenant e DJEN com o mesmo `id` e `hash` aparece uma vez, inclusive quando veio dos dois caminhos ou de execuções diferentes; os vínculos de todos os monitoramentos que a encontraram permanecem consultáveis.
6. Publicações sem igualdade da combinação `id` + `hash` não são fundidas apenas por processo ou tribunal. Se faltar `id` ou `hash` válido, guardar separadamente e exibir na consulta do tenant como pendente, com aviso de possível duplicidade.
7. Estado de sucesso/falha é distinguível por execução e tribunal; após falha final a dashboard pode identificar o tribunal falho, sem converter falha em zero publicações.
8. A data inicial e final passada ao fallback é igual à data corrente da execução, e a coleta não consulta automaticamente datas anteriores.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** comandos não existem no repositório e são bloqueantes para implementação. A stack da aplicação central foi decidida (ver [stack](docs/stack.md)), mas isso não define comandos, versões, runtime, bibliotecas ou ferramentas dos componentes de planejamento/ETL; não inventá-los.
- **Estrutura física:** pendente. O limite lógico reúne planejador/control plane e ETL e mantém esses componentes separados da aplicação central, sem decidir diretórios, deploy ou processos.
- **Estilo de código:** não há implementação ou snippet real para servir de padrão. Convenções, formatação e exemplo devem ser definidos a partir de código existente quando houver; a escolha da stack central não define o estilo real nem a tecnologia do planejador/ETL.

## Estratégia de testes comportamentais proposta

São cenários propostos de contrato, não repetição de teste da fonte externa. A stack da aplicação central está definida, mas framework de testes, diretório, comandos e cobertura permanecem pendentes. A validação de cadernos/API reais deve ser planejada separadamente; as amostras existentes não devem ser tratadas como prova global.

- Um ZIP contendo JSONs é processado por tribunal, data e meio; advogados são associados por igualdade do nome completo normalizado ou por igualdade do par número OAB + UF em qualquer inscrição principal/secundária, e partes por igualdade do nome completo normalizado. A normalização ignora caixa e acentos e remove espaços excedentes; não há correspondência aproximada.
- Nomes completos que diferem apenas em caixa, acentos ou espaços excedentes são iguais para matching, tanto para advogado quanto para parte.
- Dois advogados com o mesmo número OAB e UFs diferentes não correspondem por OAB; se os nomes completos normalizados forem iguais, podem corresponder pelo nome. A OAB de uma inscrição secundária pode estabelecer correspondência pelo mesmo par número + UF.
- Uma abreviação não corresponde ao nome completo por matching de nome. Se nomes normalizados iguais puderem se referir a homônimos, não se presume unicidade nem se escolhe um por desambiguação não definida.
- O fallback consulta mais de uma página quando necessário e envia início/fim iguais ao dia corrente; não inclui dia anterior.
- Falha do caderno sob as condições de fallback acordadas ativa a API paginada; resposta válida sem itens não é falsamente apresentada como falha.
- A mesma combinação `id` + `hash` do tenant em caderno, API e execuções repetidas resulta em uma comunicação, preservando os vínculos dos vários monitoramentos.
- Dois tenants com a mesma combinação mantêm isolamento; no mesmo tenant, mudança em qualquer componente da combinação não é colapsada. Mesmos processo/tribunal sem chave conjunta igual não causam deduplicação.
- Publicação sem `id` ou `hash` válido é guardada separadamente e exibida apenas na consulta autorizada do tenant com aviso de pendência e possível duplicidade.
- Por padrão, cada caminho tenta até três vezes com intervalos de um e cinco minutos; após esgotar o caderno, usa fallback e, após falha persistente, registra estado identificável por tribunal.
- Após reinício do worker, pendências da data corrente em `America/Sao_Paulo` são retomadas automaticamente; pendências de datas anteriores não são. Uma segunda execução no mesmo dia também pode recuperar dados, e uma execução normal não reprocessa automaticamente data anterior.

## Fronteiras

- **Sempre:** restringir a coleta ao dia corrente por execução; planejar por entidade/tenant; usar cadernos ZIP/JSON como caminho principal e API paginada como fallback; enviar datas de fallback iguais; buscar advogado por nome completo normalizado ou par OAB+UF em qualquer inscrição principal/secundária e parte por nome completo normalizado; preservar possíveis homônimos sem desambiguá-los; deduplicar por `id` e `hash` conjuntamente, por tenant e fonte lógica DJEN; preservar todos os vínculos; separar falha de zero publicações.
- **Pedir aprovação:** mudar fonte, janela de datas, critérios de correspondência já definidos, chave/escopo da deduplicação, retenção/alteração de publicação, número ou limites de execuções/tentativas, política de recuperação histórica ou comportamento para identificadores ausentes; definir regras ainda pendentes para sinais de pontuação nos nomes e correspondência por processo.
- **Nunca:** deduplicar só por processo/tribunal ou só por um dos identificadores; tratar API e caderno como fontes lógicas diferentes; confiar tenant enviado pelo cliente; apresentar falha persistente como zero publicações; afirmar que a estabilidade/unicidade global foi provada pela amostra TJRO; coletar e-mail ou outras fontes na primeira entrega.

## Questões abertas e bloqueios

- Quais nomes, unidades, formato e validações das variáveis de ambiente para horários, tentativas e backoff? Como determinar elegibilidade e representar pendências? Os horários vêm do ambiente, o fuso é fixo em `America/Sao_Paulo` e a retomada automática das pendências da data corrente já está decidida.
- Quais tribunais são aplicáveis a cada entidade, e como a fonte indica indisponibilidade, incompletude ou resposta válida sem itens? Os meios já estão definidos: D e E; ZIP inválido ou divergência de metadados e conteúdo já implicam falha e fallback após as tentativas.
- Como identificar as demais falhas do caderno e definir o esgotamento de tentativas antes do fallback? Quais são a semântica de paginação, limites e disponibilidade efetiva da API? O filtro por processo não foi comprovado de forma geral; evidência inconclusiva está documentada na especificação geral.
- Qual regra deve ser aplicada aos sinais de pontuação nos nomes e a dados de OAB ausentes, inválidos ou com sufixos? A comparação por processo sem máscara, com zeros preservados, e OAB com UF separada já estão definidas; não converter identificadores em inteiros nem remover sufixos por suposição.
- Como tratar alteração ou inconsistência de `id`/`hash` e mudanças posteriores no conteúdo da fonte? Para valores ausentes ou inválidos, guardar separadamente e manter o aviso sem mecanismo de resolução nesta entrega.
- Como configurar e validar os limites e intervalos aprovados, e quais critérios de parada e estado de execução parcial devem ser usados?
- Quais métricas/estados são mantidos por execução e tribunal para permitir consulta e aviso sem levar detalhes de erro ao Escriba?
- A stack da aplicação central está definida em [docs/stack.md](docs/stack.md). Quais versões, runtime, bibliotecas, comandos, convenções de estilo, estrutura física e framework/localização/cobertura dos testes serão adotados? Quais tecnologias serão usadas no planejador e nos componentes ETL? A escolha central não determina essas tecnologias.

## Critérios de sucesso

Duas execuções diárias consultam apenas o dia corrente; cadernos são primários e fallback percorre páginas com as datas corretas; advogados correspondem por igualdade do nome completo normalizado ou por qualquer par OAB+UF principal/secundário, e partes por igualdade do nome completo normalizado, sem correspondência aproximada nem desambiguação presumida de homônimos; persistência mantém tenant e vínculos corretos; deduplicação conjunta funciona entre caminhos e execuções sem fundir tenants ou publicações distintas; falhas persistentes permanecem observáveis como falhas. Limites operacionais e bloqueios técnicos devem ser resolvidos antes de implementação.
