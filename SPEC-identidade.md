# Especificação proposta: identidade

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas pendentes continuam bloqueantes antes da implementação. **ID:** `identidade`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md).

## Objetivo

Estabelecer como um advogado independente e os usuários de seu ambiente se autenticam, como o servidor reconhece a identidade e o tenant da solicitação e como se aplica a validade opcional da credencial. No onboarding, o advogado informa nome completo, OAB principal e, se houver, OABs secundárias. O tenant pertence ao advogado, não ao escritório; nome comercial do escritório é opcional e não define o tenant.

## Escopo e dono dos contratos

Este módulo é dono do contrato de identidade autenticada, do tenant associado a essa identidade, do perfil profissional do advogado e da validade da credencial. Ele não decide o que a identidade pode fazer: [autorização](SPEC-autorizacao.md) consome o contexto autenticado e é dona das decisões de acesso. [Monitoramentos](SPEC-monitoramentos.md) consome o perfil profissional para representar o advogado monitorado.

Usuários de equipe podem pertencer ao tenant do advogado, mas a gestão de usuários e grupos é responsabilidade de autorização. A criação de credenciais ou identidades da equipe e sua relação com o mecanismo de login não estão detalhadas nas fontes e não são definidas aqui.

## Contratos lógicos

- **Contexto autenticado:** para uma solicitação autenticada, o servidor reconhece uma identidade de usuário e o tenant a que ela pertence. O tenant efetivo é derivado pelo servidor; um valor de tenant enviado pelo cliente nunca prova associação nem concede acesso.
- **Perfil do advogado:** o onboarding registra nome completo, uma OAB principal e zero ou mais OABs secundárias. O tenant continua sendo o advogado mesmo que exista nome comercial opcional do escritório.
- **Credencial e validade:** somente os usuários criados pelo advogado recebem a validade opcional, sem expiração ou em dias. Essa funcionalidade não aplica prazo à própria conta do advogado. No vencimento, negar solicitações protegidas inclusive em sessão ativa.
- **Revogação:** o advogado pode revogar uma credencial imediatamente, interrompendo o acesso inclusive de sessões abertas. Renovação não reativa uma credencial revogada; para restabelecer esse acesso, criar nova credencial.
- **Renovação:** o advogado pode renovar uma credencial não revogada, inclusive expirada. Para N dias, novo vencimento = instante da renovação + N períodos de 24 horas, sem somar ao vencimento anterior.
- **Fronteira com autorização:** este módulo fornece o contexto autenticado e seu estado de validade; não fornece permissões, associação a grupos ou escopo de tribunais/dashboard.

O contrato é lógico; não fixa protocolo, formato de sessão, endpoint, esquema de dados ou mecanismo de login.

## Requisitos

1. O fluxo de onboarding permite ao advogado informar nome completo e OAB principal, e adicionar OABs secundárias quando existirem.
2. Cada advogado é associado a seu próprio tenant. O escritório não é um tenant; seu nome comercial, se coletado, é informação opcional e não altera a associação.
3. A aplicação obtém do lado servidor a identidade do usuário e o tenant autenticado. Dados de tenant fornecidos pelo cliente não substituem esse contexto nem permitem escolher outro tenant.
4. A política de validade permite opção sem expiração ou validade em dias. A configuração e a checagem da expiração são efetivas para operações autenticadas, inclusive enquanto a sessão estiver ativa.
5. Uma credencial expirada não dá acesso protegido. A verificação deve ocorrer no servidor, não somente na interface.
6. Este módulo não atribui escopos de leitura/escrita, grupos, permissões de tribunal nem acesso à dashboard.

## Critérios observáveis

