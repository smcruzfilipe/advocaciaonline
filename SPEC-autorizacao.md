# Especificação proposta: autorização

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas ainda pendentes continuam bloqueantes antes da implementação. **ID:** `autorizacao`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [identidade](SPEC-identidade.md), [stack](docs/stack.md).

## Objetivo

Permitir que o advogado administre usuários e grupos de seu tenant e que a aplicação decida, no servidor, se uma identidade autenticada pode executar uma operação ou consultar determinado tribunal/dashboard. Restrições precisam proteger dados e respostas, não apenas ocultar controles da interface.

## Escopo e dono dos contratos

Este módulo é dono da gestão lógica de usuários/grupos e da decisão de autorização por operação, tribunal e dashboard. Recebe de [identidade](SPEC-identidade.md) usuário, tenant e estado de validade; não autentica usuários, não cria credenciais nem decide expiração. [Monitoramentos](SPEC-monitoramentos.md) e consulta de comunicações dependem das decisões de acesso para as ações e dados correspondentes. A consulta é dona da apresentação da dashboard, inclusive da representação `*` para números não autorizados; autorização define que esses números não podem ser revelados.

A composição funcional e o catálogo lógico das decisões estão fixados abaixo. Permanecem por definir a representação técnica das regras, os transportes e o ciclo técnico de convites; essas decisões não alteram a política aprovada.

## Contratos lógicos

- **Entrada da decisão:** identidade autenticada, tenant derivado no servidor, operação e, quando aplicável, tribunal. Tenant enviado pelo cliente nunca é prova de associação nem de autorização.
- **Resultado:** permitir ou negar a operação e o escopo avaliados. A decisão é aplicada no servidor a listas, detalhes, agregações, respostas e dados subjacentes; formato/código de resposta continuam técnicos.
- **Sem grupos:** por decisão funcional, a identidade lê os monitoramentos do próprio tenant, comunicações de todos os tribunais desse tenant e acessa a dashboard. Isso não concede operações de escrita por grupo; a administração do titular é a fronteira fixa descrita no catálogo.
- **Com grupos:** não se soma o padrão amplo sem grupos. Concessões se somam para a mesma identidade, tenant e escopo; negação explícita prevalece sobre concessão da mesma operação e escopo. Ausência de regra não é negação explícita, mas, havendo ao menos um grupo, a operação sem concessão aplicável é negada.
- **Escopo:** consulta de monitoramentos é no tenant; leitura de comunicações e agregações é avaliada por tribunal, com as mesmas restrições para lista, detalhe, volumetria e aviso. A permissão de dashboard é distinta da leitura de comunicações e não amplia o conjunto de tribunais autorizados.
- **Permissões por grupos:** permissões operacionais de usuários de equipe não são concedidas ou negadas diretamente à pessoa; exceção individual, se necessária, é representada por grupo específico. Administração do tenant pelo advogado titular é a fronteira fixa de propriedade já prevista, não uma concessão delegável nem uma role de grupo.

Catálogo lógico fechado para as ações já previstas; não define nomes de endpoints nem formato de armazenamento:

| Operação lógica | Ações incluídas | Escopo e decisão |
|---|---|---|
| `consultar_monitoramentos` | Listar e abrir configurações de monitoramentos de partes e processos | Concessão no tenant; sem grupos, leitura do próprio tenant é permitida. |
| `consultar_comunicacoes` | Listar e abrir detalhes de comunicações | Concessão por tribunal; todos os resultados e detalhes respeitam o mesmo tenant e tribunal. |
| `consultar_dashboard` | Consultar números e avisos da dashboard | Concessão de dashboard no tenant; conteúdo limitado aos tribunais em que `consultar_comunicacoes` é permitido. |
| `cadastrar_monitoramento` | Cadastrar monitoramento de parte ou processo | Exige concessão específica do grupo; escopo do tenant autenticado. |
| `editar_monitoramento` | Editar monitoramento de parte ou processo | Exige concessão específica do grupo; escopo do tenant autenticado. |
| `desativar_monitoramento` | Desativar monitoramento de parte ou processo | Exige concessão específica do grupo; escopo do tenant autenticado. |
| Administração do tenant pelo advogado titular | Convidar usuário; revogar ou renovar credencial; consultar e administrar grupos, suas regras e associações | Exclusiva ao advogado titular do tenant, conforme a fronteira funcional existente; não é delegável por concessão de grupo nem por identificador enviado pelo cliente. Não inclui exclusão da conta de usuário ou concessão direta individual. |

