# Especificação proposta: Escriba (`escriba`)

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `escriba`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack da aplicação central](docs/stack.md).

## Objetivo

Manter um registro imutável e consultável do fluxo de coleta, com os marcos de início e término e os dados relevantes disponíveis para rastrear o trabalho por tenant, execução, entidade e tribunal. O Escriba não é trilha de auditoria de ações de usuários nem repositório de erros técnicos.

## Escopo e contratos lógicos

- **Responsabilidade:** aceitar e acrescentar registros do fluxo de coleta; não os alterar nem excluir.
- **Dependência do mapa:** `identidade`. O contexto de execução deve estar vinculado ao usuário/tenant autenticado e imposto no servidor. Tenant enviado pelo cliente, isoladamente, não comprova acesso. RLS é uma camada adicional: não substitui autorização/RBAC nem a derivação server-side do tenant.
- **Consumidor lógico:** `coleta` (`SPEC-coleta.md`). A fronteira não exige serviço, processo, armazenamento ou transporte independente.
- **Dados mínimos do fluxo, quando disponíveis:** início ou término, execução, tenant, fonte lógica, entidade/monitoramento, advogado, tribunal e processos associados. Fonte e execução devem permitir distinguir ocorrências; o formato e a cardinalidade desses dados não estão definidos.
- O Escriba registra cada marco como nova informação. Não sobrescreve um registro anterior para refletir estado posterior. O prazo de retenção será configurável por variável de ambiente; seu nome, formato, valor padrão e procedimento de expurgo ainda serão definidos na implementação. Imutabilidade nas operações normais não impede o tratamento administrativo de retenção.
- Não recebe ações de usuários nem detalhes de erro. Tratamento de falhas técnicas e seu estado por execução/tribunal pertencem a outros contratos; um registro do Escriba não substitui esse estado.

## Requisitos e critérios observáveis

1. Ao iniciar e concluir um fluxo de coleta, cada marco ocorrido é registrado como acréscimo, com os dados relevantes disponíveis enumerados acima.
2. Um tenant não pode ser escolhido como prova de autorização por dado controlado pelo cliente; o contexto confiável deve vir da identidade imposta pelo servidor.
3. Depois de gravado, um registro não pode ser editado ou removido por operações normais do produto. Uma nova informação não modifica o histórico anterior. RLS, por si só, não assegura essa imutabilidade; permissões e operações capazes de alterar ou remover registros precisam de proteção própria antes da implementação (ver [stack](docs/stack.md)).
4. Registros do Escriba não contêm ações de usuários nem detalhes de erro técnico. A ocorrência e o estado da falha são tratados separadamente.
5. A ausência de um marco de término não deve ser preenchida por inferência ou por alteração retroativa do registro de início.

## Comandos, estrutura e estilo

- **Build, teste, lint e formatação:** comandos inexistentes neste repositório e bloqueantes para implementação. A stack da aplicação central foi decidida (ver [stack](docs/stack.md)), mas versões, runtime, bibliotecas e comandos continuam pendentes; essa decisão não determina a tecnologia do Escriba caso venha a ser implementado como componente independente.
- **Estrutura física:** não definida. `escriba` é um limite lógico no mapa, não uma decisão por diretório, pacote, serviço ou banco. A stack central não decide se o Escriba ficará dentro da aplicação central ou será um componente independente; neste último caso, sua tecnologia também permanece em aberto, sem presumir Ruby/Rails.
- **Estilo de código:** não há código ou snippet de estilo real do produto. Convenções de linguagem, nomes, formatação e exemplo de código ficam pendentes até existir uma base observável; se o Escriba for independente, sua linguagem/tecnologia também não está decidida.

## Estratégia de testes comportamentais proposta

Os cenários abaixo descrevem resultados observáveis, não comandos nem uma decisão de framework. A stack da aplicação central está definida, mas ferramenta, local dos testes, cobertura e execução permanecem pendentes; a tecnologia do Escriba independente também não foi decidida.

- Iniciar e concluir uma coleta produz marcos acrescentados com os dados de contexto e rastreio disponíveis.
- Uma tentativa de alterar ou excluir um registro já gravado não muda nem remove seu conteúdo.
- Não se encontra, nos registros do Escriba, uma ação de usuário ou detalhe de erro técnico; o estado de falha consultável é mantido fora deste módulo.
- Contexto de tenant autenticado no servidor prevalece; enviar outro tenant pelo cliente não desloca o registro para esse tenant.
- Uma execução sem marco de término permanece sem término registrado, em vez de receber um evento fabricado.

## Fronteiras

- **Sempre:** acrescentar registros do fluxo; manter os dados de rastreio disponíveis; usar contexto de identidade/tenant confiável do servidor; não registrar ações de usuários nem detalhes de erro.
- **Pedir aprovação:** mudar o conjunto de dados, granularidade ou semântica dos marcos; estabelecer retenção, expurgo, anonimização, exportação ou mecanismo excepcional de remoção; tornar obrigatório dado hoje apenas disponível quando houver.
- **Nunca:** editar ou apagar registros como operação ordinária; registrar ações de usuário, segredos ou detalhes de erro; aceitar tenant informado pelo cliente como autorização.

## Questões abertas e bloqueios

- Qual o esquema lógico mínimo, a identificação da execução e a granularidade dos marcos de início/término?
- Quais campos de identidade precisam constar do registro sem transformá-lo em log de ações de usuário?
- Como implementar e validar o prazo de retenção configurável e o tratamento administrativo dos dados pessoais, mantendo a exigência append-only nas operações normais?
- Onde o estado de falha será mantido e como a consulta o relacionará à execução/tribunal sem expor detalhes de erro no Escriba?
- O Escriba será implementado dentro da aplicação central ou como componente independente? No segundo caso, qual será sua tecnologia? Versões, runtime, bibliotecas, comandos, estrutura física, estilo real, framework/localização de testes e cobertura continuam pendentes antes da implementação.

## Critérios de sucesso

O fluxo de coleta deixa registros somente de acréscimo com marcos e contexto disponíveis; os registros anteriores permanecem inalterados; ações de usuários e detalhes de erro ficam fora do Escriba; a retenção e os bloqueios técnicos são resolvidos antes de implementar.
