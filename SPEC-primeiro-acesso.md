# Especificação proposta: primeiro acesso controlado

**Estado:** implementação integrada na branch, autorizada na [issue #16](https://github.com/smcruzfilipe/advocaciaonline/issues/16). O solicitante aprovou globalmente a continuidade one-shot e as revisões intermediárias; aceites técnicos permanecem verificáveis nas [tarefas](tasks/todo-primeiro-acesso.md) e no README. Decisões vinculantes em [Decisões de PA00](#decisões-de-pa00). Nenhum deploy ou uso de dados persistentes autorizado.

## Objetivo

Permitir que somente a administradora da plataforma libere o primeiro acesso de advogados. Ela informa apenas o e-mail; o advogado recebe um link, prepara senha e autenticador e confirma o primeiro TOTP para concluir cadastro e autenticação, seguindo diretamente ao onboarding profissional existente. Depois, administra os convites de sua equipe como atualmente. Sucesso significa que nenhuma nova titularidade de tenant pode ser obtida por cadastro público, convite de equipe ou chamada direta sem liberação administrativa vinculada à identidade.

## Escopo e contratos

- A área administrativa fica no mesmo frontend, em `/admin` e `/admin/convites`; usa login e sessão existentes, com capacidade administrativa verificada no servidor. Titularidade de tenant não concede administração da plataforma.
- A administradora informa o e-mail do advogado. “Enviar convite por e-mail” persiste o convite e solicita o envio SMTP. Para WhatsApp, informa também o telefone com país e DDD; a ação abre `https://api.whatsapp.com/send/` com `phone`, mensagem e link preenchidos, `type=phone_number` e `app_absent=0`. O telefone fica somente em memória, não é salvo. A abertura não envia a mensagem sem confirmação no WhatsApp; não há integração com API de disparo.
- Cada link é associado ao e-mail normalizado, válido por 24 horas desde a emissão e de uso único. Reemissão é explícita; copiar ou reenviar o mesmo link não renova o prazo. As regras de concorrência e contas existentes estão em Q3.
- Cadastro da credencial e onboarding profissional são etapas distintas. Para conta nova, senha/autenticador ficam pendentes, sem sessão ou reset, até confirmar senha preparada e primeiro TOTP dentro do prazo do convite. Só então criar identidade/credencial com TOTP confirmado, vincular liberação, consumir convite e criar sessão normal atomicamente; emitir cookie apenas após commit, sem perfil/tenant nessa transação. Seguir diretamente ao onboarding, sem repetir login/TOTP. Conta existente resgata com sua sessão após senha/TOTP, sem mudar credenciais. Reutilizar mecanismos existentes, conforme A1–A2.
- O advogado não confirma adicionalmente o e-mail para esse cadastro/onboarding. O endereço do convite não pode ser substituído no resgate; o link não prova posse da caixa postal. Para conta nova, quem obtiver o segredo antes do uso/vencimento poderá cadastrar a credencial; para conta existente, o token não substitui a autenticação da mesma identidade.
- Cadastro público genérico é removido da interface e da API, migrando seus consumidores. A orientação sem contato fictício está definida em Q2.
- Equipe continua exigindo convite válido, confirmação real do mesmo e-mail e senha/TOTP; não recebe titularidade por esse fluxo. Contas existentes são preservadas, com as regras de cutover de Q4 e distinção de e-mail de Q5.
- Emissão persiste o convite antes de SMTP; falha de transporte não impede copiar o mesmo link. Aceitação SMTP não é prova de entrega; timeout pode ter resultado desconhecido, conforme A6.

## Segurança e limites

O link é segredo equivalente à autorização para criar a conta: usar HTTPS, token imprevisível, impedir exposição em logs e evitar vazamento por referências a terceiros. Validar estado e prazo no servidor; nunca confiar apenas na interface. Proteger credenciais administrativas, sessões e operações contra acesso não autorizado. Não incluir tokens, senhas ou segredos em documentação ou logs.

- **Sempre:** validar entradas, prazo, estado e autorização no servidor; preservar isolamento de tenants e regras de equipe; reutilizar as proteções de origem, CSRF, ingresso e limitação existentes.
- **Pedir autorização própria:** iniciar implementação ou execução de verificações, deploy ou infraestrutura; acrescentar integrações, alterar escopo ou executar ações destrutivas sobre dados existentes. As escolhas de Q1–Q6 e A1–A7 já foram delegadas, não são novas perguntas de preferência.
- **Nunca:** reintroduzir cadastro público por API; registrar segredos; presumir que convite administrativo verifica e-mail; usar recuperação para contornar TOTP; enfraquecer convites de equipe.

## Stack, estrutura e estilo

Monorepo existente: Rails API em `apps/backend/`, Next.js/TypeScript em `apps/web/`, PostgreSQL com RLS; referências de versões em [stack](docs/stack.md). Testes Rails ficam em `apps/backend/test/`; a interface segue as convenções e testes existentes em `apps/web/`. Documentação funcional e contratos ficam em `SPEC-*.md` e `docs/`. Reutilizar autenticação, cookies, senha/TOTP, recuperação, SMTP e perfil existentes; não criar outro aplicativo, provedor de identidade, fila ou serviço. Os endpoints abaixo são contratos futuros, não rotas implementadas ou APIs testadas. Shapes finais de DTOs, assinaturas SQL, timestamps de migrations e nomes de arquivos novos serão ratificados na respectiva folha antes de codificar.

Exemplo real do estilo de transporte existente (`apps/backend/app/services/team_invitation_mailer.rb`):

```ruby
message = Mail.new
message.from = settings.fetch(:from)
message.to = email
message.subject = "Convite para sua equipe no Advocacia Online"
```

Seguir nomes e formatação existentes em Ruby e TypeScript; não reutilizar o assunto acima para o convite do advogado.

## Comandos e estratégia de verificação

Comandos de referência já documentados para o frontend, com o container de desenvolvimento existente e dependências preparadas:

```bash
docker exec advocacia-web npm test
docker exec advocacia-web npm run lint
docker exec advocacia-web npm run typecheck
docker exec advocacia-web npm run build
```

A execução Rails depende do banco e das credenciais de teste isoladas; os comandos exatos devem ser confirmados antes da implementação, sem usar dados reais nem iniciar containers fora dos gates aplicáveis. A verificação futura deve cobrir autorização administrativa, cadastro e onboarding separados, retomada via login, e-mail/recuperação, equipe, concorrência, cutover, expurgo e transporte simulado. Deve incluir interface no navegador e recusa direta por HTTP e pela função de bootstrap com a role de runtime. Testes não substituem um smoke do caminho funcional. Nenhuma cobertura percentual ou limite operacional novo é exigido. Estes são comandos e estratégia de referência; nenhuma dessas verificações foi executada ou aprovada nesta etapa documental.

## Critérios de aceite

1. Somente a administradora autenticada por senha/TOTP e autorizada pelo servidor consegue consultar, emitir, recuperar, enviar ou reemitir convites; usuário comum e solicitações anônimas são recusados, inclusive por chamada direta. Provisionamento e recuperação administrativa obedecem Q1.
2. Ao informar e-mail válido, a administradora pode enviar ou copiar o mesmo link. Com telefone internacional válido, pode abrir diretamente o WhatsApp com destinatário e mensagem preenchidos; telefone ausente/inválido impede essa ação antes de criar convite. Telefone não é obrigatório para envio por e-mail. Falha SMTP mantém o convite copiável/compartilhável; configuração ausente é informada explicitamente e timeout é comunicado como resultado desconhecido, nunca como entrega confirmada, conforme A6.
3. Pelo convite válido, o advogado cadastra credencial para o e-mail fixado e segue diretamente ao onboarding existente, sem confirmação adicional de e-mail ou repetição de login/TOTP. Conta nova e sessão normal só nascem após validar senha preparada e primeiro TOTP; preparação não permite sessão/reset. Cadastro, retomada por login normal quando necessária e transação separada de perfil/tenant seguem A1–A2 e Q5.
4. No instante de emissão + 24 horas ou depois, confirmação final/resgate são recusados, mesmo com preparação anterior; abertura/inspeção não consomem nem prorrogam o convite. Consumo e vínculo da liberação são atômicos, com rollback em erro e no máximo um sucesso concorrente, conforme A1–A2.
5. A administradora pode reemitir explicitamente, invalidando o anterior atomicamente e reiniciando 24 horas; copiar/reenviar não renova prazo. Há no máximo um convite ativo por e-mail normalizado; contas existentes seguem Q3, sem duplicar identidade/tenant, alterar credenciais ou reativar conta desativada.
6. Interface e API impedem cadastro público genérico e mostram a orientação de Q2. Sem liberação vinculada, serviço/HTTP de onboarding e `claim_tenant`, inclusive por chamada direta de runtime, negam tenant próprio, conforme A2/A5.
7. O advogado continua convidando equipe sem liberação administrativa, preservando convite válido, confirmação real do mesmo e-mail e senha/TOTP. Contas e sessões válidas existentes são preservadas no cutover de Q4; equipe e identidade ainda sem caixa verificada seguem Q5, sem conceder titularidade por convite de equipe.
8. Links/credenciais não vazam e usuários comuns não obtêm acesso administrativo. Recuperação não contorna TOTP nem afirma verificação inexistente; sigilo, ausência de histórico, expurgo oportunista e invalidação de todos os convites restaurados seguem Q1/Q5/Q6 e A3–A4, sem manutenção agendada.

## Decisões de PA00

Esta seção é a fonte única das decisões funcionais e arquiteturais do primeiro acesso; plano, checklist, identidade e arquitetura a consomem por referência. O solicitante aprovou diretamente a base funcional, conta administrativa única, senha/TOTP, códigos de recuperação e redefinição de senha por e-mail. Depois delegou as demais recomendações e exigiu a solução mais simples, sem suposições. As decisões abaixo registram essa seleção; não atestam implementação ou testes, nem autorizam infraestrutura ou execução.

### Q1 — Conta administrativa e recuperação

Uma conta administrativa é provisionada por procedimento operacional protegido no servidor, sem cadastro público nem flag de cliente. Conta, e-mail e senha reais são fornecidos pelo operador nesse procedimento; nenhum valor é presumido aqui. Reutilizar senha, login, TOTP, sessão e recuperação atuais; capacidade administrativa é distinta da condição de titular de tenant.

Na inscrição/troca do autenticador, exibir códigos de recuperação de uso único para guarda fora da plataforma, persistidos somente como hashes. Senha e um código válido, consumido atomicamente, habilitam **somente reinscrição de TOTP**: não criam sessão administrativa nem autorizam convites. Confirmar um código do novo autenticador antes de liberar acesso administrativo e invalidar códigos antigos, sessões e desafios na troca.

Na inscrição inicial e reinscrição do autenticador, exibir somente QR code gerado localmente a partir do `otpauth_uri` retornado pelo backend, sem chave manual ou alternativa textual. Não enviar o segredo a um serviço de QR externo. Falha de geração deve informar o erro e orientar nova tentativa pela etapa anterior, sem fallback manual. Login de autenticador já confirmado continua solicitando somente seu código TOTP.

Redefinição de senha usa o e-mail da conta, prazo de 30 minutos e uso único do fluxo existente; novo pedido invalida o anterior. Redefinir senha não remove TOTP nem autentica automaticamente. Conforme recomendação adotada por delegação, perda do autenticador e de todos os códigos deixa a conta sem recuperação pelos fluxos normais; e-mail sozinho não desativa MFA. Recuperação exclusivamente pelo servidor foi rejeitada pelo solicitante; não criar bypass de suporte, conforme recomendação adotada por delegação. Preservar origem/CSRF/ingresso e limites existentes, sem novos limiares arbitrários.

### Q2 — Orientação sem contato inventado

Usar somente o texto: “O cadastro está disponível apenas por convite. Entre em contato com o responsável pela plataforma para solicitar acesso.” Sem botão WhatsApp, `mailto`, contato fictício ou novo parâmetro enquanto nenhum contato real foi fornecido.

### Q3 — E-mail, reemissão e identidade existente

Normalizar o e-mail e manter no máximo um convite administrativo ativo por endereço. Emissão não substitui convite ativo implicitamente. Reemitir é ação explícita: invalida o anterior e cria seu substituto atomicamente, com 24 horas a partir da nova emissão. Copiar ou reenviar recupera o mesmo link, sem renovar o prazo. Emissão e resgate concorrentes revalidam o estado sob lock/constraints; no máximo um resultado concorrente incompatível pode ter sucesso.

E-mail já pertencente a titular com tenant gera conflito administrativo e orientação para login, sem duplicar conta/tenant nem redefinir senha/TOTP. Conta existente sem tenant próprio pode receber convite, mas o resgate exige sessão da mesma identidade/e-mail, obtida por senha/TOTP, e vincula a liberação atomicamente. Token não cria duplicata nem altera credenciais existentes, não reativa conta desativada e não concede titularidade pela mera ausência de tenant. A liberação fica na identidade, independente do segredo depois consumido.

### Q4 — Cutover de contas e cadastros anteriores

O procedimento futuro preserva identidades, credenciais, tenants e sessões válidas existentes; titulares com tenant conservam sua titularidade. Invalidar tokens pendentes do cadastro público, sem criar conta a partir deles nem apagar contas ou dados do usuário. Identidade já existente sem tenant próprio mantém login, mas precisa de convite administrativo explícito para se tornar titular. Se tiver apenas convite de equipe, pode concluir equipe, não criar tenant próprio. Esta etapa não executa migration, invalidação ou limpeza.

### Q5 — Login, caixa postal e autorização são distintos

O desenho futuro separa endereço canônico de login, instante nullable de verificação real da caixa postal e liberação administrativa vinculada à identidade. Convite de advogado não preenche a verificação real. Migrar todos os consumidores do atual `verified_email` para a distinção, sem fingir verificação; dados antigos considerados verificados pelo contrato atual preservam esse significado. A representação final é detalhe técnico da folha, não autorização para supor outro schema atual.

O advogado liberado entra por senha/TOTP sem nova confirmação de e-mail. Recuperação pode enviar ao endereço de acesso indicado e aceito no convite, tratado como destino de recuperação e não como prova prévia da caixa postal. A preparação de cadastro de A1 não cria conta ativa nem elegibilidade a reset; na conta nova concluída, TOTP já está confirmado e reset não revela seu segredo. Simples emissão ou confirmação de reset não modifica a verificação real nem contorna TOTP; mantêm-se prazo, uso único, revogação e ausência de login automático do fluxo de senha.

Equipe nova exige convite válido, confirmação real do mesmo e-mail e senha/TOTP para aceite. Identidade de advogado sem caixa verificada que queira aceitar convite de equipe de outro tenant recebe confirmação específica nesse contexto antes do aceite; isso não acrescenta confirmação ao onboarding do advogado. Convite de equipe não amplia permissões nem cria tenant próprio.

### Q6 — Retenção mínima e expurgo

Não criar histórico de convites ou auditoria nova. Manter somente o necessário ao convite ativo e à preparação pendente de A1. Consumo ou substituição eliminam digest, cópia cifrada, preparação pendente e registro terminal na transição; consumo preserva a liberação vinculada à identidade e a credencial concluída. Vencimento torna o link imediatamente inutilizável e irrecuperável pela aplicação. Expurgar vencidos nas operações de listar, emitir, recuperar e resgatar, reutilizando o padrão atual de limpeza de `pending_registrations`. Sem nova rake task, cron, job, fila, serviço ou rotina agendada. Sem atividade, não prometer prazo de exclusão física; validade absoluta no servidor e recusa de segredo expirado independem desse expurgo.

Não há retenção arbitrária de 30 dias. Após restauração, **invalidar todos os convites administrativos restaurados antes de reabrir emissão/resgate**, inclusive os ainda dentro de 24 horas; preservar identidades e liberações válidas do snapshot. A administradora reemite explicitamente quando necessário. Expurgar somente vencidos não basta: um token consumido/substituído depois do snapshot poderia reaparecer ainda no prazo. Esta é uma condição de segurança do convite, não projeto de ledger ou infraestrutura de backups.

### A1 — Preparação pendente e transação de cadastro

Para conta nova, preparar senha, segredo de inscrição TOTP e challenge usando as validações/TOTP e o padrão de registro pendente existentes. Essa preparação **não cria identidade ativa, liberação de titularidade, sessão ou elegibilidade a reset**. Não consumir o convite nessa etapa. Na confirmação final, validar senha preparada e primeiro TOTP com convite ainda ativo e dentro das 24 horas; só então uma única transação revalida convite e preparação, cria identidade/credencial com TOTP confirmado, vincula liberação, consome convite e cria a sessão normal pelo mecanismo existente. Emitir o cookie somente após commit. Registrar uso dos tokens/challenges no consumo e último passo TOTP na credencial para negar replay, sem histórico novo de convites. Não criar tenant ou perfil nessa transação.

Abrir link, inspecionar token ou preparar/validar formulário não consome. Erro faz rollback integral e mantém convite ativo somente até o prazo original. Abandono ou challenge não prorrogam validade; posse do convite ainda válido permite reiniciar a preparação, inclusive por esquecimento da senha, sem habilitar recuperação de conta inexistente. Invalidar preparação substituída para não confirmar tentativa antiga. Para identidade preexistente, consumo e vínculo da liberação continuam atômicos após login/TOTP e validação da sessão correta, sem recriar ou alterar credenciais.

**Razão da etapa pendente:** o achado local da revisão em `apps/backend/app/controllers/password_auth_controller.rb:81–85` identificou risco de apropriação da inscrição TOTP ainda não confirmada mediante reset por e-mail. Não basta consumir convite e liberar identidade antes dessa confirmação. O custo escolhido é uma preparação pendente até o primeiro TOTP, evitando usar o endereço não verificado como caminho para tomar o cadastro. Reutilizar o mecanismo existente sem reescrever o onboarding profissional; o código atual não foi corrigido por esta atualização.

### A2 — Retomada e bootstrap protegido do tenant

Após confirmação final e commit, usar a sessão normal já criada para seguir diretamente a perfil nome/OAB → tenant, sem repetir login/TOTP nem esperar outro passo do autenticador. A sessão só nasce após ambos os fatores, nunca durante preparação; não criar sistema paralelo de sessão. Conta existente já autenticada reutiliza sua sessão válida. Se sair ou interromper após a conclusão, retomar por login normal com senha/TOTP. As 24 horas governam resgate completo, inclusive confirmação inicial, não expiram conta concluída nem limitam retomada do onboarding. Antes do consumo, vencer durante preparação/confirmação nega conclusão; GET, cookies e challenge não prorrogam prazo. Depois dele, falha de perfil não desfaz cadastro nem exige novo convite. Reset de senha continua sem login automático.

Perfil e tenant continuam atômicos na transação existente de onboarding, separada da transação de cadastro. Exigir liberação vinculada na função `claim_tenant` e no serviço/HTTP, inclusive em chamada direta pela role de runtime. Não basta sessão válida nem ausência de tenant; convite de equipe nunca satisfaz essa autorização. Não juntar transações por rede nem reescrever o onboarding inteiro.

### A3 — Segredo recuperável apenas durante a validade

Token opaco aleatório de 256 bits, com hash para lookup/consumo e cópia cifrada autenticada apenas enquanto ativo, para a administradora recuperar/copiar o **mesmo** link. Reutilizar criptografia Rails com chave derivada e finalidade distinta de TOTP; preservar `SECRET_KEY_BASE`, sem nova variável por conveniência. Não persistir texto puro, criar JWT ou criptografia própria.

Consulta/decriptação retorna segredo somente para sessão administrativa autorizada e convite ainda ativo, com resposta `Cache-Control: no-store`. Consumo, reemissão ou expiração tornam o segredo anterior irrecuperável e eliminam sua cópia conforme Q6; para vencido, a administradora pode emitir outro explicitamente.

### A4 — Navegação, sessão e fronteiras HTTP

Link `/primeiro-acesso#token=...`: remover o fragmento após captura e manter o token apenas na memória do formulário. O capturador de convites de equipe deve excluir explicitamente essa rota; não usar query string ou `localStorage`. Antes de consumir, reabrir o link permite retomar a preparação. Após confirmação final, a sessão normal segue diretamente ao onboarding; se sair/interromper depois, retomar por login normal, não pelo convite consumido.

`/admin` e `/admin/convites` pertencem à mesma aplicação. Reutilizar sessão/cookie/login comuns, com destino administrativo autorizado pelo servidor; não criar outro sistema de login. Operações administrativas exigem sessão e capacidade administrativa; mutações também exigem CSRF. Resgate/inspeção públicos exigem token e as proteções existentes de origem, ingresso e limitação. Com sessão, mutações mantêm CSRF; nenhum token de convite concede acesso sem senha/TOTP.

### A5 — Endpoints mínimos e semântica de erro

Contrato futuro, não declaração de rotas implementadas. Token de convite vai no corpo JSON, nunca no path/query. `:id` administrativo é identificador do registro, não o segredo.

| Método e caminho | Contrato mínimo |
|---|---|
| `GET /api/admin/invitations` | Consultar apenas convites ativos, sem devolver seus segredos na listagem. |
| `POST /api/admin/invitations` | Emitir para o e-mail informado, respeitando Q3; não substituir ativo implicitamente. |
| `GET /api/admin/invitations/:id/link` | Recuperar o mesmo link somente enquanto ativo; `no-store`. |
| `POST /api/admin/invitations/:id/email` | Enviar/reenviar o mesmo link ativo via SMTP, sem reemissão ou prorrogação. |
| `POST /api/admin/invitations/:id/reissue` | Substituição explícita e atômica conforme Q3. |
| `POST /api/auth/first-access/inspect` | Receber token no JSON; devolver somente e-mail, expiração e necessidade de login, sem consumir nem autorizar sessão. |
| `POST /api/auth/first-access` | Conta nova: token, senha e confirmação iniciam/reiniciam somente preparação pendente de A1 e retornam dados mínimos de inscrição TOTP/challenge, sem identidade ativa, liberação, sessão ou reset. Conta existente: token e sessão do mesmo e-mail após senha/TOTP vinculam liberação e consomem convite atomicamente, sem mudar credenciais. |
| `POST /api/auth/first-access/confirm` | Conta nova: token, challenge pendente e primeiro TOTP; validar senha preparada, prazo e estado e concluir atomicamente A1 com credencial TOTP confirmado, liberação, consumo e sessão normal. Cookie só após commit; seguir ao onboarding sem repetir login/TOTP. Perfil/tenant permanecem separados. |
| `POST /api/admin/auth/recovery` | Senha e código de recuperação habilitam apenas reinscrição de TOTP, conforme Q1, sem capacidade de emitir convites. |
| `POST /api/admin/auth/recovery/confirm` | Confirmar novo autenticador e concluir troca/invalidações de Q1; acesso continua pelo login normal, não por bypass de MFA. |
| `POST /api/auth/team-register` | Exigir token de equipe no JSON e e-mail correspondente; preservar confirmação real e autenticação para aceite, sem liberação de titularidade. |

Reutilizar `/api/auth/login`, `/api/auth/totp`, `/api/auth/password-reset`, `/api/auth/password-reset/confirm`, verificação de e-mail no contexto de equipe e `/api/onboarding`. Remover o acesso genérico público de `/api/auth/register`, migrando todos os callers para primeiro acesso ou equipe; não manter alias permissivo. Estender a verificação existente somente para atender a identidade já existente ainda não verificada no contexto de equipe.

Usar o envelope existente `{ error: { code, message, details? } }`, sem segredos ou detalhes internos. Semântica mínima: `401` quando a operação exige sessão/autenticação ausente ou inválida; `403` para capacidade administrativa ausente ou falha de origem/ingresso/CSRF; `409` para conflito administrativo de emissão/titular já existente; `422` para entrada inválida ou resgate/inspeção indisponível. Token inválido, vencido, já consumido ou destinado a outra identidade usa a mesma resposta pública de indisponibilidade, sem revelar conta por erro. Recuperação administrativa inválida também não revela qual credencial falhou. Identificador administrativo sem convite ativo não devolve link (`404`), inclusive após expurgo; falha SMTP usa erro de transporte (`503`) sem desfazer convite ativo. Solicitação de reset preserva resposta não enumerável existente.

Sucesso distingue preparação pendente de criação de conta e de consulta/vínculo/envio, sem alegar entrega SMTP ou criar sessão antecipada. Não devolver senha ou código TOTP; segredo de inscrição é restrito à preparação do autenticador, nunca recuperável pelo reset de conta ativa. Mutações não prometem replay idempotente: não repetir automaticamente emissão, reemissão ou confirmação/resgate após timeout; comunicar resultado desconhecido e permitir consulta administrativa ou tentativa de login normal, sem emitir novo convite ocultamente. DTOs, códigos específicos e assinaturas SQL serão fixados na folha antes de codificar; os comportamentos acima não ficam pendentes.

### A6 — Persistência antes do transporte

Persistir emissão antes de chamar SMTP. Falha SMTP mantém o mesmo convite ativo e copiável; não reemitir ocultamente. Timeout pode significar envio com resultado desconhecido e deve ser comunicado assim; a administradora pode copiar ou reenviar explicitamente o mesmo link. Sem retry automático ou fila. Sucesso SMTP significa aceitação, não entrega.

### A7 — Fontes e limites da decisão

Não introduzir limiares, provedores ou valores de ambiente nesta etapa. Fontes oficiais consultadas que fundamentam as alternativas:

- [OWASP — Multifactor Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html#resetting-mfa): recuperação por códigos de uso único e risco de bypass; Q1 escolhe senha+código apenas para reinscrição e assume a indisponibilidade sem ambos os fatores de recuperação.
- [OWASP — Forgot Password Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html#user-resets-password): tokens seguros de uso único, respostas não enumeráveis e retorno ao login normal, sem autenticação automática.
- [Rails — ActiveSupport::MessageEncryptor](https://api.rubyonrails.org/classes/ActiveSupport/MessageEncryptor.html): criptografia autenticada, chave derivada, finalidade e expiração para a cópia recuperável do segredo.

Essas fontes não provam execução, não substituem o contrato delegado e não aprovam todos os números operacionais. Conferir as APIs na versão fixada do Rails antes de codificar. Nenhuma API, SMTP, conta, migration ou recuperação é declarada testada por esta atualização.