Para ações de escrita de equipe sujeitas a grupos, cada operação requer concessão própria; conceder cadastro não concede edição ou desativação. Operações não listadas não são autorizadas por inferência. As ações de administração do tenant pelo advogado titular são exclusivas e não delegáveis. Administração de grupos inclui criar, alterar e remover grupos e suas concessões/associações, sempre no tenant do titular. Se a remoção da última associação deixar uma identidade sem grupos, aplica-se o padrão aprovado de leitura ampla; para encerrar seu acesso, o advogado revoga a credencial antes de remover a associação.

O advogado titular pode cadastrar, editar e desativar os monitoramentos do próprio tenant por propriedade, independentemente de grupos; negações de grupo não restringem esse poder do titular. Essa exceção não se estende à equipe. Somente o titular consulta marcos do Escriba do próprio tenant; nenhum grupo concede essa consulta à equipe.

## Requisitos

1. O advogado administra os usuários e grupos do próprio tenant. Uma administração ou leitura de estado de outro tenant não pode ser autorizada por identificador enviado pelo cliente.
2. Grupos definem operações autorizadas e podem restringir o acesso a tribunais. A decisão é aplicada no servidor a cada operação e ao conjunto de dados retornado.
3. A identidade sem grupos recebe leitura das configurações de monitoramentos do próprio tenant, leitura de comunicações de todos os tribunais do tenant e acesso à dashboard por padrão.
4. Para usuário de equipe com grupos, uma operação não concedida por grupo é negada. A leitura ampla sem grupos não concede escrita; cada operação de escrita de equipe exige concessão específica em grupo. As ações administrativas exclusivas do advogado titular permanecem conforme o catálogo lógico.
5. `Consulta TJSP` concede somente consulta de comunicações no TJSP. Acesso à dashboard é operação separada e, quando concedido, permanece limitado aos tribunais permitidos para consulta.
6. O advogado pode negar acesso à dashboard. Quando negado, os valores numéricos protegidos são apresentados como `*` pela consulta/interface e não podem ser extraídos pelas respostas do servidor.
7. A autorização de tribunal e dashboard é aplicada também a consultas de comunicações, detalhes e volumetrias; esconder links ou controles na interface não satisfaz o requisito.
8. A avaliação usa a identidade e o tenant autenticados fornecidos por identidade; identidade/credencial expirada não constitui contexto válido para permitir operação.

Critérios observáveis:

- Para usuário de equipe sem grupos, a leitura das configurações do tenant, das comunicações de todos os tribunais e da dashboard é permitida; operações de escrita atribuíveis a grupos são negadas. A administração exclusiva do advogado titular não é delegada nem inferida do estado de grupos.
- `Consulta TJSP` concede somente leitura de comunicações do TJSP; não concede leitura de outro tribunal, configurações de monitoramento, dashboard nem escrita por si só. O dashboard requer concessão própria e, quando permitido, só mostra indicadores dos tribunais de leitura autorizada.
- Grupos com concessões de leitura TJSP e TJRJ permitem ambos; adicionar negação explícita de leitura TJRJ bloqueia TJRJ, mas não TJSP.
- Concessão de `cadastrar_monitoramento` não autoriza `editar_monitoramento` ou `desativar_monitoramento`; uma negação explícita da mesma operação e escopo bloqueia a operação mesmo havendo outra concessão.
- Lista, detalhe, números e avisos de dashboard nunca incluem tribunais fora do escopo permitido. Negar dashboard mascara todos os números protegidos como `*`, sem incluir os valores subjacentes em respostas, agregações, cache ou rota alternativa.
- Uma identidade autenticada de equipe não administra usuários ou grupos; só o advogado titular opera as ações administrativas enumeradas para o próprio tenant.
- Remover a última associação a grupo não equivale a revogar: a identidade passa ao padrão sem grupos e recebe leitura ampla. A revogação da credencial é necessária para interromper acesso.

Matriz de revisão da política 2b (para usuário de equipe autenticado no tenant correto):

| Grupos e regras | Monitoramentos | Leitura TJSP | Leitura TJRJ | Dashboard | Cadastrar monitoramento | Editar/desativar monitoramento |
|---|---|---|---|---|---|---|
| Sem grupo | Permitida | Permitida | Permitida | Permitida por padrão | Negada | Negada |
| Apenas `Consulta TJSP` | Negada sem concessão | Permitida | Negada | Negada sem concessão separada | Negada | Negada |
| Grupo concede leitura TJSP e TJRJ, dashboard negada | Negada sem concessão | Permitida | Permitida | Negada; números `*` | Negada sem concessão | Negada sem concessão |
| Concessões TJSP e TJRJ, mais negação explícita de leitura TJRJ | Conforme concessão própria | Permitida | Negada | Conforme concessão própria, limitada a TJSP | Negada sem concessão | Negada sem concessão |
| Grupo concede `cadastrar_monitoramento` | Negada sem concessão | Sem leitura sem concessão | Sem leitura sem concessão | Negada sem concessão | Permitida | Negada |
| Concessão e negação explícita da mesma escrita e escopo | Conforme concessão própria | Conforme regras de leitura | Conforme regras de leitura | Conforme regra própria | Negada se houver conflito de cadastro | Negada se houver conflito de edição/desativação |

