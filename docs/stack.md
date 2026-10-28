# Stack da aplicação central

## Decisões do solicitante

- API central: Ruby e Ruby on Rails exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).
- Tenant: advogado independente, não escritório; RLS deve preservar esse isolamento.

A escolha não fixa versões, runtime Node.js, bibliotecas, hospedagem, estrutura de pastas, linguagem dos coletores/ETL, fila ou infraestrutura. Esses pontos continuam pendentes. Não inicializar a aplicação nem inventar comandos de build/teste antes de definir essas decisões e resolver os gates do [plano](../tasks/plan.md).

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
