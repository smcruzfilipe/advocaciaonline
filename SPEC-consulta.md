# Especificação proposta: consulta (`consulta`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `consulta`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Permitir que usuários autorizados consultem comunicações coletadas para seu tenant, de forma independente e agrupada por tribunal, abram seus detalhes com o conteúdo fornecido pela fonte e acompanhem volumetrias e falhas persistentes na dashboard.

## Escopo e contratos lógicos

- **Dependências do mapa:** `autorizacao` (`SPEC-autorizacao.md`) determina operação, tribunais e acesso à dashboard; `coleta` (`SPEC-coleta.md`) fornece comunicações, vínculos e estado por execução/tribunal.
- O contexto autenticado determina usuário e tenant no servidor, respeita expiração de credenciais e não aceita tenant enviado pelo cliente como prova de acesso. RLS é uma camada adicional e não substitui autorização/RBAC nem a derivação server-side do tenant.
- O acesso à lista, ao detalhe e às agregações precisa respeitar escopo autorizado por tribunal e tenant em cada resposta; ocultar informação apenas na interface não satisfaz o contrato.
- Usuário sem grupos tem leitura ampla de todos os tribunais e acesso à dashboard por padrão. Se o acesso à dashboard for negado, os valores numéricos são apresentados como `*`.
- Cada comunicação permanece resultado independente; agrupamento visual/organizacional é por tribunal, não uma fusão de comunicações por processo. O detalhe contém pelo menos tribunal, número do processo e conteúdo fornecido pela fonte.
- Comunicações sem `id` ou `hash` válido são exibidas na consulta autorizada do tenant como pendentes, com aviso de possível duplicidade; ficam armazenadas separadamente e não há mecanismo de resolução nesta entrega, conforme [coleta](SPEC-coleta.md).
- A dashboard apresenta volumetrias acordadas e aviso do tribunal cuja coleta falhou persistentemente. Falha não deve ser exibida como zero publicações.
- Quando apenas parte dos tribunais concluir, apresentar os resultados disponíveis dos tribunais concluídos e identificar os tribunais com falha, respeitando o escopo autorizado. Não representar tribunal falho como zero.
- O sistema central deve suportar pelo menos 300 usuários simultâneos. Este requisito é compartilhado e não possui ainda metas de latência, perfil de carga, ambiente ou taxa de erro para comprovação.
- Os limites de latência e erro serão definidos após medir uma linha de base real. Não declarar os 300 usuários simultâneos comprovados antes de aprovar metas e executar o teste representativo correspondente.
- Relatórios e avisos por e-mail estão fora da primeira entrega; não são parte do módulo de consulta.

## Requisitos e critérios observáveis

1. Um usuário pode consultar comunicações do tenant autenticado somente nos tribunais permitidos pelo contrato de autorização.
2. Usuário sem grupos consegue ler resultados de todos os tribunais e abrir a dashboard por padrão; demais permissões são determinadas pelo módulo `autorizacao`, não presumidas por esta especificação.
3. As comunicações são exibidas individualmente e agrupadas por tribunal. Abrir uma comunicação apresenta tribunal, número de processo e conteúdo que a fonte forneceu.
4. Ao receber acesso negado à dashboard, a interface apresenta `*` nos números; não revela valores negados por meio de agregação, resposta de dados ou rota alternativa.
5. Quando uma coleta falha persistentemente, a dashboard identifica o tribunal falho. O evento não é contado nem rotulado como zero publicações.
6. Mostrar separadamente comunicações novas persistidas e números de processo distintos aos quais essas comunicações pertencem, nos períodos selecionados. Uma comunicação já persistida não volta a contar como novidade quando reencontrada por outro monitoramento, pelo fallback ou por outra execução. As contagens respeitam tenant e tribunais autorizados.
7. O requisito de 300 usuários simultâneos só pode ser aceito como comprovado depois de definidos critérios de desempenho mensuráveis e exercitado um perfil de carga representativo.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** não há comandos definidos no repositório; são bloqueantes para implementação. A stack da aplicação central está definida em [docs/stack.md](docs/stack.md), mas versões, runtime, bibliotecas e comandos permanecem pendentes.
- **Estrutura física:** não definida. A stack central escolhe Rails em modo API-only, Next.js e PostgreSQL com RLS, mas não fixa rotas, telas, pastas, caminhos físicos ou organização dos componentes.
- **Estilo de código:** não existe snippet real do produto; convenções, formatação e exemplo ficam pendentes até haver código observável.

## Estratégia de testes comportamentais proposta

Cenários abaixo expressam contratos observáveis, sem assumir framework, comandos, pastas ou cobertura. A stack da aplicação central está definida, mas essas decisões de teste permanecem pendentes.

