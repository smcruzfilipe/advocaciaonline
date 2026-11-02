# Agenda e atendimento online integrado

**Estado:** proposta de produto refinada com o solicitante e registrada com sua confirmação. Não autoriza implementação nem altera os gates de `tasks/plan.md`. Hospedagem Jitsi e demais decisões abaixo permanecem pendentes.

## Problema

Como permitir que advogado, secretária e cliente agendem atendimentos sem retrabalho, com videochamada na plataforma, publicação no Google Agenda e detalhes enviados por e-mail?

## Direção recomendada

Uma **agenda do advogado com reserva direta**, administrada por ele e pela secretária autorizada. O cliente recebe um **link individual de agendamento**, visualiza somente horários disponíveis e reserva sem precisar criar conta ou aguardar aprovação.

Reuniões online podem ter vários participantes e acontecem dentro da plataforma, usando Jitsi. Os convidados acessam o link recebido por e-mail, sem cadastro, e aguardam admissão pelo anfitrião. A solução Jitsi escolhida deverá comprovar suporte a esse controle.

A plataforma é a referência dos compromissos criados nela. A integração publica esses compromissos no Google Agenda do advogado, **sem importar eventos, consultar ocupação ou receber alterações feitas diretamente no Google**.

## Escopo mínimo proposto

- **Agenda:** cadastrar, consultar, remarcar e cancelar compromissos presenciais ou online, com início, término e fuso explícitos.
- **Gestão:** advogado configura disponibilidade; secretária autorizada gerencia a agenda sem acesso implícito às agendas de outros advogados.
- **Reserva pelo cliente:** acesso individual, sem cadastro; exibir apenas horários reserváveis, nunca detalhes dos demais compromissos.
- **Concorrência:** uma reserva confirmada bloqueia o horário; duas tentativas simultâneas não podem confirmar atendimentos sobrepostos.
- **Participantes:** permitir vários convidados, informados pelo organizador.
- **Videochamada:** sala associada à reunião, interface integrada à plataforma e admissão de convidados pelo anfitrião.
- **Google Agenda:** conectar um calendário do advogado mediante autorização específica; criar, atualizar e cancelar o evento correspondente às operações feitas na plataforma.
- **E-mails:** enviar confirmação, remarcação e cancelamento aos convidados. Informar advogado, data, horário, fuso, duração e, quando online, link de acesso.
- **Falhas externas:** distinguir compromisso reservado, publicação no Google e envio do convite. Não apresentar sucesso completo quando alguma dessas etapas estiver pendente ou tiver falhado.
- **Privacidade:** não incluir conteúdo jurídico sensível nos convites ou no evento do Google.

## Hipóteses a validar

- [ ] **A agenda pode funcionar sem ler a ocupação do Google.** Simular a rotina com advogado e secretária, incluindo compromissos externos. Se houver sobreposições frequentes, essa limitação compromete a proposta.
- [ ] **O cliente consegue reservar pelo link individual sem auxílio.** Observar clientes realizando o fluxo até a confirmação.
- [ ] **O acesso sem conta, com admissão, atende à experiência e ao sigilo necessários.** Validar com chamadas reais, inclusive pelo celular, na modalidade Jitsi candidata.
- [ ] **Disponibilidade e duração padrão cobrem a rotina inicial.** Conferir exemplos reais antes de introduzir tipos de atendimento.

## Não fazer nesta entrega

- **Sincronização Google → plataforma ou leitura de ocupação** — exclusão escolhida; compromissos criados diretamente no Google não bloquearão a disponibilidade.
- **Agenda pública e cadastro obrigatório de clientes** — a reserva será por acesso individual.
- **Aprovação manual de cada reserva** — o cliente confirma diretamente um horário liberado.
- **Votação de horários entre participantes** — vários convidados não exigem um sistema de negociação de disponibilidade.
- **Gravação, transcrição ou resumo por IA** — ampliam tratamento de dados e não são necessários para realizar a chamada.
- **Lembretes automáticos e alertas de publicações judiciais** — são capacidades distintas dos e-mails transacionais desta agenda.
- **Catálogo de serviços e recorrência de compromissos** — sem necessidade validada até aqui.

## Decisões pendentes antes de implementar

- Jitsi gerenciado ou próprio: custo, capacidade, privacidade e operação.
- Validade, reutilização e revogação do link individual de agendamento.
- Quem pode atuar como anfitrião e admitir convidados.
- Duração padrão, intervalos e antecedência mínima para reserva, remarcação e cancelamento.
- Provedor de e-mail e procedimento para comunicar falhas de entrega.

## Critério de sucesso

Um cliente reserva pelo link individual; o compromisso aparece na agenda da plataforma e no Google conectado; todos os convidados recebem os detalhes e conseguem entrar na chamada integrada, mediante admissão, **sem copiar horários ou links manualmente**. Remarcação e cancelamento seguem o mesmo fluxo, sem deixar convites ou eventos apresentados como atuais indevidamente.

## Contexto do projeto

- `apps/backend/app/services/google_oidc.rb:14–18` solicita atualmente apenas `openid email`. Login Google não concede acesso ao calendário; a integração exige autorização adicional.
- `docs/arquitetura.md` registra Rails API e frontend Next.js previsto, ainda não criado. Esta proposta descreve uma capacidade futura, não uma interface existente.
- `docs/especificacao.md` deixa envio de e-mails fora da primeira entrega de monitoramento jurídico. Os e-mails transacionais desta proposta são novo escopo; seu registro aqui não altera aquela especificação nem libera implementação.

## Alternativas consideradas

- **Solicitação com aprovação:** descartada em favor de reserva direta para evitar trabalho operacional a cada agendamento.
- **Página pública ou área de cliente autenticada:** preteridas pelo link individual, conforme escolha do solicitante.
- **Agenda por tipo de atendimento:** pode facilitar durações distintas, mas depende de validar que o cliente sabe escolher o tipo e de que a configuração adicional é necessária.
- **Escolha conjunta de horário:** útil para coordenação de grupos, mas acrescenta uma etapa desnecessária aos atendimentos simples.
