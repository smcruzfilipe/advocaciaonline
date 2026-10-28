# Especificação proposta: monitoramentos

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas ainda pendentes continuam bloqueantes antes da implementação. **ID:** `monitoramentos`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [identidade](SPEC-identidade.md), [autorização](SPEC-autorizacao.md), [stack](docs/stack.md).

## Objetivo

Permitir ao advogado e aos usuários autorizados manter os alvos de acompanhamento do tenant: o próprio advogado, partes identificadas por nome e processos identificados por número, com seleção de tribunais para partes e processos. Os cadastros alimentam os módulos de coleta e consulta sem transferir a este módulo a responsabilidade por executar buscas na fonte ou decidir quem pode acessar os dados.

## Escopo e dono dos contratos

Este módulo é dono da identidade lógica dos monitoramentos e de sua associação ao tenant: referência ao perfil profissional do advogado monitorado, cadastro de partes por nome, cadastro de processos por número e filtros de tribunal associados aos cadastros de partes/processos. Fornece a identidade da entidade e seu tenant ao módulo de coleta, conforme o [mapa](CAPABILITIES.md).

- [Identidade](SPEC-identidade.md) é dona do perfil profissional do advogado e seu tenant; monitoramentos consome nome e OAB principal/secundárias sem criar um segundo perfil divergente. [Autorização](SPEC-autorizacao.md) decide se o usuário pode cadastrar ou ler monitoramentos e se pode operar no tribunal em questão. Coleta é dona da obtenção/normalização de publicações e implementa o matching destas contra monitoramentos, aplicando os critérios de equivalência definidos nesta especificação. Consulta é dona de comunicações, detalhes e dashboard.

## Contratos lógicos

