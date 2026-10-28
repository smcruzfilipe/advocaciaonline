# Tarefas: monitoramento jurídico

Plano: [plan.md](plan.md). As tarefas são propostas; não executar antes da aprovação e das decisões bloqueantes.

- [ ] **1. Confirmar contrato da fonte.** Aceite: filtros, cobertura, paginação, identidade e limites documentados com fontes oficiais. Verificação: consulta real controlada. Dependências: nenhuma. Arquivos: documentação do contrato.
- [ ] **2. Fechar decisões de segurança e desempenho.** Aceite: regras de grupos, expiração, dashboard, retenção e meta mensurável de carga aprovadas. Verificação: revisão dos cenários conflitantes. Dep.: 1 quando aplicável. Arquivos: especificação.
- [ ] **3. Definir stack e contratos.** Aceite: comandos, estrutura, fronteiras de tenant e mensagens entre componentes documentados. Verificação: revisão de contrato e ameaça de vazamento. Dep.: 1–2. Arquivos: especificação e contratos.

## Checkpoint 1
- [ ] Especificação e plano aprovados; bloqueios resolvidos.

- [ ] **4. Onboarding do advogado.** Aceite: login, nome e OABs persistidos no tenant do advogado. Verificação: fluxo real de primeiro acesso e isolamento. Dep.: 3. Arquivos: identidade, persistência, interface e testes.
- [ ] **5. Gestão de usuários e expiração.** Aceite: usuário criado com validade em dias ou sem expiração; acesso vencido recusado. Verificação: exercitar antes/depois do vencimento, inclusive sessão ativa. Dep.: 4. Arquivos: gestão, autenticação, interface e testes.
- [ ] **6. Grupos e escopo de tribunais.** Aceite: usuário sem grupo tem leitura ampla; grupo Consulta TJSP restringe outros tribunais. Verificação: chamadas diretas e interface com múltiplos tenants. Dep.: 5. Arquivos: autorização, administração, interface e testes.

## Checkpoint 2
- [ ] Fluxo de acesso e isolamento exercitados; build e testes conforme stack escolhida.

- [ ] **7. Cadastro de partes.** Aceite: nome e filtros de tribunal persistidos por tenant. Verificação: cadastro e leitura por usuário autorizado. Dep.: 6. Arquivos: monitoramentos, interface e testes.
- [ ] **8. Cadastro de processos.** Aceite: número e filtros de tribunal persistidos por tenant. Verificação: cadastro e leitura por usuário autorizado. Dep.: 6. Arquivos: monitoramentos, interface e testes.
- [ ] **9. Escriba append-only.** Aceite: registros de coleta inseríveis e legíveis sem alteração ou exclusão, sem ações de usuário nem detalhes de erro. Verificação: tentativas reais de alteração e remoção recusadas. Dep.: 3–4. Arquivos: armazenamento, interface do serviço e testes.

## Checkpoint 3
- [ ] Cadastros e invariantes do Escriba demonstrados.

- [ ] **10. Planejamento da coleta.** Aceite: linhas de execução identificam tenant, entidade, fonte e tribunal aplicável. Verificação: planejar advogados, partes e processos em mais de um tenant. Dep.: 7–9. Arquivos: planejador e testes.
- [ ] **11. Coleta e persistência reais.** Aceite: obter, normalizar e persistir comunicações reais com vínculo correto; registrar fluxo no Escriba. Verificação: execução controlada contra fonte e inspeção dos dados. Dep.: 1, 9–10. Arquivos: conector, processamento e testes.
- [ ] **12. Deduplicação.** Aceite: repetidos por busca ou execução aparecem uma vez por tenant; comunicações distintas permanecem distintas. Verificação: simular 15 resultados repetidos e cinco novos. Dep.: 11. Arquivos: persistência e testes.
- [ ] **13. Agenda e falhas.** Aceite: duas execuções diárias, tentativas e estado de falha por tribunal; execução posterior recupera resultados. Verificação: fonte controlada falha e depois responde. Dep.: 12. Arquivos: agendador, execução e testes.

## Checkpoint 4
- [ ] Duas coletas e recuperação demonstradas sem duplicação; registros rastreáveis.

- [ ] **14. Consulta de comunicações.** Aceite: resultados independentes agrupados por tribunal e detalhes com conteúdo disponível, respeitando permissões. Verificação: navegador e chamadas diretas com usuários restritos. Dep.: 6, 12. Arquivos: consulta, interface e testes.
- [ ] **15. Dashboard e restrição.** Aceite: volumetrias acordadas, aviso de tribunal com falha e `*` para usuário sem acesso. Verificação: navegador com usuários permitidos e restritos. Dep.: 2, 13–14. Arquivos: agregação, interface e testes.
- [ ] **16. Verificação integrada e carga.** Aceite: 300 usuários simultâneos atendem ao critério mensurável aprovado; fluxos e isolamento íntegros. Verificação: teste de carga reproduzível e cenário ponta a ponta no navegador. Dep.: 14–15. Arquivos: cenários e documentação de resultados.

## Checkpoint final
- [ ] Critérios da especificação satisfeitos, resultados registrados e revisão humana concluída.
