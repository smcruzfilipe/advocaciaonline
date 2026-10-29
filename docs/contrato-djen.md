# Contrato DJEN — evidências para as tarefas 1a–1c

Fonte oficial: [OpenAPI](https://comunicaapi.pje.jus.br/swagger/djen.yml). Referência funcional: [coleta](../SPEC-coleta.md). Documento de validação, não implementação de processador. Estabilidade de `id` e `hash` permanece premissa aceita; não foi reaberta.

## Cadernos: contrato e campos

`GET /api/v1/caderno/{sigla_tribunal}/{data}/{meio}` recebe data no formato `YYYY-MM-DD`; na API da fonte, `D` representa Diário Eletrônico e `E`, Edital. A aplicação usa exclusivamente `D`; a existência de `E` no contrato externo não autoriza sua coleta. Segundo a documentação, o endpoint retorna metadados e URL temporária de cinco minutos; cadernos do dia são disponibilizados a partir das 03h. O fuso operacional da aplicação foi fixado pelo solicitante em `America/Sao_Paulo`.

Decisão vigente do solicitante: **somente Diário Eletrônico (`D`), nenhuma coleta de editais (`E`)**, nas duas coletas diárias dos tribunais monitorados, sem configuração adicional por advogado. Primeiro slot: caderno com fallback API após esgotar tentativas; segundo slot: API diretamente, sem consultar cadernos. A inclusão anterior de D/E foi superada; as amostras E abaixo permanecem apenas como evidência histórica.

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

Exercício de mesa da operação diária vigente (cenários de contrato, não testes de coleta executados): (1) no primeiro horário, o caderno de um trabalho D falha três vezes com esperas de um e cinco minutos e o fallback também falha três vezes; esse trabalho permanece em falha final. Outro trabalho D de entidade diferente no mesmo tribunal conclui sem correspondências, e o agregado do tribunal é parcial, não zero; (2) no segundo horário da mesma data, a API paginada encontra publicações sem consultar cadernos, a nova execução conclui sem apagar a falha anterior e a deduplicação por `id` + `hash` mantém uma comunicação e todos os vínculos; (3) interrupção durante a página 2 da API não conclui a consulta, consome a tentativa interrompida e, após reinício no mesmo dia e backoff restante, a tentativa seguinte começa na página 1; só a página vazia válida conclui. Reinício após mudança da data local não consulta o dia anterior, mas mantém a pendência identificada como interrompida/não recuperada.

## Decisões operacionais do gate 1c

Dois horários diários são obrigatórios no fuso `America/Sao_Paulo`, configurados sem defaults por `COLETA_HORARIO_1` e `COLETA_HORARIO_2` em `HH:MM` 24 horas; devem ser distintos e ascendentes, com o primeiro a partir de 04:00. Recomenda-se configurar `04:00` e `16:00`: a documentação informa disponibilização de cadernos a partir das 03h, sem garantir disponibilidade imediata por tribunal/meio. Recomendações não são defaults; configuração ausente ou inválida impede iniciar o despachante.

Cada slot gera execução identificável, com data corrente fixada ao início. Planejar o perfil profissional válido do tenant e monitoramentos de parte/processo não desativados; sem filtro, aplicar a todos os tribunais disponíveis na fonte, e com filtro, somente aos selecionados. Consultar somente `D` por tribunal aplicável, nunca `E`. Estado e vínculos são fixados no planejamento; desativação posterior afeta as próximas execuções, não altera retroativamente trabalho em andamento. Sem entidade elegível após resolução válida do tenant/perfil/escopo, registrar “sem trabalho elegível”; falha para resolver esses vínculos/escopo é falha de planejamento, não ausência de trabalho. Nenhum desses casos é zero publicações.

Cada trabalho é rastreado por execução, tenant, entidade, tribunal e meio, sempre `D`. No primeiro slot, sucesso exige caderno validado ou fallback totalmente percorrido; no segundo, exige consulta direta da API totalmente percorrida. Resposta válida vazia ou sem correspondências é sucesso com zero; ausência de trabalho é outro estado. O agregado do tribunal é sucesso quando todos os trabalhos D planejados concluíram, parcial quando algum concluiu e outro falhou ou permanece pendente, e em andamento quando nenhum concluiu e há pendências. Falha final exige todos os trabalhos terminados, nenhum com sucesso e pelo menos uma falha final. Não anunciar parcial como completo nem falha como zero.

Uma falha de caderno inclui erro de transporte/timeout, HTTP não exitoso, status ausente/desconhecido ou diferente de `Processado`/`Sem comunicações`, resposta malformada ou sem URL fora do status explicitamente vazio, download falho, ZIP inválido/CRC incorreto, JSON inválido, raiz não objeto, `items` ausente ou de tipo incorreto, item não objeto, ou divergência nos metadados fornecidos. A OpenAPI oficial lista os estados `Não Processado`, `Em processamento`, `Processado`, `Sem comunicações` e `Cancelado`: `Processado` exige pacote/URL validável; `Sem comunicações` é sucesso vazio se nenhum metadado fornecido contradiz zero; os demais estados não são zero. Quando presentes, comparar `hash` com SHA-256 do ZIP, `numero_paginas` com o número de JSONs e `total_comunicacoes` com a soma dos itens. Metadado opcional ausente não é divergência por si só. O campo `count` do JSON foi observado, mas sua semântica não é definida pela OpenAPI e ele não é critério de completude. Zero também é válido para ZIP completo/validado com zero itens. Os estados, URL temporária de cinco minutos e disponibilização a partir de 03h estão descritos na [OpenAPI oficial](https://comunicaapi.pje.jus.br/swagger/djen.yml), endpoint `/api/v1/caderno/{sigla_tribunal}/{data}/{meio}`. Respostas HTTP/transporte/JSON/estrutura inválidas da API também falham; falha em qualquer página invalida a tentativa inteira, mesmo após páginas com itens. A página vazia válida continua sendo o critério de término já decidido, sem alteração da regra de paginação.

Os defaults são três tentativas por caminho (`COLETA_TENTATIVAS_POR_CAMINHO`, inteiro de 1–3; qualquer override diferente de 3 requer aprovação, e nenhum valor acima de 3 é aceito sem nova decisão), com `COLETA_BACKOFF_APOS_FALHA_1_SEGUNDOS=60` e `COLETA_BACKOFF_APOS_FALHA_2_SEGUNDOS=300` (inteiros positivos; overrides requerem aprovação). As esperas ocorrem somente quando resta tentativa; cada tentativa do caderno inclui novo pedido de metadados/URL, download e validação, e cada tentativa da API percorre toda a paginação. No primeiro slot, depois de esgotar o caderno, iniciar o fallback, com limite/backoff próprios; no segundo, aplicar diretamente as tentativas da API, sem etapa de caderno. Se a fonte fornecer `Retry-After`, aguardar pelo menos esse prazo. Tentativa da API interrompida ou com qualquer página falha recomeça em `pagina=1`, em ambos os slots; a paginação contratual não muda.

No reinício dentro da mesma data local, retomar trabalho pendente preservando data, plano, vínculos, etapa, espera e tentativas; não repetir trabalho concluído. Chamada em andamento de resultado desconhecido consome uma tentativa. Horários perdidos no mesmo dia são executados uma vez na retomada, em ordem, sem criar slots adicionais. O segundo horário cria execução independente, permitindo recuperar publicações no mesmo dia sem apagar falhas anteriores. Após mudança de data antes da retomada, não consultar datas anteriores: deixar o trabalho identificado como interrompido/não recuperado e executar somente os slots da data corrente.

Na API de comunicações, tanto o fallback do primeiro slot quanto o caminho direto do segundo consultam tribunal e meio `D` com `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais ao dia corrente, sem filtrar por entidade na fonte. A regra de paginação adotada está em [SPEC-coleta.md](../SPEC-coleta.md#escopo-e-contratos-lógicos); a política de tentativas, falhas e retomada está acima. Seleção de tribunais, disponibilidade e cobertura efetiva continuam condicionadas à operação da fonte, não à decisão operacional.

Somente o campo `texto` recebido pela API é convertido em texto simples antes de persistir; o texto dos cadernos não é sanitizado. A deduplicação preserva a primeira versão para a chave conjunta `id` + `hash`: HTML recebido primeiro do caderno não é substituído pela versão sanitizada recebida depois da API. O consumidor deve tratar todo conteúdo como não confiável e escapá-lo na renderização.

### Evidências de paginação

A referência independente não oficial alegava limite de 50 itens, páginas vazias transitórias e possível teto de 10.000 no `count`. O [OpenAPI oficial](https://comunicaapi.pje.jus.br/swagger/djen.yml), acessado em 28/10/2026 via nó de saída Tailscale, informa valores válidos **5 e 100** para `itensPorPagina` e limita a 10.000 resultados consultas textuais ou OAB, com até cinco itens por página, com datas inicial e final diferentes, ou por número de processo. A consulta por tribunal deve manter datas iguais e não pressupor que filtros por entidade preservem a cobertura.

Na mesma data, consultas reais a TJRO, meio D, com início e fim em 28/10/2026 retornaram HTTP 200 e `status: success`:

| Itens por página | Página | `count` | Quantidade em `items` |
|---:|---:|---:|---:|
| 5 | 1 | 7729 | 5 |
| 50 | 1 | 7729 | 50 |
| 100 | 1 | 100 | 100 |
| 100 | 2 | 100 | 100 |
| 100 | 77 | 100 | 100 |
| 100 | 78 | 29 | 29 |
| 100 | 79, 80 e 1000 | 0 | 0 |

O valor 50 funcionou nesta amostra, mas não é um dos valores que a documentação oficial indica como válidos. O comportamento observado de `count` mudou com o tamanho da página; portanto, não se pode presumir que sempre represente o total da consulta. Adota-se página de 100 itens e parada na primeira resposta válida com `items` vazio, após processar todas as páginas anteriores, inclusive parciais. Falhas de resposta não são consideradas páginas vazias. Respeitar os cabeçalhos de limite de requisições informados pela fonte.

### Verificações adicionais de 28/10/2026

**Evidências históricas de 28/10/2026, anteriores à restrição ao meio D:** consultas com data inicial e final iguais a 28/10/2026, tribunal, meio e `itensPorPagina=100` retornaram `status: success`. As linhas E preservam observações anteriores, não instruções de coleta vigente:

| Tribunal/meio | Metadados do caderno | Páginas observadas na API: página → itens |
|---|---|---|
| TJAC/E | Processado, 5 comunicações | 1 → 5; 2 → 0 |
| TJRR/E | Sem comunicações, 0 | 1 → 0 |
| TJAP/D | Processado, 467 comunicações | 1–4 → 100 cada; 5 → 67; 6 → 0 |
| TJRR/D | Processado, 13.253 comunicações | 100 → 100; 101 → 100; 133 → 53; 134 → 0 |

Para TJAP/D, todos os itens das páginas 1–6 foram comparados ao ZIP do caderno: ambos continham 467 combinações únicas de `id` e `hash`, sem chaves exclusivas de qualquer dos dois conjuntos. O SHA-256 do ZIP coincidiu com o metadado e o teste CRC não identificou erro. A comparação não verificou a equivalência dos demais campos nem prova cobertura geral. Para TJRR/D, as páginas intermediárias não foram todas percorridas; a página 133 demonstra apenas que esta consulta específica alcançou resultados além da posição 10.000.

Uma nova consulta das páginas 1 e 2 de TJAP/D, repetida em sequência na mesma data, apresentou a mesma ordem de pares `id`/`hash` em cada repetição e nenhuma interseção entre as duas páginas. Isso é uma observação pontual, não garantia de estabilidade durante alterações no DJEN. O [padrão genérico de APIs do PJe](https://docs.pje.jus.br/manuais-basicos/padroes-de-api-do-pje) descreve um objeto `page-info` com última página, mas a resposta observada e o OpenAPI específico do DJEN não estabelecem esse objeto; não se pode transferir essa garantia genérica ao endpoint.

Esses casos ilustram resposta vazia com caderno sem comunicações e final de paginação após página parcial. A regra adotada usa esse comportamento observado como critério operacional; a documentação oficial consultada não garante ordenação estável ou consistência durante alterações da fonte, e as amostras não comprovam completude universal.
