# Regras do projeto

## Registro de variáveis de ambiente

- Toda variável de ambiente criada ou alterada em uma implementação deve ser registrada em `README.md` na mesma mudança.
- Documentar o nome exato, o valor default (ou `Nenhum`), se é obrigatória e sua finalidade; para valores sem default, explicar como fornecê-los sem registrar segredos.
- Remover da tabela qualquer variável eliminada e manter explícitas as configurações previstas mas ainda não implementadas.

## Monorepo e imagens Docker

- O projeto é um monorepo: frontend Next.js e backend Rails API ficam no mesmo repositório e devem ter imagens Docker separadas. Para testes locais, usar uma imagem PostgreSQL separada; ela não é destinada ao deploy.
- No servidor de deploy, usar a instância PostgreSQL já existente; não criar nem instalar outra instância para a aplicação. A criação do banco da aplicação e a execução das migrations nessa instância dependem de permissões adequadas e da definição do procedimento de deploy.
- Ao implementar imagens, usar a menor imagem base adequada a cada componente e incluir na imagem final somente o runtime, as dependências e os artefatos necessários à sua execução. Usar builds multi-stage quando houver dependências de build; não incluir ferramentas de build, testes, caches ou código desnecessário na imagem final.
- Todos os containers, inclusive o PostgreSQL, devem iniciar e executar seus processos com usuário não root, sem etapas de inicialização privilegiadas. Configurar permissões e volumes de dados para esse usuário; não contornar a regra executando o entrypoint como root.
- Verificar a configuração de usuário e a execução real de cada imagem, incluindo inicialização e persistência do PostgreSQL, e registrar tamanho e justificativa da base escolhida. Não declarar conformidade apenas pela presença de uma instrução `USER`.
- Esses são requisitos para a futura containerização, não autorização para iniciar implementação ou instalar e executar containers antes dos gates e decisões pendentes em `tasks/plan.md`.
