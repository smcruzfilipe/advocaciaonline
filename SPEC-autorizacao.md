# Especificação proposta: autorização

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `autorizacao`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [identidade](SPEC-identidade.md).

## Objetivo

Permitir que o advogado administre usuários e grupos de seu tenant e que a aplicação decida, no servidor, se uma identidade autenticada pode executar uma operação ou consultar determinado tribunal/dashboard. Restrições precisam proteger dados e respostas, não apenas ocultar controles da interface.

## Escopo e dono dos contratos

Este módulo é dono da gestão lógica de usuários/grupos e da decisão de autorização por operação, tribunal e dashboard. Recebe de [identidade](SPEC-identidade.md) usuário, tenant e estado de validade; não autentica usuários, não cria credenciais nem decide expiração. [Monitoramentos](SPEC-monitoramentos.md) e consulta de comunicações dependem das decisões de acesso para as ações e dados correspondentes. A consulta é dona da apresentação da dashboard, inclusive da representação `*` para números não autorizados; autorização define que esses números não podem ser revelados.

A administração por usuário advogado e os grupos são requisitos. Login é Google para advogado e equipe; primeiro acesso de equipe ocorre por convite ao e-mail informado, sem senha local, conforme [identidade](SPEC-identidade.md). Grupos somam concessões com prevalência de negação explícita. Formato das permissões, detalhes técnicos de convite, ciclo de vida completo, operações de grupos e transportes ainda precisam ser definidos.

## Contratos lógicos

- **Entrada da decisão:** contexto autenticado de identidade (usuário e tenant) e a operação solicitada; quando aplicável, tribunal ou escopo de dashboard. O tenant vem do contexto server-side, nunca de um parâmetro do cliente usado como prova de acesso.
- **Resultado da decisão:** permissão ou negação para a operação e o escopo avaliados. A decisão deve ser aplicada a dados, respostas de API e agregações correspondentes. Formato, códigos e transporte não estão definidos.
- **Sem grupos:** um usuário sem grupo tem leitura de todos os tribunais e acesso à dashboard por padrão. Essa leitura ampla não implica autorização de escrita.
- **Grupo `Consulta TJSP`:** é um grupo de somente leitura associado ao tribunal TJSP. Para uma identidade cujo único grupo relevante seja esse, a leitura permitida fica restrita a TJSP; leitura de outros tribunais e operações de escrita não são permitidas por esse grupo.
- **Dashboard negada:** quando o advogado negar acesso à dashboard, os números correspondentes aparecem como `*`; o valor numérico não pode vazar por API, agregação, cache ou outra resposta ao usuário sem acesso.
- **Fronteiras:** identidade determina quem é o ator e a qual tenant pertence; autorização determina o acesso; cada módulo consumidor continua responsável por filtrar as próprias respostas segundo a decisão recebida.

Composição aprovada pelo solicitante: somar as permissões concedidas pelos grupos, com **negação explícita prevalecendo** sobre concessões para a mesma operação e escopo. Ausência de concessão não é negação explícita. Com grupos associados, a leitura ampla padrão de usuários sem grupo não é somada às permissões. Exemplo: leitura TJSP e leitura TJRJ permitem ambos; uma negação explícita de dashboard prevalece mesmo que outro grupo conceda esse acesso. Nenhuma combinação ultrapassa o tenant autenticado.
Permissões são atribuídas **somente por grupos**, conforme decisão do solicitante. Não há concessões ou negações diretamente no usuário; uma exceção individual é representada por um grupo específico, mantendo a mesma composição de regras.

## Requisitos

1. O advogado administra os usuários e grupos do próprio tenant. Uma administração ou leitura de estado de outro tenant não pode ser autorizada por identificador enviado pelo cliente.
2. Grupos definem operações autorizadas e podem restringir o acesso a tribunais. A decisão é aplicada no servidor a cada operação e ao conjunto de dados retornado.
3. A identidade sem grupos recebe leitura de todos os tribunais e acesso à dashboard por padrão.
4. A regra de leitura ampla sem grupo não concede escrita implicitamente. A lista de operações e suas regras efetivas precisa ser definida antes de habilitar escrita; não inferir um nível fixo de permissão.
5. Um grupo `Consulta TJSP` é somente leitura e restringe o escopo de leitura a TJSP quando avaliado sem conflito de outros grupos.
6. O advogado pode negar acesso à dashboard. Quando negado, os valores numéricos protegidos são apresentados como `*` pela consulta/interface e não podem ser extraídos pelas respostas do servidor.
7. A autorização de tribunal e dashboard é aplicada também a consultas de comunicações, detalhes e volumetrias; esconder links ou controles na interface não satisfaz o requisito.
8. A avaliação usa a identidade e o tenant autenticados fornecidos por identidade; identidade/credencial expirada não constitui contexto válido para permitir operação.

