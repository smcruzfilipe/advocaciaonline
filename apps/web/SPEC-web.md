# Especificação: interface web de monitoramento jurídico

**Estado:** implementação autorizada para o frontend em `apps/web/`; não altera o backend nem aprova os checkpoints pendentes. Os módulos e contratos funcionais continuam sendo os de `CAPABILITIES.md` e das respectivas `SPEC-*.md`. As telas exportadas em `banani-selecao.json` são referência visual, não prova de integração nem autoridade sobre regras de negócio.

## Objetivo e usuários

Permitir que advogados e equipes autorizadas acessem, configurem monitoramentos e consultem comunicações e estados da coleta. A experiência deve ser utilizável em desktop e celular e refletir os dados e permissões reais do servidor.

## Capacidades e telas

| Módulo existente | Telas e responsabilidades | Dependências |
|---|---|---|
| identidade | Login Google, cadastro inicial com nome/OABs/escritório opcional, seleção de vínculo, aceite de convite e saída | Sessão e endpoints de identidade existentes |
| autorizacao | Equipe, credenciais, convites, grupos, regras e membros; decisões por operação e tribunal | identidade; somente titular administra equipe/grupos |
| monitoramentos | Perfil monitorado, lista, cadastro, detalhe, edição, desativação e reativação de partes e processos; filtros de tribunal | identidade e autorizacao |
| consulta | Dashboard, lista por tribunal e detalhe independente de comunicações; estados, avisos e pendências | identidade, autorizacao e coleta |
| escrevente/coleta | Consulta de execuções, trabalhos, estado e marcos do fluxo para titular | identidade e coleta; registros somente leitura |

Ordem proposta: identidade → autorização e monitoramentos → consulta/dashboard e visão operacional → validação integrada. A ordem não altera os checkpoints do projeto.

## Comportamento e critérios de aceite

- Login Google sem senha local; onboarding inclui nome completo, OAB principal, OABs secundárias opcionais e escritório opcional. Vínculo selecionado e validade são reconhecidos pelo servidor; convite usa o fluxo existente.
- Usuários de equipe e grupos seguem `SPEC-identidade.md` e `SPEC-autorizacao.md`: sem grupos há leituras padrão, não escrita implícita; concessões se somam e negação explícita prevalece. Administração é exclusiva do titular; remover último grupo não revoga credencial.
- Partes e processos usam catálogo real de tribunais; sem filtro significa todos, seleção explícita não vazia. CNJ e OAB preservam zeros. Erro de catálogo não produz opções inventadas.
- Lista de comunicações agrupa por tribunal sem fundir publicações por processo; detalhe apresenta origem disponível, vínculos autorizados e aviso de possível duplicidade para identidade pendente. Campos não fornecidos não são inventados. Texto da fonte é não confiável: renderizar como texto, nunca HTML bruto.
- Dashboard apresenta comunicações novas e processos distintos para hoje, semana civil e últimos sete dias em `America/Sao_Paulo`; `*` quando negada, sem recuperar número por outra via. Falha, parcial, andamento, indisponibilidade, ausência de trabalho e sucesso vazio são distintos.
- O Escrevente é somente leitura. Coleta é limitada a Diário Eletrônico `D`; não implementar editais, busca histórica automática, fontes adicionais, relatórios ou avisos de publicação por e-mail. Convites de equipe por e-mail permanecem previstos.
- Cada fluxo deve tratar carregamento, vazio, erro, sucesso e ausência de permissão quando aplicáveis. Dados de demonstração jamais substituem respostas reais nem simulam gravação ou autenticação.
- Leituras, alterações e troca de vínculo em abas da aplicação são coordenadas com Web Locks; leituras conferem a sessão antes e depois da solicitação, e mutações comparam sessão e vínculo antes de enviar. Navegador sem Web Locks recebe erro e não envia operações protegidas. O backend continua responsável pela autorização efetiva.
- A limitação de início do Google permanece por IP do cliente: o ingresso HTTPS confiável substitui os cabeçalhos internos de IP e segredo, e o Next.js rejeita o início de login sem essa configuração. Os detalhes e variáveis estão no README.
- O link `/invite/accept#token=...` emitido pelo backend é recebido pela interface; o fragmento é removido da barra de endereço e o token fica em cookie HttpOnly de curta duração. A confirmação compara a impressão digital do convite aberto naquela aba, evitando aceitar um convite de outra aba. Não armazenar o token no cliente.

## Visual e acessibilidade

Usar `docs/design-system.md` como contrato visual e `banani-selecao.json` como referência de telas. Paleta preta/branca/cinza, cantos retos, fonte de sistema, sem gradientes ou sombras decorativas; navegação responsiva e leitura jurídica sem truncamento. Corrigir divergências do design exportado em favor das specs. Teclado, foco visível, rótulos e mensagens associadas, contraste e funcionamento a partir de 320px são obrigatórios. A escolha explícita de `apps/web/` substitui referências anteriores ao diretório previsto `frontend/`.

## Stack, comandos e estrutura

Next.js 16.4.3, React 19.3.1 e TypeScript no monorepo; backend Rails API e PostgreSQL permanecem separados. O `package-lock.json` fixa as dependências. O runtime de desenvolvimento e teste é Node.js 24 em container não root; a imagem de frontend para deploy depende dos gates de containerização aplicáveis.

- Desenvolvimento: `npm run dev -- --hostname 0.0.0.0`
- Dependências: `npm ci --ignore-scripts`
- Formatação: `npm run format:check`
- Lint: `npm run lint`
- Tipos: `npm run typecheck`
- Testes: `npm test`
- Build: `npm run build`

Os comandos são executados a partir de `apps/web/`, dentro do container. `src/app/` contém rotas, telas e handlers; `src/components/` reúne o shell e a sessão; `src/lib/` contém o cliente HTTP. Testes comportamentais ficam junto à lógica testada. A lista dos endpoints existentes está em `apps/web/endpoints.md`.

O estilo usa TypeScript estrito, componentes por tarefa, nomes explícitos e formatação Prettier. Exemplo da regra de apresentação, em `src/app/dashboard/presentation.mjs`:

```js
if (masked || value === "*") return { value: "*", note: "Sem permissão" };
```

## Testes e verificação

Exercitar no navegador headless desktop e móvel: login/onboarding, troca de vínculo, cadastro e ciclo de monitoramentos, administração restrita, comunicações com HTML da fonte escapado, identidade pendente e dashboard com zero, falha, parcial e máscara. Confirmar erros e ausência de acesso com chamadas reais; RLS e autorização do servidor não são substituídas por controles escondidos. Testar login Google real quando houver credenciais, sem incluí-las no repositório. `node:test` cobre bordas de estado e transporte; executar também lint, tipos, formatação, build e verificação integrada.

## Fronteiras

- **Sempre:** seguir os contratos existentes, proteger dados por tenant/tribunal, escapar conteúdo da fonte, registrar variáveis de ambiente novas/alteradas no README e documentar comandos executados e limitações.
- **Pedir aprovação:** mudanças em regras funcionais, permissões, schema, fontes ou escopo; gates humanos de checkpoints continuam vigentes.
- **Nunca:** registrar segredos, confiar tenant enviado pelo cliente, exibir números negados, tratar falha como zero, inserir HTML bruto da fonte ou alegar integração e verificação não realizadas.

## Dependências externas para comprovação

O teste de OAuth Google real exige cliente web e segredo externos configurados para `APP_ORIGIN/auth/google/callback`; a entrega SMTP real exige servidor e credenciais externos. Sessões e convites controlados comprovam os caminhos internos, não essas integrações externas.
