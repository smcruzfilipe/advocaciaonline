# Especificação proposta: consulta (`consulta`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `consulta`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Permitir que usuários autorizados consultem comunicações coletadas para seu tenant, de forma independente e agrupada por tribunal, abram seus detalhes com o conteúdo fornecido pela fonte e acompanhem volumetrias e falhas persistentes na dashboard.

## Escopo e contratos lógicos

- **Dependências do mapa:** `autorizacao` (`SPEC-autorizacao.md`) determina operação, tribunais e acesso à dashboard; `coleta` (`SPEC-coleta.md`) fornece comunicações, vínculos e estado por execução/tribunal.
- O contexto autenticado determina usuário e tenant no servidor, respeita expiração de credenciais e não aceita tenant enviado pelo cliente como prova de acesso. RLS é uma camada adicional e não substitui autorização/RBAC nem a derivação server-side do tenant.
- O acesso à lista, ao detalhe e às agregações precisa respeitar escopo autorizado por tribunal e tenant em cada resposta; ocultar informação apenas na interface não satisfaz o contrato.
- Usuário sem grupos tem leitura de todos os tribunais e dashboard por padrão; com grupos, as permissões seguem [autorização](SPEC-autorizacao.md). Dashboard é operação separada: permiti-la não concede leitura de comunicações nem amplia os tribunais que a identidade pode ler. Se dashboard for negada, todos os números protegidos são `*`.
- Cada comunicação permanece resultado independente; agrupamento visual/organizacional é por tribunal, não uma fusão de comunicações por processo. O detalhe contém pelo menos tribunal, número do processo e conteúdo fornecido pela fonte.
- Comunicações sem `id` ou `hash` válido são exibidas na consulta autorizada do tenant como pendentes, com aviso de possível duplicidade; ficam armazenadas separadamente e não há mecanismo de resolução nesta entrega, conforme [coleta](SPEC-coleta.md).
- A dashboard apresenta duas métricas aprovadas — comunicações novas persistidas e processos distintos associados a elas — e avisos de falha persistente. Resultados parciais incluem apenas tribunais autorizados concluídos e identificam os autorizados com falha; falha não é zero.
- O número de 300 usuários simultâneos é referência de planejamento, não requisito de aceitação nem capacidade comprovada. Medição e teste serão definidos futuramente e não bloqueiam esta entrega.
- Relatórios e avisos por e-mail estão fora da primeira entrega; não são parte do módulo de consulta.

## Requisitos e critérios observáveis

1. Um usuário pode consultar comunicações do tenant autenticado somente nos tribunais permitidos pelo contrato de autorização.
2. Usuário sem grupos consegue ler resultados de todos os tribunais e abrir a dashboard por padrão; demais permissões são determinadas pelo módulo `autorizacao`, não presumidas por esta especificação.
3. As comunicações são exibidas individualmente e agrupadas por tribunal. Abrir uma comunicação apresenta tribunal, número de processo e conteúdo que a fonte forneceu.
4. Ao receber acesso negado à dashboard, a interface apresenta `*` nos números; não revela valores negados por meio de agregação, resposta de dados ou rota alternativa.
5. Quando uma coleta falha persistentemente, a dashboard identifica o tribunal falho. O evento não é contado nem rotulado como zero publicações.
6. Contar separadamente (a) comunicações novas persistidas e (b) processos distintos associados a essas comunicações. Uma comunicação conta uma única vez no tenant/fonte lógica DJEN, pela combinação conjunta válida `id` + `hash` e pelo instante da primeira persistência local; reencontro por outro monitoramento, caminho ou execução não a torna nova novamente. Comunicações sem chave completa válida permanecem pendentes e fora das duas métricas, pois não há identidade confiável para evitar dupla contagem.
7. O instante da primeira persistência é o marco temporal das métricas, não a data de publicação na fonte nem a data da coleta. Processos são distintos pela identidade canônica já definida em [coleta](SPEC-coleta.md), contados uma vez por tenant e janela entre as comunicações novas qualificadas.
8. Janelas no fuso `America/Sao_Paulo`: hoje começa às 00h locais; semana civil começa segunda-feira às 00h locais; últimos sete dias de calendário começam às 00h locais de hoje menos seis dias. Cada intervalo inclui o início e exclui o instante da consulta. O instante de persistência é um instante absoluto convertido para o fuso. Cada comunicação é contada no máximo uma vez em cada métrica; as três janelas independentes se sobrepõem intencionalmente.
9. Toda métrica e aviso é filtrado pelo tenant autenticado e pelos tribunais de leitura autorizados. Se dashboard for negada, cada número protegido é `*` e seu valor não aparece em respostas do servidor, agregações, cache ou rotas alternativas. Avisos não numéricos podem identificar apenas tribunais cuja leitura é autorizada.
10. Zero só representa consulta/coleta concluída com nenhuma comunicação nova no escopo. Falha persistente e estado ainda não concluído/indisponível são estados distintos de zero e não recebem contagem inventada.
11. Não afirmar capacidade de 300 usuários sem medição representativa; o teste é futuro e não integra o aceite desta entrega.