## Critérios observáveis

- O advogado consegue administrar usuários e grupos dentro do tenant próprio, sem obter acesso administrativo a outro tenant. As operações exatas do ciclo de vida ainda são pendência.
- Sem grupos, a identidade consegue ler dados dos tribunais permitidos pela regra ampla e acessar a dashboard; isso, por si só, não autoriza nenhuma operação de escrita.
- Para um usuário no grupo `Consulta TJSP` sem outros grupos relevantes, leitura TJSP é permitida; leitura de outro tribunal e escrita não são permitidas por esse grupo.
- Para uma identidade sem acesso à dashboard, os números são mostrados como `*`, e inspeção das respostas de servidor não revela os números numéricos protegidos.
- Uma tentativa de consultar recurso de outro tenant não tem sucesso, mesmo que o cliente conheça ou envie um identificador válido desse recurso.
- Uma restrição por tribunal continua efetiva ao abrir detalhe, consultar API e receber agregações, e não apenas na listagem inicial.
- Grupos de leitura TJSP e TJRJ juntos permitem ambos; adicionar negação explícita de leitura TJRJ mantém apenas TJSP. Não confundir ausência de concessão de um grupo com negação explícita.
- Se um grupo concede dashboard e outro a nega explicitamente, os números permanecem protegidos e aparecem como `*`.

## Ambiente de implementação e teste: pendências bloqueantes

Não há aplicação, stack, convenção de comandos, estrutura de código, framework de teste ou exemplo real de estilo estabelecidos no repositório. Não inventar comandos de build, teste ou lint, diretórios, sintaxe de implementação, dependências ou snippet de estilo. Esses itens precisam ser escolhidos antes da implementação.

- **Comandos:** build, execução de testes, lint e desenvolvimento local — não definidos; nenhum comando é proposto.
- **Estrutura:** diretórios de aplicação, testes e configuração — não definidos.
- **Estilo:** não há código real que sirva de referência. Convenções e snippet só podem ser definidos após a escolha da stack e do repositório de implementação.
- **Estratégia de teste:** framework, localização e comandos são pendências. Cobrir isolamento por tenant, decisão por tribunal/operação, padrão sem grupo, `Consulta TJSP`, união de concessões e precedência de negação explícita, inclusive dashboard com `*` sem exposição por respostas ou agregações.
- **Limite de desempenho compartilhado:** a aplicação central deve suportar ao menos 300 usuários simultâneos; perfil, latências-alvo, ambiente e taxa de erro continuam pendentes na [especificação geral](docs/especificacao.md).

## Fronteiras

- **Sempre:** aplicar autorização no servidor e ao conjunto de dados; manter a leitura ampla sem grupo sem convertê-la em escrita implícita; garantir o escopo TJSP do grupo `Consulta TJSP`; não revelar números de dashboard negada; usar tenant autenticado de identidade.
- **Pedir aprovação:** alterar união de concessões com prevalência de negação explícita; definir operações e concessões de escrita, escopo das métricas/dashboard, ciclo de vida de usuários/grupos e apresentação/contrato técnico das decisões.
- **Nunca:** inventar níveis fixos, roles ou permissões; confiar em IDs/tenant enviados pelo cliente para conceder acesso; tratar controles ocultos como autorização; vazar números de dashboard negada; ampliar o grupo `Consulta TJSP` para outros tribunais ou escrita.

## Questões abertas

1. Regras diretamente em usuários foram excluídas por decisão do solicitante: atribuir permissões somente por grupos, inclusive para exceções individuais.
2. Quais operações existem e quais concessões de leitura/escrita cada uma exige? Qual regra se aplica à escrita até essa matriz ser definida?
3. Escopo parcial definido pelo solicitante: dashboard, métricas e avisos respeitam os tribunais autorizados; acesso à dashboard não concede acesso a agregados de outros tribunais. Quais métricas e janelas serão usadas ainda precisa ser definido.
4. Quais ações de ciclo de vida ainda não definidas o advogado poderá executar para usuários e grupos? O acesso de equipe já é por convite ao e-mail com aceitação pelo Google, sem senha local; validade, revogação e renovação seguem o contrato de identidade.
5. O acesso `*` cobre todos os números da dashboard ou somente indicadores definidos? Como distinguir valores indisponíveis por autorização de zero/falha sem vazar dados?
6. Qual representação distinguirá concessão, negação explícita e ausência de regra, preservando a leitura ampla somente para usuários sem grupo?
7. Quais stack, layout de código, comandos, estilo real e ferramentas/locais de teste serão escolhidos antes da implementação?
