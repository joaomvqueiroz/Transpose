# BETA PLAN

## 1. Fases

### Alpha interna

Participantes:
- equipa/desenvolvimento.

Objetivo:
- estabilidade técnica.

Entrada:
- Player funcional.

Saída:
- nenhum P0;
- player 60 min;
- loop básico;
- restore básico;
- QA overlay.

### Beta fechada 1

5–15 músicos.

Objetivo:
- fluxo real de prática.

Tarefas:
- abrir música;
- mudar tom;
- desacelerar;
- criar loop;
- praticar 20 min;
- fullscreen;
- lock/unlock;
- BT.

Saída:
- sem bloqueadores;
- UX principal compreendida sem treino;
- P1 críticos corrigidos.

### Beta fechada 2

20–50 testers, dispositivos diversos.

Objetivo:
- compatibilidade.

Foco:
- Android fraco;
- Android médio;
- Android forte;
- iPhone antigo suportado;
- iPhone recente;
- speaker;
- wired/USB;
- Bluetooth.

### Release Candidate

Objetivo:
- provar critérios quantitativos.

Saída:
- suite de release aprovada;
- zero P0/P1 aberto;
- privacy/store checklist;
- crash-free e métricas dentro do orçamento.

## 2. Sessões de teste

### Sessão A — 15 min

- load;
- Play;
- pitch;
- speed;
- loop;
- seek.

### Sessão B — 30 min

- practice mode;
- vários loops;
- fullscreen;
- background.

### Sessão C — 60 min stress

- pitch -2;
- speed 0.75;
- loop;
- fullscreen;
- lock;
- Home;
- BT connect/disconnect;
- chamada;
- retorno;
- troca de música.

## 3. Bug report obrigatório

```text
Build:
Dispositivo:
SO:
RAM:
Fonte:
Saída de áudio:
Bluetooth modelo:
Passos:
Esperado:
O que aconteceu:
Reproduz quantas vezes:
Horário aproximado:
Session/diagnostic ID:
Screenshot/video opcional:
```

Nunca pedir gravação pessoal sem necessidade.

## 4. Severidade

P0:
- perda/corrupção;
- crash crítico;
- comportamento de áudio potencialmente perigoso.

P1:
- áudio para/duplica;
- estado musical errado;
- restore falha.

P2:
- loop/drift/BT inconsistente.

P3:
- UX.

P4:
- cosmético.

## 5. Exit criteria

Antes de RC:

- 0 P0;
- 0 P1 conhecido;
- 60 min sem crash;
- state restore >= 99,9% nos testes definidos;
- loop dentro das metas;
- A/V dentro das metas;
- BT desconexão segura;
- chamada segura;
- nenhuma gravação corrompida nos casos de QA;
- onboarding testado sem explicação.

## 6. Teste observacional

Dar o app a músicos sem tutorial falado.

Observar:
- onde hesitam;
- onde erram;
- quais nomes não entendem;
- se encontram Loop;
- se conseguem voltar ao Player;
- se Modo Palco é legível à distância.

Não corrigir o utilizador durante os primeiros minutos, salvo risco.
