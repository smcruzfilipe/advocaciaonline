# Especificação proposta: Escriba (`escriba`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `escriba`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Manter um registro imutável e consultável do fluxo de coleta, com os marcos de início e término e os dados relevantes disponíveis para rastrear o trabalho por tenant, execução, entidade e tribunal. O Escriba não é trilha de auditoria de ações de usuários nem repositório de erros técnicos.

## Escopo e contratos lógicos

- **Responsabilidade:** aceitar e acrescentar registros do fluxo de coleta; não os alterar nem excluir.
- **Dependência do mapa:** `identidade`. Chamadas humanas usam usuário e tenant autenticados no servidor; o worker usa identidade de serviço com privilégios mínimos e deriva o tenant de trabalho persistido, reivindicado por interface controlada, nunca de parâmetro externo isolado. A transação estabelece esse tenant antes de gravar; trabalho inexistente ou inconsistente é recusado. RLS complementa, mas não substitui autorização ou contexto confiável.
- **Consumidor lógico:** `coleta` (`SPEC-coleta.md`). A fronteira não exige serviço, processo, armazenamento ou transporte independente.
- **Dados mínimos:** cada marco usa instante de registro confiável e, quando disponíveis, execução, tenant, fonte lógica, referência interna da entidade/monitoramento, advogado, tribunal e processos associados. Não registrar nomes, números de OAB ou de processo em claro, conteúdo da comunicação, e-mail, segredo ou dado desnecessário.
- **Acréscimo e retenção:** marcos não são sobrescritos ou removidos por operações normais. Por decisão do solicitante, não há prazo automático de retenção ou expurgo nesta etapa; não presumir exclusão de registros ou cópias por tempo.
- **Cópias:** backup, restauração e acesso seguem os controles de segurança e isolamento do ambiente. A ausência de prazo automático não implica que dados públicos deixem de ser dados pessoais nem determina sua situação jurídica.
- **Consulta:** apenas o advogado titular pode consultar marcos do próprio tenant; não há acesso de equipe nem concessão por grupo nesta entrega. Listas, detalhes e agregações aplicam o mesmo controle server-side, inclusive para referências sem tribunal.

## Requisitos e critérios observáveis

1. Cada marco de início ou término ocorrido é acrescentado com instante de registro e dados mínimos de rastreio disponíveis; nenhum marco anterior é sobrescrito.
2. Tenant é derivado do contexto confiável no servidor. Tenant enviado pelo cliente não autoriza nem desloca um registro.
3. Uma vez gravado, o registro não pode ser editado ou removido por operações normais do produto. RLS não basta para assegurar append-only; operações e permissões capazes de alterar/remover exigem proteção própria (ver [stack](docs/stack.md)).
4. Registros não contêm ações de usuários, conteúdo de comunicações, identificadores pessoais diretos ou detalhes técnicos de erro. Referências internas necessárias podem constituir dados pessoais e permanecem protegidas.
5. Marco sem término permanece sem término; o estado de falha é mantido separadamente, sem inferência retroativa nem inclusão de detalhe de erro no Escriba.
6. Nenhum prazo automático de expurgo é exigido para os marcos nesta etapa; acessos e cópias permanecem sujeitos a controle de tenant e segurança.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** comandos inexistentes neste repositório e bloqueantes para implementação. A stack da aplicação central foi decidida (ver [stack](docs/stack.md)), mas versões, runtime, bibliotecas e comandos continuam pendentes; essa decisão não determina a tecnologia do Escriba caso venha a ser implementado como componente independente.
- **Estrutura física:** não definida. `escriba` é um limite lógico no mapa, não uma decisão por diretório, pacote, serviço ou banco. A stack central não decide se o Escriba ficará dentro da aplicação central ou será um componente independente; neste último caso, sua tecnologia também permanece em aberto, sem presumir Ruby/Rails.
- **Estilo de código:** não há código ou snippet de estilo real do produto. Convenções de linguagem, nomes, formatação e exemplo de código ficam pendentes até existir uma base observável; se o Escriba for independente, sua linguagem/tecnologia também não está decidida.

## Estratégia de testes comportamentais proposta

Os cenários abaixo descrevem resultados observáveis, não comandos nem uma decisão de framework. A stack da aplicação central está definida, mas ferramenta, local dos testes, cobertura e execução permanecem pendentes; a tecnologia do Escriba independente também não foi decidida.

- Iniciar e concluir uma coleta produz marcos acrescentados com os dados de contexto e rastreio disponíveis, sem nomes/OAB/processos em claro, conteúdo de comunicações, ações de usuário ou detalhes de erro.
- Uma tentativa normal de alterar ou excluir registro não muda nem remove seu conteúdo; não há expurgo automático por tempo nesta etapa.
- O contexto de tenant autenticado no servidor prevalece; enviar outro tenant pelo cliente não desloca o registro.
- Uma execução sem marco de término permanece sem término registrado, em vez de receber evento fabricado; estado de falha consultável permanece fora do Escriba.

Exemplos verificáveis da política 2c:

| Caso | Decisão |
|---|---|
| Marco existente após 90 dias | Permanece disponível ao titular autorizado; não existe expurgo automático por tempo. |
| Tentativa normal de editar ou excluir marco | Negada; o conteúdo permanece inalterado. |

## Fronteiras

- **Sempre:** acrescentar registros do fluxo; manter apenas referências mínimas; usar tenant confiável; não registrar ações de usuários, conteúdo, identificadores pessoais diretos, segredos ou detalhes de erro.
- **Pedir aprovação:** alterar dados ou granularidade dos marcos, instituir expurgo ou tornar obrigatório dado hoje apenas disponível.
- **Nunca:** editar ou apagar registros por operação normal; registrar ações de usuários, conteúdo de comunicações, identificadores pessoais diretos, segredos ou detalhes de erro; aceitar tenant informado pelo cliente como autorização.

## Questões abertas e bloqueios

- O conjunto semântico de campos está definido como referências internas do tenant, execução, fonte, entidade/monitoramento, advogado, tribunal e processos disponíveis; esquema físico, identificação e granularidade técnica dos marcos permanecem para o contrato de implementação.
- O solicitante dispensou prazo automático de retenção e expurgo nesta etapa. Dados públicos podem conter dados pessoais; a aplicação deve preservar isolamento e avaliar obrigações legais aplicáveis antes do uso em produção.
- Onde o estado de falha será mantido e como a consulta o relacionará à execução/tribunal sem expor detalhes de erro no Escriba?
- O Escriba será implementado dentro da aplicação central ou como componente independente? No segundo caso, qual será sua tecnologia? Versões, runtime, bibliotecas, comandos, estrutura física, estilo real, framework/localização de testes e cobertura continuam pendentes antes da implementação.

## Critérios de sucesso

O fluxo acrescenta marcos mínimos, sem alteração ou exclusão por operação normal e sem prazo automático de expurgo. Ações de usuários, identificadores diretos, conteúdo e erros técnicos ficam fora do Escriba; isolamento e segurança devem ser verificados.
