# Direção visual: Central de Processos

## Fonte e decisão

A refatoração `refactor/frontend` adota a exportação **Central de Processos** do [Banani](https://app.banani.co/flow/byZqYk7YE568), preservada em [`banani/byZqYk7YE568/`](banani/byZqYk7YE568/). `export.json`, as 14 telas, os componentes e `style.css` são os originais de comparação; não devem ser formatados nem adaptados no diretório documental.

O solicitante escolheu integrar o desenho à aplicação real, não publicar uma galeria estática. Layout, cores, tipografia, espaçamentos e ícones seguem a exportação. Dados, estados, permissões e gravações continuam sendo os da API. Esta decisão substitui a direção visual anterior de fonte de sistema, paleta exclusivamente monocromática e navegação lateral; não altera as especificações funcionais, o backend nem os gates de deploy.

## Implementação e fronteiras

- `apps/web/src/app/globals.css`: Tailwind CSS 4 e tokens de `style.css` do Banani. A integração usa o [plugin PostCSS oficial](https://tailwindcss.com/docs/installation/using-postcss), configurado em `apps/web/postcss.config.mjs`.
- `apps/web/src/components/ui.tsx`: botões, alertas, badges, campos, métricas, títulos, estado vazio e contêineres com as classes da exportação; controles reais em vez de divs que simulam inputs.
- `apps/web/src/components/application-shell.tsx`: cabeçalho com abas, vínculo, saída e variante móvel, sem a antiga sidebar.
- `apps/web/src/app/`: telas ligadas aos endpoints existentes. O backend Rails não recebe estilos, JSX nem novas regras de autenticação.
- Lucide React renderiza os ícones originais; IBM Plex Sans é distribuída localmente por `@fontsource`, sem solicitações a um serviço de fontes externo.

Não há dados demonstrativos em produção, login simulado, confirmação de gravação antecipada ou HTML da fonte inserido com `dangerouslySetInnerHTML`.

## Tokens

Os nomes abaixo são tokens CSS, não variáveis de ambiente. O arquivo original é a referência para os valores exatos.

| Token `--color-*` | Valor |
|---|---|
| `background` | `#ffffff` |
| `foreground` | `#111111` |
| `border` | `#d4d4d4` |
| `input` | `#f5f5f5` |
| `primary` / `primary-foreground` | `#111111` / `#ffffff` |
| `secondary` / `secondary-foreground` | `#f0f0f0` / `#111111` |
| `muted` / `muted-foreground` | `#e8e8e8` / `#737373` |
| `accent` / `accent-foreground` | `#2563eb` / `#ffffff` |
| `success` / `success-bg` | `#16a34a` / `#f0fdf4` |
| `warning` / `warning-bg` | `#b45309` / `#fffbeb` |
| `error` / `error-bg` | `#dc2626` / `#fef2f2` |
| `info` / `info-bg` | `#0369a1` / `#f0f9ff` |
| `nav-bg` / `table-row-alt` | `#fafafa` / `#fafafa` |

Fonte de corpo e títulos: **IBM Plex Sans**, pesos 400, 500 e 600. Os tamanhos exportados são `xs=11px`, `sm=13px`, `base=14px`, `lg=16px`, `xl=18px`, `2xl=22px`, `3xl=28px` e `4xl=36px`. Os tokens de raio `sm`, `md`, `lg` e `xl` são `2px`; botões, campos e painéis mantêm os cantos sem arredondamento quando o componente original não especifica raio. Avatares e indicadores de seleção preservam suas formas circulares.

## Composição

- Cabeçalho desktop: `px-8 py-3`, abas abaixo; cabeçalho público: `px-8 py-4`. No celular, `px-4` e navegação com rolagem horizontal local.
- Conteúdo autenticado: `px-8 py-8` no desktop; variante móvel com `px-4 py-5`.
- Dashboard: `max-w-5xl`; comunicações/equipe/grupos: larguras conforme suas telas; cadastro de parte/processo: `max-w-2xl`.
- Identidade: login `max-w-sm`, onboarding `max-w-xl`, vínculos `max-w-lg`, convite `max-w-md`.
- Métricas: grade de duas colunas; painel `border p-5 gap-2`, valor `text-3xl font-semibold`.
- Formulários: bordas e preenchimento `bg-input`; seções delimitadas por bordas, sem gradientes ou sombras decorativas.
- Gerenciar credencial: modal `max-w-md`, cabeçalho `px-5 py-4`, conteúdo `px-5 py-5`, fundo escurecido; escolhas de validade visíveis, Escape e foco contido pelo `<dialog>` nativo.

## Adaptações funcionais aprovadas

1. O backend usa e-mail, senha e TOTP. Esses controles substituem o botão Google no espaço visual de acesso; a refatoração não reintroduz OAuth.
2. Erro, carregamento, salvamento, sucesso e expiração aparecem somente no estado correspondente. A exportação mostra exemplos simultâneos, não um estado real de execução.
3. Nomes, tribunais, identificadores, grupos e contagens vêm da API. Metadados não fornecidos não são preenchidos com os exemplos do desenho. A lista de comunicações não recebe resumo nem data de publicação da API atual.
4. Cadastro, edição, desativação/reativação, renovação/reemissão, convites, regras e associações existentes continuam acessíveis. Histórico de coletas/Escrevente, recuperação de senha e verificação de e-mail, sem novas telas exportadas próprias, usam os mesmos tokens.
5. Em telas estreitas, campos e ações podem quebrar linha sem perder controles; tabelas operacionais têm rolagem local. Isso não autoriza mudar o desenho desktop.

## Semântica e verificação

Preservar rótulos associados, foco visível, estados de erro anunciados, navegação por teclado, restauração de foco ao fechar o modal e o link de salto para o conteúdo. Conteúdo jurídico deve continuar legível e inerte; números CNJ e OAB permanecem strings, incluindo seus zeros.

A comparação de código com o Banani e o smoke visual não constituem certificação WCAG nem comparação automatizada pixel a pixel. Comandos, cenários efetivamente exercitados e limitações ficam no [README](../README.md#implementação-e-verificações).
