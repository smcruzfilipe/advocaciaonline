# Stack da aplicação central

## Decisões do solicitante

- API central: Ruby e Ruby on Rails exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).
- Tenant: advogado independente, não escritório; RLS deve preservar esse isolamento.

As versões centrais selecionadas estão documentadas abaixo. [Arquitetura e contratos propostos](arquitetura.md) escolhem Ruby para despachante e ETL, layout e ferramentas; dependências exatas e deploy continuam sujeitos a validação. Por instrução do solicitante, runtimes e dependências não devem ser instalados no host: a implementação e as verificações usam Docker. O frontend fica para uma etapa posterior.

## Versões selecionadas

Referência da consulta: 28/10/2026. Seleção de releases estáveis documentadas nas fontes oficiais, sem beta, RC ou canary como versão dos componentes listados. Não é uma garantia de que não exista patch posterior ao anúncio consultado.

| Componente | Versão de referência | Fonte e evidência |
|---|---|---|
| Ruby | 4.0.9 | [Anúncio oficial de 23/10/2026](https://www.ruby-lang.org/en/news/2026/10/23/ruby-4-0-9-released/) |
| Ruby on Rails | 8.1.4, somente API-only | [Metadados exatos do gem](https://rubygems.org/api/v2/rubygems/rails/versions/8.1.4.json): publicado em 24/09/2026, `prerelease: false`, requisito Ruby `>= 3.2.0` |
| Next.js | 16.4.1 | [Atualização oficial de segurança de 14/10/2026](https://nextjs.org/blog/nextjs-security-update-october-14-2026): versão corrigida da linha Active LTS |
| PostgreSQL | 18.6, com RLS | [Política oficial de versões](https://www.postgresql.org/support/versioning/): minor atual da linha 18, suportada até novembro de 2030 |
| Node.js, referência de runtime do frontend | 24.22.1 LTS | [Anúncio oficial](https://nodejs.org/en/blog/release/v24.22.1); [requisito do Next.js 16](https://nextjs.org/docs/app/guides/upgrading/version-16): Node.js `>= 20.9.0` |

Ruby 4.0.9 satisfaz o requisito numérico do gem Rails 8.1.4. Isso não substitui uma matriz explícita de suporte. Node.js 24.22.1 satisfaz o mínimo documentado do Next.js 16; suas dependências serão fixadas na etapa de frontend.

As versões de referência também se aplicam ao runtime Ruby proposto para despachante e ETL. Em teste local descartável, PostgreSQL 18.6 inicializou como UID 70 e preservou dados após reinicialização; uma aplicação Rails API-only temporária executou teste de persistência contra esse banco. Isso não comprova o funcionamento da aplicação do repositório, da imagem final ou a integração futura com Next.js.

## Referências oficiais consultadas

- [Rails API-only](https://guides.rubyonrails.org/api_app.html): guia específico para aplicações Rails voltadas a clientes de API.
- [Next.js: componentes de servidor e cliente](https://nextjs.org/docs/app/getting-started/server-and-client-components): referência de fronteiras de execução do frontend; a consulta não escolhe versão nem biblioteca de autenticação.
- [PostgreSQL: Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html): políticas de leitura e modificação de linhas.

## Requisitos para o desenho do isolamento

RLS não substitui autenticação Google, expiração/revogação de acesso ou permissões por grupo, tribunal e dashboard. Contexto de usuário/tenant deve ser derivado no servidor; o parâmetro enviado pelo cliente não comprova acesso.

A documentação PostgreSQL informa que superusuários e roles `BYPASSRLS` ignoram RLS; o proprietário normalmente também ignora as políticas, salvo `FORCE ROW LEVEL SECURITY`. O desenho deve separar administração/migração da role de execução e verificar isolamento usando a role real da aplicação, não uma role que contorne RLS.

O contexto de tenant deve ser delimitado a cada transação, sem vazar entre requisições ou jobs que reutilizem conexões; a proposta de roles e políticas está em [arquitetura](arquitetura.md#isolamento-e-privilégios) e deve ser verificada na implementação.

RLS não protege operações de tabela inteira como `TRUNCATE`, segundo a documentação. Portanto, não é suficiente sozinho para garantir o Escrevente append-only: permissões de operação e proteção contra alteração/exclusão precisam de desenho próprio.

## Verificações futuras obrigatórias

- Leitura e escrita cruzadas entre dois tenants devem ser negadas com a role real de execução, inclusive em jobs.
- Após reutilizar uma conexão entre tenants, não pode restar contexto de acesso anterior.
- Ausência de contexto confiável de tenant não deve ampliar acesso.
- Negação de tribunal/dashboard e revogação/expiração precisam continuar efetivas independentemente de RLS.

São critérios de verificação para a aplicação implementada; o teste local descartável mencionado acima não comprova todos esses comportamentos.
