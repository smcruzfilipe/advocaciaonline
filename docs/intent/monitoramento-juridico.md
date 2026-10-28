# Intenção: monitoramento jurídico

Declaração confirmada pelo solicitante.

- **Objetivo:** permitir que advogados independentes acompanhem comunicações relacionadas às suas OABs, partes e processos, sem consultas manuais.
- **Tenancy:** cada advogado é um tenant. Secretárias e estagiários podem acessar seu ambiente; o escritório não é o tenant.
- **Primeira entrega:** onboarding, cadastros de partes e processos, filtros por tribunal, dashboard e consulta de comunicações agrupadas por tribunal, com detalhes.
- **Coletas:** duas execuções diárias, inicialmente pelo Comunica, com novas tentativas e aviso na dashboard em caso de falha persistente. Publicações repetidas não serão persistidas novamente.
- **Escriba:** registrar o fluxo e os dados relevantes das coletas desde o início, sem registrar ações do usuário nem erros.
- **Permissões:** o advogado administra usuários e grupos, com restrições por operação, tribunal e dashboard. Usuários sem grupo têm leitura de todos os tribunais e acesso à dashboard por padrão; sem acesso à dashboard, os números aparecem como `*`.
- **Credenciais:** o advogado pode definir validade em número de dias ou deixar a credencial sem expiração. Após o prazo definido, ela não permite mais acesso.
- **Capacidade:** a aplicação central deve suportar pelo menos 300 usuários simultâneos sem travamentos ou lentidão significativa.
- **Fora da primeira entrega:** relatórios e avisos por e-mail; outras fontes de coleta ficam para o futuro.
