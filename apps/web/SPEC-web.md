# Especificação: interface web de monitoramento jurídico

**Estado:** proposta para revisão. Escopo: frontend em `apps/web/`; não altera backend nem aprova os checkpoints pendentes. Os módulos e contratos funcionais continuam sendo os de `CAPABILITIES.md` e das respectivas `SPEC-*.md`. As telas exportadas em `banani-selecao.json` são referência visual, não prova de integração nem autoridade sobre regras de negócio.

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

## Visual e acessibilidade

Usar `docs/design-system.md` como contrato visual e `banani-selecao.json` como referência de telas. Paleta preta/branca/cinza, cantos retos, fonte de sistema, sem gradientes ou sombras decorativas; navegação responsiva e leitura jurídica sem truncamento. Corrigir divergências do design exportado em favor das specs. Teclado, foco visível, rótulos e mensagens associadas, contraste e funcionamento a partir de 320px são obrigatórios. A escolha explícita de `apps/web/` substitui referências anteriores ao diretório previsto `frontend/`.

## Stack, comandos e estrutura

Next.js com TypeScript, no monorepo, em `apps/web/`; backend Rails API e PostgreSQL permanecem separados. Não há frontend instalado, lockfile, versão de Next.js, gerenciador de pacotes, comandos de desenvolvimento/build/lint/teste ou convenção de testes frontend existentes para esta aplicação. Essas escolhas e comandos exatos devem ser definidos e verificados antes da implementação; não são resultados já observados. O frontend terá imagem própria quando os gates de containerização aplicáveis estiverem cumpridos.

Estrutura certa: `apps/web/` é a raiz da aplicação; endpoints existentes constam de `apps/web/endpoints.md`; documentação e specs permanecem na raiz e em `docs/`. Subdiretórios de código e testes, estilo e exemplo real ainda dependem da implementação e não devem ser apresentados como existentes.

## Testes e verificação

Exercitar no navegador real desktop e móvel: login/onboarding, troca de vínculo, cadastro e ciclo de monitoramentos, administração restrita, comunicações com HTML da fonte escapado, identidade pendente e dashboard com zero, falha, parcial e máscara. Confirmar erros e ausência de acesso com chamadas reais; RLS e autorização do servidor não são substituídas por controles escondidos. Testar login Google real quando houver credenciais, sem incluí-las no repositório. Definir comando de testes e lint conforme ferramentas escolhidas; testar isoladamente casos de estado e segurança relevantes e rodar verificação integrada antes do aceite.

## Fronteiras

- **Sempre:** seguir os contratos existentes, proteger dados por tenant/tribunal, escapar conteúdo da fonte, registrar variáveis de ambiente novas/alteradas no README e documentar comandos executados e limitações.
- **Pedir aprovação:** mudanças em regras funcionais, permissões, schema, fontes ou escopo; gates humanos de checkpoints continuam vigentes.
- **Nunca:** registrar segredos, confiar tenant enviado pelo cliente, exibir números negados, tratar falha como zero, inserir HTML bruto da fonte ou alegar integração e verificação não realizadas.

## Questões técnicas a resolver antes do código

Versões e gerenciador de pacotes; comandos reproduzíveis de execução, build e verificação; organização concreta e padrões de estilo; estratégia de comunicação segura entre origens, cookies e CSRF; configuração de OAuth real e infraestrutura. Soluções devem respeitar o backend existente e as regras de documentação de variáveis. A disponibilidade de credenciais externas é condição para comprovar Google real, não evidência de que já esteja configurado.