- **Advogado monitorado:** o monitoramento do advogado é derivado do perfil de identidade do advogado do tenant, incluindo nome e OAB principal/secundárias existentes. Não cria um tenant de escritório nem um cadastro profissional conflitante.
- **Matching do advogado:** uma publicação corresponde ao advogado se o nome completo normalizado corresponder **ou** se houver igualdade de qualquer par OAB elegível (`número OAB` + `UF`) do perfil. OAB principal e secundárias têm o mesmo efeito; chaves repetidas no perfil contam uma só vez.
- **Parte:** cadastro com nome informado pelo usuário autorizado, associado ao tenant autenticado. A publicação corresponde à parte pelo nome completo normalizado.
- **Validação e equivalência de nomes:** nome informado deve ser não vazio após remover espaços nas extremidades e reduzir sequências de espaços em branco a um só; a forma apresentada conserva caixa, acentos e pontuação. Para matching, comparar nomes completos sem diferença de caixa ou diacríticos e com espaços excedentes reduzidos. Pontuação é significativa e não é removida nem equiparada a espaço; não há correspondência aproximada, por trecho, apelido ou abreviação. Nome ausente/vazio na publicação não corresponde.
- **Processo:** aceitar o número CNJ no formato mascarado `NNNNNNN-DD.AAAA.J.TR.OOOO` ou como exatamente 20 dígitos sem máscara. Retirar apenas os separadores `-` e `.` do formato mascarado; validar 20 dígitos ASCII e comparar essa sequência, preservando zeros iniciais e sem conversão para inteiro. Entrada fora desses formatos é recusada; número malformado vindo da fonte não corresponde. Estrutura conforme [Resolução CNJ nº 65/2008](https://atos.cnj.jus.br/atos/detalhar/atos-normativos?documento=119).
- **OAB:** para matching, `numero_oab` deve ser texto não vazio, aparado apenas nas extremidades e comparado literalmente; preservar zeros, sufixos, pontuação, caracteres internos e caixa, sem converter para número ou remover sufixo. `uf_oab` é aparada e convertida para maiúsculas e deve ser uma das 27 siglas de unidades federativas, incluindo DF. Não validar existência/regularidade da inscrição em cadastro externo. O perfil e a validação de seus dados de entrada continuam sob responsabilidade de Identidade.
- **Duplicidade de monitoramentos:** dentro de um tenant, só pode existir um alvo de parte por nome canônico e um alvo de processo por sequência canônica de 20 dígitos, incluindo alvos desativados e sem considerar o filtro de tribunal. Repetição é conflito, não novo alvo; editar ou reativar o existente. A unicidade é da chave de busca, não afirma identidade civil nem funde registros de tenants diferentes.
- **Homônimos:** nomes completos iguais após a normalização continuam ambíguos; a publicação corresponde ao alvo por nome sem desambiguação, exclusão ou escolha de pessoa por destinatário, polo ou outro campo.
- **Tribunais:** ausência de filtro em parte ou processo significa todos os tribunais atualmente disponibilizados pela fonte. Filtro explícito deve conter ao menos um código disponibilizado e suportado; lista vazia é inválida, códigos repetidos são reduzidos a um só e códigos não oferecidos são recusados. Se um código selecionado deixar de estar disponível, conservar a seleção e não ampliar silenciosamente para todos; não coletar por esse código até voltar a ser disponibilizado. O escopo de coleta não amplia a permissão de consulta dos usuários.
- **Saída para coleta:** cada monitoramento disponibiliza ao consumidor sua identidade lógica e o tenant dono, além dos dados de busca definidos para o tipo de entidade. Formato de ID, persistência, serialização e transporte são decisões técnicas pendentes.
- **Acesso:** cadastro, leitura e qualquer outra ação dependem da decisão de autorização. O servidor vincula o registro ao tenant do contexto autenticado e não aceita tenant enviado pelo cliente como prova de propriedade.

## Requisitos

1. O advogado do tenant é acompanhado por seu nome e suas OABs, conforme perfil de identidade; o perfil não é duplicado nem escolhido como entidade de outro tenant.
2. Um usuário autorizado pode cadastrar e ler partes por nome e processos por número no tenant do advogado.
3. Partes e processos podem ter filtro de tribunais disponibilizados pela fonte, sujeito à capacidade real de consulta da fonte. Filtro ausente abrange os tribunais disponíveis; seleção explícita precisa conter somente códigos suportados e não se amplia silenciosamente se um código deixar de estar disponível.
4. Cada monitoramento pertence a exatamente seu tenant autenticado para fins de isolamento; dados de tenant enviados pelo cliente não alteram essa associação.
5. O módulo disponibiliza a identidade lógica da entidade e o tenant para coleta, sem executar a coleta nem implementar o matching. Os critérios de equivalência estão definidos nesta especificação e Coleta os aplica ao matching de publicações; resultado da fonte e deduplicação continuam fora do escopo deste módulo.
6. A interface oferece páginas de cadastro e leitura dos monitoramentos e navegação para dashboard e resultados. A autorização de cada destino continua sob responsabilidade de autorização/consulta.
7. O matching usa igualdade dos nomes completos após normalizar caixa, diacríticos e espaços em branco; pontuação permanece significativa, e não se aceitam aproximações, trechos, apelidos ou abreviações. Para advogado, igualdade de nome **ou** de um par OAB elegível principal/secundário estabelece correspondência. Homônimos não são desambiguados.
8. O cadastro de parte exige nome não vazio após trim/colapso de espaços. Processo deve ser um número CNJ de 20 dígitos, mascarado no formato `NNNNNNN-DD.AAAA.J.TR.OOOO` ou sem máscara; somente `-` e `.` do formato são removidos. OAB para matching exige número textual não vazio e UF brasileira reconhecida; o perfil continua sob responsabilidade de Identidade.
9. Parte/processo duplicado no mesmo tenant é definido por chave canônica de busca, inclusive se desativado e independentemente do filtro; edição ou reativação reutiliza o alvo existente. A chave não declara identidade única de pessoa, e tenants diferentes podem manter a mesma chave.
10. Na primeira entrega, o advogado pode editar e desativar monitoramentos de partes e processos. Desativar interrompe novas coletas do alvo, preservando comunicações já coletadas, vínculos históricos e registros imutáveis do Escriba. Não implementar exclusão do cadastro como substituta da desativação.

## Critérios observáveis

- No tenant do advogado, o acompanhamento do advogado reflete o nome, OAB principal e OABs secundárias do perfil de identidade, sem exigir cadastro profissional separado.
- Um usuário autorizado consegue cadastrar uma parte informando nome e consultar a leitura desse cadastro no tenant correto.
- Um usuário autorizado consegue cadastrar um processo informando número e consultar a leitura desse cadastro no tenant correto.
- O usuário consegue selecionar filtros de tribunal oferecidos para os cadastros aplicáveis; a aplicação não apresenta como suportado um tribunal/filtro que a fonte não disponibiliza.
- Um cadastro associado a um tenant não pode ser lido ou alterado por outro tenant apenas pelo envio do identificador do cadastro.
- A saída lógica para coleta permite identificar a entidade monitorada e seu tenant, sem exigir formato técnico ainda não escolhido.
- As páginas de cadastro/leitura e a navegação para dashboard/resultados estão disponíveis aos usuários autorizados; negar acesso impede leitura dos dados protegidos.
- Nome vazio após trim/colapso de espaços é rejeitado; caixa, diacríticos e espaços excedentes não mudam a equivalência. Exemplo: `  JOSE  da Silva ` e `José da Silva` correspondem; `José, da Silva`, `José-da-Silva` e `José da Silva Filho` não correspondem a `José da Silva`.
- Número CNJ mascarado `0001234-56.2024.8.01.0001` e a forma de 20 dígitos `00012345620248010001` são o mesmo alvo; zeros iniciais permanecem. Número truncado, com letra ou com máscara fora do padrão é recusado no cadastro e não corresponde quando vier assim da fonte.
- OAB `001234-A`/`AC` corresponde apenas ao mesmo token completo e à mesma UF após normalizar UF para maiúsculas; não corresponde a `1234-A`/`AC`, `001234`/`AC` ou `001234-A`/`AL`. OAB ausente ou com UF não reconhecida não estabelece matching por inscrição, mas a alternativa por nome continua válida. Não se promete validação da inscrição perante a OAB.
- Segunda inclusão de parte com a mesma chave nominal ou de processo com o mesmo número canônico no mesmo tenant é conflito, mesmo que o alvo existente esteja desativado ou tenha outro filtro; o alvo pode ser editado/reativado. A mesma chave em outro tenant é independente. Repetir par OAB+UF em campos do perfil não gera correspondência adicional.
- Publicações contendo o mesmo nome normalizado de pessoas homônimas correspondem ao mesmo alvo nominal; o sistema não escolhe entre pessoas nem usa polo/destinatário para desfazer a ambiguidade.
- Filtro ausente significa todos os tribunais disponibilizados; seleção explícita exige pelo menos um código suportado. Código não oferecido e lista explícita vazia são rejeitados. Se tribunal salvo ficar indisponível, o filtro permanece salvo, não é convertido em ausência de filtro e volta a valer quando o código for disponibilizado.

## Ambiente de implementação e teste: pendências bloqueantes

Stack base definida: API central em Ruby on Rails exclusivamente no modo API (`--api`), frontend Next.js e PostgreSQL com Row-Level Security (RLS), conforme [stack](docs/stack.md). Versões, ferramentas e dependências, comandos e caminhos físicos da aplicação continuam pendentes; não inventar comandos de build, teste ou lint, diretórios, sintaxe de implementação, dependências ou snippet de estilo. Ainda não há aplicação nem código real que sirva de referência para estilo.

As políticas de RLS não substituem RBAC nem a autorização exigida para cada ação; o tenant efetivo deve ser derivado no servidor do contexto autenticado, nunca de dado enviado pelo cliente. Ver também [stack](docs/stack.md).

- **Comandos:** build, execução de testes, lint e desenvolvimento local — não definidos; nenhum comando é proposto.
- **Estrutura:** diretórios de aplicação, testes e configuração — não definidos.
- **Estilo:** não há código real que sirva de referência. Convenções e snippet dependem do repositório de implementação e de seu estilo, ainda não estabelecidos.
- **Estratégia de teste:** framework, localização e comandos são pendências; os itens abaixo são cenários comportamentais de contrato, não testes executados. Cobrir nome vazio, equivalência de caixa/diacríticos/espaços, pontuação significativa e rejeição de matching parcial; equivalência entre CNJ mascarado e não mascarado, zeros iniciais e formatos inválidos; par OAB com UF válida, sufixo preservado, UF inválida e OAB ausente com fallback por nome; conflito de duplicata ativa/inativa e isolamento entre tenants; homônimos sem desambiguação; filtro ausente, inválido/vazio, seleção suportada e tribunal selecionado que fica indisponível sem expansão silenciosa. Também cobrir autorização e fornecimento de identidade/tenant à coleta. Não usar amostras da fonte como garantia de cobertura.
- **Desempenho:** 300 usuários simultâneos são referência de planejamento; medição futura não bloqueia esta entrega.

## Fronteiras

- **Sempre:** vincular cadastros ao tenant autenticado no servidor; usar perfil profissional de identidade para o advogado monitorado; validar as chaves de busca conforme os contratos acima; restringir filtros à disponibilidade real da fonte sem ampliá-los silenciosamente; aplicar decisões de autorização em cadastro e leitura; fornecer identidade lógica e tenant a coleta.
- **Pedir aprovação:** comportamento de edições/desativação sobre trabalhos já planejados ou em execução; formato técnico e persistência. Edição e desativação estão aprovadas; exclusão de cadastro não foi escolhida.
- **Nunca:** tratar escritório como tenant; aceitar tenant enviado pelo cliente como prova de propriedade; inventar correspondência por similaridade, apelidos, abreviações ou desambiguação de homônimos; prometer cobertura da fonte ou recuperação histórica; executar coleta ou decisão de acesso dentro deste módulo.

## Questões abertas

As decisões de domínio do gate 3c para nome, OAB, processo, duplicidade, homônimos e filtros de tribunal estão registradas nos contratos lógicos e critérios observáveis. Permanecem fora deste gate, sem alteração ou presunção de fluxo novo:

1. Trabalhos já planejados preservam os critérios e vínculos fixados no planejamento; edição ou desativação afeta apenas novos planejamentos, conforme [coleta](SPEC-coleta.md#política-operacional-gate-1c). Exclusão de cadastro não substitui desativação e não foi aprovada.
2. O contrato entre módulos e os componentes propostos estão em [arquitetura](docs/arquitetura.md#contratos-de-módulo); formato físico e testes dependem da implementação.

Este fechamento não cria fluxo de convite, edição/remoção além da edição/desativação já aprovada, comunicação por e-mail ou recuperação histórica; aplicam-se os limites já aprovados nas especificações de identidade, coleta e intenção.
