# Especificação: monitoramento jurídico

**Estado:** proposta para revisão; não iniciar implementação antes da aprovação. Fonte de intenção: [declaração confirmada](intent/monitoramento-juridico.md).

## Objetivo e fronteiras

Advogados independentes e suas equipes acompanham publicações judiciais sem consultas manuais. A fonte inicial é o DJEN: cadernos como fonte principal e consulta paginada de comunicações como fallback. O [contrato OpenAPI oficial](https://comunicaapi.pje.jus.br/swagger/djen.yml) foi acessado pela máquina local; cobertura, identidade e comportamento efetivo ainda precisam de validação.

Fora da primeira entrega: envio de e-mails e implementação de fontes adicionais. O sistema deve permitir fontes adicionais sem prometer cobertura não verificada. Nome comercial do escritório é informação opcional, não tenant.

## Mapa de capacidades proposto

| Identificador | Responsabilidade | Dependências |
|---|---|---|
| identidade | Login, tenant do advogado, onboarding e credenciais | — |
| autorizacao | Grupos, permissões e escopo de tribunais | identidade |
| monitoramentos | Advogado, partes, processos e filtros | identidade, autorizacao |
| coleta | Planejamento, execução, fontes, normalização e deduplicação | monitoramentos |
| escriba | Registros append-only do fluxo de coleta | identidade |
| consulta | Comunicações, agrupamento, detalhes e dashboard | autorizacao, coleta |

Construção orientada por dependências e fatias verticais. Os limites são propostos, não uma escolha de tecnologia ou exigência de processos independentes para cada módulo. Coleta compreende microaplicações de ETL e uma aplicação de planejamento/control plane, separadas da aplicação central.

## Requisitos e critérios de aceitação

### Identidade e autorização

1. Após o primeiro login, o advogado informa nome completo e OAB principal e, se existirem, OABs secundárias. Seu tenant pertence ao advogado, não ao escritório.
2. O advogado administra usuários e grupos. Grupos definem operações autorizadas e podem limitar o acesso a tribunais. Um usuário sem grupos possui leitura de todos os tribunais e acesso à dashboard por padrão; não se presume autorização de escrita.
3. Ao adicionar um usuário ao grupo somente leitura `Consulta TJSP`, ele deixa de acessar outros tribunais. O advogado pode negar acesso à dashboard; nesse caso os números aparecem como `*`.
4. Uma credencial pode não expirar ou ter validade expressa em número de dias; vencida, não permite acesso. A aplicação deve impor o vencimento também a sessões em uso.
5. Dados e operações de um tenant não podem ser acessados por outro tenant. Restrições devem ser verificadas no servidor, não apenas ocultas na interface.

### Monitoramentos

1. O advogado é monitorado por nome e OABs; o usuário autorizado cadastra partes por nome e processos por número.
2. Partes e processos podem ter filtros dos tribunais disponibilizados pela fonte, sujeitos à capacidade real da API. Cada monitoramento pertence ao tenant.
3. A interface oferece páginas de cadastro e leitura, além de navegação para dashboard e resultados.

### Coleta e Escriba

1. Duas execuções por dia, em horários configuráveis a definir; o planejador produz linhas rastreáveis para cada entidade elegível e sua associação ao advogado, fonte e tribunal aplicável. Horário e fuso ainda não foram decididos.
2. Para cada execução, a data de consulta é o dia corrente da execução. A coleta principal consulta o caderno por tribunal, data corrente e meio, baixa o ZIP, descompacta seus JSONs e procura correspondências por nome ou OAB do advogado, número de processo e nome de parte. Se houver problema nos cadernos, o fallback consulta comunicações paginadas, sempre passando `dataDisponibilizacaoInicio` e `dataDisponibilizacaoFim` iguais à data corrente. Trata e normaliza os dados e persiste os resultados e vínculos aos tenants corretos. Tentativas com backoff ocorrem após falhas, com limites a definir.
3. Cada publicação distinta aparece uma vez por tenant mesmo que encontrada por buscas ou execuções diferentes. Assumir os identificadores estáveis conforme decisão do solicitante. Usar conjuntamente `id` e `hash` da comunicação como referência para deduplicação, escopada por fonte e tenant, preservando os vínculos de todos os monitoramentos que a encontraram. Cadernos e consulta de comunicações são dois acessos à mesma fonte lógica DJEN e devem deduplicar entre si. Ambos os identificadores são essenciais. A unicidade global não foi comprovada pelos testes. Não deduplicar publicações distintas só por compartilharem processo ou tribunal.
4. O Escriba registra, linha por linha, início, término e dados relevantes do fluxo, incluindo fonte, execução, entidade, advogado, tribunal e processos associados quando disponíveis. Seus registros são somente leitura e inserção: sem alteração ou exclusão. Não registra ações de usuários nem detalhes de erros; falhas técnicas são tratadas separadamente.
5. Se as tentativas se esgotarem, a dashboard informa qual tribunal falhou. Uma execução posterior no mesmo dia pode recuperar publicações; não há recuperação automática de datas anteriores. Falha não pode ser apresentada como zero publicações.

### Consulta e desempenho

1. Cada comunicação é apresentada independentemente, agrupada por tribunal. O usuário autorizado pode abrir detalhes com tribunal, número do processo e conteúdo fornecido pela fonte.
2. A dashboard mostra volumetrias relevantes, incluindo coletas do dia, semana e últimos sete dias. A definição exata de cada contagem e período ainda precisa ser acordada.
3. Suportar pelo menos 300 usuários simultâneos na aplicação central. O alvo de latência, perfil de uso, ambiente e taxa de erro precisam ser definidos antes de um teste de carga que permita comprovar o requisito.

## Segurança e riscos

A restrição a tribunais e dashboard precisa aplicar-se também às respostas da API e a agregações; a interação exata entre permissões de tribunal e dashboard requer decisão. O padrão de leitura ampla para usuários sem grupo é uma decisão expressa do solicitante, com risco de exposição por configuração acidental. Não inventar proteção ou alterar esse padrão sem aprovação. O Escriba imutável e dados judiciais exigem uma política de retenção e tratamento de dados pessoais a definir.

## Decisões pendentes e evidências

- Credenciais: instante inicial da validade, fuso, renovação e revogação; comportamento de múltiplos grupos, conflitos e permissões de escrita.
- Regras de escopo da dashboard e suas agregações quando o usuário só acessa alguns tribunais.
- Comunicação versus processo: definição das volumetrias, janelas temporais e inclusão de repetidos.
- Horários, fuso, recuperação após interrupção, limites de retry/backoff e status de conclusão parcial.
- Disponibilidade por tribunal, paginação, limites e política de acesso; o caderno retorna URL temporária de cinco minutos e é disponibilizado a partir das 03h segundo a documentação. A estabilidade dos identificadores é premissa aceita, não uma decisão pendente.
- Consulta real de metadados em 28/10/2026: TJSP, meio D, status `Processado`, 273.925 comunicações e 274 arquivos no pacote. Essa amostra evidencia o volume, mas não verifica o conteúdo do ZIP nem a capacidade do sistema.
- Inspeção real do ZIP TJAC/D de 28/10/2026: dois arquivos JSON; o primeiro contém objeto com `count` e `items` e 1.000 itens. Um item inspecionado contém `id`, `hash`, `numero_processo`, `texto`, `siglaTribunal`, `destinatarios` e `destinatarioadvogados`. Presença numa amostra não prova unicidade, estabilidade nem preenchimento desses campos em todos os registros.
- Comparação em 28/10/2026: uma comunicação TJAC/D retornada pela consulta paginada por tribunal e data tinha o mesmo `id` e `hash` no caderno. A consulta específica pelo número do mesmo processo, com datas inicial e final iguais e tribunal, retornou zero itens, inclusive ao testar número com máscara. Não comprova estabilidade ao longo do tempo nem correção do filtro por processo; investigar antes de depender dele como fallback.
- Teste adicional no mesmo dia, com números sem máscara do caderno TJAC/D: cinco consultas com `numeroProcesso`, `dataDisponibilizacaoInicio`, `dataDisponibilizacaoFim`, `pagina` e `itensPorPagina`, e cinco consultas apenas com número e as duas datas, retornaram `count: 0`. As amostras se sobrepõem; o resultado não prova que o filtro falhe para todos os processos.
- Referência observada em 28/10/2026: uma publicação TJRO/D apareceu tanto no caderno quanto na página 1 da consulta por número de processo sem máscara e datas iguais, com `id` **769263947** e `hash` **jlx8NKdwzRKJtohPTKe77wYbD1mrEX** em ambas as fontes. As páginas 2 e 3 estavam vazias. Para uma publicação de cada caderno TJRR/D e TJAP/D, as páginas 1–3 estavam vazias. Essas amostras não demonstram unicidade global.
- Correspondência por nome, homônimos e vínculos entre monitoramentos; política para alterações posteriores da fonte. A chave conjunta `id` e `hash` já está definida no requisito de deduplicação.
- Critérios quantitativos de desempenho para 300 usuários e perfis de carga.
- Retenção, dados pessoais e compatibilidade do Escriba imutável com obrigações legais.
- Stack, infraestrutura, ferramentas, comandos de build/teste/lint e estrutura de código: não há aplicação existente no repositório; decidir antes da implementação, sem inventar comandos.

## Verificação e limites

Verificar isolamento entre tenants e escopos na API; expiração em sessão ativa; duas coletas com repetidos e publicações distintas; registros append-only; falha, recuperação e dashboard; inspeção visual e teste de carga com critérios acordados. Não alterar registros do Escriba, registrar segredos, presumir cobertura da fonte ou iniciar implementação com decisões bloqueantes não resolvidas.

## Fluxo Git

`dev` é a branch principal de desenvolvimento e a branch padrão remota, confirmada após sua publicação. Para cada nova feature, criar uma branch `feature/<nome>` a partir de `dev`; integrar em `dev` após revisão.
