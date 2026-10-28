# Especificação proposta: monitoramentos

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `monitoramentos`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [identidade](SPEC-identidade.md), [autorização](SPEC-autorizacao.md).

## Objetivo

Permitir ao advogado e aos usuários autorizados manter os alvos de acompanhamento do tenant: o próprio advogado, partes identificadas por nome e processos identificados por número, com seleção de tribunais para partes e processos. Os cadastros alimentam os módulos de coleta e consulta sem transferir a este módulo a responsabilidade por executar buscas na fonte ou decidir quem pode acessar os dados.

## Escopo e dono dos contratos

Este módulo é dono da identidade lógica dos monitoramentos e de sua associação ao tenant: referência ao perfil profissional do advogado monitorado, cadastro de partes por nome, cadastro de processos por número e filtros de tribunal associados aos cadastros de partes/processos. Fornece a identidade da entidade e seu tenant ao módulo de coleta, conforme o [mapa](CAPABILITIES.md).

- [Identidade](SPEC-identidade.md) é dona do perfil profissional do advogado e seu tenant; monitoramentos consome nome e OAB principal/secundárias sem criar um segundo perfil divergente. [Autorização](SPEC-autorizacao.md) decide se o usuário pode cadastrar ou ler monitoramentos e se pode operar no tribunal em questão. Coleta é dona da obtenção/normalização de publicações e implementa o matching destas contra monitoramentos, aplicando os critérios de equivalência definidos nesta especificação. Consulta é dona de comunicações, detalhes e dashboard.

## Contratos lógicos

- **Advogado monitorado:** o monitoramento do advogado é derivado do perfil de identidade do advogado do tenant, incluindo nome e OAB principal/secundárias existentes. Não cria um tenant de escritório nem um cadastro profissional conflitante.
- **Matching do advogado:** uma publicação corresponde ao advogado se o nome completo normalizado corresponder **ou** se houver igualdade do par númeroOAB+UF com qualquer OAB principal ou secundária do perfil.
- **Parte:** cadastro com nome informado pelo usuário autorizado, associado ao tenant autenticado. A publicação corresponde à parte pelo nome completo normalizado.
- **Equivalência de nomes para matching:** comparar nomes completos após ignorar diferenças de maiúsculas/minúsculas e acentos, remover espaços no início/fim e reduzir sequências internas de espaços a um só. Correspondência exige igualdade após essa normalização; não há matching por aproximação, apelidos ou abreviações. O critério não define tratamento de pontuação.
- **Processo:** comparar pelos dígitos do número sem máscara, preservando zeros iniciais e sem conversão para inteiro. Cadastro e dados da fonte usam a mesma regra de comparação.
- **OAB:** comparar número e UF separadamente, sem conversão do identificador para inteiro. Não remover sufixos de OAB; qualquer tratamento deles exige regra específica.
- **Tribunais:** ausência de filtro em parte ou processo significa todos os tribunais disponíveis na fonte. Se houver seleção, limitar o monitoramento aos tribunais selecionados. O escopo de coleta não amplia a permissão de consulta dos usuários.
- **Saída para coleta:** cada monitoramento disponibiliza ao consumidor sua identidade lógica e o tenant dono, além dos dados de busca definidos para o tipo de entidade. Formato de ID, persistência, serialização e transporte são decisões técnicas pendentes.
- **Acesso:** cadastro, leitura e qualquer outra ação dependem da decisão de autorização. O servidor vincula o registro ao tenant do contexto autenticado e não aceita tenant enviado pelo cliente como prova de propriedade.

## Requisitos

1. O advogado do tenant é acompanhado por seu nome e suas OABs, conforme perfil de identidade; o perfil não é duplicado nem escolhido como entidade de outro tenant.
2. Um usuário autorizado pode cadastrar e ler partes por nome e processos por número no tenant do advogado.
3. Partes e processos podem ter filtro de tribunais disponibilizados pela fonte, sujeito à capacidade real de consulta da fonte. Não prometer cobertura de tribunal ou capacidade de filtro não verificada.
4. Cada monitoramento pertence a exatamente seu tenant autenticado para fins de isolamento; dados de tenant enviados pelo cliente não alteram essa associação.
5. O módulo disponibiliza a identidade lógica da entidade e o tenant para coleta, sem executar a coleta nem implementar o matching. Os critérios de equivalência estão definidos nesta especificação e Coleta os aplica ao matching de publicações; resultado da fonte e deduplicação continuam fora do escopo deste módulo.
6. A interface oferece páginas de cadastro e leitura dos monitoramentos e navegação para dashboard e resultados. A autorização de cada destino continua sob responsabilidade de autorização/consulta.
7. O matching de nomes exige igualdade de nomes completos após normalizar caixa, acentos e espaços excedentes; não aceita aproximações, apelidos ou abreviações. Para advogado, o matching também pode ocorrer pela igualdade do par númeroOAB+UF em qualquer OAB principal/secundária. Homônimos continuam possíveis e não há promessa de desambiguá-los ou excluí-los. Normalização/validação de OAB e número de processo, tratamento de pontuação e de duplicatas continuam pendentes.

## Critérios observáveis

