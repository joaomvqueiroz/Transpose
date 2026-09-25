# ACCESSIBILITY

## 1. Objetivo

Acessibilidade faz parte da definição de pronto, não é acabamento tardio.

## 2. Touch targets

- mínimo recomendado: 44–48 dp/pt;
- Modo Palco: preferir ainda maiores;
- espaço entre controles críticos;
- não colocar -1 e +1 tão próximos que provoquem taps acidentais.

## 3. Contraste

- texto principal com contraste forte;
- cinza secundário ainda legível;
- cyan não pode ser a única indicação de estado;
- erros não dependem apenas de vermelho.

## 4. Screen readers

Todo controle precisa de:

- label;
- role;
- state;
- value quando aplicável.

Exemplo:

```text
"Tom atual, Si bemol, menos dois semitons"
"Diminuir tom em um semitom"
"Velocidade, 75 por cento"
"Loop A-B, ativo"
```

## 5. Ordem de foco

Player:

```text
Vídeo
Tom
Diminuir
Aumentar
Velocidade
Loop
Retroceder
Play/Pause
Avançar
Ferramentas
Bottom navigation
```

## 6. Motion

Respeitar Reduce Motion.

Quando ativo:

- remover transforms grandes;
- reduzir parallax;
- trocar animações complexas por fade curto;
- manter feedback funcional.

## 7. Haptics

- opcional;
- nunca única forma de feedback;
- desligável;
- usar em ações discretas: set loop point, lock, preset applied.

## 8. Tipografia

Evitar texto essencial < 12.

Preferência:

- 20–32 títulos/valores dominantes;
- 14–16 texto normal;
- 12–13 secundário.

Suportar text scaling até limite que preserve operação; telas críticas podem reorganizar layout.

## 9. Orientação

Fullscreen deve funcionar landscape/portrait se suportado.

Palco deve manter controles acessíveis em orientação escolhida.

## 10. Destreza

Permitir operação com uma mão quando possível.

Não depender de gestos escondidos para ações essenciais; gestos têm alternativa por botão.

## 11. Cor

Estados:

- ativo = cyan + forma/ícone/texto;
- erro = vermelho + ícone/mensagem;
- disabled = opacidade + semântica de disabled.

## 12. Áudio

Não depender apenas de beep para confirmação.

## 13. Testes

- TalkBack;
- VoiceOver;
- text scaling;
- Reduce Motion;
- alto contraste quando disponível;
- navegação com switch/teclado quando plataforma suportar;
- daltonismo simulado.

## 14. Definition of Done

Nova feature não está pronta sem:

- labels;
- foco;
- touch target;
- contraste;
- estado disabled;
- redução de movimento;
- alternativa a gesto essencial.
