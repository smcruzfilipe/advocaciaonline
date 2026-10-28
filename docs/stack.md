# Stack da aplicação central

## Decisões do solicitante

- API central: Ruby e Ruby on Rails exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).
- Tenant: advogado independente, não escritório; RLS deve preservar esse isolamento.

As versões centrais selecionadas estão documentadas abaixo. Bibliotecas adicionais, hospedagem, estrutura de pastas, linguagem dos coletores/ETL, fila e infraestrutura continuam pendentes. Por instrução expressa do solicitante, este trabalho é **somente documental: não instalar runtimes, pacotes, dependências ou containers nesta máquina**. Não gerar a aplicação nem executar instalação, build ou testes de integração.

## Versões selecionadas

Referência da consulta: 28/10/2026. Seleção de releases estáveis documentadas nas fontes oficiais, sem beta, RC ou canary como versão dos componentes listados. Não é uma garantia de que não exista patch posterior ao anúncio consultado.

| Componente | Versão de referência | Fonte e evidência |
|---|---|---|
| Ruby | 4.0.9 | [Anúncio oficial de 23/10/2026](https://www.ruby-lang.org/en/news/2026/10/23/ruby-4-0-9-released/) |
| Ruby on Rails | 8.1.4, somente API-only | [Metadados exatos do gem](https://rubygems.org/api/v2/rubygems/rails/versions/8.1.4.json): publicado em 24/09/2026, `prerelease: false`, requisito Ruby `>= 3.2.0` |
| Next.js | 16.4.1 | [Atualização oficial de segurança de 14/10/2026](https://nextjs.org/blog/nextjs-security-update-october-14-2026): versão corrigida da linha Active LTS |
| PostgreSQL | 18.6, com RLS | [Política oficial de versões](https://www.postgresql.org/support/versioning/): minor atual da linha 18, suportada até novembro de 2030 |
| Node.js, referência de runtime do frontend | Linha 24 LTS; patch ainda não fixado | [Estado de suporte](https://nodejs.org/en/about/previous-releases); [requisito do Next.js 16](https://nextjs.org/docs/app/guides/upgrading/version-16): Node.js `>= 20.9.0` |

Ruby 4.0.9 satisfaz o requisito numérico do gem Rails 8.1.4. Isso não substitui uma matriz explícita de suporte nem demonstra funcionamento em execução. A linha Node.js 24 LTS satisfaz o mínimo documentado do Next.js 16; a versão exata do runtime e as dependências React/adapter PostgreSQL precisam ser fixadas no futuro contrato de dependências, sem instalar nada agora.

Estas são versões de referência para a aplicação central. Não definem versões ou tecnologias do planejador, ETL ou de um Escriba independente. Não houve instalação, inicialização de banco, geração de lockfiles, migration, teste de RLS ou smoke da integração Rails–Next.js–PostgreSQL. A compatibilidade operacional permanece não verificada.

## Referências oficiais consultadas

- [Rails API-only](https://guides.rubyonrails.org/api_app.html): guia específico para aplicações Rails voltadas a clientes de API.
- [Next.js: componentes de servidor e cliente](https://nextjs.org/docs/app/getting-started/server-and-client-components): referência de fronteiras de execução do frontend; a consulta não escolhe versão nem biblioteca de autenticação.
- [PostgreSQL: Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html): políticas de leitura e modificação de linhas.

## Requisitos para o desenho do isolamento

RLS não substitui autenticação Google, expiração/revogação de acesso ou permissões por grupo, tribunal e dashboard. Contexto de usuário/tenant deve ser derivado no servidor; o parâmetro enviado pelo cliente não comprova acesso.

A documentação PostgreSQL informa que superusuários e roles `BYPASSRLS` ignoram RLS; o proprietário normalmente também ignora as políticas, salvo `FORCE ROW LEVEL SECURITY`. O desenho deve separar administração/migração da role de execução e verificar isolamento usando a role real da aplicação, não uma role que contorne RLS.

O contexto de tenant precisa ser delimitado a cada operação/transação, sem vazar entre requisições ou jobs que reutilizem conexões. Detalhes da integração Rails/pool/worker e das políticas serão definidos no contrato técnico, não nesta escolha de stack.

RLS não protege operações de tabela inteira como `TRUNCATE`, segundo a documentação. Portanto, não é suficiente sozinho para garantir o Escriba append-only: permissões de operação e proteção contra alteração/exclusão precisam de desenho próprio.

## Verificações futuras obrigatórias

- Leitura e escrita cruzadas entre dois tenants devem ser negadas com a role real de execução, inclusive em jobs.
- Após reutilizar uma conexão entre tenants, não pode restar contexto de acesso anterior.
- Ausência de contexto confiável de tenant não deve ampliar acesso.
- Negação de tribunal/dashboard e revogação/expiração precisam continuar efetivas independentemente de RLS.

São critérios de verificação futura; não há banco, políticas ou aplicação implementados nem testes desses comportamentos executados.