**Exemplo verificável — janelas (`America/Sao_Paulo`):**

Numa consulta às 10h de quarta-feira, 28/10/2026, as janelas são hoje `[28/10 00h, 28/10 10h)`, semana `[26/10 00h, 28/10 10h)` e sete dias `[22/10 00h, 28/10 10h)`. Uma primeira persistência às 00h de 28/10 entra nas três métricas; uma às 00h de 26/10 entra na semana e nos sete dias, mas não em hoje; uma às 10h de 28/10 fica fora até consulta posterior. A mesma comunicação aparece uma única vez em cada janela em que se enquadra, embora as janelas se sobreponham.

### Estratégia de capacidade

Futuramente, definir perfil, ambiente, duração e limites de latência e erro a partir de medições reais; 300 usuários simultâneos são referência, não uma meta já comprovada. Nenhum teste de carga ou medição foi executado.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** não há comandos definidos no repositório; são bloqueantes para implementação. A stack da aplicação central está definida em [docs/stack.md](docs/stack.md), mas versões, runtime, bibliotecas e comandos permanecem pendentes.
- **Estrutura física:** não definida. A stack central escolhe Rails em modo API-only, Next.js e PostgreSQL com RLS, mas não fixa rotas, telas, pastas, caminhos físicos ou organização dos componentes.
- **Estilo de código:** não existe snippet real do produto; convenções, formatação e exemplo ficam pendentes até haver código observável.

## Estratégia de testes comportamentais proposta

Cenários abaixo expressam contratos observáveis, sem assumir framework, comandos, pastas ou cobertura. A stack da aplicação central está definida, mas essas decisões de teste permanecem pendentes.

- Usuários de tenants diferentes não acessam lista, detalhe ou agregações uns dos outros, mesmo ao tentar identificar registros por parâmetro enviado pelo cliente.
- Usuário sem grupos lê comunicações de todos os tribunais e acessa dashboard; usuário com escopo restrito não recebe resultados, detalhes, métricas ou avisos fora de seu tribunal autorizado.
- Quando a autorização nega dashboard, todos os números protegidos aparecem como `*` e não podem ser recuperados por outra resposta; avisos não numéricos só podem referir-se a tribunais legíveis.
- Cada comunicação aparece independentemente, dentro do agrupamento de seu tribunal; detalhe exibe tribunal, número de processo e conteúdo de origem.
- Comunicação com chave incompleta aparece somente para tenant e tribunal autorizados, com aviso de pendência, e não compõe contagem de comunicações novas nem de processos distintos.
- Para uma comunicação válida, sua primeira persistência local a inclui uma vez nas janelas em que o instante de persistência cai; reencontros não repetem a contagem. Um mesmo processo relacionado a várias comunicações qualificadas é contado uma vez por janela.
- Sucesso sem comunicações no escopo autorizado apresenta `0`; falha persistente mostra aviso sem convertê-la em zero; resultado parcial usa somente tribunais concluídos autorizados e identifica os falhos; estado sem conclusão permanece indisponível/em andamento, não zero.
- Futuramente, medir linha de base e definir teste representativo; a referência de 300 usuários não constitui gate desta entrega.