- No onboarding concluído, o perfil do advogado contém nome completo, OAB principal e as OABs secundárias informadas; não é exigida uma OAB secundária.
- O contexto autenticado associa o advogado ao tenant próprio, independentemente de nome de escritório.
- Enviar pelo cliente um tenant diferente não muda o tenant reconhecido pelo servidor nem permite operar sobre seus dados.
- Com validade sem expiração, o acesso não é encerrado por uma data de expiração configurada; com validade em dias, a credencial deixa de permitir acesso após vencer.
- Uma sessão aberta antes do vencimento não permite uma nova operação protegida depois do vencimento.
- Após revogação, uma sessão previamente aberta não permite nova operação protegida; tentar renovar a credencial revogada não a reativa.
- Renovar uma credencial não revogada às 14h por dois dias define novo vencimento às 14h, 48 horas depois da renovação, independentemente do vencimento anterior.
- Identidade sem validade reconhecida ou credencial expirada não é apresentada aos módulos consumidores como contexto autenticado válido.

Decisão do solicitante: contar a validade desde o instante de criação da credencial em períodos completos de 24 horas. Para N dias, o vencimento é o instante de criação mais N × 24 horas, sem depender do primeiro login ou do fim do dia de calendário. No instante de vencimento e depois dele, negar operações protegidas, inclusive em sessão já aberta.

## Ambiente de implementação e teste: pendências bloqueantes

Não há aplicação, stack, convenção de comandos, estrutura de código, framework de teste ou exemplo real de estilo estabelecidos no repositório. Não inventar comandos de build, teste ou lint, diretórios, sintaxe de implementação, dependências ou snippet de estilo. Esses itens precisam ser escolhidos antes da implementação.

- **Comandos:** build, execução de testes, lint e desenvolvimento local — não definidos; nenhum comando é proposto.
- **Estrutura:** diretórios de aplicação, testes e configuração — não definidos.
- **Estilo:** não há código real que sirva de referência. Convenções e snippet só podem ser definidos após a escolha da stack e do repositório de implementação.
- **Estratégia de teste:** framework, localização e comandos são pendências. Os testes de aceitação devem cobrir onboarding do perfil profissional, derivação server-side do tenant, isolamento de tenant e expiração aplicada a solicitações com sessão ativa. Isso é uma estratégia comportamental, não escolha de ferramenta nem repetição de testes já feitos sobre a fonte de dados.
- **Limite de desempenho compartilhado:** a aplicação central deve suportar ao menos 300 usuários simultâneos; perfil, latências-alvo, ambiente e taxa de erro continuam pendentes na [especificação geral](docs/especificacao.md).

## Fronteiras

- **Sempre:** derivar identidade e tenant autenticados no servidor; aplicar expiração também a sessões em uso; manter tenant vinculado ao advogado, nunca ao escritório; não expor a módulos consumidores uma identidade expirada como válida.
- **Pedir aprovação:** escolher mecanismo de login, política de validade e ciclo de credenciais; definir como usuários de equipe recebem identidades; alterar campos ou regras de associação do advogado/tenant.
- **Nunca:** confiar em tenant declarado pelo cliente como prova de acesso; permitir que uma sessão ativa ignore expiração; transformar escritório em tenant; presumir mecanismo de login, campos de credencial, recuperação, convite ou outros fluxos não aprovados.

## Questões abertas

1. Qual mecanismo de login será adotado e como será iniciada a identidade do advogado e de cada usuário da equipe?
2. Escopo definido: validade opcional somente para usuários criados pelo advogado, não para a conta do advogado. Detalhes técnicos de criação e entrega de credenciais continuam pendentes.
3. A contagem está definida: desde a criação, em períodos de 24 horas. Representação técnica dos instantes e validação dos dias informados devem constar do contrato de identidade.
4. Revogação é imediata inclusive em sessões abertas; renovação conta desde o instante em que ocorre e não reativa credencial revogada. Não criar exceções silenciosas a essas regras.
5. Quais validações, formatos canônicos e tratamento de duplicidades se aplicam a nome e OAB principal/secundárias?
6. Quais stack, layout de código, comandos, estilo real e ferramentas/locais de teste serão escolhidos antes da implementação?
