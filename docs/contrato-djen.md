# Contrato DJEN — evidências para as tarefas 1a e 1b

Fonte oficial: [OpenAPI](https://comunicaapi.pje.jus.br/swagger/djen.yml). Referência funcional: [coleta](../SPEC-coleta.md). Documento de validação, não implementação de coletor. Estabilidade de `id` e `hash` permanece premissa aceita; não foi reaberta.

## Cadernos: contrato e campos

`GET /api/v1/caderno/{sigla_tribunal}/{data}/{meio}` recebe data no formato `YYYY-MM-DD`; `D` representa Diário Eletrônico e `E`, Edital. Segundo a documentação, retorna metadados e URL temporária de cinco minutos; cadernos do dia são disponibilizados a partir das 03h. O fuso operacional da aplicação foi fixado pelo solicitante em `America/Sao_Paulo`.

Decisão do solicitante: incluir **D e E** nas duas coletas diárias dos tribunais monitorados, sem configuração adicional por advogado.

A data de referência é exclusivamente o dia corrente da execução. A disponibilidade de um caderno/tribunal/meio não é garantia de cobertura de todos os tribunais ou tipos de publicação.

ZIP contém arquivos JSON com objeto raiz `count` e `items`. Os campos observados incluem `id`, `hash`, `numero_processo`, `siglaTribunal`, `texto`, `destinatarios` e `destinatarioadvogados`. O objeto `advogado` em `destinatarioadvogados` contém `id`, `nome`, `numero_oab` e `uf_oab`. Nomes de partes são disponibilizados em `destinatarios[].nome` na amostra anteriormente inspecionada do TJAC.

Esses campos oferecem os insumos de busca por nome/OAB do advogado, número de processo e nome de parte. Não fixam correspondência aproximada, desambiguação de homônimos ou regras de normalização; essas decisões pertencem à tarefa 3c.

## Validação real pela máquina local

Amostra TJRO/D de 28/10/2026, status `Processado`:

- Download do ZIP realizado em memória, sem persistir publicações no repositório.
- SHA256 do ZIP igual ao `hash` dos metadados do caderno. Esse hash do arquivo é distinto do `hash` de cada comunicação usado na deduplicação.
- Oito arquivos JSON, coincidindo com `numero_paginas` dos metadados.
- Verificação de CRC do ZIP íntegra; todos os JSONs foram decodificados e percorridos.
- Total de 7.729 comunicações, igual a `total_comunicacoes` dos metadados.
- Nenhuma comunicação sem `id` ou `hash` nessa amostra; isso não garante preenchimento universal.
- Uma cópia truncada em memória, com os primeiros cem bytes do ZIP, foi recusada com `BadZipFile`. ZIP inválido não equivale a uma consulta válida com zero publicações.

O experimento verifica estrutura e integridade dessa amostra, não capacidade de produção, ausência de riscos em arquivos de terceiros nem cobertura global.

Revisão de contrato da tarefa 1a: para o TJRO/D da amostra, os metadados identificaram oito arquivos e 7.729 comunicações; o pacote íntegro confirmou essas contagens. Em exercício de mesa, um pacote com menos JSONs ou comunicações que o informado é incompleto e deve falhar, repetir e, ao esgotar tentativas, acionar fallback. O ZIP truncado efetivamente testado também falha. Esses cenários não demonstram cobertura universal nem estabelecem que metadados estarão sempre presentes.

Exercício de mesa da operação diária: se o caderno da primeira execução falhar três vezes, com esperas de um e cinco minutos, o fallback consulta apenas a data corrente. Se o fallback também falhar, o tribunal permanece em estado de falha, não de zero publicações. A segunda execução no mesmo dia pode recuperar as publicações; após interrupção, retomam-se pendências apenas da data corrente em `America/Sao_Paulo`. São cenários de contrato, não testes de coleta executados.

## Decisões ainda pendentes

Os meios D e E estão decididos. Horários, limite de tentativas e intervalos de backoff serão definidos por variáveis de ambiente; os valores iniciais aprovados são três tentativas por caminho e intervalos de um e cinco minutos. Nomes, formato e validações permanecem pendentes do contrato técnico. Agenda e data corrente usam sempre Brasília (`America/Sao_Paulo`), independentemente do fuso do servidor. ZIP inválido ou divergência entre metadados e conteúdo configura falha: repetir o caderno e, esgotadas as tentativas, acionar fallback sem aceitar conteúdo parcial como coleta completa nem apresentar falha como zero publicações. Após reinício ou interrupção, retomar automaticamente pendências do dia corrente, preservando planejamento, vínculos e deduplicação, sem recuperar datas anteriores. Permanecem pendentes seleção de tribunais, identificação das divergências verificáveis e demais critérios operacionais de falha.

Na API de comunicações, usar paginação e sempre `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais ao dia corrente. Detalhamento e fechamento do contrato de paginação permanecem na tarefa 1b. Nenhuma dessas tarefas deve ser marcada concluída apenas pela existência desta amostra.

### Risco de paginação a verificar

Uma [referência independente não oficial](https://raw.githubusercontent.com/thiagozs/skills-datajud-djen-jus/main/skills/djen/references/consultas.md) relata limite de 50 itens por página, páginas vazias transitórias e possível teto de 10.000 no `count`. São alegações não verificadas nesta sessão, não contrato oficial nem motivo para descartar resultados. A consulta direta ao OpenAPI retornou HTTP 403; antes de declarar o fallback completo, verificar em ambiente com acesso à fonte a paginação, os limites, a semântica de `count` e o comportamento de páginas vazias. Não adotar sugestões daquela referência que alterem a janela diária, a chave de deduplicação ou a comparação de OAB já aprovadas.