### Matriz de resultados da dashboard

| Situação | Números e estado permitidos |
|---|---|
| Dashboard e tribunal autorizados; coleta concluída sem comunicações novas | Mostrar `0` para as contagens correspondentes. |
| Dashboard e tribunal autorizados; coleta concluída com comunicações novas | Mostrar as contagens de comunicações novas e processos distintos conforme as janelas aprovadas. |
| Tribunal autorizado com falha persistente | Avisar a falha; não mostrar a falha como zero. Em resultado parcial, contar somente os tribunais concluídos autorizados e marcar o resultado como parcial. |
| Tribunal autorizado ainda sem resultado concluído/estado disponível | Apresentar estado indisponível ou em andamento; não inferir zero nem falha persistente. |
| Dashboard negada, tribunal legível | Mostrar `*` para todos os números protegidos, sem o valor numérico em qualquer resposta; aviso não numérico pode ser mostrado no escopo legível. |
| Tribunal não autorizado | Não revelar número, estado, aviso nem agregação; não incluir seus dados em agregado. |

## Fronteiras

- **Sempre:** filtrar no servidor por tenant autenticado e escopo de autorização; aplicar restrições a listas, detalhes, métricas e avisos; contar apenas primeira persistência local de publicação deduplicável; manter comunicações independentes e agrupamento por tribunal; exibir `*` sem valor subjacente quando dashboard for negada; distinguir sucesso vazio, falha e estado indisponível.
- **Pedir aprovação:** alterar definições aprovadas de métricas, períodos, escopos, máscara `*`, apresentação do detalhe ou aviso; alterar estratégia de desempenho; introduzir relatórios, exportação, notificações ou novos tipos de dado.
- **Nunca:** confiar tenant enviado pelo cliente; expor dado/aviso agregado de tribunal não autorizado; contar reencontro como novidade; contar chave incompleta como métrica deduplicada; fundir comunicações distintas por processo; substituir falha ou ausência de estado por zero; mostrar valor protegido por rota alternativa; incluir e-mail ou outra fonte fora da primeira entrega.

## Questões abertas e bloqueios

- **Resolvido na decisão 2b/2c:** concessões de grupos se somam e negação explícita prevalece; leitura ampla e dashboard sem grupos; concessão de dashboard não amplia tribunais legíveis; escopo de métricas/avisos, `*`, unidades, períodos, timestamp de primeira persistência e distinção entre zero, falha, resultado parcial e estado indisponível estão definidos nesta especificação e em [autorização](SPEC-autorizacao.md).
- **Pendente de evidência da fonte:** quais campos do conteúdo são fornecidos em todos os casos e como apresentar cada campo ausente. O detalhe só promete o que a fonte efetivamente forneceu.
- **Pendente do contrato operacional/técnico:** códigos e armazenamento do estado por execução/tribunal e mapeamento para os estados observáveis desta especificação; não incluir detalhes técnicos de erro no Escrevente.
- **Futuro:** definir e medir desempenho sob perfil representativo; 300 usuários simultâneos são referência e não bloqueiam a entrega.
- A stack da aplicação central está definida em [docs/stack.md](docs/stack.md). Versões, runtime, bibliotecas, comandos, estilo real, caminhos físicos, framework/localização/cobertura de testes e ferramenta de teste de carga ainda precisam ser definidos.

## Critérios de sucesso

Usuários consultam apenas dados permitidos para o tenant e tribunais; comunicações independentes e detalhes são apresentados por tribunal; dashboard respeita autorização, volumetrias e estados de falha. A referência de 300 usuários não constitui critério de aceite desta entrega. Não há notificação por e-mail.
