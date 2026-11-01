# Tarefas: primeiro acesso controlado

**Estado:** plano e implementação autorizados na issue #16. PA01/PA02 e checkpoint após PA00–PA02 aprovados em R02/R03. PA03.A–C implementadas e verificadas tecnicamente, aguardando revisão humana R04; PA04–PA15 não concluídas. A [spec](../SPEC-primeiro-acesso.md#decisões-de-pa00) é a fonte normativa; deploy permanece não autorizado.

## Execução autorizada — issue #16

O solicitante autorizou implementação e criação da [issue #16](https://github.com/smcruzfilipe/advocaciaonline/issues/16), com [plano/handoff publicado](https://github.com/smcruzfilipe/advocaciaonline/issues/16#issuecomment-6554202739). As quatro fases e a exceção de publicação draft após PA12 constam no [plano](plan-primeiro-acesso.md#autorização-de-implementação-e-pipeline). As menções históricas a planejamento sem execução descrevem PA00; não cancelam a autorização atual. R02–R18 e checkpoints humanos permanecem obrigatórios.

O solicitante aprovou PA01.A–B (“pa01 a-b ta aprovado”) e depois PA02.A/B1/B2 com o checkpoint após PA00–PA02 (“aprovado”), concluindo R02/R03 e liberando somente PA03.A–C. R04 e checkpoints posteriores não estão aprovados. A branch continua interna, sem PR antes de PA12.

PA01.B inclui também `apps/backend/test/services/password_reset_mailer_test.rb`: a regressão agregada encontrou dependência de ordem no carregamento lazy de Mail e interceptação da inicialização padrão pelo stub SMTP. A folha passa a três arquivos funcionais (teste de provisionamento, teste de mailer, README) mais rastreio. Corrigir isolamento de carregamento sem mudar validação/TLS/assertions; verificar mailer isolado e suíte agregada.

## Regras de execução futura e rastreio

- Destinos exclusivos deste planejamento: `tasks/plan-primeiro-acesso.md` e `tasks/todo-primeiro-acesso.md`. Não substituir, encerrar ou mover o trabalho aberto em `tasks/plan.md`, `tasks/todo.md` ou `tasks/agenda/`.
- IDs canônicos PA00–PA15, sua ordem e suas dependências são estáveis. Letras nas unidades abaixo são apenas subdivisões internas de um PA, não novos IDs canônicos. Um PA subdividido é agregador: somente suas folhas são executáveis, cada qual com escopo próprio; concluir uma folha não conclui o PA.
- Cada folha admite **até cinco arquivos, incluindo este checklist para rastreio**. Portanto, cada lista abaixo contém no máximo quatro arquivos funcionais; `tasks/todo-primeiro-acesso.md` é sempre o quinto arquivo implícito, ou menos. O total de um agregador pode exceder cinco, nunca o de uma folha. Documentação, testes e configuração contam. Se aparecer outro arquivo necessário, subdividir e registrar sua responsabilidade **antes** de executar; não omitir superfícies nem esconder arquivos em globs.
- Caminhos existentes foram identificados no repositório. Caminhos marcados **novo proposto** não existem por força deste documento, não fixam arquitetura nem autorizam sua criação: ratificar nomes, localização e timestamps de migrations após PA00 e antes da respectiva implementação. Migrations futuras são incrementais; não reescrever migrations históricas já aplicadas para simular cutover.
- Toda folha ocorre futuramente em branch não publicada, com teste focado e smoke interno; não expor uma API intermediária, cadastro público residual ou bypass para tornar a fatia demonstrável. Frontend, backend e migrations só podem ser liberados juntos após validação de PA00, autorização própria de implementação e validação integrada. Os checkpoints exigem revisão humana; a aprovação do plano já registrada não os dispensa.
- Reusar Rails/Next/PostgreSQL, autenticação, sessão, senha/TOTP, recuperação, SMTP e perfil existentes. `/admin` vive no frontend atual, com login/sessão comuns e capacidade administrativa server-side; não criar outro app, cookie, stack de identidade, fila ou serviço. Não presumir novas dependências, integração automatizada WhatsApp, contas demo ou deploy.
- Toda variável criada/alterada exige atualização de `README.md` **na mesma mudança**, com nome exato, default ou `Nenhum`, obrigatoriedade, finalidade e fornecimento sem segredos. PA14 consolida a documentação, não adia essa obrigação. Repartir a folha se o README exceder seu teto.
- Mudança de contrato de registro, proveniência do e-mail ou autorização para tenant exige migrar **helpers, fixtures, callers e testes realmente afetados no mesmo conjunto que altera esse contrato**, no primeiro PA que os invalidaria. PA13 confere o resultado; não é prazo para restaurar compatibilidade. Não mudar expectativas incidentais, suprimir cobertura, conceder autorização por default, criar bypass ou seguir com árvore sabidamente incompatível para alcançar o próximo PA.
- Antes da mudança, inventariar os consumidores enumerados em PA13 A–H e os encontrados por busca: caminho exato, operação/estado usado, contrato que o afeta, primeiro PA/folha responsável e teste/smoke; para os demais, registrar **intencionalmente inalterado**, com motivo. A superfície depende das decisões de PA00: a enumeração é cobertura obrigatória de análise, não alegação de que todo arquivo precisa mudar. Materializar previamente as subfolhas necessárias, cada uma com até quatro arquivos funcionais explícitos mais checklist, aceite, teste focado e smoke; não executar um inventário genérico como se fosse folha de implementação.
- Preparação antecipada só pode deixar callers funcionais sob o contrato vigente, com intenção explícita de titular liberado, membro verificado ou conta legada quando pertinente. A troca efetiva de chamadas/estados ocorre junto do contrato que a exige. Se a sequência não puder manter cada folha funcional e dentro do teto, subdividir o contrato e registrar a nova sequência antes de executar, sem shims públicos nem adiamento para PA13. Cada migração tem um único responsável; outras folhas apenas a referenciam.
- Preservar contas existentes, isolamento/RLS, autorização por tenant, senha e TOTP. Convite administrativo autoriza cadastro, **não prova posse da caixa postal**; não adicionar confirmação extra de e-mail ao advogado. Equipe nova precisa de convite válido para criar conta, confirmar seu e-mail e autenticar com TOTP; isso não autoriza tenant próprio.
- Referências `C1`–`C8` abaixo correspondem, na ordem, aos oito critérios de aceite da spec. As Decisões de PA00 também são requisitos; este checklist resume e referencia a fonte normativa, sem reabrir escolhas delegadas.

## Verificações propostas, não executadas

Nenhum teste, build, lint, formatador, smoke, gate ou container foi executado por este planejamento. Os comandos abaixo são referências para execução futura autorizada; não constituem evidência nem instrução para usar o ambiente persistente atual.

### Pré-condições obrigatórias

1. PostgreSQL **descartável**, sem dados reais, com as roles do CI provisionadas por `apps/backend/db/provision.sql`, `provision_despachante.sql` e `provision_processador.sql`; migrations aplicadas pela role migrator. Nunca executar a suíte contra banco persistente, local de uso real ou produção: há testes que modificam dados e preparam/removem fixtures administrativamente.
2. Imagem de testes construída com a versão autorizada da branch, rede interna `advocacia-ci` e banco `advocacia_test`, conforme `.github/workflows/backend.yml`. Não presumir que esses recursos existam. Preparação/remoção de recursos descartáveis depende de autorização própria; nenhum comando destrutivo sobre recursos persistentes é proposto aqui.
3. API usa `advocacia_runtime`, sem propriedade das tabelas, superuser ou BYPASSRLS; migrator não é fornecida à API de runtime. URLs de despachante/processador são exclusivas dos consumidores/testes correspondentes. Containers e processos, inclusive PostgreSQL e SMTP de teste, executam não root; não contornar regras do `AGENTS.md`.
4. `APP_ORIGIN=https://example.test`; `AUTH_INGRESS_SECRET` e `SECRET_KEY_BASE` de teste fornecidos por ambiente protegido, sem imprimir valores. Web, API e navegador do smoke apontam exclusivamente para esse ambiente sintético. SMTP controlado, STARTTLS obrigatório, certificado de teste confiado apenas no ambiente descartável e nenhum destinatário real.
5. Corridas usam dados commitados, conexões/contextos independentes e barreiras explícitas; não compartilhar transação que esconda a concorrência, nem usar sleeps como oráculo. Registrar falhas reais dos workers, estado final e limpeza dos recursos sintéticos.

### Notação dos comandos focados

**`B <arquivos>`**, usada nas tarefas, significa o seguinte comando existente de Rails/Minitest com a seleção dos arquivos indicados, no ambiente descartável preparado acima. Não é um script ou alias novo do projeto:

```bash
docker run --rm --network advocacia-ci \
  -e RAILS_ENV=test \
  -e DATABASE_URL=postgresql://advocacia_runtime@advocacia-ci-db/advocacia_test \
  -e MIGRATION_DATABASE_URL=postgresql://advocacia_migrator@advocacia-ci-db/advocacia_test \
  -e DESPACHANTE_DATABASE_URL=postgresql://advocacia_despachante@advocacia-ci-db/advocacia_test \
  -e PROCESSADOR_DATABASE_URL=postgresql://advocacia_processador@advocacia-ci-db/advocacia_test \
  -e APP_ORIGIN=https://example.test \
  -e AUTH_INGRESS_SECRET -e SECRET_KEY_BASE \
  advocacia-ci:test ruby bin/rails test <arquivos relativos a apps/backend/>
```

Para testes novos, o comando é **condicionado à criação do teste**, com nomes ratificados antes de executar. Testes específicos que precisem da URL administrativa do processador devem seguir seu runner/CI existente, exclusivamente no banco descartável, sem acrescentá-la ao runtime web.

**`W <arquivo>`** significa `node --test <arquivo relativo a apps/web/>`, com diretório de trabalho `apps/web/` em container Node 24 não root de desenvolvimento/teste, dependências do lockfile e ambiente descartável acima. É a seleção focada do runner existente `npm test`/`node --test`; não executar no runtime standalone, que não contém npm/testes. Os comandos de referência da spec `docker exec advocacia-web npm test`, `npm run lint`, `npm run typecheck` e `npm run build` pressupõem container de desenvolvimento preparado e isolado; o nome sozinho não comprova essa condição. `npm run format:check` é o gate existente de formatação, não formatação automática.

Para UI sem teste automatizado existente, o teste focado é um cenário de navegador real descrito na tarefa; caso seja necessário teste permanente novo, fixar arquivo/runner e atualizar a folha antes de implementar. Não inventar uma suíte de componentes ou aceitar teste que apenas confira texto, wiring ou mocks como prova do comportamento. Smoke sempre exercita o caminho funcional contra o servidor real de teste.

## Ordem e dependências canônicas

| ID | Trabalho | Dependências exatas |
|---|---|---|
| PA00 | Decisões e validação documental | Nenhuma |
| PA01 | Provisionamento e autorização da administradora | PA00 |
| PA02 | Sessão comum e proteção administrativa | PA01 |
| PA03 | Destino administrativo no login comum | PA02 |
| PA04 | Persistência/ciclo do convite do advogado | PA00 |
| PA05 | Emissão e acesso ao link servidor | PA02, PA04 |
| PA06 | Envio SMTP e falhas | PA05 |
| PA07 | UI para gerar/enviar/copiar | PA03, PA05, PA06 |
| PA08 | Cadastro de equipe convidada mantendo verificação e TOTP | PA00 |
| PA09 | Resgate de convite/credencial sem afirmar posse de email | PA04, PA08 |
| PA10 | Exigir autorização administrativa para tenant próprio | PA09 |
| PA11 | UI link e onboarding advogado | PA09, PA10 |
| PA12 | Cutover completo interface/API | PA07, PA08, PA09, PA10, PA11 |
| PA13 | Consolidação/conferência de fixtures e smoke CI | PA12 |
| PA14 | Documentação operacional/contratos/envs | PA12 |
| PA15 | Validação integrada/evidências | PA13, PA14 |

## Cadência obrigatória de revisão por folhas

O solicitante aprovou expressamente, de forma global, a continuidade one-shot e todas as revisões humanas intermediárias: não interromper entre R05–R18 ou checkpoints para pedir novamente essa aprovação. As revisões técnicas, os aceites, testes focados e smokes continuam obrigatórios; marcar resultados técnicos somente após observá-los. Permanecem os limites explícitos de segurança, ausência de deploy e uso exclusivo de ambientes descartáveis.

- [x] R01: PA00.A–B — integração e revisão documental concluídas por delegação; sem liberação de execução da aplicação.
- [x] R02: PA01.A–B — aprovadas expressamente pelo solicitante após apresentação do código e das evidências de PA01.
- [x] R03: PA02.A e PA02.B1–B2 — três folhas aprovadas expressamente pelo solicitante, junto do checkpoint após PA00–PA02.
- [x] R04: PA03.A–C — aprovadas expressamente pelo solicitante; liberado o próximo grupo PA04/PA05, sem ampliar escopo.
- [x] R05: PA04 e PA05.A–B — três folhas; revisão/checkpoint solicitados no [handoff da issue16](https://github.com/smcruzfilipe/advocaciaonline/issues/16#issuecomment-6561506780).
- [x] R06: PA06.A–B e PA07 — três folhas.
- [x] R07: PA08.P e PA08.A — duas folhas; conferir preparação e troca efetiva de registro, incluindo consumidores inventariados.
- [x] R08: PA08.B–D — três folhas.
- [x] R09: PA09.P e PA09.A — duas folhas; conferir distinção de prova de caixa sem callers incompatíveis.
- [x] R10: PA09.B–C — duas folhas.
- [x] R11: PA10.P e PA10.A–B — três folhas; conferir autorização explícita e regressões de titular/membro.
- [x] R12: PA11.A–C — três folhas.
- [x] R13: PA12.A–C — três folhas; nenhuma migração necessária a caller fica para PA13.
- [x] R14: PA13.A–C — três folhas de conferência.
- [x] R15: PA13.D–F — três folhas de conferência.
- [x] R16: PA13.G–H — duas folhas de conferência.
- [x] R17: PA14.A–B — duas folhas.
- [x] R18: PA15.A–C — três folhas.

## PA00 — Decisões e validação documental

- [x] Concluir PA00 documentalmente.

**Descrição:** decisões escolhidas por delegação do solicitante integradas no plano e na [fonte normativa](../SPEC-primeiro-acesso.md#decisões-de-pa00). Q1–Q6 não exigem nova rodada de preferências; escolhas de projeto não são comportamento implementado. PA00 concluída somente como entrega documental.

**Decisões registradas:** conta administrativa única com autenticação/sessão existentes e recuperação por senha+código somente para reinscrição de TOTP; orientação textual sem contato fictício; convite único ativo por e-mail e substituição explícita; preservação de contas/tenants/sessões válidas e invalidação de tokens públicos pendentes; endereço de login distinto de verificação real e de liberação de titularidade; expurgo sem histórico/serviço novo. O contrato completo, os limites de recuperação e as ambiguidades resolvidas pertencem à spec, não a uma segunda tabela neste checklist.

**Critérios verificáveis:**
- [x] Q1–Q6 e ambiguidades têm decisão explícita na fonte normativa, distinguindo aprovações diretas anteriores, recomendações delegadas, código existente e trabalho futuro; plano e contratos consumidores não mantêm escolhas decididas como pendentes.
- [x] Transições seguem a fonte normativa: preparação de conta nova não permite ativação/reset; senha e primeiro TOTP válidos precedem conta, liberação, consumo e sessão, com proteção contra replay. Preexistente usa sessão da mesma identidade; perfil/tenant permanecem separados e `claim_tenant` exige liberação. Equipe preserva prova real de caixa.
- [x] Revisão independente e validação documental confirmaram consistência, rastreio C1–C8, dependências e limites das folhas. DTOs, nomes novos e timestamps serão ratificados antes da respectiva implementação; não há autorização implícita de código ou publicação.

**Dependências:** nenhuma. **Rastreio:** Decisões de PA00 Q1–Q6 e ambiguidades; escopo/segurança; C1–C8.

**Teste focado:** revisão documental sem comando de software: conferir resultados previstos para conta existente, link válido/vencido, falha antes/depois do consumo e membro tentando criar tenant. A marcação depende da validação do orquestrador.
**Smoke comportamental proposto:** walkthrough humano dos dois canais, recuperação e retomada do advogado e confirmação da equipe; descreve comportamento futuro, não execução ou implementação observada.

**Evidência documental:** revisão dos cenários de abandono, reset antes do primeiro TOTP, reemissão, conta existente e restauração. Corrigidos dois riscos do desenho: ativação antes do TOTP e revalidação de convite restaurado. Validação estrutural dos seis documentos conferiu links/âncora, oito critérios, 16 IDs de tarefa, 25 arestas de dependência, limites por folha e sintaxe dos quatro blocos shell. Nenhum comando de aplicação, teste, migration, container ou smoke funcional foi executado. As folhas A e B abaixo estão concluídas apenas documentalmente.

**Folhas obrigatórias; executar A antes de B:**
- **A — Decisões e plano:** `SPEC-primeiro-acesso.md`; `tasks/plan-primeiro-acesso.md`. Aceite: seis respostas e transições sem contradição. Teste/smoke: revisão e walkthrough acima. **Tamanho S: 2 funcionais + rastreio = 3.**
- **B — Contratos consumidores atuais:** `SPEC-identidade.md`; `docs/arquitetura.md`; `apps/web/SPEC-web.md`. Aceite: remover somente notas futuras introduzidas nesta conversa e preservar contratos atuais; desenho não implementado fica na spec de primeiro acesso e nestes planos separados, sem espalhar contratos novos. Teste/smoke: revisão documental de escopo com A. **Tamanho M: 3 + rastreio = 4.**

### Gate inicial — após PA00

- [x] Integração documental validada pelo orquestrador sob a delegação do solicitante. Plano, decisões e contratos estão coerentes; aprovação documental não autoriza implementação parcial nem libera gates operacionais.

## PA01 — Provisionamento e autorização da administradora

- [x] Concluir PA01; revisão humana R02 aprovada expressamente pelo solicitante.

**Descrição:** provisionar a única conta administrativa por procedimento protegido no mecanismo existente de identidade, sem cadastro público, conta demo, senha padrão ou autoelevação de titular/equipe. Estender senha/TOTP e recuperação atuais; não criar autenticação paralela, comando novo só para encaminhamento ou configuração desnecessária.

**Critérios verificáveis:**
- [x] Somente procedimento protegido provisiona a conta e sua capacidade; operador fornece e-mail/senha reais sem defaults secretos, valores inventados ou exposição em código/log/saída. Cliente e papel de tenant não concedem administração.
- [x] Códigos de recuperação de uso único são exibidos na inscrição/troca do autenticador e guardados somente como hashes; senha+código consumido atomicamente habilitam apenas reinscrição de TOTP. Novo autenticador validado precede acesso administrativo; troca invalida códigos antigos/sessões/desafios.
- [x] Reset reutiliza e-mail, prazo de 30 minutos e uso único existentes, preservando MFA e sem login automático. Sem TOTP nem códigos, não há recuperação pelos fluxos normais, bypass por e-mail/suporte ou novo fluxo exclusivamente de servidor para MFA.

**Dependências:** PA00. **Rastreio:** Q1; C1, C8.
**Teste focado:** `B test/integration/platform_admin_authorization_test.rb test/integration/platform_admin_provisioning_test.rb`, condicionado aos testes novos.
**Smoke comportamental:** provisionar identidade sintética e conferir capacidade server-side; conta comum não administra. Senha+código abrem apenas reinscrição; código reutilizado e acesso administrativo antes de validar novo TOTP são negados. Reset de senha mantém o fator.

**Folhas; B depende de A:**
- **A — Capacidade e fatores no mecanismo comum:** `apps/backend/db/migrate/20261102000000_create_platform_administration.rb` (**novo proposto**); `apps/backend/app/services/password_authentication.rb`; `apps/backend/test/integration/platform_admin_authorization_test.rb` (**novo proposto**). Aceite: capacidade restrita, hashes/uso único e reinscrição conforme Q1, sem segunda base de identidade. Teste: `B test/integration/platform_admin_authorization_test.rb`; smoke: privilégios e recuperação no mecanismo real, com senha/código incorretos e repetidos. **Tamanho M: 3 + rastreio = 4.**
- **B — Procedimento operacional protegido:** `apps/backend/test/integration/platform_admin_provisioning_test.rb` (**novo proposto**); `README.md`. Aceite: documentar/testar provisionamento protegido usando as capacidades Rails existentes, sem novo executável por conveniência, default secreto ou recuperação de MFA por bypass operacional. Teste: `B test/integration/platform_admin_provisioning_test.rb`; smoke futuro: provisionar conta sintética e negar atribuição fora do procedimento. **Tamanho S: 2 + rastreio = 3.**

**Evidência PA01.A–B:** imagem `advocacia-pa16:review`, PostgreSQL 18.6 descartável na rede interna `advocacia-pa16`, banco novo por execução `advocacia_pa01_final`, roles runtime/migrator/despachante/processador segregadas. `ruby bin/migrate` aplicou todas as migrations, incluindo a nova, sem alterar banco persistente. `ruby bin/rails test` nessa imagem, com os dois testes ajustados montados somente leitura, executou **492 testes, 10.929 assertions, zero falhas, erros ou skips**, seed 32198. Foco anterior em autorização/provisionamento/reset/sessão: **32 testes, 312 assertions**, sem falhas/erros/skips. Mailer isolado após correção de carregamento lazy: **3 testes, 21 assertions**, sem falhas/erros/skips. Regressões de expiração/inscrição inicial falharam na versão anterior: **2 testes, 2 falhas**; passaram com a correção.

**Smoke PA01:** runner Rails com PostgreSQL real e identidade sintética executou transação protegida de provisionamento, HTTP senha/primeiro TOTP, negação de sessão antes do fator, revogação da sessão ao iniciar reinscrição, recusa de replay/código incorreto e confirmação do novo TOTP com rotação de códigos sem sessão automática; processo Rails UID 1000 e PostgreSQL UID 70. Fixture removida pelo próprio cenário; nenhum destinatário/credencial real, SMTP, UI administrativa ou endpoint de recuperação futuro foi declarado validado. Receita operacional: `ruby -c` retornou `Syntax OK`. Imagem de teste medida em 372.984.208 bytes (Ruby Alpine existente, dependências de testes separadas do runtime); PostgreSQL oficial em 429.615.951 bytes, iniciado efetivamente não root. O resultado integral e o pedido de R02 são registrados na issue #16.

**Falhas tratadas:** revisão corrigiu bloqueio permanente por recovery vencido/reset, reinscrição inicial e risco de eco no console. A primeira agregação encontrou inicialização lazy de Mail interceptada por stub; setup corrigido sem enfraquecer assertions/TLS/validação. Reexecução em banco já usado acumulou vínculos da fixture fixa de equipe (esperado 2, observado 4): resultado recusado; nova execução usou banco vazio, como o CI, sem alterar assertion nem contrato. A suíte em banco vazio acima é a evidência válida; a aprovação humana R02 foi registrada separadamente na autorização desta execução.


## PA02 — Sessão comum e proteção administrativa

- [x] Concluir PA02; R03 e checkpoint após PA00–PA02 aprovados expressamente pelo solicitante.

**Descrição:** reusar login, TOTP, consulta de sessão, saída e reset existentes; transportar capacidade administrativa reconhecida e exigida pelo servidor. A recuperação de MFA administrativa é extensão restrita à reinscrição, não outro login/cookie/sistema de sessão.

**Critérios verificáveis:**
- [x] A sessão comum só nasce após senha/TOTP; expiração, revogação/logout e reset preservam o contrato atual. Senha+código não concedem sessão administrativa nem emissão de convites antes da validação do novo TOTP.
- [x] Toda operação administrativa exige sessão válida + capacidade server-side + proteção de origem/CSRF/ingresso e limitação existentes; negar anônimo, titular/membro sem capacidade, sessão vencida/revogada e origem/CSRF indevidos, inclusive por API direta.
- [x] HTTP e respostas mínimas seguem as Decisões de PA00 e o envelope existente; recuperação/reinscrição não vira bypass de fatores. Não introduzir limites arbitrários, sessão paralela ou confiança em flag de cliente/relay.

**Dependências:** PA01. **Rastreio:** Q1; C1, C8; segurança da spec.
**Teste focado:** `B test/integration/platform_admin_sessions_http_test.rb`, condicionado.
**Smoke comportamental:** login comum de identidade administrativa, consulta e operação protegida, logout e cookie antigo; comparar com anônimo/titular/membro. Exercitar reinscrição por código e reset por e-mail sem acesso prévio à confirmação do novo autenticador.

**Folhas; B depende de A:**
- **A — Extensão do protocolo de autenticação existente:** `apps/backend/app/controllers/password_auth_controller.rb`; `apps/backend/app/services/password_authentication.rb`; `apps/backend/config/routes.rb`; `apps/backend/test/integration/platform_admin_sessions_http_test.rb` (**novo proposto**). Aceite/teste/smoke: login/sessão/reset comuns e recuperação administrativa limitada conforme critérios acima; não criar controlador/stack paralelo de sessões. **Tamanho M: 4 + rastreio = 5.**
- **B — Capacidade nas fronteiras existentes:** `apps/backend/app/controllers/application_controller.rb`; `apps/backend/app/services/identity_store.rb`; `apps/backend/test/integration/platform_admin_authorization_test.rb` (**proposto em PA01**). Aceite: servidor resolve/exige capacidade com sessão comum sem classe base administrativa, helper genérico ou configuração nova. Teste: `B test/integration/platform_admin_authorization_test.rb test/integration/platform_admin_sessions_http_test.rb`; smoke: chamadas diretas com/sem capacidade e proteção de segredos. **Tamanho M: 3 + rastreio = 4.**

**Ratificação antes de PA02:** A mantém seus quatro arquivos funcionais. B é agregador subdividido: **B1** usa `application_controller.rb`, `identity_store.rb`, `platform_admin_authorization_test.rb` e `sessions_controller.rb` (quatro funcionais mais checklist) para guarda administrativa e capacidade consultável na sessão comum; **B2** usa `README.md` e `SPEC-primeiro-acesso.md` (dois funcionais mais checklist) para contratos HTTP e estado realmente implementados. Propriedade única dos arquivos compartilhados; teste HTTP novo pertence a A. R03 revisa as três folhas antes do checkpoint C1 e de PA03.

**Contrato PA02 ratificado:** recuperação `POST /api/admin/auth/recovery` recebe `email`, `password`, `recovery_code` e retorna `challenge`, `secret`, `otpauth_uri` sem sessão; confirmação `POST /api/admin/auth/recovery/confirm` recebe `token` (o challenge retornado) e `code`, retornando `recovery_codes` somente após commit, sem sessão. O nome HTTP `token` reutiliza a filtragem de segredos vigente, sem expor challenge nos logs. Entrada inválida/fatores incorretos usam a mesma indisponibilidade pública `422`. Reusar origem/JSON/ingresso e limites IP/conta/challenge; com sessão válida, exigir também CSRF. `platform_admin` boolean é resolvido no servidor para login TOTP/sessão comum, nunca aceito como concessão do cliente. `IdentityStore.platform_admin?`/`require_platform_admin!` e `ApplicationController.require_platform_administration`/`authorize_platform_administration!` são as fronteiras mínimas para operações futuras de PA05, sem rota administrativa fictícia, cookie ou base de controller nova. Teste usa rota de prova apenas no ambiente de teste para exercitar a guarda.

**Evidência PA02.A/B1/B2:** `docker build --target test -t advocacia-pa02:test apps/backend` concluiu. Na imagem anterior, os novos cenários produziram **28 testes, 154 assertions, 6 falhas e 12 erros**, demonstrando ausência das rotas, capacidade e guarda. Após implementação, foco em sessão/guarda/provisionamento/reset: `ruby bin/rails test test/integration/platform_admin_sessions_http_test.rb test/integration/platform_admin_authorization_test.rb test/integration/platform_admin_provisioning_test.rb test/integration/password_reset_test.rb test/integration/password_reset_http_test.rb`, **48 testes, 805 assertions**, sem falhas/erros/skips. Removida depois uma assertion incidental de coleção não vazia; a árvore final foi verificada por `ruby bin/rails test` em banco novo `advocacia_pa02_final`: **511 testes, 11.433 assertions, zero falhas, erros ou skips**. `ruby bin/migrate` aplicado pela role migrator; API e suíte com runtime segregada, PostgreSQL descartável.

**Smoke PA02:** servidor Puma real na rede Docker interna, identidade sintética e HTTP por socket verificaram primeiro login senha/TOTP, capacidade administrativa sem tenant, negação de CSRF, recuperação/reinscrição sem sessão, TOTP incorreto e replay recusados, novo login, logout/cookie antigo e recusa de promoção por payload cliente. Runner UID 1000; API recebeu somente a URL runtime, sem a credencial migrator. O ingresso HTTPS foi representado pelo cabeçalho encaminhado em uma rede isolada; não se afirma teste de TLS, navegador, SMTP ou UI administrativa. A prova inicial usou o segredo anterior ao setup e omitiu o protocolo HTTPS encaminhado: o Rails corretamente não emitiu cookie Secure e retornou `401`; o cenário foi corrigido, sem enfraquecer cookie/TOTP, e passou integralmente.

**Revisão PA02 e mutação:** duas revisões independentes de segurança e fronteiras não identificaram achados concretos. Inverter temporariamente a condição de capacidade em `IdentityStore.require_platform_admin!` fez `ruby bin/rails test test/integration/platform_admin_authorization_test.rb --name /tenant_owner_and_member_roles/` falhar (**1 teste, 11 assertions, 1 falha**: autorização indevida detectada). Condição restaurada e comando atualizado para `--include /tenant_owner_and_member_roles/`: **1 teste, 18 assertions, zero falhas/erros/skips**. A guarda foi exercitada em rota exclusiva da suíte; não existe endpoint fictício de administração em produção. Convites e superfícies web seguem pertencendo a PA03/PA05 e posteriores; os consumidores web atuais ignoram campos adicionais da sessão e permanecem intencionalmente inalterados. Nenhuma dependência ou variável de ambiente foi criada/alterada.

**Handoff R03 concluído:** o solicitante aprovou expressamente PA02.A/B1/B2 e o checkpoint após PA00–PA02; registro da liberação restrita de PA03 no [comentário6560284606](https://github.com/smcruzfilipe/advocaciaonline/issues/16#issuecomment-6560284606). Isso não aprova R04 nem etapas posteriores. Publicação somente após PA12.


### Checkpoint — após PA00–PA02

- [x] Evidências de provisionamento/recuperação, fatores, autorização direta e segredo de sessão revisadas; solicitante respondeu “aprovado” ao pedido R03 e checkpoint após PA00–PA02, liberando somente o próximo grupo PA03.A–C.

## PA03 — Destino administrativo no login comum

- [x] Concluir PA03 tecnicamente; revisão humana R04 permanece pendente.

**Descrição:** acrescentar destino `/admin` ao login e à sessão existentes na mesma aplicação web. Reusar telas/fatores/reset comuns, exibindo recuperação por senha+código somente para reinscrição administrativa; não criar `/admin/login`, componente de login separado ou cookie paralelo.

**Critérios verificáveis:**
- [x] Login comum autentica a administradora com senha/TOTP e só entra em `/admin` após autorização server-side; recuperação por código exige confirmar novo TOTP e reset por e-mail não dispensa MFA nem autentica automaticamente.
- [x] Abrir rota administrativa como anônimo/titular/membro sem capacidade não revela dados; relay mantém cookies e envelope comuns sem ampliar origens/caminhos/confiança de IP indiscriminadamente nem duplicar sessão.
- [x] Estados reais de erro/carregamento/expiração/saída, teclado, foco, rótulos e viewport de 320 px funcionam; shell/provider distinguem destino administrativo, onboarding e equipe, sem captura indevida de tokens entre abas.

**Dependências:** PA02. **Rastreio:** Q1; C1, C8; mesma aplicação web.
**Teste focado:** `W src/app/api/transport.test.mjs` e `W src/lib/api.test.mjs`; navegador real para login/recuperação/destino, sem runner novo presumido.
**Smoke comportamental:** login/logout comuns com conta administrativa sintética, acesso direto a `/admin` como anônimo/membro/titular e recuperação com código/reset antes e depois da confirmação do TOTP.

**Folhas; B após A, C após B:**
- **A — Relay dos endpoints administrativos:** `apps/web/src/app/api/transport.ts`; `apps/web/src/app/api/[...path]/route.ts`; `apps/web/src/app/api/transport.test.mjs`. Aceite: allowlist e proteção HTTP futuras com sessão/cookies comuns, sem autorização somente no relay; `W src/app/api/transport.test.mjs`. Smoke: mesma operação por relay e API direta é autorizada/negada pelo servidor. **Tamanho M: 3 + rastreio = 4.**
- **B — Login comum e destino autorizado:** `apps/web/src/components/login-screen.tsx`; `apps/web/src/app/admin/page.tsx` (**novo proposto**); `apps/web/src/lib/api.ts`; `apps/web/src/lib/api.test.mjs`. Aceite: reusar senha/TOTP/reset e acrescentar estados de reinscrição por código sem outro login; `W src/lib/api.test.mjs` e navegador. Smoke: entrada, senha/fator incorreto, recuperação e destino administrativo negado à conta sem capacidade. **Tamanho M: 4 + rastreio = 5.**
- **C — Composição na mesma aplicação:** `apps/web/src/app/layout.tsx`; `apps/web/src/components/application-shell.tsx`; `apps/web/src/components/session-provider.tsx`; `apps/web/src/app/admin/layout.tsx` (**novo proposto**). Aceite: mesma sessão e guarda server-side, sem tratar `/admin` como onboarding/equipe. Teste focado: navegador com identidade administrativa e comum; smoke: navegação e abas sem troca indevida de identidade/privilégio. **Tamanho M: 4 + rastreio = 5.**

**Ratificação antes de PA03:** A libera somente os dois endpoints de recuperação já implementados, reutilizando origem/ingresso/IP/cookies, sem antecipar convites PA05. B mantém seus quatro arquivos; senha+código prepara o novo TOTP, confirmação exibe novos códigos sem login, e a volta exige senha/TOTP comuns. C usa `application-shell.tsx`, `session-provider.tsx` e `README.md` (três funcionais mais rastreio). Root layout permanece intencionalmente inalterado porque já compõe o único provider/shell; não criar layout administrativo pass-through. A própria página `/admin` verifica sessão/capacidade diretamente no servidor antes de renderizar: a documentação oficial Next16 alerta que layouts não impedem execução/RSC de páginas e não revalidam em toda navegação. APIs continuam autorizando junto da operação, não no relay/cliente. Destino administrativo não depende de tenant e precede convite de equipe pendente; fragmentos em `/admin` não são capturados como convite de equipe. Página fornece destino autorizado real e estado de acesso, sem simular convites de PA07. Reusar tokens/controles existentes, manter segredos somente em memória e limpar ao voltar/avançar; não alterar dependências, env, SMTP/reset ou cutover. R04 exige nova aprovação humana após A–C.

**Evidência PA03.A–C:** `npm test` executado por Node24.22.1 em container não root: **44 testes,44 aprovados,zero falhas/cancelados/skips**. `npm run typecheck`, `npm run lint` e `npm run format:check` aprovados; `docker build -t advocacia-pa03:web apps/web` concluiu build standalone Next16.4.3/TypeScript. `npm audit --omit=dev`: zero vulnerabilidades; 15 moderadas herdadas na árvore completa de desenvolvimento, sem atualização forçada. Prova anterior do relay falhou (rota recovery não permitida); teste de troca de conta falhou antes do preflight e teste de fila falhou antes de capturar contexto fora do lock. Ambos passaram no agregado. Primeiro lint recusou `<a href="/">`; corrigido para Link e reexecutados somente lint/formatação/build afetados.

**Smoke real PA03:** Rails/Puma, Next standalone, nginx HTTPS e PostgreSQL18.6 descartável com roles segregadas, banco exclusivo `advocacia_pa03`. HTTP por socket verificou envelope idêntico ao backend, origem/método/ingresso, CSRF atual, negação de owner/member, capacidade administrativa sem tenant e ausência de CSRF no RSC. Chromium149 **headless** em container descartável (sem navegador gráfico no host) verificou senha/TOTP incorretos, login administrativo, recuperação por código, TOTP incorreto, expiração do desafio, códigos novos sem sessão, novo login obrigatório, logout/replay do cookie antigo via HTTPS com certificado verificado, código consumido e sessão expirada recusados. Verificados papel administrativo/profissional na mesma identidade, fragmentos sem captura de equipe, zero consultas de perfil na área administrativa, menu/teclado/foco a320px e nenhum overflow a320/768/1024/1440px. Em targets distintos com cookies compartilhados, foco controlado no headless reconheceu nova conta mantendo códigos até confirmação; falha real de rede também preservou os códigos. Sem SMTP ou dados reais; reset existente intencionalmente inalterado e coberto em PA02.

**Revisão/limpeza PA03:** cinco achados concretos corrigidos: perda de códigos em revalidação/troca de conta, contexto lido depois do lock, regressão de acesso profissional da administradora, herança de fragmento no redirect e controles de tenant na área administrativa. Revisores conferiram correções sem novos achados; não substitui R04. Limites do driver headless (daemon ausente, aliases CDP no mesmo target e waiters) foram contornados com Chromium descartável/CDP explícito, targets realmente distintos e observação direta, sem mudar proteções do produto. Fixtures próprias removidas, containers da prova encerrados/removidos, rede frontal e imagem exclusiva do navegador removidas, chaves TLS descartadas. Web/ingresso observados UID/GID1000:1000; imagens303.629.026/72.190.907bytes, bases já vigentes. Nenhuma dependência/env permanente criada.

**Handoff R04:** aguardar aprovação humana explícita das folhas PA03.A–C antes de PA04/PA05. A feature completa, convites e cutover continuam não entregues; branch interna sem PR/push até PA12.

## PA04 — Persistência e ciclo do convite do advogado

- [x] Concluir PA04.

**Descrição:** manter somente convite administrativo ativo por e-mail normalizado, separado de `team_invitations`, conforme Q3/Q6 e ambiguidades decididas. Reusar criptografia Rails: token opaco aleatório de 256 bits, hash para lookup/consumo e cópia cifrada autenticada recuperável apenas enquanto ativo, com finalidade/chave derivada distinta de TOTP e `SECRET_KEY_BASE` existente.

**Critérios verificáveis:**
- [x] Validade absoluta termina em emissão + 24 horas, inclusive no instante exato; abrir/consultar não consome. Um convite ativo por e-mail, reemissão explícita atômica e cópia/reenvio sem prorrogação; titular com tenant recebe conflito, conta desativada não é reativada.
- [x] Remover segredo cifrado/digest e registro terminal ao consumir/substituir/expirar, preservando liberação consumida na identidade. Expurgar expirados nas operações necessárias de listar/emitir/copiar/resgatar pelo padrão existente de `pending_registrations`, sem rake/cron/job/serviço/histórico novo; sem atividade, não prometer prazo físico. Restore invalida todos os convites administrativos restaurados antes da reabertura, preservando identidades/liberações válidas do snapshot.
- [x] Locks/constraints garantem no máximo um consumo concorrente: conta nova só ativa identidade/credencial TOTP confirmada/liberação após primeiro TOTP dentro de 24 horas; conta preexistente vincula após login/TOTP correto. Preparação pendente não ativa conta/liberação/reset, falha faz rollback e challenge não prorroga.

**Dependências:** PA00. **Rastreio:** C3–C5, C8; Q3/Q6 e marco de consumo.
**Teste focado:** `B test/integration/first_access_invitations_test.rb`, condicionado, com relógio controlado e conexões independentes.
**Smoke comportamental:** emitir/abrir sem consumir, testar fronteira exata, substituir e expurgar pelas operações já necessárias; repetir operação sem reviver terminal nem remover liberação consumida. Cenário de restore invalida inclusive convite ainda no prazo antes da reabertura e exige reemissão explícita; sem implementar infraestrutura de backup.
**Arquivos prováveis:** `apps/backend/db/migrate/20261102000001_create_first_access_invitations.rb` (**novo proposto**); `apps/backend/app/services/first_access_invitation_store.rb` (**novo proposto**); `apps/backend/test/integration/first_access_invitations_test.rb` (**novo proposto**).
**Tamanho M: 3 funcionais + rastreio = 4.**

## PA05 — Emissão e acesso ao link no servidor

- [x] Concluir PA05.

**Descrição:** disponibilizar emissão, consulta ativa, recuperação do mesmo link e reemissão explícita somente à sessão comum com capacidade administrativa no servidor. A cópia cifrada ativa de PA04 permite recuperar o segredo original; hash sozinho não o reconstrói. Endpoints futuros seguem as Decisões de PA00, sem manter histórico terminal.

**Critérios verificáveis:**
- [x] Somente administradora autenticada emite/acessa link; validar e-mail, origem, CSRF e autorização em toda chamada, inclusive direta à API/função.
- [x] E-mail associado, prazo e direitos não variam por canal; duplicidade, e-mail existente e reemissão obedecem PA00, sem conceder tenant no ato da emissão.
- [x] Respostas e acesso ao segredo não são cacheados/logados nem expostos a identidade comum; erro não declara emissão que não ocorreu nem invalida silenciosamente convite fora da política.

**Dependências:** PA02, PA04. **Rastreio:** C1, C2, C5, C8.
**Teste focado:** `B test/integration/platform_admin_invitations_test.rb`.
**Smoke comportamental:** emitir e obter link como administradora, repetir via chamada direta sem sessão e com membro, e observar estado real após erro/duplicidade.

**Folhas; B depende de A:**
- **A — Serviço de emissão/acesso:** `apps/backend/app/services/first_access_invitation_store.rb`; `apps/backend/test/services/first_access_invitation_store_test.rb`; `apps/backend/app/services/identity_store.rb`. Aceite: capacidade administrativa server-side, acesso ao mesmo segredo ativo e reemissão explícita, sem bearer em claro persistido; teste `B test/services/first_access_invitation_store_test.rb`; smoke de emissão/recusa no serviço real. A integração SQL de PA04 continua no gate agregado. **Tamanho M: 3 + rastreio = 4.**
- **B — Endpoints administrativos:** `apps/backend/app/controllers/platform_admin_invitations_controller.rb`; `apps/backend/config/routes.rb`; `apps/backend/test/integration/platform_admin_invitations_test.rb`; contrato público no `README.md`. Aceite/teste/smoke: listar, emitir, copiar link ativo e reemitir nos endpoints normativos, usando guarda/sessão comuns; envio SMTP permanece em PA06, conforme ratificação abaixo. **Tamanho M: 4 funcionais + rastreio.**

**Ratificação antes de PA04/PA05:** usar a migration `20261102000001_create_first_access_invitations.rb`, store existente no plano e funções fixas da allowlist IdentityStore. Persistir somente convite ativo (id, e-mail normalizado único, digest, cópia cifrada, emissão/expiração), preparação pendente vinculada e liberação por identidade; nenhum histórico, job, configuração ou infraestrutura nova. O store oferece listar/emitir/link/reemitir/inspecionar/preparar/consultar preparação/consumir. Preparação não cria conta ou sessão; consumo exige sessão comum com TOTP confirmado do mesmo e-mail e grava liberação/elimina convite em uma transação, podendo integrar a transação de conta nova de PA09. PA09 compõe criação de identidade/credencial/sessão e a distinção de e-mail que já lhe pertence; não antecipar o cutover ou afirmar verificação de caixa. Restore usa DELETE protegido das linhas de convite, sem função runtime de manutenção. PA05.A acrescenta teste real do serviço em `test/services/first_access_invitation_store_test.rb`, mantendo no máximo quatro arquivos funcionais; integração SQL pertence a PA04. PA05.B inclui README como quarto funcional, além de controller/routes/teste HTTP. DTOs: listagem `{ invitations: [{ id, email, created_at, expires_at }] }`; emissão/reemissão `201` e metadados, sem segredo; link `200 { link, expires_at }`, com `/primeiro-acesso#token=...`. Somente listar/emitir/link/reemitir são rotas deste grupo; envio SMTP pertence a PA06. Sessão/capacidade são revalidadas no SQL; mutações exigem CSRF/origem/JSON. Leituras recusam origem explicitamente indevida e aceitam origem esperada ou fetch same-origin. Erros seguem 401/403/409/422/404 existentes, sem payload secreto.

**Entrega PA04/PA05 para R05:** persistência e quatro endpoints concluídos. Gate focado `B test/integration/first_access_invitations_test.rb test/services/first_access_invitation_store_test.rb test/integration/platform_admin_invitations_test.rb test/services/verification_mailer_test.rb`: **27 testes, 288 assertions, 0 falhas/erros/skips**. `B` completo em banco vazio: **536 testes, 11.710 assertions, 0 falhas/erros/skips**. HTTP real em runtime de produção não root comprovou senha/TOTP comuns, ausência de tenant administrativo, emissão/cópia/duplicidade/reemissão, negação de acesso, prazo exato e remoção física do segredo expirado; store consumiu convite com sessão MFA da identidade correta e restore protegido preservou essa liberação. `zeitwerk:check` aprovado. O critério compartilhado acima sobre ativação integral de **conta nova** permanece aberto para PA09/C3: não confundir primitivas transacionais comprovadas com o fluxo público ainda previsto. R05 e checkpoint continuam pendentes; nenhuma folha posterior foi liberada.

**Correções do próprio gate:** a indisponibilidade retorna ausência no SQL e vira erro no Ruby após commit, evitando rollback do expurgo. O teste legado `verification_mailer_test.rb` tinha stub global de `Mail::SMTP.new` dependente de ordem, reproduzido com `KeyError(:enable_starttls)`; foi isolado no transporte `Net::SMTP`, preservando TLS, link utilizável e sigilo. Essa correção de um arquivo é independente das folhas funcionais e não altera produção, dependências ou configuração SMTP.

### Checkpoint — após PA03–PA05

- [x] Revisão humana de UI administrativa, fronteira de autorização, estados, segredo, reemissão e limite de 24 horas; comprovar negação direta e separar evidência real de cenários ainda planejados.

## PA06 — Envio SMTP e falhas

- [x] Concluir PA06.

**Descrição:** enviar o convite do advogado pelo SMTP configurado, reutilizando os padrões existentes de normalização, transporte e erro seguro. Não reutilizar assunto/texto de convite de equipe nem criar integração WhatsApp.

**Critérios verificáveis:**
- [x] Mensagem usa destinatário vinculado e link HTTPS correto; STARTTLS é obrigatório, falhas não vazam credenciais/conteúdo e variáveis alteradas estão no README na mesma mudança.
- [x] Falha SMTP é comunicada sem declarar entrega; aceitação pelo SMTP é descrita como aceitação, **não prova recebimento na caixa postal**.
- [x] Emissão persiste antes do SMTP; falha mantém o mesmo convite ativo/copiável e timeout informa resultado de envio desconhecido, sem afirmar entrega. Reenvio explícito não prorroga nem reemite; reemissão é separada, sem retry automático/fila.

**Dependências:** PA05. **Rastreio:** C2, C8; alternativas de canal da spec.
**Teste focado:** `B test/services/first_access_invitation_mailer_test.rb test/integration/platform_admin_invitations_http_test.rb`, condicionado aos testes novos.
**Smoke comportamental:** SMTP controlado com STARTTLS aceita a mensagem e permite ler o link capturado; indisponibilidade/rejeição produz erro e a cópia continua funcional. Não usar destinatário real.

**Folhas; B depende de A:**
- **A — Transporte/mensagem:** `apps/backend/app/services/first_access_invitation_mailer.rb` (**novo proposto**); `apps/backend/test/services/first_access_invitation_mailer_test.rb` (**novo proposto**). Aceite/teste: reutilizar SMTP configurado sem novos parâmetros e preservar sigilo/STARTTLS; `B test/services/first_access_invitation_mailer_test.rb`; smoke no SMTP sintético controlado. Só alterar configuração/README se houver necessidade real, com folha previamente explicitada dentro do teto. **Tamanho S: 2 + rastreio = 3.**
- **B — Resultado do envio:** `apps/backend/app/controllers/platform_admin_invitations_controller.rb` (**proposto em PA05**); `apps/backend/app/services/first_access_invitation_store.rb` (**proposto em PA04**); `apps/backend/test/integration/platform_admin_invitations_http_test.rb` (**proposto em PA05**). Aceite/teste: erro observável sem perder cópia; `B test/integration/platform_admin_invitations_http_test.rb`; smoke rejeição SMTP seguida de acesso ao link por administradora. **Tamanho M: 3 + rastreio = 4.**

## PA07 — UI para gerar, enviar e copiar

- [x] Concluir PA07.

**Descrição:** permitir à administradora informar apenas e-mail e escolher envio ou cópia para compartilhamento manual por WhatsApp. A interface usa estados reais; cópia não pode depender do sucesso SMTP.

**Critérios verificáveis:**
- [x] Geração, prazo e erro vêm do servidor; conta comum não acessa a funcionalidade nem consegue repeti-la por URL/requisição direta.
- [x] Enviar exibe aceitação SMTP sem prometer entrega; copiar funciona antes/depois de falha SMTP e comunica também falha/permissão negada da área de transferência, sem falso sucesso.
- [x] Link/e-mail não aparecem em analytics/logs ou referências a terceiros; teclado, foco, feedback acessível e mobile funcionam sem integração automatizada de WhatsApp.

**Dependências:** PA03, PA05, PA06. **Rastreio:** C1, C2, C5, C8.
**Teste focado:** navegador real, condicionado à tela a criar: validação, erro HTTP/SMTP e clipboard permitido/negado; regressão de transporte com `W src/app/api/transport.test.mjs`. Não presumir runner de UI novo.
**Smoke comportamental:** gerar, enviar ao SMTP controlado, copiar link e abri-lo em outro contexto; repetir cópia com envio falhando e com clipboard negado. Comparar e-mail/prazo/direitos sem registrar bearer como evidência.
**Arquivos prováveis:** `apps/web/src/app/admin/convites/page.tsx` (**novo proposto**); `apps/web/src/components/platform-admin-invitations.tsx` (**novo proposto**); `apps/web/src/lib/api.ts`; `apps/web/src/lib/api.test.mjs`.
**Tamanho M: 4 funcionais + rastreio = 5.**

## PA08 — Cadastro de equipe convidada, com e-mail verificado e TOTP

- [x] Concluir PA08.

**Descrição:** preparar `POST /api/auth/team-register` como criação de conta sob convite de equipe antes do corte público. Token no JSON limita cadastro ao e-mail convidado; confirmação real e senha/TOTP continuam necessários para aceite, sem liberar tenant próprio ou alterar validade/revogação/grupos. Migrar helpers/callers afetados junto da alteração, sem adiamento para PA13 ou novo helper genérico.

**Critérios verificáveis:**
- [x] Pessoa nova com convite de equipe válido cria conta do mesmo e-mail, confirma a caixa pelo mecanismo existente e autentica com senha/TOTP antes do aceite; sem convite, outro e-mail ou convite inválido/expirado/revogado o caminho não cria uma conta pública.
- [x] Identidade sem confirmação real não é aceita como equipe por ter recebido autorização administrativa; abrir/criar credencial/confirmar e-mail não consome antecipadamente o convite de equipe nem reinicia sua validade.
- [x] Conta existente continua aceitando convite pelos critérios atuais, com email verificado, vínculo/grupos e isolamento preservados; identidade de membro novo não recebe autorização para `claim_tenant` por consequência do cadastro.

**Dependências:** PA00. **Rastreio:** C6, C7; preservação do contrato de identidade e questão 5.
**Teste focado:** `B test/integration/team_registration_http_test.rb test/integration/team_invitations_test.rb`, primeiro teste condicionado à criação; `W src/app/api/transport.test.mjs` e `W src/app/convite/preservar/invitation-body.test.mjs` para relay/preservação.
**Smoke comportamental:** convite de equipe para identidade inédita → criar conta → verificar e-mail → senha/TOTP → aceitar → operar no tenant convidante; antes da verificação e sem convite, negar. Tentar onboarding próprio sem liberação deve continuar negado após PA10.

**Inventário antes de executar:** confrontar `authenticated_session`, operações SQL de registro/confirmação e o cadastro direto no workflow com PA13 A–H; não presumir que todos os consumidores mudarão. Desdobrar aqui as adaptações necessárias além das folhas abaixo, com caminhos e critérios explícitos dentro do teto. A folha A não começa enquanto essa sequência não estiver registrada e for funcional entre folhas; os testes de convite/registro continuam pertencendo a este PA, não são reimplementados em PA13.

**Folhas; P antes de A, B após A, C após B, D após C; subfolhas de preparação inventariadas antecedem a troca que as exige:**
- **P — Preparação das fixtures de registro existentes:** `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/team_invitations_test.rb`. Aceite: separar intenção de conta convidada/verificada no helper atual sem autorizar tenant por default ou fabricar cadastro inexistente. Teste: `B test/integration/team_invitations_test.rb`; smoke: fixture sintética confirma/aceita com fatores atuais, sem liberação implícita. **Tamanho S: 2 + rastreio = 3.**
- **A — Conta convidada e troca de fixture:** `apps/backend/db/migrate/20261102000002_require_team_invitation_for_registration.rb` (**novo proposto**); `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/team_registration_http_test.rb` (**novo proposto**). Aceite: prova real de caixa e consumo no aceite preservados; helper existente troca chamada junto do contrato. Teste: `B test/integration/team_registration_http_test.rb test/integration/team_invitations_test.rb`; smoke nas operações autoritativas sintéticas. Adaptações adicionais exigem subfolha explícita compatível, sem adiamento para PA13. **Tamanho M: 3 + rastreio = 4.**
- **B — HTTP de cadastro/confirmação de equipe:** `apps/backend/app/controllers/password_auth_controller.rb`; `apps/backend/app/services/identity_store.rb`; `apps/backend/config/routes.rb`; `apps/backend/test/integration/team_registration_http_test.rb` (**proposto em A**). Aceite: endpoint normativo exige token no JSON/e-mail correspondente e preserva confirmação/TOTP; nada exigido por A é adiado. Teste: `B test/integration/team_registration_http_test.rb`; smoke HTTP com convite válido, ausente e de outro e-mail. **Tamanho M: 4 + rastreio = 5.**
- **C — Token de equipe no relay:** `apps/web/src/app/convite/preservar/route.ts`; `apps/web/src/app/api/[...path]/route.ts`; `apps/web/src/app/api/transport.ts`; `apps/web/src/app/api/transport.test.mjs`. Aceite: preservar/encaminhar somente no contexto necessário, sem cookie indiscriminado nem converter token de advogado em equipe; `W src/app/api/transport.test.mjs`; smoke entre abas com convites distintos. **Tamanho M: 4 + rastreio = 5.**
- **D — UI convidada:** `apps/web/src/components/login-screen.tsx`; `apps/web/src/app/convite/page.tsx`; `apps/web/src/app/verify-email/page.tsx`; `apps/web/src/components/session-provider.tsx`. Aceite: criação aparece apenas no fluxo convidado e confirmação permanece funcional; teste focado de navegador e smoke completo de equipe acima. **Tamanho M: 4 + rastreio = 5.**

### Checkpoint — após PA06–PA08

- [x] Revisão humana do SMTP/cópia e regressão completa de equipe nova/existente; não aceitar cadastro público residual, falsa entrega ou e-mail apenas autorizado tratado como verificado.

## PA09 — Resgate de convite e credencial sem afirmar posse do e-mail

- [x] Concluir PA09.

**Descrição:** resgatar conforme [Decisões de PA00](../SPEC-primeiro-acesso.md#decisões-de-pa00), sem confirmar caixa do advogado. Conta nova prepara senha/segredo/challenge pendentes pelo mecanismo existente, sem identidade ativa/liberação/sessão/reset elegível. Confirmar senha preparada + primeiro TOTP + convite dentro de 24 horas cria identidade/credencial confirmada/liberação, consome e estabelece sessão comum atomicamente; cookie só após commit e passo TOTP registrado contra replay. Seguir direto ao perfil/tenant existentes em transação separada, sem segundo login/TOTP imediato. Preexistente usa sessão autenticada do mesmo e-mail sem alterar credenciais; migrar consumidores de `verified_email` junto da distinção entre login, verificação real e liberação.

**Critérios verificáveis:**
- [x] Inspeção/preparação não consomem; token inválido/usado/vencido/substituído é recusado. Preparação não é conta ativa nem elegível a reset por e-mail; reiniciar senha pendente exige posse do convite, sem fluxo de reset ativo. Abandono/challenge não prorrogam 24 horas.
- [x] Confirmação inicial de senha preparada/TOTP/convite no prazo conclui identidade/credencial/liberação/consumo e sessão comum atomicamente, sem replay, com no máximo um sucesso, rollback integral e cookie só após commit. Seguir direto ao perfil/tenant; erro posterior não exige novo convite e interrupção retoma por login normal. Preexistente reutiliza sessão autenticada sem duplicar conta ou redefinir credenciais.
- [x] Login, recuperação e equipe usam endereço/prova de caixa/liberação distintos, preservando dados antigos. Reset de conta ativa mantém TOTP e não muda verificação; advogado sem prova real confirma especificamente para aceitar equipe, não no onboarding titular, sem ampliar permissões.

**Dependências:** PA04, PA08. **Rastreio:** C3–C5, C7, C8; questão 5 e ambiguidades de PA00.
**Teste focado:** `B test/integration/first_access_redemption_test.rb test/integration/first_access_redemption_http_test.rb test/integration/password_reset_test.rb test/integration/password_reset_http_test.rb`, dois primeiros condicionados.
**Smoke comportamental:** abrir/preparar e tentar reset pelo e-mail antes do primeiro TOTP: não ativar identidade, liberar tenant ou revelar TOTP de conta ativa. Abandonar/reiniciar por posse do convite sem prorrogar; confirmar TOTP dentro do prazo consome e permite perfil depois. Conta existente autentica/vincula sem alterar credenciais; recuperação ativa mantém MFA e aceite de equipe exige confirmação real específica.

**Inventário antes de executar:** revisar a proveniência usada em lookup/login, sessão, recuperação, convite de equipe, helper e workflow, incluindo a enumeração completa de PA13. A decisão de PA00 define quais arquivos mudam; materializar subfolhas com até quatro funcionais mais checklist, teste e smoke antes de A. Se controller/teste listado em C precisar mudar com A, atribuir a adaptação ao conjunto de A e registrar em C apenas o trabalho restante, sem duplicá-la.

**Folhas; P antes de A, B após A, C após B; preparação dos consumidores inventariados ocorre antes da troca efetiva:**
- **P — Fixtures existentes por proveniência:** `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/password_reset_test.rb`; `apps/backend/test/integration/session_validity_test.rb`. Aceite: intenção de caixa verificada/conta legada explícita no helper atual, sem autorização por default nem fabricar estado novo. Teste: `B test/integration/password_reset_test.rb test/integration/session_validity_test.rb`; smoke: login/fatores/reset da conta verificada preservados. **Tamanho M: 3 + rastreio = 4.**
- **A — Semântica e consumo autoritativos:** `apps/backend/db/migrate/20261102000003_separate_invited_email_authorization.rb` (**novo proposto**); `apps/backend/app/services/identity_store.rb`; `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/first_access_redemption_test.rb` (**novo proposto**). Aceite: login, verificação real nullable e liberação separados; pendência sem reset/identidade ativa e consumo atômico só após primeiro TOTP confirmado. Migrar SQL/fixture/callers necessários juntos, sem incompatibilidade até C/PA13. Teste: `B test/integration/first_access_redemption_test.rb test/integration/password_reset_test.rb test/integration/session_validity_test.rb test/integration/team_invitations_test.rb`; smoke SQL/runtime com rollback, vencimento e conta existente autenticada. **Tamanho M: 4 + rastreio = 5.**
- **B — Resgate no protocolo de autenticação existente:** `apps/backend/app/controllers/password_auth_controller.rb`; `apps/backend/app/services/password_authentication.rb`; `apps/backend/config/routes.rb`; `apps/backend/test/integration/first_access_redemption_http_test.rb` (**novo proposto**). Aceite: inspeção/preparação não consomem nem ativam conta/reset; confirmação normativa de senha preparada/TOTP/convite conclui conta/liberação/consumo e sessão comum, com cookie após commit e sem replay/segunda autenticação imediata. Teste: `B test/integration/first_access_redemption_http_test.rb`; smoke: reset pendente não ativa, TOTP vence com convite, falha não emite cookie e identidade divergente não vincula. Sem wrappers, controlador de forwarding ou token em path/query. **Tamanho M: 4 + rastreio = 5.**
- **C — Recuperação HTTP e confirmação de equipe:** `apps/backend/app/controllers/password_auth_controller.rb`; `apps/backend/test/integration/password_reset_test.rb`; `apps/backend/test/integration/password_reset_http_test.rb`; `apps/backend/test/integration/team_invitations_test.rb`. Aceite: reset preserva TOTP de conta ativa e não ativa pendência; conta de advogado não verificada confirma especificamente para aceitar equipe. Adaptações exigidas por A entram junto de A; aqui somente o restante HTTP/regressões. Teste: `B test/integration/password_reset_test.rb test/integration/password_reset_http_test.rb test/integration/team_invitations_test.rb`; smoke: tentativas antes/depois do TOTP e confirmação específica sem nova confirmação no onboarding titular. **Tamanho M: 4 + rastreio = 5.**

## PA10 — Exigir autorização administrativa para tenant próprio

- [x] Concluir PA10.

**Descrição:** exigir a liberação já vinculada em PA09 na criação de tenant por HTTP/serviço/`claim_tenant`, inclusive runtime direto. Consumo/primeiro TOTP já ocorreram; perfil/OABs e tenant permanecem atômicos separadamente no onboarding existente. Fixtures no helper atual recebem liberação explícita junto do contrato, sem módulo genérico novo, default de autorização ou adiamento para PA13.

**Critérios verificáveis:**
- [x] Identidade apenas de equipe, ainda que autenticada com e-mail verificado e TOTP, não cria tenant próprio sem liberação administrativa: negar `POST /api/onboarding`, chamada a `LawyerOnboarding.call` e chamada direta runtime a `app_private.claim_tenant`.
- [x] Identidade liberada conclui um único tenant/perfil; falha faz rollback apenas de perfil/tenant, sem desfazer conta/liberação consumida após o primeiro TOTP. Retomada usa login/TOTP e não exige novo convite após 24 horas.
- [x] Contas/tenants existentes e convites de equipe mantêm comportamento, grupos e isolamento; identificadores fornecidos pelo cliente não substituem a identidade autorizada nem permitem assumir outro tenant.

**Dependências:** PA09. **Rastreio:** C3, C4, C6–C8; sucesso definido no objetivo da spec.
**Teste focado:** `B test/integration/lawyer_onboarding_test.rb test/integration/tenant_creation_authorization_test.rb test/integration/authenticated_onboarding_http_test.rb`, teste novo condicionado.
**Smoke comportamental:** membro sintético autenticado tenta os três acessos diretos e é recusado; identidade liberada conclui perfil com nome/OAB, enquanto duas conclusões concorrentes produzem no máximo um cadastro completo.

**Inventário antes de executar:** localizar criação de tenant por `LawyerOnboarding.call`, onboarding HTTP e `claim_tenant`, inclusive fixtures indiretas e workflow; confrontar todos os consumidores de PA13. Materializar as adaptações realmente necessárias sob este PA, com arquivos exatos e no máximo quatro funcionais mais checklist por folha. A preparação deve manter o contrato vigente; se depender da nova exigência, entra na troca correspondente, com subdivisão registrada antes de executar. Não presumir que todo consumidor de sessão precisa de tenant ou liberação.

**Folhas; P antes de A, B depende de A; subfolhas de preparação dos consumidores antecedem a exigência que as afeta:**
- **P — Preparação explícita de titulares e membros:** `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/lawyer_onboarding_test.rb`. Aceite: titular solicita liberação pelo caminho aprovado já disponível; membro/sessão comum não herdam. Teste: `B test/integration/lawyer_onboarding_test.rb test/integration/team_invitations_test.rb`; smoke: titular preparado mantém onboarding e membro só vínculo convidado, sem antecipar negação ainda inexistente. **Tamanho S: 2 + rastreio = 3.**
- **A — Autorização na transação/SQL e fixture existente:** `apps/backend/db/migrate/20261102000004_require_administrative_tenant_authorization.rb` (**novo proposto**); `apps/backend/app/services/lawyer_onboarding.rb`; `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/tenant_creation_authorization_test.rb` (**novo proposto**). Aceite: `claim_tenant` nega membro sem liberação; perfil/tenant fazem rollback sem reabrir convite consumido. Fixture troca junto da exigência. Teste: `B test/integration/tenant_creation_authorization_test.rb test/integration/lawyer_onboarding_test.rb`; smoke serviço/função como runtime com concorrência e autorização explícita. **Tamanho M: 4 + rastreio = 5.**
- **B — HTTP e regressões de tenant:** `apps/backend/app/controllers/onboardings_controller.rb`; `apps/backend/test/integration/authenticated_onboarding_http_test.rb`; `apps/backend/test/integration/tenant_memberships_test.rb`; `apps/backend/test/integration/tenant_isolation_test.rb`. Aceite: API nega criação sem liberação e preserva acesso existente; adaptações exigidas já em A pertencem ao conjunto de A, não esperam B e não são repetidas. Teste: `B test/integration/authenticated_onboarding_http_test.rb test/integration/tenant_memberships_test.rb test/integration/tenant_isolation_test.rb`; smoke com membro, titular existente e identidade liberada em tenants distintos. **Tamanho M: 4 + rastreio = 5.**

## PA11 — UI do link e onboarding do advogado

- [x] Concluir PA11.

**Descrição:** `/primeiro-acesso#token=...` prepara conta nova sem ativação/reset; confirmação inicial de senha preparada/TOTP/convite dentro do prazo conclui conta/liberação/consumo e sessão comum, com cookie após commit, seguindo direto ao perfil existente sem outro login/TOTP imediato. Preexistente usa sessão autenticada sem mudar credenciais. Separar captura de equipe, memória e abas; login normal retoma somente se houver interrupção após conclusão, sem reescrever onboarding nem pedir confirmação extra de caixa.

**Critérios verificáveis:**
- [x] E-mail autorizado é imutável e nome/OAB seguem validação existente; sessão só surge após os fatores de autenticação obrigatórios, sem apresentar confirmação extra de e-mail ao advogado.
- [x] Preparação/challenge não prorrogam convite nem permitem reset ativo; vencimento antes de confirmar primeiro TOTP nega conclusão. Após consumo, conta/liberação não expiram com o link e erro de perfil retoma sem outro convite. Identidade divergente, recuperação e falta de liberação refletem servidor, sem contornar PA09/PA10.
- [x] Fragmento é removido antes de navegação/exposição; não persistir bearer em logs, query string, storage acessível ou referências a terceiros. Equipe/verificação/reset continuam separados e acessíveis por teclado/mobile, inclusive entre abas.

**Dependências:** PA09, PA10. **Rastreio:** C3–C8; segurança do link e questão 5.
**Teste focado:** cenários de navegador com link em diferentes etapas/abas e viewport de 320 px; `W src/lib/api.test.mjs` e `W src/app/api/transport.test.mjs` para regressão dos contratos de sessão/transporte. Novo teste permanente de estado, se necessário, requer nome/folha ratificados antes de executar.
**Smoke comportamental:** link recebido no SMTP controlado e link copiado abrem o mesmo fluxo em contexto limpo; concluir TOTP/perfil, repetir link consumido e comparar convite de equipe/reset em outra aba, sem despejar tokens nas evidências.

**Folhas; B após A, C após B:**
- **A — Entrada e captura separada:** `apps/web/src/app/primeiro-acesso/page.tsx` (**novo proposto**); `apps/web/src/components/session-provider.tsx`; `apps/web/src/components/application-shell.tsx`; `apps/web/src/app/layout.tsx`. Aceite/teste: nenhum token de primeiro acesso é preservado como equipe; cenário de navegador com os quatro tipos de link; smoke abrir, recarregar e alternar abas sem consumir/trocar convite. **Tamanho M: 4 + rastreio = 5.**
- **B — Preparação/TOTP e perfil existente:** `apps/web/src/components/first-access-registration.tsx` (**novo proposto**); `apps/web/src/app/onboarding/page.tsx`; `apps/web/src/lib/identity-navigation.ts`; `apps/web/src/lib/api.ts`. Aceite: e-mail fixado, preparação sem conta ativa/reset e confirmação inicial no prazo conclui sessão comum e segue direto ao perfil, sem repetir senha/TOTP; preexistente usa sessão correta sem redefinir credenciais. Teste: navegador com reset pendente, challenge vencido e erro posterior de perfil; smoke: cookie só após sucesso/commit, perfil direto e retomada por login após interrupção/24 horas sem novo convite. **Tamanho M: 4 + rastreio = 5.**
- **C — Recuperação e regressão de transporte:** `apps/web/src/components/password-reset-request.tsx`; `apps/web/src/components/password-reset-confirmation.tsx`; `apps/web/src/lib/api.test.mjs`; `apps/web/src/app/api/transport.test.mjs`. Aceite: textos/estados não alegam posse de caixa e não burlam política aprovada; `W src/lib/api.test.mjs` e `W src/app/api/transport.test.mjs`; smoke de recuperação real controlada e retorno ao login com TOTP obrigatório. **Tamanho M: 4 + rastreio = 5.**

### Checkpoint — após PA09–PA11 e antes de PA12

- [x] Revisão humana explícita da semântica de e-mail, recuperação, atomicidade/expiração entre etapas, negação de tenant a membro por chamada direta e separação web de tokens. Confirmar que equipe inédita e contas existentes continuam funcionais.
- [x] Aprovar o cutover conjunto antes de executá-lo: API, SQL/funções/grants, UI/relay/provider, tratamento do cadastro público pendente e eventuais adaptações restantes de fixtures/CI exigidas pelo próprio PA12. As adaptações necessárias a PA08–PA10 já pertencem àquelas mudanças; PA13 apenas confere. Não publicar estado intermediário nem liberar bypass para passar testes.

## PA12 — Cutover completo de interface e API

- [x] Concluir PA12.

**Descrição:** fechar cadastro público de advogado em todas as superfícies, preservando identidades, credenciais, tenants e sessões válidas; titulares existentes conservam titularidade. Invalidar tokens públicos pendentes sem criar conta a partir deles ou apagar dados. Identidade sem tenant próprio mantém login, mas precisa de convite administrativo explícito; equipe preserva cadastro convidado/confirmado e não autoriza tenant próprio. Remover obsoletos sem alias público ou exclusão de fluxo necessário à equipe.

**Critérios verificáveis:**
- [x] Login remove cadastro público e usa somente texto de Q2, sem contato fictício, parâmetro novo, WhatsApp ou mailto. API, relay e funções/grants negam criação de advogado sem convite, inclusive por requisição antiga.
- [x] `register_password`/`verify_password_email`, cookie de registro e rotas/callers são removidos, substituídos ou restritos à necessidade real da equipe; não sobra entrada genérica pública. Tokens públicos pendentes são invalidados sem apagar contas/dados; ausência de tenant não concede titularidade.
- [x] Administração, link, equipe/verificação, TOTP, recuperação, contas existentes e onboarding funcionam juntos na branch integrada; frontend/backend/migration não são liberados separadamente nem se a validação estiver pendente.

**Dependências:** PA07, PA08, PA09, PA10, PA11. **Rastreio:** C1–C8; questão 4.
**Teste focado:** `B test/integration/first_access_cutover_http_test.rb test/integration/team_registration_http_test.rb test/integration/authenticated_onboarding_http_test.rb`, primeiro condicionado; `W src/app/api/transport.test.mjs`.
**Smoke comportamental:** requisição antiga web/API/SQL não cria conta; orientação de Q2 aparece e os dois fluxos legítimos funcionam. Conta existente mantém credenciais/sessão válida/tenant; pendência pública não cria conta nem liberação e identidade sem tenant próprio exige convite explícito. Gate de liberação permanece fechado até PA15.

**Compatibilidade no próprio cutover:** inventariar as chamadas antigas ainda usadas após PA08–PA11, inclusive `.github/workflows/backend.yml`; adaptar os consumidores realmente afetados na mudança que remove/restringe a operação. Se algum arquivo exceder as listas A–C, registrar previamente subfolhas explícitas, testes e smoke dentro do teto e recompor as revisões de duas ou três folhas. Não preservar chamadas públicas antigas nem aguardar PA13 para corrigir o workflow.

**Folhas; B após A, C após B:**
- **A — Fechamento autoritativo e pendências antigas:** `apps/backend/db/migrate/20261102000005_cut_over_controlled_first_access.rb` (**novo proposto**); `apps/backend/app/services/identity_store.rb`; `apps/backend/app/controllers/password_auth_controller.rb`; `apps/backend/test/integration/first_access_cutover_http_test.rb` (**novo proposto**). Aceite: funções/grants e dados pendentes obedecem decisão, sem bypass público; teste focado Rails do PA; smoke direto com operações antigas sob runtime. **Tamanho M: 4 + rastreio = 5.**
- **B — Rotas e login sem cadastro público:** `apps/backend/config/routes.rb`; `apps/web/src/components/login-screen.tsx`; `apps/web/src/app/login/page.tsx`; `apps/web/src/app/api/transport.ts`. Aceite: texto de Q2 sem contato inventado/botão de canal e caminhos públicos removidos/restritos sem bloquear equipe; teste focado Rails/web do PA; smoke URL direta e equipe acessível somente com convite. **Tamanho M: 4 + rastreio = 5.**
- **C — Relay/provider e chegada de equipe:** `apps/web/src/app/api/[...path]/route.ts`; `apps/web/src/app/api/transport.test.mjs`; `apps/web/src/components/session-provider.tsx`; `apps/web/src/app/invite/accept/page.tsx`. Aceite: allowlist/cookies/captura não reabrem cadastro nem quebram a chegada de equipe existente; `W src/app/api/transport.test.mjs`; smoke links de ambos os tipos, verificação e reset em abas distintas. **Tamanho M: 4 + rastreio = 5.**

## PA13 — Consolidação e conferência de fixtures e smoke do CI

- [x] Concluir PA13.

**Descrição:** conferir e consolidar a compatibilidade que já foi mantida em cada alteração de contrato, não iniciar a migração de helpers/fixtures após PA12. O smoke de `.github/workflows/backend.yml` chama hoje diretamente `register_password` e `verify_password_email` antes de `LawyerOnboarding.call`: sua adaptação pertence, uma única vez, ao primeiro PA que tornar essas chamadas incompatíveis, conforme o inventário de PA08/PA09/PA10 ou PA12. PA13 verifica o resultado sem preservar funções públicas antigas para satisfazê-lo.

**Critérios verificáveis:**
- [x] Helper não concede liberação administrativa a toda identidade por default; fixtures distinguem titular autorizado, membro efetivamente verificado e legado quando pertinente. Para cada consumidor abaixo existe referência à folha que o migrou no momento do contrato ou motivo registrado de **intencionalmente inalterado**.
- [x] Smoke CI já prepara titular pelo caminho/fixture autorizada aprovada e continua comprovando planejamento do despachante, sem chamada SQL antiga insegura, destinatário real ou bypass permanente para testes; toda cobertura e afirmação de negócio foi preservada.
- [x] Testes e CI usam somente PostgreSQL descartável e roles segregadas existentes, mantendo processos não root e escopo dos demais módulos. Uma incompatibilidade descoberta impede concluir PA13 e reabre a folha de contrato responsável com subdivisão explícita se necessária; não é pendência aceita, supressão ou migração duplicada aqui.

**Dependências:** PA12. **Rastreio:** C4, C6–C8; regressão e comandos da spec.
**Teste focado:** `B` selecionando os testes explícitos de cada folha abaixo; arquivo auxiliar novo somente após criação. Suíte completa e workflow integrado pertencem à validação autorizada de PA15; não disparar CI agora.
**Smoke comportamental:** ambiente CI descartável cria um titular liberado e uma equipe sem liberação; titular alimenta o despachante, membro não cria tenant próprio. Confirmar funções chamadas e estado final sem salvar bearers.

**Folhas de conferência; A antes das demais; B–H conferem o contrato de fixture já entregue. Os caminhos abaixo são superfícies explícitas de conferência, não alterações obrigatórias: nesta etapa somente o checklist registra evidência/referências. Cada folha mantém teste focado e smoke do consumidor; correção necessária volta à folha de contrato, sem duplicar sua implementação. Revisar A–C, depois D–F e depois G–H, conforme R14–R16:**
- **A — Helper existente e autenticação/recuperação:** `apps/backend/test/test_helper.rb`; `apps/backend/test/integration/authenticated_onboarding_http_test.rb`; `apps/backend/test/integration/password_reset_test.rb`. Aceite: rastrear migração tempestiva ou motivo de não alteração; titular exige liberação explícita, membro não herda e pendência nova não é reset elegível. Teste: `B test/integration/authenticated_onboarding_http_test.rb test/integration/password_reset_test.rb`; smoke: titular liberado, equipe realmente verificada e recuperação conforme PA00. **Superfície M: 3 + rastreio = 4.**
- **B — Reset, perfil, sessão e transação:** `apps/backend/test/integration/password_reset_http_test.rb`; `apps/backend/test/integration/lawyer_onboarding_test.rb`; `apps/backend/test/integration/session_validity_test.rb`; `apps/backend/test/integration/database_context_test.rb`. Aceite: referências/justificativas completas, sem retrocesso de TOTP, atomicidade, expiração ou contexto. Teste: `B` nos quatro testes listados; smoke: reset/login e onboarding com rollback/duas conexões. **Superfície M: 4 + rastreio = 5.**
- **C — Equipe e vínculos:** `apps/backend/test/integration/team_credentials_http_test.rb`; `apps/backend/test/integration/team_credential_lifecycle_test.rb`; `apps/backend/test/integration/team_invitations_test.rb`; `apps/backend/test/integration/tenant_memberships_test.rb`. Aceite: referências/justificativas completas; conta nova convidada é verificada sem liberação de tenant próprio. Teste: `B` nos quatro testes listados; smoke: convite, aceite, troca de vínculo, expiração e revogação. **Superfície M: 4 + rastreio = 5.**
- **D — Autorização e isolamento:** `apps/backend/test/integration/authorization_groups_test.rb`; `apps/backend/test/integration/authorization_groups_http_test.rb`; `apps/backend/test/integration/monitoring_authorization_http_test.rb`; `apps/backend/test/integration/tenant_isolation_test.rb`. Aceite: referências/justificativas completas; fixtures não transformam membros em titulares nem ampliam grants. Teste: `B` nos quatro testes listados; smoke: membro/titular, negações e tenant forjado. **Superfície M: 4 + rastreio = 5.**
- **E — Perfil e monitoramentos:** `apps/backend/test/integration/lawyer_monitoring_http_test.rb`; `apps/backend/test/integration/onboarding_profile_http_test.rb`; `apps/backend/test/integration/party_monitorings_http_test.rb`; `apps/backend/test/integration/process_monitorings_http_test.rb`. Aceite: referências/justificativas completas; perfil e operações mantêm contexto real e limites. Teste: `B` nos quatro testes listados; smoke: leitura do perfil autorizado e operações entre dois tenants isolados. **Superfície M: 4 + rastreio = 5.**
- **F — Consulta, catálogo e execuções:** `apps/backend/test/integration/communications_http_test.rb`; `apps/backend/test/integration/dashboard_http_test.rb`; `apps/backend/test/integration/court_catalog_http_test.rb`; `apps/backend/test/integration/collection_runs_http_test.rb`. Aceite: referências/justificativas completas; permissões e dados reais das respostas preservados, sem acesso administrativo implícito. Teste: `B` nos quatro testes listados; smoke: contexto sem onboarding, membro e titular na superfície correspondente. **Superfície M: 4 + rastreio = 5.**
- **G — Planejamento e Escrevente:** `apps/backend/test/integration/collection_planning_test.rb`; `apps/backend/test/integration/despachante_execution_test.rb`; `apps/backend/test/integration/escrevente_http_test.rb`; `apps/backend/test/integration/escrevente_processor_test.rb`. Aceite: referências/justificativas completas; titular sintético liberado conserva contratos dos processos sem alterar escopo. Teste: `B` nos quatro testes listados; smoke: plano idempotente e leitura permitida/negada por contexto. **Superfície M: 4 + rastreio = 5.**
- **H — Persistência e workflow:** `apps/backend/test/integration/processador_persistence_test.rb`; `.github/workflows/backend.yml`. Aceite: registrar o primeiro PA/folha que adaptou o workflow, ou motivo concreto se a operação não foi afetada; após o cutover não depende de cadastro SQL público antigo e mantém roles/rede/imagens não root. Teste: `B test/integration/processador_persistence_test.rb`; conferência documental do job `test` atualizado, cuja execução integrada autorizada pertence a PA15, sem inventar equivalente local a GitHub Actions. Smoke: despachante real no banco descartável usando a fixture já migrada. **Superfície S: 2 + rastreio = 3.**

A enumeração mantém todos os consumidores conhecidos de `authenticated_session` e das operações antigas, sem afirmar que todos mudam. Novo consumidor afetado entra no inventário e em subfolha do primeiro contrato que o invalidaria, antes de executar essa alteração; nunca é escondido em glob, adiado para PA13 ou resolvido por concessão global no helper. Nenhum teste falhou nesta atividade: o achado corrigido é um risco concreto de dependência no planejamento, não evidência de execução.

## PA14 — Documentação operacional, contratos e ambientes

- [x] Concluir PA14.

**Descrição:** somente na futura implementação autorizada, atualizar contratos/operação afetados conforme a mudança realmente entregue; manter fonte normativa na spec e não duplicar desenho não implementado nos contratos atuais. Remover instruções obsoletas sem reescrever evidência histórica, criar documento paralelo ou infraestrutura por conveniência.

**Critérios verificáveis:**
- [x] Contratos efetivamente afetados correspondem à implementação e referenciam a fonte normativa de PA00 sem duplicação extensa; login/sessão/fatores existentes, consumo após primeiro TOTP, equipe confirmada e liberação no tenant permanecem coerentes.
- [x] Procedimento registra preservação de contas, invalidação de pendências públicas, canais/reeemissão e expurgo oportunista nas operações necessárias, sem prazo físico sem atividade nem rake/cron/job/serviço novo. Restore invalida TODOS os convites administrativos restaurados antes da reabertura, inclusive dentro de 24 horas, preservando identidades/liberações válidas do snapshot e exigindo reemissão explícita. Documentar somente envs realmente alteradas, sem novos parâmetros, ledger ou infraestrutura de backup.
- [x] Mapa HTTP/comandos e evidências correspondem à versão entregue; há pré-condições explícitas de banco descartável/roles, STARTTLS, containers não root e limites da comprovação. Nenhuma instrução autoriza deploy ou uso destrutivo de base persistente.

**Dependências:** PA12. **Rastreio:** C1–C8; seis decisões e regras de env do projeto.
**Teste focado:** revisão documental manual contra código/rotas/configuração finais, sem comando automático novo; todos os exemplos devem apontar a caminhos e variáveis reais. Não executar os comandos durante a revisão deste planejamento.
**Smoke comportamental:** walkthrough futuro do operador cobre provisionamento, canais, recuperação e expurgo oportunista; restore exige invalidar todos os convites restaurados antes da reabertura, não apenas os vencidos. Lacuna impede concluir a tarefa, mas não autoriza ação em produção ou infraestrutura nova.

**Folhas; B após A:**
- **A — Operação e contratos centrais:** `README.md`; `SPEC-primeiro-acesso.md`; `SPEC-identidade.md`; `docs/arquitetura.md`. Aceite/teste/smoke: atualizar somente após implementação autorizada, sem espalhar desenho futuro; procedimento descreve expurgo nas operações necessárias e invalidação de todos os convites restaurados antes de reabrir emissão/resgate, preservando identidades/liberações do snapshot. Sem tarefa agendada, ledger/serviço novo, infraestrutura de backup ou alegação de SMTP externo entregue. **Tamanho M: 4 + rastreio = 5.**
- **B — Web, endpoints e plano:** `apps/web/SPEC-web.md`; `apps/web/endpoints.md`; `tasks/plan-primeiro-acesso.md`. Aceite/teste: mapa de rotas, separação dos fluxos, comandos e estado dos gates coerentes com A e a implementação; smoke walkthrough pela web e seus endpoints reais de teste. **Tamanho M: 3 + rastreio = 4.**

### Checkpoint — após PA12–PA14

- [x] Revisão humana do cutover integrado, fixtures/CI e documentação; ausência de bypass público e consistência dos contratos devem ser demonstradas. Aprovar ambiente e execução de PA15 sem publicar, fazer deploy ou usar dados persistentes.

## PA15 — Validação integrada e evidências

- [x] Concluir PA15.

**Descrição:** comprovar o comportamento fim a fim contra Rails/PostgreSQL reais descartáveis, web e SMTP controlado STARTTLS, com navegador desktop/mobile. Registrar resultados observados e limitações em documentação existente, sem confundir proposta, simulação de transporte ou aceitação SMTP com entrega real.

**Critérios verificáveis:**
- [x] Canais, prazo, uso único/concorrência e reemissão seguem PA00; pendência não ativa conta/liberação/reset. Confirmação inicial de senha preparada/TOTP/convite conclui conta/liberação/consumo e sessão comum sem replay, com cookie após commit, seguindo direto ao perfil sem repetir autenticação. Expurgo oportunista não promete prazo sem atividade; restore invalida todos os convites restaurados preservando identidades/liberações e exigindo reemissão. SMTP controlado não prova entrega externa.
- [x] Anônimo/usuário comum não administram; cadastro público e acessos diretos a API, serviço e `claim_tenant` não criam advogado/tenant sem autorização. Equipe nova/existente verifica e-mail e usa TOTP, membro sem liberação não cria tenant próprio; contas existentes, isolamento de tenants, recuperação segura e revogação preservam os contratos.
- [x] Ausência de vazamento de token/credenciais, separação entre abas/fluxos, acessibilidade e comportamento a 320 px são exercitados; checks autorizados e smoke têm evidência/limites, com revisão humana final. Falha não é contornada por mock, bypass ou supressão de teste.

**Dependências:** PA13, PA14. **Rastreio:** C1–C8, segurança, seis decisões e todos os invariantes deste checklist.
**Teste focado:** `B test/integration/first_access_end_to_end_test.rb test/integration/first_access_invitations_test.rb test/integration/tenant_creation_authorization_test.rb`, primeiro condicionado; `W src/app/api/transport.test.mjs`, `W src/lib/api.test.mjs` e `W src/app/convite/preservar/invitation-body.test.mjs`. A suíte integrada é executada uma vez pelo responsável pela integração após todas as folhas aterrissarem, nunca em concorrência com suites que alterem o mesmo banco.
**Checks integrados futuros:** no ambiente descartável autorizado, comando `B` sem seleção para suíte Rails completa; frontend `npm test`, `npm run format:check`, `npm run lint`, `npm run typecheck` e `npm run build` no container Node de teste. Executar o job backend atualizado somente com sua rede/banco descartáveis. Aplicar migrations apenas nesse banco pela role migrator conforme workflow, não usar rollback/deleção de dados persistentes como preparação. Nada disso foi executado agora.
**Smoke comportamental:** gerar/enviar/copiar → preparar senha/TOTP sem conta ativa/reset → confirmar senha preparada/TOTP/convite no prazo e concluir sessão comum/consumo → perfil direto, sem segundo login/TOTP; ou vincular preexistente já autenticada. Equipe confirma/autentica/aceita e membro não cria tenant. Repetir reset pendente, abandono/reinício sem prorrogar, challenge vencido/replay, falha antes do commit sem cookie, interrupção posterior retomada por login, erro de perfil, SMTP/clipboard, concorrência e abas distintas. Expurgo oportunista/restore preservam identidades/liberações e não revivem convites; não salvar segredos.

**Folhas; B após A, C após B:**
- **A — Casos integrados e concorrência:** `apps/backend/test/integration/first_access_end_to_end_test.rb` (**novo proposto**); `apps/backend/test/integration/first_access_invitations_test.rb` (**proposto em PA04**); `apps/backend/test/integration/tenant_creation_authorization_test.rb` (**proposto em PA10**); `apps/backend/test/integration/team_registration_http_test.rb` (**proposto em PA08**). Aceite/teste: estados e negações dos critérios, concorrência por conexões independentes; `B` em cada teste listado; smoke fim a fim e acessos diretos acima. **Tamanho M: 4 + rastreio = 5.**
- **B — Regressão de links/transporte e navegador:** `apps/web/src/app/api/transport.test.mjs`; `apps/web/src/lib/api.test.mjs`; `apps/web/src/app/convite/preservar/invitation-body.test.mjs`. Aceite/teste: `W` em cada arquivo e navegador real com clipboard/abas/fatores/320 px, sem criar framework novo por suposição; smoke ambos os canais e fluxos distintos com SMTP controlado. **Tamanho M: 3 + rastreio = 4.**
- **C — Evidências e revisão final:** `README.md`; `apps/web/endpoints.md`; `tasks/plan-primeiro-acesso.md`. Aceite: registrar comandos efetivamente executados, ambiente/roles, cenários, resultado, falhas e limites sem segredos; teste documental de correspondência com as evidências das folhas A/B e checks integrados; smoke: revisão humana acompanha os caminhos funcionais exercitados. **Tamanho M: 3 + rastreio = 4.**

### Checkpoint final — após PA15

- [x] Confrontar evidências com C1–C8, seis decisões e critérios de cada PA; marcar somente tarefas realmente concluídas, mantendo bloqueios/falhas explícitos.
- [x] Revisão humana final de segurança, regressões, acessibilidade, ambientes e documentação; conclusão técnica não autoriza deploy nem publicação por inferência.

## Limites do estado registrado

PA00–PA15 concluídos na branch de implementação; continuidade e revisões humanas aprovadas globalmente pelo solicitante. PR único [#17](https://github.com/smcruzfilipe/advocaciaonline/pull/17). Os resultados abaixo substituem os estados intermediários históricos; nenhum deploy ou dado persistente foi usado.

## Evidência integrada de encerramento

- **C1/C2/C5:** Chromium headless em HTTPS local exercitou administradora com senha/TOTP, emissão, SMTP real autenticado com STARTTLS e certificado confiado, cópia idêntica ao e-mail e reemissão; SMTP indisponível manteve cópia, e permissão negada de clipboard mostrou erro e alternativa manual. Aceitação não foi declarada entrega externa.
- **C3/C4:** antes do primeiro TOTP, consulta protegida mostrou 0 identidades, 1 preparação e 0 liberações; depois, TOTP confirmado, liberação presente, convite removido e caixa postal ainda não verificada. O navegador concluiu perfil/tenant sem novo login. Membro já autenticado resgatou seu convite administrativo, interrompeu o perfil, retomou por `/onboarding` sem query e concluiu o próprio tenant; preservou o vínculo anterior.
- **C6/C7:** equipe inédita recebeu convite, criou conta contextual, confirmou caixa pelo SMTP no mesmo navegador, autenticou senha/TOTP e aceitou. Antes de receber liberação administrativa, administração e criação de tenant retornaram 403; cadastro público web retornou 404. A suíte cobre recusa direta SQL/serviço/HTTP, revogação, validade, confirmação contextual de conta existente e isolamento.
- **C8/Q6:** contexto anônimo recebeu 401 na administração; fragmentos foram removidos e mantidos separados em contextos de navegador. Restore protegido eliminou convite ainda ativo e preparação, preservando 3 identidades, 2 liberações e 2 tenants; token restaurado invalidado retornou 422. Painel e dashboard conferidos a 320 px sem overflow, com foco de teclado visível. Nenhum segredo real, destinatário real ou integração WhatsApp foi usado.
- **Upgrade:** imagem anterior preparou titular, conta sem tenant, credenciais/sessões e pendência pública sintéticos. Migrations novas preservaram credenciais, prova legada e sessões; só titular recebeu grant, conta sem tenant foi recusada e token público pendente não criou identidade. Instalação vazia também passou.
- **Testes/CI:** Backend remoto [41336829129](https://github.com/smcruzfilipe/advocaciaonline/actions/runs/41336829129): 560 testes/11.949 assertions; processador 135/1.253; zero falhas/erros/skips; smoke real do despachante persistiu dois planos idempotentes com UID1000. Web: 47 testes, tipos/lint/formatação/build/audit de produção verdes em [41336829136](https://github.com/smcruzfilipe/advocaciaonline/actions/runs/41336829136). Correção de retomada: foco 6 testes/79 assertions. Mutação isolada da condição TOTP falhou no teste consumidor esperado; sem a mutação, foco 4 testes/45 assertions verde. Produção não foi alterada por essa prova.
- **Conferência PA13 A–H:** compatibilidade migrada no commit `b5207c6`, junto do contrato: helper guarda banco descartável e liberação é opt-in `owner: true`; consumidores que criam tenant usam essa opção explícita. Os demais permanecem intencionalmente sem grant porque exercitam apenas autenticação/equipe. Workflow migrou a fixture protegida e executou o despachante real no CI; não depende de função pública removida.
- **Consolidação dos testes propostos:** os casos SQL/transacionais e HTTP de resgate estão em `first_access_redemption_http_test.rb`, `first_access_invitations_test.rb` e `first_access_invitation_store_test.rb`; corte público também foi exercitado diretamente por HTTP/SQL e navegador. O formulário foi incorporado a `app/primeiro-acesso/page.tsx`, sem componente paralelo desnecessário. Os nomes anteriormente propostos/condicionados não indicam arquivos obrigatórios faltantes.
- **Limites:** SMTP controlado não comprova caixa postal externa; não houve deploy, merge, acesso a dados persistentes, alteração de dependências ou variável de ambiente nova. Aprovação global não substitui resultado técnico; evidências acima são observadas.
