# Especificação: monitoramento jurídico

**Estado:** base de requisitos; mapa e seis especificações modulares aprovados funcionalmente pelo solicitante. Decisões técnicas pendentes continuam bloqueantes antes da implementação. Fonte de intenção: [declaração confirmada](intent/monitoramento-juridico.md).

## Objetivo e fronteiras

Advogados independentes e suas equipes acompanham publicações judiciais sem consultas manuais. A fonte inicial é o DJEN: cadernos como fonte principal e consulta paginada de comunicações como fallback. O [contrato OpenAPI oficial](https://comunicaapi.pje.jus.br/swagger/djen.yml) foi acessado pela máquina local; cobertura, identidade e comportamento efetivo ainda precisam de validação.

Fora da primeira entrega: envio de e-mails e implementação de fontes adicionais. O sistema deve permitir fontes adicionais sem prometer cobertura não verificada. Nome comercial do escritório é informação opcional, não tenant.

## Mapa de capacidades aprovado

O [mapa aprovado](../CAPABILITIES.md) é o índice canônico dos módulos, dependências e especificações aprovadas como base funcional. Esta especificação geral preserva requisitos e evidências; aprovação funcional não resolve as decisões técnicas pendentes nem aprova o plano de implementação.

Coleta compreende microaplicações de ETL e uma aplicação de planejamento/control plane, separadas da aplicação central. As fronteiras lógicas não exigem um processo independente para cada módulo.

## Requisitos e critérios de aceitação

### Identidade e autorização

1. Após o primeiro login, o advogado informa nome completo e OAB principal e, se existirem, OABs secundárias. Seu tenant pertence ao advogado, não ao escritório.
2. O advogado administra usuários, credenciais e grupos do próprio tenant; permissões operacionais de equipe são concedidas somente por grupos. Sem grupos, a identidade lê as configurações de monitoramento do tenant, comunicações de todos os tribunais e dashboard por padrão, sem conceder escrita de equipe implicitamente; a administração do titular é uma fronteira própria.
3. `Consulta TJSP` concede apenas consulta de comunicações no TJSP; dashboard e leitura de configurações de monitoramento são operações separadas. Dashboard não amplia o escopo de tribunais; quando negada, todos os números protegidos aparecem como `*` sem valor numérico nas respostas.
4. A validade opcional aplica-se apenas às credenciais de equipe criadas pelo advogado. A escolha explícita é sem expiração ou número inteiro positivo de dias, contado em períodos de 24 horas desde a criação no instante UTC; no instante do vencimento, sessões ativas já não permitem operação protegida. Alteração só tem efeito em renovação; credencial revogada não pode ser reativada.
5. Dados e operações de um tenant não podem ser acessados por outro tenant. Restrições devem ser verificadas no servidor, não apenas ocultas na interface.

### Monitoramentos

1. O advogado é monitorado por nome e OABs; o usuário autorizado cadastra partes por nome e processos por número.
2. Partes e processos podem ter filtros dos tribunais disponibilizados pela fonte, sujeitos à capacidade real da API. Cada monitoramento pertence ao tenant.
3. A interface oferece páginas de cadastro e leitura, além de navegação para dashboard e resultados.

### Coleta e Escriba

1. Duas execuções por dia, em horários configuráveis sem valores padrão; o planejador produz linhas rastreáveis para cada entidade elegível e sua associação ao advogado, fonte e tribunal aplicável. Agenda e data corrente usam `America/Sao_Paulo`.
2. Para cada execução, a data de consulta é o dia corrente da execução. A coleta principal consulta o caderno por tribunal, data corrente e meio, baixa o ZIP, descompacta seus JSONs e procura correspondências por nome ou OAB do advogado, número de processo e nome de parte. ZIP inválido ou divergente é falha; esgotadas as tentativas do caderno, o fallback consulta comunicações paginadas, com início e fim iguais à data corrente. São inicialmente três tentativas por caminho, com esperas de um e cinco minutos, configuráveis.
3. Publicações com `id` e `hash` válidos são deduplicadas conjuntamente por fonte e tenant, preservando os vínculos de todos os monitoramentos. Cadernos e consulta de comunicações são dois acessos à mesma fonte lógica DJEN. Publicação sem chave completa válida é guardada separadamente e exibida ao tenant autorizado com aviso de pendência e possível duplicidade; não há resolução nesta entrega. A unicidade global dos identificadores não foi comprovada.
4. O Escriba registra início, término e referências necessárias do fluxo; seus registros não são alterados nem excluídos por operações normais. O solicitante dispensou retenção automática nesta etapa. Não registra ações de usuários nem detalhes de erros; falhas técnicas são tratadas separadamente.
5. Se as tentativas se esgotarem, a dashboard informa qual tribunal falhou. Uma execução posterior no mesmo dia pode recuperar publicações; não há recuperação automática de datas anteriores. Falha não pode ser apresentada como zero publicações.

### Consulta e desempenho

1. Cada comunicação é apresentada independentemente, agrupada por tribunal. O usuário autorizado pode abrir detalhes com tribunal, número do processo e conteúdo fornecido pela fonte.
2. A dashboard mostra comunicações novas persistidas e processos distintos associados a elas, respeitando tenant e tribunais autorizados, para hoje, semana civil e últimos sete dias de calendário em `America/Sao_Paulo`.
3. Considerar 300 usuários simultâneos como referência de planejamento; testes de capacidade serão definidos futuramente e não bloqueiam a entrega atual.

## Segurança e riscos

A restrição a tribunais e dashboard aplica-se a respostas e agregações; dashboard não amplia tribunais legíveis, e a negação mascara números sem expor valores subjacentes. O padrão de leitura ampla para usuários sem grupo é decisão expressa do solicitante, com risco de exposição por configuração acidental. O Escriba mantém referências internas mínimas e não registra ações de usuários, identificadores diretos ou erros técnicos. Dados públicos podem conter dados pessoais e continuam sujeitos aos controles de acesso e obrigações legais aplicáveis.

### Documentação da API

A API usará Swagger UI para expor sua documentação interativa, protegida por login e senha, conforme requisito do solicitante. O mecanismo de autenticação dessa documentação deve ser definido no contrato técnico; não está decidido se compartilha identidade com o login Google da aplicação. Usuários e senhas padrão não devem ser embutidos no código nem versionados. A aplicação e a documentação ainda não estão implementadas.

## Decisões pendentes e evidências

- Identidade: login Google; validade apenas para equipe, explicitamente sem expiração ou por número inteiro positivo de dias desde a criação em UTC; contagem por 24 horas, recusa no instante de vencimento, renovação, alteração e revogação estão decididas. Permanecem detalhes técnicos de convite, sessões e implementação.
- Autorização: composição por união de concessões e negação explícita prevalecente; catálogo de leitura/escrita e escopos definidos; usuário sem grupos tem leitura de monitoramentos/comunicações e dashboard, sem escrita por grupo. A administração do tenant é exclusiva do advogado titular.
- Consulta: métricas são comunicações novas persistidas e processos distintos associados; primeira persistência local define o período; combinação válida `id` + `hash` impede recontagem e chaves incompletas ficam fora das métricas. Janelas em `America/Sao_Paulo`, máscara `*` e estados zero/falha/parcial/indisponível estão definidos nas especificações.
- Coleta: duas execuções com horários configuráveis sem padrão, fuso Brasília, retomada do dia corrente e três tentativas por caminho com intervalos iniciais de um e cinco minutos. Resultados parciais identificam tribunais concluídos e falhos.
- Acesso à documentação interativa da API: Swagger UI protegida por login e senha; mecanismo de autenticação, configuração de credenciais, nomes/defaults/obrigatoriedade das variáveis correspondentes e relação com a identidade da aplicação ainda precisam ser definidos antes da implementação.
- Disponibilidade por tribunal e política de acesso continuam sujeitas à fonte; o caderno retorna URL temporária de cinco minutos e é disponibilizado a partir das 03h segundo a documentação. A regra de paginação e os limites observados constam do [contrato DJEN](contrato-djen.md#evidências-de-paginação). A estabilidade dos identificadores é premissa aceita, não uma decisão pendente.
- Consulta real de metadados em 28/10/2026: TJSP, meio D, status `Processado`, 273.925 comunicações e 274 arquivos no pacote. Essa amostra evidencia o volume, mas não verifica o conteúdo do ZIP nem a capacidade do sistema.
- Inspeção real do ZIP TJAC/D de 28/10/2026: dois arquivos JSON; o primeiro contém objeto com `count` e `items` e 1.000 itens. Um item inspecionado contém `id`, `hash`, `numero_processo`, `texto`, `siglaTribunal`, `destinatarios` e `destinatarioadvogados`. Presença numa amostra não prova unicidade, estabilidade nem preenchimento desses campos em todos os registros.
- Comparação em 28/10/2026: uma comunicação TJAC/D retornada pela consulta paginada por tribunal e data tinha o mesmo `id` e `hash` no caderno. A consulta específica pelo número do mesmo processo, com datas inicial e final iguais e tribunal, retornou zero itens, inclusive ao testar número com máscara. Não comprova estabilidade ao longo do tempo nem correção do filtro por processo; o fallback definido não depende desse filtro.
- Teste adicional no mesmo dia, com números sem máscara do caderno TJAC/D: cinco consultas com `numeroProcesso`, `dataDisponibilizacaoInicio`, `dataDisponibilizacaoFim`, `pagina` e `itensPorPagina`, e cinco consultas apenas com número e as duas datas, retornaram `count: 0`. As amostras se sobrepõem; o resultado não prova que o filtro falhe para todos os processos.
- Referência observada em 28/10/2026: uma publicação TJRO/D apareceu tanto no caderno quanto na página 1 da consulta por número de processo sem máscara e datas iguais, com `id` **769263947** e `hash` **jlx8NKdwzRKJtohPTKe77wYbD1mrEX** em ambas as fontes. As páginas 2 e 3 estavam vazias. Para uma publicação de cada caderno TJRR/D e TJAP/D, as páginas 1–3 estavam vazias. Essas amostras não demonstram unicidade global.
- Correspondência por nome, homônimos e vínculos entre monitoramentos; política para alterações posteriores da fonte. A chave conjunta `id` e `hash` já está definida no requisito de deduplicação.
- Capacidade: 300 usuários simultâneos são referência; não há meta comprovada nem teste de carga exigido para esta entrega.
- Escriba: sem prazo automático de retenção nesta etapa, por decisão do solicitante. Referências internas permanecem protegidas; avaliar as obrigações legais aplicáveis antes de produção.
- Stack central definida pelo solicitante: Ruby/Rails exclusivamente API-only, Next.js e PostgreSQL com RLS, conforme [registro técnico](stack.md). Versões, infraestrutura, tecnologias de ETL, ferramentas, comandos e estrutura física continuam pendentes; não há aplicação implementada.

## Verificação e limites

Verificar isolamento entre tenants e escopos na API; expiração em sessão ativa; duas coletas com repetidos e publicações distintas; registros append-only; falha, recuperação e dashboard; inspeção visual e teste de carga com critérios acordados. Não alterar registros do Escriba, registrar segredos, presumir cobertura da fonte ou iniciar implementação com decisões bloqueantes não resolvidas.

## Fluxo Git

`dev` é a branch principal de desenvolvimento e a branch padrão remota, confirmada após sua publicação. Para cada nova feature, criar uma branch `feature/<nome>` a partir de `dev`; integrar em `dev` após revisão.
