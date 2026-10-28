# Contrato DJEN — evidências para as tarefas 1a e 1b

Fonte oficial: [OpenAPI](https://comunicaapi.pje.jus.br/swagger/djen.yml). Referência funcional: [coleta](../SPEC-coleta.md). Documento de validação, não implementação de coletor. Estabilidade de `id` e `hash` permanece premissa aceita; não foi reaberta.

## Cadernos: contrato e campos

`GET /api/v1/caderno/{sigla_tribunal}/{data}/{meio}` recebe data no formato `YYYY-MM-DD`; `D` representa Diário Eletrônico e `E`, Edital. Segundo a documentação, retorna metadados e URL temporária de cinco minutos; cadernos do dia são disponibilizados a partir das 03h. O fuso operacional não foi decidido.

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

## Decisões ainda pendentes

Os meios D e E estão decididos. Permanecem pendentes seleção de tribunais, critérios de pacote incompleto, comportamento para divergência de hash/contagem e acionamento do fallback. A validação não decide se cada problema deve provocar nova tentativa ou fallback imediato. Quantidade de tentativas, backoff, horários/fuso e definição operacional de falha dependem da tarefa 1c.

Na API de comunicações, usar paginação e sempre `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais ao dia corrente. Detalhamento e fechamento do contrato de paginação permanecem na tarefa 1b. Nenhuma dessas tarefas deve ser marcada concluída apenas pela existência desta amostra.
