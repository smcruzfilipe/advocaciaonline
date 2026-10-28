# Monitoramento jurídico

Projeto de especificação para uma plataforma de monitoramento de publicações judiciais voltada a advogados independentes e suas equipes. A fonte inicial prevista é o Diário de Justiça Eletrônico Nacional (DJEN), com consulta a cadernos como caminho principal e à API paginada de comunicações como fallback.

> **Estado atual:** este repositório ainda não contém a aplicação. Requisitos funcionais e stack central estão documentados; decisões técnicas bloqueantes de implementação continuam pendentes. Não há comandos de instalação, execução, build ou teste definidos. Não execute comandos presumidos: consulte primeiro as decisões e os gates em [`tasks/plan.md`](tasks/plan.md).

## Escopo funcional

- Login Google para advogado e equipe; o contrato de identidade não prevê senha local para usuários da aplicação.
- Isolamento por tenant do advogado, autorização por grupos e tribunal, monitoramentos de advogados/partes/processos e consulta de comunicações.
- Coleta diária do DJEN, com cadernos como fonte principal, API paginada como fallback e deduplicação pela combinação de `id` e `hash`.
- Dashboard e registros append-only do fluxo de coleta.

O mapa de módulos e a ordem de dependências estão em [`CAPABILITIES.md`](CAPABILITIES.md). Requisitos detalhados: [`docs/especificacao.md`](docs/especificacao.md) e as seis especificações `SPEC-*.md` na raiz.

## Stack definida

- API central: Ruby on Rails, exclusivamente em modo API (`--api`).
- Frontend: Next.js.
- Banco de dados: PostgreSQL com Row-Level Security (RLS).

Versões de referência e limites da decisão: [`docs/stack.md`](docs/stack.md). Estrutura de diretórios, dependências, infraestrutura, ferramentas e comandos ainda não foram definidos. O planejador e os componentes ETL também não têm stack definida.

## Swagger UI e acesso à documentação

Requisito registrado: a documentação interativa da API será publicada com Swagger UI e protegida por login e senha. A aplicação e o Swagger UI ainda não existem neste repositório, portanto esse acesso não está implementado nem pode ser exercitado agora. O mecanismo de autenticação da documentação, sua relação com o login Google da aplicação e a configuração/armazenamento das credenciais precisam ser definidos no contrato técnico antes da implementação. Não há usuário ou senha padrão definidos; credenciais não devem ser inventadas ou versionadas.

## Variáveis de ambiente

Esta tabela cobre as variáveis **implementadas no repositório hoje**. A inspeção do conteúdo não encontrou aplicação ou arquivos de configuração executáveis que leiam variáveis de ambiente; portanto, atualmente não há variáveis ativas a configurar.

| Variável | Default | Obrigatória? | Finalidade |
|---|---|---|---|
| Nenhuma definida | — | — | Nenhuma variável de ambiente está implementada neste repositório. |

Os requisitos já preveem configurações futuras por ambiente: horários das duas coletas diárias, limites de tentativas e intervalos de backoff. Os nomes, formatos, defaults e obrigatoriedade dessas variáveis ainda não foram definidos; ver [`SPEC-coleta.md`](SPEC-coleta.md). A configuração de acesso do Swagger UI também está pendente. Não use a tabela acima como contrato dessas configurações futuras.

**Regra de manutenção:** toda variável de ambiente introduzida ou alterada em uma implementação deve ser registrada nesta seção do README no mesmo conjunto de mudanças. Para cada variável, informe nome exato, valor default (ou `Nenhum` se não houver), se é obrigatória e para que serve. Quando não existir default, documente também como fornecer o valor sem incluir segredos. Atualize a tabela ao remover variáveis.

## Documentação do projeto

- [Especificação geral](docs/especificacao.md)
- [Stack e versões de referência](docs/stack.md)
- [Mapa de capacidades](CAPABILITIES.md)
- [Plano de implementação e gates](tasks/plan.md)
- [Checklist de implementação](tasks/todo.md)
- [Contrato OpenAPI do DJEN consultado](docs/contrato-djen.md)

## Implementação e verificações

Ainda não há instruções executáveis de instalação, inicialização, build, lint ou teste. Os IDs 1–3 do plano são gates anteriores à implementação e devem ser concluídos antes de criar a aplicação ou escolher comandos e estrutura. Este README descreve o estado documental atual; não afirma que a integração Rails–Next.js–PostgreSQL, autenticação, coleta ou Swagger UI já estejam funcionando.
