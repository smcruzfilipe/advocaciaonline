# Especificação proposta: consulta (`consulta`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `consulta`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md).

## Objetivo

Permitir que usuários autorizados consultem comunicações coletadas para seu tenant, de forma independente e agrupada por tribunal, abram seus detalhes com o conteúdo fornecido pela fonte e acompanhem volumetrias e falhas persistentes na dashboard.

## Escopo e contratos lógicos

- **Dependências do mapa:** `autorizacao` (`SPEC-autorizacao.md`) determina operação, tribunais e acesso à dashboard; `coleta` (`SPEC-coleta.md`) fornece comunicações, vínculos e estado por execução/tribunal.
- O contexto autenticado determina usuário e tenant no servidor, respeita expiração de credenciais e não aceita tenant enviado pelo cliente como prova de acesso.
- O acesso à lista, ao detalhe e às agregações precisa respeitar escopo autorizado por tribunal e tenant em cada resposta; ocultar informação apenas na interface não satisfaz o contrato.
- Usuário sem grupos tem leitura ampla de todos os tribunais e acesso à dashboard por padrão. Se o acesso à dashboard for negado, os valores numéricos são apresentados como `*`.
- Cada comunicação permanece resultado independente; agrupamento visual/organizacional é por tribunal, não uma fusão de comunicações por processo. O detalhe contém pelo menos tribunal, número do processo e conteúdo fornecido pela fonte.
- A dashboard apresenta volumetrias acordadas e aviso do tribunal cuja coleta falhou persistentemente. Falha não deve ser exibida como zero publicações.
- O sistema central deve suportar pelo menos 300 usuários simultâneos. Este requisito é compartilhado e não possui ainda metas de latência, perfil de carga, ambiente ou taxa de erro para comprovação.
- Relatórios e avisos por e-mail estão fora da primeira entrega; não são parte do módulo de consulta.

## Requisitos e critérios observáveis

1. Um usuário pode consultar comunicações do tenant autenticado somente nos tribunais permitidos pelo contrato de autorização.
2. Usuário sem grupos consegue ler resultados de todos os tribunais e abrir a dashboard por padrão; demais permissões são determinadas pelo módulo `autorizacao`, não presumidas por esta especificação.
3. As comunicações são exibidas individualmente e agrupadas por tribunal. Abrir uma comunicação apresenta tribunal, número de processo e conteúdo que a fonte forneceu.
4. Ao receber acesso negado à dashboard, a interface apresenta `*` nos números; não revela valores negados por meio de agregação, resposta de dados ou rota alternativa.
5. Quando uma coleta falha persistentemente, a dashboard identifica o tribunal falho. O evento não é contado nem rotulado como zero publicações.
6. As volumetrias refletem a definição de período e unidade que vier a ser aprovada; até então não se fixam resultados numéricos nem semântica de contagem.
7. O requisito de 300 usuários simultâneos só pode ser aceito como comprovado depois de definidos critérios de desempenho mensuráveis e exercitado um perfil de carga representativo.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** não há comandos definidos no repositório; são bloqueantes para implementação. Não escolher stack ou fabricar comandos.
- **Estrutura física:** não definida. `consulta` é um limite lógico no mapa; não implica rotas, telas, serviços, pastas ou tecnologia específicas.
- **Estilo de código:** não existe snippet real do produto; linguagem, convenções, formatação e exemplo ficam pendentes até haver stack e código observável.

## Estratégia de testes comportamentais proposta

Cenários abaixo expressam contratos observáveis, sem assumir framework, comandos, pastas ou cobertura. Essas escolhas precisam ser feitas antes da implementação.

- Usuários de tenants diferentes não acessam lista, detalhe ou agregações uns dos outros, mesmo ao tentar identificar registros por parâmetro enviado pelo cliente.
- Usuário sem grupos lê comunicações de todos os tribunais e acessa dashboard; usuário com escopo restrito não recebe resultados, detalhes ou agregações fora de seu tribunal autorizado.
- Quando a autorização nega dashboard, todos os números protegidos aparecem como `*` e não podem ser recuperados por outra resposta de consulta.
- Cada comunicação aparece independentemente, dentro do agrupamento de seu tribunal; detalhe exibe tribunal, número de processo e conteúdo de origem.
- Uma falha persistente por tribunal gera aviso identificável e não se confunde com volumetria zero; estado de sucesso sem publicações permanece distinguível segundo os contratos da coleta.
- Definidos os critérios de desempenho pendentes, executar teste representativo com pelo menos 300 usuários simultâneos e avaliar latência, erro e estabilidade segundo os limites aprovados; não há limiar numérico atualmente acordado.

## Fronteiras

- **Sempre:** filtrar no servidor por tenant autenticado e escopo de autorização; aplicar restrições a listas, detalhes e agregações; manter comunicações independentes e agrupamento por tribunal; mostrar `*` quando dashboard for negada; distinguir falha de zero publicações.
- **Pedir aprovação:** definir ou alterar escopo de métricas, composição de grupos, períodos/unidade das volumetrias, conteúdo do detalhe, comportamento de mensagens e metas de desempenho; introduzir relatórios, exportação, notificações ou novos tipos de dado.
- **Nunca:** confiar tenant enviado pelo cliente; expor em resultado, detalhe ou agregado informação de tenant/tribunal não autorizado; fundir comunicações distintas por processo; substituir falha por zero; mostrar valores de dashboard negada em uma rota alternativa; incluir e-mail ou outra fonte fora da primeira entrega.

## Questões abertas e bloqueios

- Como se compõem permissões de vários grupos, restrições por operação e tribunal? Como a permissão de dashboard interage com um escopo parcial de tribunais?
- Quais métricas são necessárias e qual a unidade de contagem: comunicação, processo, execução ou outra? Como tratar publicações repetidas?
- Quais são as janelas de “dia”, “semana” e “últimos sete dias”, seu fuso e limites inclusivos? Essas definições não devem ser presumidas equivalentes.
- Qual conteúdo da fonte é exibido integralmente e como o módulo lida com campos ausentes? O detalhe não deve prometer campos não fornecidos pela fonte.
- Como a consulta distingue coleta parcial, falha persistente e coleta bem-sucedida sem resultados?
- Para validar 300 usuários simultâneos: quais latências, taxa de erro, perfil de uso, duração e ambiente são aceitáveis?
- Stack, estrutura física, comandos, estilo real, framework/localização/cobertura de testes e ferramenta de teste de carga precisam ser decididos antes da implementação.

## Critérios de sucesso

Usuários consultam apenas dados permitidos para o tenant e tribunais; comunicações independentes e detalhes de origem são apresentados agrupados por tribunal; dashboard obedece à permissão `*`, mostra volumetrias segundo definições acordadas e identifica falhas sem convertê-las em zero. O requisito de 300 simultâneos só será verificável após aprovação dos limites de desempenho. Nenhuma notificação por e-mail é incluída.
