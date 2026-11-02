# Especificação proposta: identidade

**Estado:** aprovada pelo solicitante como base funcional; decisões técnicas ainda pendentes continuam bloqueantes antes da implementação. **ID:** `identidade`. Referências: [mapa](CAPABILITIES.md), [especificação geral](docs/especificacao.md), [intenção](docs/intent/monitoramento-juridico.md), [stack](docs/stack.md).

O [primeiro acesso controlado](SPEC-primeiro-acesso.md#decisões-de-pa00) define o cadastro exclusivo por convite, a liberação de titularidade e a distinção entre endereço de login e prova real da caixa postal. Senha, TOTP e sessão são compartilhados entre administradora, advogado e equipe.

## Objetivo

Estabelecer como um advogado independente e os usuários de seu ambiente se autenticam, como o servidor reconhece a identidade e o tenant da solicitação e como se aplica a validade opcional da credencial. No onboarding, o advogado informa nome completo, OAB principal e, se houver, OABs secundárias. O tenant pertence ao advogado, não ao escritório; nome comercial do escritório é opcional e não define o tenant.

## Escopo e dono dos contratos

Este módulo é dono do contrato de identidade autenticada, do tenant associado a essa identidade, do perfil profissional do advogado e da validade da credencial. Ele não decide o que a identidade pode fazer: [autorização](SPEC-autorizacao.md) consome o contexto autenticado e é dona das decisões de acesso. [Monitoramentos](SPEC-monitoramentos.md) consome o perfil profissional para representar o advogado monitorado.

Usuários de equipe pertencem ao tenant do advogado que os convidou; autorização administra vínculo e grupos, enquanto identidade valida o acesso, a aceitação do convite, validade e revogação. A autenticação não substitui a autorização no tenant.

## Contratos lógicos

- **Contexto autenticado:** para uma solicitação autenticada, o servidor reconhece uma identidade de usuário e o tenant a que ela pertence. O tenant efetivo é derivado pelo servidor; um valor de tenant enviado pelo cliente nunca prova associação nem concede acesso.
- **Perfil do advogado:** o onboarding registra nome completo, uma OAB principal e zero ou mais OABs secundárias. O tenant continua sendo o advogado mesmo que exista nome comercial opcional do escritório.
- **Validade:** aplica-se apenas às credenciais de usuários de equipe criados pelo advogado; a credencial do advogado titular não expira por esta política. Na criação, o advogado escolhe explicitamente entre sem expiração e um número inteiro positivo de dias; não há valor padrão implícito.
- **Início e vencimento:** a contagem começa no instante em que o advogado confirma a criação da credencial e emite o convite, não no envio, aceite ou primeiro login. Instantes são absolutos e normalizados em UTC; para N dias, vencimento = instante de criação + N × 24 horas, sem ajuste por fuso, horário de verão ou fim de dia civil. No instante exato do vencimento e depois dele, a credencial é inválida.
- **Alteração e renovação:** alterar a validade escolhida não modifica retroativamente uma credencial existente; a nova escolha só passa a valer mediante renovação explícita. Renovar uma credencial não revogada, inclusive expirada, inicia um novo período no instante da renovação, usando a escolha de validade vigente; não se soma ao prazo anterior.
- **Revogação:** interrompe imediatamente novas operações protegidas, inclusive em sessões abertas. Renovação não reativa credencial revogada; para restabelecer acesso, é necessária uma nova credencial.
- **Fronteira com autorização:** este módulo fornece o contexto autenticado e seu estado de validade; não fornece permissões, associação a grupos ou escopo de tribunais/dashboard.
- **Login:** advogado e equipe usam senha local e código temporário de aplicativo autenticador (TOTP), ambos obrigatórios. A sessão só é criada após validação dos dois fatores.
- **Recuperação de senha:** link enviado ao endereço canônico de acesso, válido por 30 minutos e de uso único. Isso não comprova a caixa postal. Novo pedido invalida o anterior; a confirmação altera somente a senha e revoga sessões e desafios, preservando TOTP e sua proteção contra replay. Não autentica automaticamente, recupera TOTP ou ativa preparação pendente.
- **Convite de equipe:** o advogado informa e-mail e grupos; a pessoa aceita o convite após verificar o mesmo e-mail e autenticar-se com os dois fatores. Autenticação isoladamente não concede participação em um tenant. Identidade implementa a aceitação; autorização administra vínculo e grupos.
- **Primeiro acesso:** o advogado usa convite administrativo de 24 horas; preparar senha/autenticador não ativa identidade, reset ou sessão. Confirmar o primeiro TOTP conclui conta, liberação, consumo e sessão atomicamente. Perfil/tenant são uma transação posterior e exigem liberação também na função de banco. Contas e titulares existentes são preservados.
- **Prova da caixa postal:** `identities.verified_email` conserva o nome histórico, mas representa o endereço canônico de login; somente `email_verified_at` não nulo comprova verificação real. Convite administrativo não preenche esse instante; equipe exige confirmação contextual antes do aceite.
- **E-mail de acesso:** o convite faz parte da primeira entrega e é distinto dos relatórios e avisos diários de coleta, que continuam futuros.

O contrato técnico de login, sessão, convite e documentação está registrado em [arquitetura](docs/arquitetura.md#identidade-convites-e-documentação). Autenticação não substitui a autorização nem a checagem de validade da credencial.

## Requisitos

1. O fluxo de onboarding permite ao advogado informar nome completo e OAB principal, e adicionar OABs secundárias quando existirem.
2. Cada advogado é associado a seu próprio tenant. O escritório não é um tenant; seu nome comercial, se coletado, é informação opcional e não altera a associação.
3. A aplicação obtém do lado servidor a identidade do usuário e o tenant autenticado. Dados de tenant fornecidos pelo cliente não substituem esse contexto nem permitem escolher outro tenant.
4. A validade de credenciais de equipe é explicitamente escolhida no ato de criação: sem expiração ou número inteiro positivo de dias. A contagem, a alteração, a renovação e a revogação seguem os instantes absolutos e efeitos definidos nos contratos lógicos; verificação server-side ocorre em cada operação protegida, inclusive em sessão ativa.
5. Uma credencial expirada não dá acesso protegido. A verificação deve ocorrer no servidor, não somente na interface.
6. Este módulo não atribui escopos de leitura/escrita, grupos, permissões de tribunal nem acesso à dashboard.

## Critérios observáveis

- No onboarding concluído, o perfil do advogado contém nome completo, OAB principal e as OABs secundárias informadas; não é exigida uma OAB secundária.
- O contexto autenticado associa o advogado ao tenant próprio, independentemente de nome de escritório.
- Enviar pelo cliente um tenant diferente não muda o tenant reconhecido pelo servidor nem permite operar sobre seus dados.
- A opção sem expiração permanece válida até revogação; a opção por N dias vence no instante UTC de criação + N × 24 horas, inclusive quando a solicitação ocorre em sessão já aberta.
- A credencial do advogado titular não recebe expiração opcional; a regra aplica-se às credenciais de equipe criadas pelo advogado.
- Alterar a escolha de validade sem renovar não muda o vencimento já efetivo. Renovar credencial expirada, mas não revogada, inicia o prazo selecionado no instante da renovação.
- Uma credencial revogada não autentica operações protegidas e não pode ser reativada por renovação; uma credencial nova é necessária.
- Identidade sem credencial válida ou não revogada não é apresentada aos módulos consumidores como contexto autenticado válido.

Exemplos verificáveis da política 2a:

| Caso | Decisão |
|---|---|
| Credencial de equipe criada às 10h30 UTC, sem expiração | Não há vencimento por tempo; revogação continua efetiva. |
| Credencial criada às 10h30 UTC por dois dias | Vence exatamente às 10h30 UTC, 48 horas depois; uma operação nesse instante ou depois é negada. |
| Sessão aberta antes desse vencimento; solicitação às 10h29 UTC | Permitida se os demais controles autorizarem. |
| A mesma sessão solicita operação às 10h30 UTC ou depois | Negada no servidor; sessão aberta não prolonga a credencial. |
| Validade é alterada, mas a credencial não é renovada | O prazo já efetivo não muda. |
| Credencial expirada, não revogada, é renovada às 14h por dois dias | Novo vencimento às 14h, 48 horas depois da renovação, sem somar ao vencimento anterior. |
| Credencial revogada é renovada | Continua revogada; só uma credencial nova restabelece acesso. |

Convites e sessões não alteram o início da validade da credencial. O protocolo, o prazo técnico do convite e a revogação de sessões no provedor continuam decisões de implementação; em qualquer caso, o servidor nega operações protegidas no vencimento ou após revogação.

## Ambiente de implementação e teste

O monorepo contém API Rails em `apps/backend` e frontend Next.js em `apps/web`, com PostgreSQL/RLS e roles segregadas. Comandos, imagens e evidências estão no README; contratos HTTP web em `apps/web/endpoints.md`.

As políticas de RLS não substituem RBAC nem as verificações de identidade e autorização da aplicação; o tenant efetivo deve ser derivado no servidor do contexto autenticado, nunca de dado enviado pelo cliente. Ver também [stack](docs/stack.md).

- **Backend:** Minitest em imagem Docker de testes contra PostgreSQL descartável, com runtime e migrator separados.
- **Frontend:** testes `node:test`, typecheck, lint, formatação e build existentes, executados em container Node não root; fluxos visuais em Chromium headless.
- **Estilo:** implementação vigente e design system do repositório, sem nova convenção.
- **Aceite:** fatores, origem/CSRF, bootstrap autorizado, perfis, vínculos, expiração/revogação, recuperação, isolamento e concorrência são cobertos nos testes e no smoke integrado.
- **Desempenho:** 300 usuários simultâneos são referência de planejamento; medição futura não bloqueia esta entrega.

## Fronteiras

- **Sempre:** derivar identidade e tenant autenticados no servidor; validar em cada operação protegida se a credencial está vigente e não revogada, inclusive no instante de vencimento e em sessão ativa; manter tenant vinculado ao advogado, nunca ao escritório; não expor identidade inválida como contexto autenticado.
- **Pedir aprovação:** alterar o escopo, o início, a duração ou os efeitos de alteração, renovação e revogação já definidos; definir detalhes técnicos de login, convite, validação da identidade e sessões; alterar campos ou regras de associação do advogado/tenant.
- **Nunca:** confiar em tenant declarado pelo cliente como prova de acesso; permitir que sessão ativa ignore expiração ou revogação; transformar escritório em tenant; aplicar validade à conta do advogado titular; usar convite, aceite ou primeiro login para reiniciar o prazo; renovar credencial revogada.

## Questões abertas

1. **Técnica, fora da decisão 2a:** emissão, envio, validade e aceite do convite não podem reiniciar a validade já iniciada na criação da credencial.
2. **Validação de perfil:** nome e OAB seguem [monitoramentos](SPEC-monitoramentos.md#contratos-lógicos); no perfil, inscrição principal é obrigatória e pares número/UF duplicados são recusados. Não há verificação externa de inscrição.
3. **Implementação:** representação e persistência dos instantes UTC, validação do número positivo de dias, sessões e fluxos técnicos; os comportamentos de política já estão definidos acima.
4. **Ambiente:** caminhos físicos/layout, comandos, estilo real, ferramentas e locais de teste do repositório de implementação; a stack base está em [stack](docs/stack.md).
