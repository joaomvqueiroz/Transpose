# MONETIZATION — proposta

> Documento de produto, não decisão imutável. Ajustar após beta.

## 1. Princípio

O músico nunca deve ser interrompido por um paywall no meio de uma prática ou apresentação.

Evitar:

- anúncio entre loops;
- anúncio ao tocar Play;
- popup premium durante Modo Palco;
- bloquear acesso a gravação já criada;
- tornar a app inútil sem assinatura.

## 2. Free sugerido

Manter um núcleo realmente útil:

- Player;
- Play/Pause/seek;
- pitch básico;
- speed;
- A-B loop;
- número limitado razoável de loops/presets ou sem limite inicialmente;
- afinador/metrónomo básicos;
- uso local.

## 3. Pro sugerido

Possíveis diferenciadores:

- treino progressivo avançado;
- biblioteca de loops ilimitada;
- presets/setlists avançados;
- análise automática de BPM/key/acordes;
- export/backup;
- cloud sync;
- comparação de recordings;
- qualidade DSP Studio;
- ferramentas avançadas de palco;
- recursos de IA;
- stem separation se futuramente suportada.

## 4. Não vender segurança/confiabilidade

Nunca deixar Pro como requisito para:

- recovery;
- autosave;
- estabilidade;
- privacidade;
- acessibilidade;
- suporte básico de Bluetooth.

## 5. Trial

Se usar trial:

- mostrar duração claramente;
- não esconder renovação;
- não bloquear sessão ativa quando expira no meio de prática; aplicar mudança no próximo boundary seguro.

## 6. Paywall

Mostrar quando o utilizador tenta uma função Pro.

Formato:

```text
Análise automática de acordes
Disponível no Pro.

[Experimentar Pro]
[Agora não]
```

Sem dark patterns.

## 7. Métricas

Avaliar:

- conversão;
- retenção;
- uso real da feature;
- cancelamento;
- regressão de uso após paywall.

Não otimizar apenas receita sacrificando a experiência principal.

## 8. Segurança

Entitlements validados por backend/mecanismo confiável.

Offline:
- cache assinado/validado;
- política de graça definida;
- não confiar em flag editável simples.
