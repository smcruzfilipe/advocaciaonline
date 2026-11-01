# Golden Rules — YAGNI

> **YAGNI** — *You Aren't Gonna Need It*
> Não implemente algo até que exista uma necessidade real e presente para isso.

Estas regras valem para qualquer agente (humano ou IA) que contribua com este projeto. Em caso de conflito entre estas regras e a vontade de "deixar pronto para o futuro", **estas regras vencem**.

> **Disclaimer**
>
> Embora seja um excelente norte, seguir o YAGNI de forma cega ou extrema pode ser prejudicial. Ignorar completamente boas práticas de arquitetura ou deixar o código totalmente engessado para o futuro pode gerar retrabalho excessivo. O segredo está no discernimento: construir de forma simples o presente, mas mantendo a base aberta para evoluir quando a necessidade real aparecer.

---

## 1. Faça apenas o que foi pedido

Implemente exatamente o escopo da tarefa. Nada de funcionalidades "já que estou aqui", refatorações paralelas ou melhorias não solicitadas.

- Se não está no pedido, não entra no diff.
- Se achou algo que vale melhorar, **sugira** em vez de implementar.

## 2. Resolva o problema de hoje, não o de amanhã

Não construa para requisitos hipotéticos. O futuro é incerto; o código especulativo quase sempre está errado quando a necessidade real chega.

- ❌ "Vamos precisar suportar vários bancos de dados algum dia."
- ✅ "Hoje usamos PostgreSQL. Usamos PostgreSQL."

## 3. Sem abstração prematura

Não crie interfaces, classes base, factories, strategies ou camadas até que exista **repetição real**.

- **Regra dos três:** duplique uma vez, tolere duas, abstraia na terceira.
- Uma abstração com uma única implementação é complexidade sem retorno.
- Duplicação é mais barata que a abstração errada.

## 4. Sem configurabilidade especulativa

Não transforme em parâmetro, flag, variável de ambiente ou arquivo de configuração aquilo que não precisa variar hoje.

- Valor fixo e claro > opção que ninguém usa.
- Adicione a opção no dia em que alguém realmente precisar de outro valor.

## 5. Prefira a solução mais simples que funciona

Entre duas soluções corretas, escolha a mais simples, curta e legível.

- Funções simples antes de classes.
- Código direto antes de padrões de projeto.
- Biblioteca padrão antes de dependência externa.

## 6. Não adicione dependências sem necessidade

Cada dependência é custo permanente: atualização, segurança, tamanho, compatibilidade.

- Só adicione quando o benefício for claro e a alternativa própria for sensivelmente pior.
- Não puxe uma biblioteca inteira para usar uma única função.

## 7. Código morto não fica

Código não utilizado, comentado ou "guardado para depois" deve ser removido. O controle de versão existe para isso.

- Sem blocos comentados.
- Sem funções, parâmetros ou arquivos sem uso.
- Sem `TODO` que descrevem funcionalidades futuras especulativas.

## 8. Sem pontos de extensão "para o futuro"

Não crie hooks, plugins, eventos ou camadas de indireção só porque *talvez* alguém queira estender.

- Extensibilidade se adiciona quando o primeiro caso real de extensão aparece.

## 9. Mudanças pequenas e focadas

Prefira diffs pequenos, revisáveis e com um único propósito.

- Uma mudança = um motivo.
- Não misture refatoração, correção de bug e nova funcionalidade no mesmo commit.

## 10. Teste o que existe

Escreva testes para o comportamento implementado, não para cenários imaginários.

- Cubra o caminho principal e os erros que realmente podem ocorrer.
- Não crie infraestrutura de teste elaborada antes de ter o que testar.

## 11. Trate apenas erros que podem acontecer

Valide nas fronteiras (entrada do usuário, APIs externas, I/O). Não proteja código interno contra situações impossíveis.

- Sem `try/catch` defensivo "por garantia".
- Sem validações redundantes de algo que o sistema de tipos ou o chamador já garante.

## 12. Documente o que existe

Documentação descreve o comportamento atual, não planos futuros.

- Comentários explicam o **porquê**, não repetem o **o quê**.
- Sem seções de "roadmap" ou "funcionalidades futuras" espalhadas pelo código.

## 13. Na dúvida, escolha o mínimo — ou pergunte

Se o requisito for ambíguo, não preencha as lacunas com suposições elaboradas.

1. Faça a menor implementação que atenda ao que está claro.
2. Pergunte sobre o que não está claro.
3. Evolua quando houver resposta.

---

## Checklist antes de adicionar qualquer coisa

Antes de criar uma função, classe, parâmetro, dependência ou arquivo, responda:

- [ ] Isso é **necessário agora** para a tarefa atual?
- [ ] Existe um caso de uso **real e concreto** (não hipotético)?
- [ ] Existe uma forma **mais simples** de resolver?
- [ ] Posso adicionar isso **depois**, quando precisar, sem grande custo?

Se qualquer resposta indicar que não é necessário: **não adicione**.

---

## Sinais de alerta (violações comuns)

| Frase típica | Problema | O que fazer |
|---|---|---|
| "Vamos precisar disso depois" | Especulação | Implemente depois |
| "Deixei configurável por garantia" | Configuração sem uso | Use um valor fixo |
| "Criei uma interface genérica" | Abstração com 1 implementação | Use a implementação direta |
| "Vou deixar comentado, vai que" | Código morto | Delete (o Git guarda) |
| "Já que estou aqui, melhorei também…" | Escopo expandido | Separe em outra tarefa |
| "Adicionei uma lib para facilitar" | Dependência desnecessária | Use a biblioteca padrão |

---

## O que YAGNI **não** significa

YAGNI combate o excesso, não a qualidade. Continuam obrigatórios:

- Código legível, bem nomeado e correto.
- Testes para o comportamento implementado.
- Tratamento de erros e segurança onde há risco real.
- Refatoração contínua para manter o código simples.

> **Simples não é descuidado.** É fazer o necessário, bem feito, e nada além disso.
