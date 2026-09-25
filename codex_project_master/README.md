# MASTER DOCS — App Musical

Este diretório é a fonte de contexto para o Codex.

## Ordem de leitura obrigatória

1. `PROJECT_MEMORY.md` — o que o produto é e quais decisões já estão fixadas.
2. `ARCHITECTURE_DECISIONS.md` — decisões arquiteturais aceites, propostas e ainda abertas.
3. `TECHNICAL_SPEC.md` — como os módulos devem funcionar juntos.
4. `AUDIO_ARCHITECTURE.md` — regras específicas do motor de áudio/vídeo.
5. `DATA_MODEL.md` — entidades, campos, persistência e migrações.
6. `STATE_MACHINES.md` — estados e transições válidas.
7. `BEHAVIOR_CONTRACT.md` — comportamento oficial para situações ambíguas.
8. `AUTOSAVE_RECOVERY.md` — gravação de estado, snapshots e recuperação.
9. `ERROR_CATALOG.md` — erros internos e mensagens para o utilizador.
10. `CODEX_BACKLOG.md` — sequência executável de tarefas.
11. `QA_TELEMETRY.md` — instrumentação e diagnóstico.
12. `matriz_qa_app_musical.csv` — casos de teste reproduzíveis.
13. `ACCESSIBILITY.md` — requisitos de acessibilidade.
14. `ONBOARDING.md` — primeiro uso.
15. `PRIVACY_STORE_CHECKLIST.md` — segurança, privacidade e preparação para lojas.
16. `BETA_PLAN.md` — plano de validação real.
17. `MONETIZATION.md` — proposta de monetização sem prejudicar a prática.
18. `CODEX_PROMPTS.md` — prompts prontos para executar fases com escopo controlado.
19. `RELEASE_CHECKLIST.md` — última verificação antes de publicar.

## Regra de precedência

Em caso de conflito:

1. requisito explícito mais recente do utilizador;
2. `PROJECT_MEMORY.md`;
3. ADR `Accepted` em `ARCHITECTURE_DECISIONS.md`;
4. `TECHNICAL_SPEC.md` / `AUDIO_ARCHITECTURE.md`;
5. `BEHAVIOR_CONTRACT.md`;
6. `ROADMAP.md`;
7. implementação atual.

Não resolver conflito importante silenciosamente. Registar uma decisão.

## Regra para Codex

Antes de editar:

- ler os documentos relevantes;
- identificar o módulo dono da mudança;
- limitar o escopo;
- indicar testes afetados;
- preservar decisões aceites;
- não fazer refactors laterais sem necessidade.

Depois de editar:

- executar os testes aplicáveis;
- adicionar teste de regressão para qualquer bug corrigido;
- atualizar `PROJECT_MEMORY.md` quando uma nova decisão permanente for tomada;
- atualizar `ARCHITECTURE_DECISIONS.md` para decisões arquiteturais novas;
- não marcar uma tarefa como concluída sem satisfazer os critérios de aceitação.
