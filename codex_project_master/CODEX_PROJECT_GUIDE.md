# CODEX PROJECT GUIDE

Antes de qualquer tarefa:

1. Leia `PROJECT_MEMORY.md`.
2. Leia `ARCHITECTURE_DECISIONS.md`.
3. Localize a tarefa em `CODEX_BACKLOG.md`.
4. Leia o spec correspondente.
5. Verifique os testes na matriz QA.
6. Liste os ficheiros que pretende alterar antes de uma mudança grande.
7. Faça escopo mínimo.
8. Execute testes.
9. Atualize documentação quando uma decisão permanente mudar.

Não faça:
- refactor lateral desnecessário;
- escolha silenciosa de stack/SDK em ADR Open;
- mudança visual global fora da tarefa;
- autoplay após restore;
- segundo player no fullscreen;
- secrets no cliente;
- lógica de negócio presa a widgets;
- DB/rede no callback de áudio.

Ao terminar uma tarefa, reporte:

```text
Tarefa:
Ficheiros alterados:
Comportamento:
Testes:
Métricas:
Riscos restantes:
Docs/ADR atualizados:
```
