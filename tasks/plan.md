# Plano de implementação: monitoramento jurídico

Base: [especificação](../docs/especificacao.md). Plano proposto, sujeito à aprovação e à resolução das decisões bloqueantes; não implica autorização para implementar. Checklist detalhado em [todo.md](todo.md).

## Sequência

1. Validar contrato real do Comunica, critérios de capacidade, política de dados e modelo de permissões; aprovar a especificação e o mapa de capacidades.
2. Definir stack, infraestrutura e contratos entre aplicação central, planejador, ETL e Escriba. Implementar acesso do advogado e isolamento em uma fatia verificável.
3. Entregar gestão de usuários, grupos e credenciais; depois cadastros de monitoramento.
4. Entregar planejamento e coleta real de ponta a ponta, com registros Escriba, persistência e deduplicação; acrescentar segunda execução e recuperação de falhas.
5. Entregar consulta agrupada e detalhes, dashboard e aplicação de permissões às respostas.
6. Validar cenários integrados, isolamento, carga de 300 usuários e experiência no navegador.

## Dependências e riscos

Identidade precede permissões e monitoramentos; estes precedem planejamento e coleta. Escriba precisa estar disponível durante a primeira coleta real. Consulta depende de resultados persistidos e autorização. A documentação oficial foi acessada pela máquina local; a estabilidade dos identificadores é premissa aceita e a deduplicação usa conjuntamente `id` e `hash`, por fonte e tenant. Cadernos e comunicações pertencem à mesma fonte lógica DJEN. A coleta principal baixa cadernos ZIP e lê seus JSONs; comunicações paginadas são fallback. Ambas usam somente a data corrente, sem recuperação automática de dias anteriores. Outros riscos: homônimos, divergências observadas no filtro por processo, dados pessoais em registros imutáveis, permissões amplas por padrão e critérios de carga indefinidos.

## Fluxo de branches

`dev` é a base e a branch padrão remota; criar `feature/<nome>` a partir de `dev` para cada feature e integrar após revisão.

## Verificações

Cada tarefa descreve aceite, dependências e verificação no checklist. Comandos concretos serão registrados após escolha da stack; não existem comandos de build ou testes neste repositório ainda. Revisão humana nos checkpoints antes de avançar.