Uma negação explícita aplica-se somente à mesma operação e ao mesmo escopo; para operação de leitura, o escopo é o tribunal; para dashboard, é o tenant. Nenhuma concessão ultrapassa o tenant autenticado. Expiração ou revogação da identidade bloqueia toda operação protegida. A matriz é revisão de contrato, não teste executado.

## Ambiente de implementação e teste: pendências bloqueantes

Stack base definida: API central em Ruby on Rails exclusivamente no modo API (`--api`), frontend Next.js e PostgreSQL com Row-Level Security (RLS), conforme [stack](docs/stack.md). Versões, ferramentas e dependências, comandos e caminhos físicos da aplicação continuam pendentes; não inventar comandos de build, teste ou lint, diretórios, sintaxe de implementação, dependências ou snippet de estilo. Ainda não há aplicação nem código real que sirva de referência para estilo.

As políticas de RLS não substituem RBAC nem as decisões de autorização por operação e grupo desta especificação; o tenant efetivo deve ser derivado no servidor do contexto autenticado, nunca de dado enviado pelo cliente. Ver também [stack](docs/stack.md).

- **Comandos:** build, execução de testes, lint e desenvolvimento local — não definidos; nenhum comando é proposto.
- **Estrutura:** diretórios de aplicação, testes e configuração — não definidos.
- **Estilo:** não há código real que sirva de referência. Convenções e snippet dependem do repositório de implementação e de seu estilo, ainda não estabelecidos.
- **Estratégia de teste:** framework, localização e comandos são pendências. Cobrir isolamento por tenant; leitura das configurações de monitoramento; decisões por tribunal e operação; padrão sem grupo; `Consulta TJSP`; união de concessões e precedência de negação explícita; dashboard com `*` sem exposição dos números; ações administrativas somente pelo titular; e o efeito de remover a última associação (retorno ao padrão sem grupos, não revogação).
- **Desempenho:** 300 usuários simultâneos são referência de planejamento; medição futura não bloqueia esta entrega.

## Fronteiras

- **Sempre:** aplicar autorização no servidor e ao conjunto de dados; manter a leitura ampla sem grupo sem convertê-la em escrita implícita; garantir o escopo TJSP do grupo `Consulta TJSP`; não revelar números de dashboard negada; usar tenant autenticado de identidade.
- **Pedir aprovação:** alterar a composição de concessões/negações, os escopos e catálogo lógico já definidos, ou a fronteira de administração exclusiva do advogado titular; definir representação e transporte técnicos das decisões.
- **Nunca:** inventar níveis fixos, roles ou permissões; confiar em IDs/tenant enviados pelo cliente para conceder acesso; tratar controles ocultos como autorização; vazar números de dashboard negada; ampliar o grupo `Consulta TJSP` para outros tribunais ou escrita.

## Questões abertas

1. Decisão resolvida: usuários de equipe não recebem permissões diretamente; exceção individual requer grupo específico. As ações administrativas do tenant permanecem exclusivas ao advogado titular, conforme o contrato existente, e não são delegadas por grupos.
2. Operações de leitura/escrita e seus escopos estão enumerados em [Contratos lógicos](#contratos-lógicos). Operações não listadas não são autorizadas por inferência.
3. Decisão resolvida em conjunto com [consulta](SPEC-consulta.md): dashboard e avisos respeitam os tribunais autorizados; permissão de dashboard não amplia a leitura; métricas e períodos têm definição própria no contrato de consulta.
4. Ciclo lógico resolvido: o advogado pode convidar usuários, revogar/renovar credenciais e administrar grupos, suas regras e associações no próprio tenant. A exclusão de conta não faz parte do ciclo definido.
5. Decisão resolvida em [consulta](SPEC-consulta.md): todo número protegido pela negação de dashboard é `*`, sem valor numérico na resposta; zero, falha parcial e indisponibilidade são estados distintos.
6. Representação técnica de concessão, negação explícita e ausência de regra permanece para o contrato de implementação; sua semântica funcional está definida nesta especificação.
7. Caminhos físicos/layout, comandos, estilo real, ferramentas e locais de teste do repositório de implementação permanecem pendentes; ver a stack base em [stack](docs/stack.md).
