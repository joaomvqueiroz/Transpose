# BEHAVIOR CONTRACT

Este documento responde “o que deve acontecer?” em cenários que costumam gerar implementações diferentes.

## 1. Play/Pause

- Um toque = uma intenção.
- Repetidos taps não criam múltiplos players.
- UI só mostra PLAYING quando o Player Core confirmou estado.

## 2. Seek

Durante playback:

- seek atualiza posição;
- pitch e speed permanecem;
- loop permanece somente conforme política abaixo.

Se seek for para fora de um loop ativo:
- comportamento oficial recomendado: manter marcadores A/B, mas desativar `loop_enabled`.
- mostrar estado de loop como OFF.
- não forçar utilizador de volta para A silenciosamente.

## 3. Alterar A/B

- `A < B` sempre.
- se utilizador tentar B <= A, impedir visualmente ou ajustar conforme mínimo definido;
- nunca persistir loop inválido.

## 4. Trocar música

Ao trocar música:

- salvar snapshot da atual;
- parar/finalizar operações dependentes;
- loop ativo não migra para a nova música;
- pitch/speed:
  - aplicar preset da nova música se existir;
  - caso contrário usar defaults definidos pelo produto;
- recording associado à música anterior deve ser finalizado ou exigir confirmação se isso implicar perda.

## 5. Fullscreen

- mesma sessão;
- mesma posição;
- mesmo loop;
- mesmo pitch/speed;
- sair de fullscreen não recarrega mídia.

## 6. Bloqueio do fullscreen

Com lock ativo:

- bloquear seek gestual;
- bloquear pitch/speed;
- bloquear taps de transporte;
- permitir mecanismo explícito de desbloqueio por pressão longa/gesto deliberado;
- não bloquear ações de segurança do SO.

## 7. Background

Ao ir para Home:

- autosave imediato do snapshot;
- se background playback suportado/ativado, continuar;
- caso contrário, pausar;
- parar render/animação de vídeo desnecessária.

## 8. Lock screen

Segue mesma política do background.

Nunca iniciar playback porque o ecrã foi desbloqueado.

## 9. Chamada

Ao receber chamada:

```text
PLAYING → INTERRUPTED
```

Default seguro no fim da chamada:

```text
INTERRUPTED → PAUSED
```

Se no futuro houver auto-resume, precisa ser opção/decisão explícita.

## 10. Notificação curta

Pode ocorrer ducking se plataforma recomendar.

Não deve:

- zerar loop;
- alterar pitch;
- resetar speed;
- duplicar saída.

## 11. Bluetooth disconnect

Default seguro recomendado:

- pausar a reprodução;
- preservar posição;
- preservar pitch/speed/loop;
- mostrar aviso discreto;
- não começar a tocar em speaker automaticamente se houver risco de volume inesperado.

## 12. Bluetooth reconnect

- reconhecer nova rota;
- não autoplay;
- utilizador retoma manualmente, salvo configuração futura explícita.

## 13. Bluetooth + microfone

Se o sistema mudar para perfil de comunicação:

- preservar sessão;
- informar possível redução de qualidade/maior latência;
- gravação não pode corromper;
- diagnóstico deve registrar route/profile.

## 14. Processo morto pelo SO

Ao reabrir:

- carregar último snapshot consistente;
- mostrar sessão restaurada;
- estado de reprodução = PAUSED/READY;
- nunca autoplay.

## 15. Crash

Mesmo comportamento de process death.

Se o snapshot mais novo for inválido:
- tentar último snapshot válido;
- se não houver, abrir de forma limpa.

## 16. Reboot

- restaurar dados e sessão;
- não iniciar mídia;
- não iniciar gravação;
- não reconectar ações destrutivas automaticamente.

## 17. Apagar loop ativo

Recomendado:

- pedir confirmação apenas se não houver Undo;
- após delete:
  - `loop_enabled=false`;
  - limpar referência ativa;
  - manter playback.

## 18. Apagar gravação

Preferir:
- mover para estado recuperável/Undo por curto período;
- deleção física posterior.

## 19. Aplicar preset

Transação lógica:

```text
validate preset
→ apply supported properties
→ confirm engine state
→ persist active preset
→ update UI
```

Se um campo não for suportado pela fonte atual:
- aplicar os demais;
- informar apenas se necessário;
- não falhar o preset inteiro.

## 20. Erro de fonte online

- não apagar estado local;
- mostrar ação "Tentar novamente";
- funções de biblioteca local continuam disponíveis.

## 21. Falta de microfone

- Player continua funcionando;
- gravador mostra erro contextual;
- não pedir permissão no launch.

## 22. Permissão negada

- explicar por que a função precisa;
- oferecer ir às definições quando adequado;
- não bloquear app inteira.

## 23. Modo Palco

- prevenir sleep se o utilizador estiver em apresentação e a política permitir;
- lock interno opcional;
- não mostrar popups não críticos no meio da execução;
- erros críticos podem interromper com mensagem clara.

## 24. Practice Mode

Se utilizador sair da tela:
- treino continua se sessão continuar ativa;
- progresso persistido;
- voltar à tela reconstrói UI a partir do estado do engine.

## 25. Mudança de speed durante treino

Recomendado:
- se manual, pausa progressão automática;
- pedir/mostrar que o treino passou para ajuste manual;
- não continuar incrementos escondidos.

## 26. Fonte sem capability

Exemplo: fonte não permite processamento de áudio.

A UI:
- desativa Pitch/Speed/Loop preciso;
- mostra motivo curto;
- não finge que a função foi aplicada.
