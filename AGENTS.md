# Regras do projeto

## Feedback obrigatório do advisor

- Todo agente deve aguardar o feedback do advisor antes de concluir qualquer tarefa, etapa ou entrega, declarar o trabalho pronto ou encerrar sua participação.
- Finalizar a implementação, executar verificações ou receber resultados de subagentes não substitui o feedback do advisor. A regra também se aplica a alterações de documentação e configuração.
- Após receber o feedback, tratar todos os apontamentos pertinentes e verificar as correções antes de concluir. Se o advisor solicitar nova revisão, aguardar também esse novo retorno.
- Não presumir aprovação por silêncio, demora ou ausência de apontamentos ainda não recebidos. Não fabricar feedback nem apresentar a própria revisão ou a de outro agente como se fosse do advisor.
- Se o advisor estiver indisponível ou não existir um canal para receber seu feedback, registrar explicitamente o bloqueio de revisão e não declarar a tarefa concluída.

## Registro de variáveis de ambiente

- Toda variável de ambiente criada ou alterada em uma implementação deve ser registrada em `README.md` na mesma mudança.
- Documentar o nome exato, o valor default (ou `Nenhum`), se é obrigatória e sua finalidade; para valores sem default, explicar como fornecê-los sem registrar segredos.
- Remover da tabela qualquer variável eliminada e manter explícitas as configurações previstas mas ainda não implementadas.
