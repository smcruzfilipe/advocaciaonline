# Direção visual: UI, tipografia e cores

**Estado:** contrato visual do Advocacia Online: cantos retos, preto e branco e composição funcional. A interface em `apps/web/` aplica esta direção; o guia por si só não comprova conformidade visual ou de acessibilidade e não altera os gates do [plano](../tasks/plan.md).

## Escopo no monorepo

O Advocacia Online é um **monorepo**: a interface Next.js e a API Rails pertencem ao mesmo repositório, não a projetos versionados separadamente. A [estrutura do monorepo](../README.md#estrutura-do-monorepo) distingue caminhos existentes de componentes previstos.

- `docs/design-system.md`, na raiz documental compartilhada, é o contrato visual do produto.
- `apps/web/` é o componente Next.js que implementa este contrato: páginas em `apps/web/src/app/`, componentes em `apps/web/src/components/` e estilos mantidos dentro do aplicativo.
- `apps/backend/` contém a API Rails, responsável por identidade, autorização, domínio e persistência. Não recebe estilos nem renderiza a UI Next.js.
- `apps/backend/despachante/` contém o despachante, executado fora do servidor da API; não possui interface própria. `apps/etl/` contém o processador, também sem UI, no mesmo monorepo.

Frontend e backend terão imagens distintas, preservando o repositório único. As fronteiras técnicas estão na [arquitetura](arquitetura.md#estrutura-do-monorepo-e-fronteiras). Este guia define apresentação; as [especificações funcionais](especificacao.md) prevalecem em dados, ações e autorização.

## Princípios de UI

- **Ferramenta de trabalho, não landing page.** Priorizar consulta, leitura e cadastro; sem hero decorativo, slogans ou ilustrações genéricas.
- **Geometria reta.** Botões, campos, painéis, avisos, etiquetas e contêineres com `border-radius: 0`. Sem pílulas ou cartões arredondados.
- **Hierarquia sem efeitos.** Usar contraste, peso tipográfico, alinhamento, bordas e espaço. Sem gradientes, sombras, vidro, brilho ou animações decorativas.
- **Densidade legível.** Preferir listas e tabelas para registros repetidos. Painéis delimitam tarefas; não transformar todo dado em um card isolado.
- **Estado verdadeiro.** Não simular contagens, sucesso de gravação, cobertura de coleta ou disponibilidade. Vazio, falha, parcial, carregamento e acesso negado são situações diferentes.

## Cores e tokens

Paleta clara monocromática. Os nomes são tokens CSS propostos, não variáveis de ambiente. Valores devem ser definidos uma vez no frontend e consumidos por função semântica, sem hexadecimais avulsos em componentes.

| Token proposto | Valor | Uso |
|---|---|---|
| `--color-background` | `#FFFFFF` | Fundo da página e área de leitura. |
| `--color-surface` | `#F4F4F4` | Cabeçalhos de tabela, instruções, hover de ação secundária e controles indisponíveis. |
| `--color-text` | `#111111` | Corpo, títulos e labels. |
| `--color-text-muted` | `#595959` | Ajuda, metadados e motivo de indisponibilidade; não reduzir opacidade. |
| `--color-action` | `#000000` | Ação principal e item atual da navegação. |
| `--color-action-hover` | `#333333` | Hover e pressionamento da ação principal. |
| `--color-on-action` | `#FFFFFF` | Texto e ícone sobre ação principal ou item atual. |
| `--color-border` | `#767676` | Limite de campos e controles sobre branco ou superfície auxiliar. |
| `--color-divider` | `#DEDEDE` | Separador decorativo de linhas e seções; nunca único limite de um controle. |
| `--color-focus` | `#000000` | Contorno de foco sobre superfícies claras. |

Não usar vermelho, verde ou amarelo como linguagem padrão de estado. Erro recebe rótulo como “Não foi possível salvar”, texto de orientação e borda reforçada; sucesso recebe confirmação textual. Ações destrutivas, quando previstas funcionalmente, têm verbo explícito e não dependem de botão vermelho.

Texto normal deve alcançar contraste mínimo de 4,5:1; texto grande, 3:1. Limites necessários à identificação de controles e indicadores visuais de estado devem alcançar 3:1 contra a superfície adjacente. Não usar `--color-divider` para texto ou foco. Os pares relevantes da paleta devem ser verificados na implementação; uma paleta não certifica acessibilidade de uma tela.

A paleta descreve o tema claro, não cria um seletor de tema. Respeitar cores forçadas do sistema: foco com `Highlight`, limites com `CanvasText` e indisponibilidade com `GrayText`, sem bloquear a preferência do usuário.

## Tipografia

Uma única família para interface e leitura, sem download de fonte:

```css
font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
```

Usar unidades relativas; os equivalentes abaixo consideram a preferência padrão de 16px do navegador. Não fixar a raiz em pixels nem impedir ampliação. A aparência exata da fonte varia por sistema operacional; não há fonte de marca customizada nesta proposta.

| Papel | Tamanho | Peso | Entrelinha |
|---|---|---|---|
| Título de página (`h1`), a partir de 48rem | `2rem` (32px) | 700 | 1,25 |
| Título de página abaixo de 48rem | `1,5rem` (24px) | 700 | 1,25 |
| Título de seção (`h2`) | `1,25rem` (20px) | 700 | 1,4 |
| Subseção (`h3`) | `1rem` (16px) | 700 | 1,5 |
| Corpo, conteúdo jurídico e campos | `1rem` (16px) | 400 | 1,5 |
| Label e ação | `1rem` (16px) | 600 | 1,5 |
| Metadados, ajuda e cabeçalhos de tabela | `0,875rem` (14px) | 400; 600 no cabeçalho | 1,5 |
| Métrica da dashboard | `2rem` (32px) | 700 | 1,25 |

- Um `h1` por página; não pular níveis para obter tamanho visual. Negrito organiza, não substitui semântica.
- Sem peso ultrafino, texto corrido em caixa alta ou espaçamento artificial de letras. Links no conteúdo são sublinhados, inclusive sem hover.
- Texto jurídico usa coluna de leitura de até `75ch`, altura automática e parágrafos separados. Não truncar o conteúdo integral do detalhe.
- Contagens e datas em colunas comparáveis usam `font-variant-numeric: tabular-nums`; contagens alinhadas à direita. Identificadores de processo e OAB continuam textuais, preservando zeros e sufixos.
- Nomes longos e identificadores não podem alargar a página: permitir quebra quando necessário, sem esconder informação essencial por reticências.

## Geometria, espaçamento e layout

| Regra proposta | Valor/aplicação |
|---|---|
| Raio dos elementos da aplicação | `0` |
| Borda padrão | `1px solid var(--color-border)` |
| Ênfase de erro de campo | Borda de 2px, texto de erro e `aria-invalid`; reservar espaço para não deslocar o layout. |
| Escala de espaçamento | `0,25rem`, `0,5rem`, `0,75rem`, `1rem`, `1,5rem`, `2rem`, `3rem` (4–48px na base padrão). |
| Alvo de interação | Mínimo de `2,75rem` (44px na base padrão); altura pode crescer com o texto. |
| Conteúdo principal | Até `80rem`, largura fluida e `min-width: 0` nos filhos de grid/flex. |
| Formulário de cadastro | Até `42rem`; campos agrupados por tarefa, não por grade decorativa. |
| Recuo do conteúdo | `1rem` em largura estreita; `2rem` a partir de 48rem. |
| Navegação lateral | `16rem` acima de 64rem; conteúdo ocupa o restante. |
| Navegação até 64rem | Acima do conteúdo, links quebráveis e sem sidebar fixa sobre a leitura. |
| Colunas de formulário | Uma abaixo de 48rem; múltiplas somente para campos relacionados e com espaço suficiente. |

A ordem de leitura no DOM permanece a mesma em todas as larguras. A aplicação deve funcionar a partir de 320px sem rolagem horizontal da página. Tabela que realmente exigir duas dimensões pode ter rolagem local, região identificada e operação por teclado; priorizar lista ou pares label/valor quando preservarem a comparação necessária.

Controles nativos, incluindo radios, select e calendário, podem manter formas impostas pelo navegador ou sistema. O raio zero rege os elementos desenhados pela aplicação; não substituir semântica e comportamento nativos só para forçar um rádio quadrado.

## Padrões de componentes e interação

| Elemento | Contrato visual e comportamental |
|---|---|
| Estrutura da página | Navegação, título, contexto e ações, seguidos do conteúdo. Link de salto para o conteúdo; identificação textual do usuário e contexto autorizado. |
| Navegação | Links reais; item atual preto com texto branco, peso reforçado e `aria-current="page"`. Não usar apenas ícone para identificar uma seção. |
| Ação primária | Fundo preto, texto branco e canto reto; hover/pressionamento em cinza escuro. Uma ação principal por grupo de tarefa, próxima ao conteúdo afetado. |
| Ação secundária | Fundo branco, texto escuro e borda de controle; hover em superfície cinza. Link navega; botão executa ação. |
| Foco | `outline: 2px solid var(--color-focus)` com `outline-offset: 2px` sobre claro; contorno branco sobre fundo escuro. Não remover foco nem encobri-lo com cabeçalhos fixos. |
| Processamento/indisponibilidade | Texto “Salvando…” ou motivo concreto; `disabled` nativo quando aplicável, sem reduzir opacidade. Não confundir carregamento de página com contagem zero. |
| Campos | Label visível acima, ajuda associada e obrigatoriedade explícita. Placeholder não substitui label; erro perto do campo, associado por `aria-describedby`; preservar entradas após rejeição. |
| Filtros | Grupo identificado, critérios atuais visíveis e ação “Aplicar filtros”. Empilhar no mobile sem ocultar o contexto da consulta. Não criar filtros ausentes do contrato funcional. |
| Listas e tabelas | Cabeçalhos claros, separadores leves e ações por registro. Não tornar a linha inteira clicável como substituto de um link explícito; tabela com cabeçalhos semânticos. |
| Detalhes | Pares label/valor para metadados; conteúdo jurídico com leitura contínua. `<details>` pode recolher metadados auxiliares, não esconder falha ou aviso essencial. |
| Avisos e etiquetas | Retângulos com texto explícito; ícone opcional complementar. Avisos persistentes não somem em toast; mudanças relevantes anunciadas com semântica adequada, sem anúncios repetitivos. |
| Ícones | Simples e monocromáticos; decorativos ignorados por leitores de tela. Ação só com ícone exige nome acessível e alvo de interação completo. |

## Aplicação aos fluxos jurídicos

A organização abaixo orienta composição, não fixa URLs nem adiciona funcionalidades às especificações.

- **Acesso e onboarding:** coluna única, sem navegação privada antes de autenticação. Usar a identidade Google prevista em [identidade](../SPEC-identidade.md), sem inventar formulário de senha local. Nome, OABs e escritório opcional organizados em grupos legíveis.
- **Monitoramentos:** separar contexto do advogado, partes e processos conforme [monitoramentos](../SPEC-monitoramentos.md). Exibir nome ou número, tribunais aplicáveis e situação com texto; deixar ações previstas junto ao registro.
- **Consulta:** cada comunicação permanece independente, agrupada por tribunal; nunca fundir resultados por número de processo. O detalhe prioriza tribunal, número e conteúdo efetivamente fornecido pela fonte, escapado na renderização, nunca inserido como HTML bruto. Somente o texto da API é sanitizado na coleta; o caderno não é sanitizado, e a primeira versão deduplicada pode conservar seu HTML. A referência funcional é [consulta](../SPEC-consulta.md).
- **Dashboard:** apenas as duas métricas aprovadas — comunicações novas persistidas e processos distintos associados — nas janelas definidas em consulta. Compor números, rótulos e períodos sem inventar gráficos, tendências ou métricas. Avisos de coleta aparecem junto ao escopo afetado.
- **Equipe e grupos:** seguir [autorização](../SPEC-autorizacao.md). Nome comercial do escritório não equivale ao tenant. Ocultar ações não substitui autorização no servidor; apresentação não amplia acesso.

### Estados obrigatórios

Esta tabela define apresentação monocromática; as regras completas e a máscara de autorização continuam na [matriz da dashboard](../SPEC-consulta.md#matriz-de-resultados-da-dashboard).

| Situação | Apresentação |
|---|---|
| Carregando | Texto de carregamento e região ocupada sem contagens provisórias; `aria-busy` na região pertinente. |
| Consulta concluída sem resultados | Mensagem de vazio específica; contagem `0` somente quando o contrato permitir, nunca por falha ou ausência de resposta. |
| Operação concluída | Confirmação textual da ação realmente persistida, sem depender de verde. |
| Falha | Explicar a falha em linguagem de tarefa; não apagar dados digitados, não simular sucesso e não inventar ação de recuperação. |
| Coleta parcial | Rótulo “Resultado parcial”, escopo e tribunais autorizados afetados; não apresentar como completo. |
| Coleta não concluída ou indisponível | Estado textual correspondente, distinto de falha persistente e de zero. |
| Dashboard negada | `*` em todos os números protegidos, com explicação acessível “Sem permissão”; valor real não pode estar no HTML, atributos, tooltips ou respostas. |
| Tribunal não autorizado | Não revelar dados, números, estado ou aviso desse tribunal. |
| Comunicação sem chave válida | Aviso de pendência e possível duplicidade, sem botão de resolução ou inclusão nas métricas. |

## Critérios de aplicação e verificação futura

Antes de declarar uma tela aderente:

- Conferir raio zero, paleta sem cores cromáticas, ausência de sombras/gradientes e uso consistente dos tokens.
- Inspecionar a superfície real em 320, 768, 1024 e 1440px; verificar fronteiras de 48rem e 64rem, nomes longos e conteúdo jurídico extenso.
- Ampliar texto a 200% e verificar reflow a 320 CSS px, sem perda de conteúdo, ações ou foco; permitir exceção local apenas para conteúdo genuinamente bidimensional.
- Percorrer teclado, link de salto, controles nativos e navegação; conferir foco visível sobre superfícies claras e escuras, labels, headings e anúncios de estado.
- Medir contraste nos pares realmente renderizados, incluindo hover, seleção, erro, indisponibilidade e cores forçadas.
- Exercitar os estados da tabela com respostas reais autorizadas e restritas; conferir que nenhuma falha vira zero e nenhum valor negado chega ao navegador.

Os critérios acima não são, por si, declaração de conformidade WCAG; verificações da implementação são registradas no README.