- Usuários de tenants diferentes não acessam lista, detalhe ou agregações uns dos outros, mesmo ao tentar identificar registros por parâmetro enviado pelo cliente.
- Usuário sem grupos lê comunicações de todos os tribunais e acessa dashboard; usuário com escopo restrito não recebe resultados, detalhes ou agregações fora de seu tribunal autorizado.
- Quando a autorização nega dashboard, todos os números protegidos aparecem como `*` e não podem ser recuperados por outra resposta de consulta.
- Cada comunicação aparece independentemente, dentro do agrupamento de seu tribunal; detalhe exibe tribunal, número de processo e conteúdo de origem.
- Uma comunicação com chave incompleta aparece apenas para o tenant e tribunal autorizados, com aviso de pendência e possível duplicidade.
- Uma falha persistente por tribunal gera aviso identificável e não se confunde com volumetria zero; estado de sucesso sem publicações permanece distinguível segundo os contratos da coleta.
- Definidos os critérios de desempenho pendentes, executar teste representativo com pelo menos 300 usuários simultâneos e avaliar latência, erro e estabilidade segundo os limites aprovados; não há limiar numérico atualmente acordado.

Revisão de estados da dashboard:

| Situação | Resultado permitido |
|---|---|
| Tribunal autorizado, coleta bem-sucedida sem comunicações novas | Mostrar zero para a contagem correspondente. |
| Tribunal autorizado, coleta com falha persistente | Identificar a falha; não apresentá-la como zero. |
| Coleta parcial entre tribunais autorizados | Mostrar resultados disponíveis dos concluídos e identificar os falhos. |
| Dashboard negada | Apresentar `*` nos números protegidos, sem disponibilizar os valores em respostas alternativas. |
| Tribunal não autorizado | Não revelar seus resultados, avisos ou agregações. |

## Fronteiras

- **Sempre:** filtrar no servidor por tenant autenticado e escopo de autorização; aplicar restrições a listas, detalhes e agregações; manter comunicações independentes e agrupamento por tribunal; mostrar `*` quando dashboard for negada; distinguir falha de zero publicações.
- **Pedir aprovação:** definir ou alterar escopo de métricas, composição de grupos, períodos/unidade das volumetrias, conteúdo do detalhe, comportamento de mensagens e metas de desempenho; introduzir relatórios, exportação, notificações ou novos tipos de dado.
- **Nunca:** confiar tenant enviado pelo cliente; expor em resultado, detalhe ou agregado informação de tenant/tribunal não autorizado; fundir comunicações distintas por processo; substituir falha por zero; mostrar valores de dashboard negada em uma rota alternativa; incluir e-mail ou outra fonte fora da primeira entrega.

## Questões abertas e bloqueios

- Decisões resolvidas: concessões de grupos se somam e negação explícita prevalece. Acesso à dashboard não amplia o escopo de tribunais: usuário restrito ao TJSP vê apenas volumetrias e avisos do TJSP, conforme escolha do solicitante. Formatos técnicos das regras permanecem no contrato de autorização.
- Métricas aprovadas: comunicações novas persistidas e processos distintos associados a elas, sem contar duplicatas como novidades. A referência temporal técnica da primeira persistência deve constar do contrato de consulta.
- Períodos aprovados no fuso `America/Sao_Paulo`: hoje desde 00h; semana civil desde segunda-feira às 00h; últimos sete dias de calendário incluindo hoje e os seis anteriores. Todos terminam no instante da consulta. A implementação deve delimitar esses intervalos sem dupla contagem nas fronteiras.
- Qual conteúdo da fonte é exibido integralmente e como o módulo lida com campos ausentes? O detalhe não deve prometer campos não fornecidos pela fonte.
- Como representar tecnicamente os estados por execução e tribunal? O resultado parcial mostra os tribunais concluídos e identifica os falhos, sem converter falha em zero.
- Para validar 300 usuários simultâneos: medir primeiro uma linha de base real e, a partir dela, aprovar latências, taxa de erro, perfil de uso, duração e ambiente; sem metas aprovadas e teste correspondente, não declarar capacidade comprovada.
- A stack da aplicação central está definida em [docs/stack.md](docs/stack.md). Versões, runtime, bibliotecas, comandos, estilo real, caminhos físicos, framework/localização/cobertura de testes e ferramenta de teste de carga ainda precisam ser definidos.

## Critérios de sucesso

Usuários consultam apenas dados permitidos para o tenant e tribunais; comunicações independentes e detalhes de origem são apresentados agrupados por tribunal; dashboard obedece à permissão `*`, mostra volumetrias segundo definições acordadas e identifica falhas sem convertê-las em zero. O requisito de 300 simultâneos só será verificável após aprovação dos limites de desempenho. Nenhuma notificação por e-mail é incluída.