- No tenant do advogado, o acompanhamento do advogado reflete o nome, OAB principal e OABs secundárias do perfil de identidade, sem exigir cadastro profissional separado.
- Um usuário autorizado consegue cadastrar uma parte informando nome e consultar a leitura desse cadastro no tenant correto.
- Um usuário autorizado consegue cadastrar um processo informando número e consultar a leitura desse cadastro no tenant correto.
- O usuário consegue selecionar filtros de tribunal oferecidos para os cadastros aplicáveis; a aplicação não apresenta como suportado um tribunal/filtro que a fonte não disponibiliza.
- Um cadastro associado a um tenant não pode ser lido ou alterado por outro tenant apenas pelo envio do identificador do cadastro.
- A saída lógica para coleta permite identificar a entidade monitorada e seu tenant, sem exigir formato técnico ainda não escolhido.
- As páginas de cadastro/leitura e a navegação para dashboard/resultados estão disponíveis aos usuários autorizados; negar acesso impede leitura dos dados protegidos.
- Para matching de nomes, comparar nomes completos após ignorar caixa e acentos, remover espaços no início/fim e reduzir sequências internas de espaços a um só; somente valores iguais após essa normalização correspondem. Nomes parciais, aproximações, apelidos e abreviações não correspondem; tratamento de pontuação não está definido.
- Para o advogado, o matching também ocorre quando há igualdade do par númeroOAB+UF de qualquer OAB principal ou secundária do perfil; esta alternativa não substitui a correspondência por nome.
- Homônimos continuam possíveis: o critério não promete distinguir pessoas diferentes com nomes equivalentes nem excluir correspondências por homonímia.

## Ambiente de implementação e teste: pendências bloqueantes

Não há aplicação, stack, convenção de comandos, estrutura de código, framework de teste ou exemplo real de estilo estabelecidos no repositório. Não inventar comandos de build, teste ou lint, diretórios, sintaxe de implementação, dependências ou snippet de estilo. Esses itens precisam ser escolhidos antes da implementação.

- **Comandos:** build, execução de testes, lint e desenvolvimento local — não definidos; nenhum comando é proposto.
- **Estrutura:** diretórios de aplicação, testes e configuração — não definidos.
- **Estilo:** não há código real que sirva de referência. Convenções e snippet só podem ser definidos após a escolha da stack e do repositório de implementação.
- **Estratégia de teste:** framework, localização e comandos são pendências. Os testes de aceitação devem cobrir perfil do advogado derivado de identidade, criação/leitura de partes e processos, filtros de tribunal suportados, autorização e isolamento entre tenants, e fornecimento de identidade/tenant ao consumidor coleta. Testes de matching devem verificar igualdade de nomes completos após ignorar caixa/acentos, remover espaços nas extremidades e reduzir sequências internas de espaços, rejeitar nomes parciais/aproximações/apelidos/abreviações, e verificar para advogado a alternativa de correspondência por nome ou igualdade do par númeroOAB+UF em qualquer OAB principal/secundária. Não exigir desambiguação ou exclusão de homônimos; a normalização/validação de OAB e número de processo e o tratamento de pontuação permanecem pendentes. Não usar testes de fonte como se fossem garantia de cobertura.
- **Limite de desempenho compartilhado:** a aplicação central deve suportar ao menos 300 usuários simultâneos; perfil, latências-alvo, ambiente e taxa de erro continuam pendentes na [especificação geral](docs/especificacao.md).

## Fronteiras

- **Sempre:** vincular cadastros ao tenant autenticado no servidor; usar perfil profissional de identidade para o advogado monitorado; restringir a seleção de tribunal à disponibilidade real da fonte; aplicar decisões de autorização em cadastro e leitura; fornecer identidade lógica e tenant a coleta.
- **Pedir aprovação:** definir normalização/validação da representação de OAB e números de processo, tratamento de pontuação em nomes e números e identificação de cadastros duplicados; filtros disponíveis, comportamento sem filtro e alterações posteriores de cadastro; edição/remoção e formato técnico/persistência dos registros.
- **Nunca:** tratar escritório como tenant; aceitar tenant enviado pelo cliente como prova de propriedade; inventar correspondência por similaridade, apelidos, abreviações ou desambiguação de homônimos, nem regras de normalização de OAB/processo ou tratamento de pontuação; prometer cobertura da fonte ou recuperação histórica; executar coleta ou decisão de acesso dentro deste módulo.

## Questões abertas

1. Que validações ou tratamento de pontuação se aplicam a nomes sem alterar o critério de equivalência nominal já definido?
2. Como validar representações inválidas, sufixos de OAB e cadastros duplicados? Processo sem máscara com zeros preservados e OAB/UF separadas já foram definidos.
3. Quais tribunais estão efetivamente disponíveis e como tratar alterações posteriores do filtro? Ausência de filtro já significa todos os tribunais disponíveis na fonte.
4. Quais operações de ciclo de vida existem além do cadastro e leitura, inclusive edição e remoção?
5. Qual referência lógica de entidade e contrato de saída serão necessários para coleta, sem acoplar a escolha a um formato de armazenamento/transportes ainda não decidido?
6. Quais stack, layout de código, comandos, estilo real e ferramentas/locais de teste serão escolhidos antes da implementação?
