# RELEASE CHECKLIST

## Build

- [ ] release build compila
- [ ] debug flags removidas
- [ ] QA overlay inacessível em produção
- [ ] nenhuma test API key
- [ ] nenhum secret no bundle
- [ ] version/build number correto

## Core

- [ ] Play/Pause
- [ ] Seek
- [ ] Pitch
- [ ] Speed
- [ ] Loop
- [ ] Fullscreen
- [ ] Autosave
- [ ] Restore

## Reliability

- [ ] 60 min stress
- [ ] zero áudio duplicado
- [ ] zero crash crítico
- [ ] zero take corrompido nos testes
- [ ] background
- [ ] lock/unlock
- [ ] process death
- [ ] reboot
- [ ] chamada
- [ ] Bluetooth connect
- [ ] Bluetooth disconnect
- [ ] wired/USB quando suportado

## Metrics

- [ ] Play/Pause P95 < 100 ms
- [ ] Pitch P95 < 150 ms
- [ ] Speed P95 < 150 ms
- [ ] Loop P95 < 25 ms
- [ ] Loop P99 < 40 ms
- [ ] Loop drift < 25 ms / 1000
- [ ] A/V drift < 50 ms / 30 min
- [ ] Restore >= 99,9%

## UX

- [ ] primeiro Play sem confusão
- [ ] Tom legível
- [ ] speed legível
- [ ] loop compreensível
- [ ] fullscreen realmente imersivo
- [ ] Modo Palco legível
- [ ] ações destrutivas têm Undo/confirmação

## Accessibility

- [ ] touch targets
- [ ] labels
- [ ] foco
- [ ] contraste
- [ ] Reduce Motion
- [ ] alternativa a gestos

## Security

- [ ] secrets
- [ ] storage seguro
- [ ] logs sanitizados
- [ ] WebView
- [ ] import validation
- [ ] entitlement
- [ ] dependency audit

## Privacy

- [ ] data map atualizado
- [ ] permissões contextuais
- [ ] política de privacidade corresponde ao app
- [ ] delete/export quando aplicável
- [ ] disclosures das lojas revistos com requisitos atuais

## Beta

- [ ] zero P0 aberto
- [ ] zero P1 aberto
- [ ] feedback de músicos revisto
- [ ] regressões convertidas em testes
