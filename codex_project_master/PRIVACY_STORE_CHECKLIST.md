# PRIVACY & STORE CHECKLIST

> Checklist de produto/engenharia. Requisitos específicos de App Store/Google Play mudam; verificar as regras atuais antes da submissão.

## 1. Data map

Documentar:

| Dado | Onde | Por quê | Retenção | Cloud? |
|---|---|---|---|---|
| Presets | local | preferência | até apagar | opcional |
| Setlists | local | organização | até apagar | opcional |
| Loops | local | prática | até apagar | opcional |
| Practice progress | local | progresso | configurável | opcional |
| Recordings | ficheiro privado | gravação | até apagar | não por padrão |
| Auth token | secure storage | sessão | sessão/refresh | sim |
| QA logs | local limitado | diagnóstico | curto | opt-in export |

## 2. Permissões

Cada permissão:

- necessidade documentada;
- momento contextual;
- fallback se negada;
- mensagem clara.

Nunca pedir todas no primeiro launch.

## 3. Microfone

- indicador de gravação;
- Start explícito;
- Stop claro;
- não capturar em background sem feature e consentimento claros;
- não enviar áudio para cloud silenciosamente.

## 4. Ficheiros

- usar picker/scoped access quando possível;
- validar MIME real e estrutura;
- limites de tamanho;
- não executar conteúdo;
- não confiar na extensão.

## 5. Gravações

Default:

- armazenamento privado;
- nomes seguros;
- sem upload automático;
- delete/undo;
- proteção contra corrupção.

## 6. Conta

- logout;
- revogação de sessão;
- refresh token seguro;
- rate limit;
- não revelar se determinada conta existe quando isso criar risco desnecessário.

## 7. Cloud

- HTTPS;
- auth;
- authorization server-side;
- object access control;
- signed URLs com tempo limitado quando aplicável;
- secrets fora do cliente;
- backups protegidos.

## 8. WebView

- allowlist;
- bloquear esquemas perigosos;
- não injetar token na URL;
- bridge mínima;
- navegação externa tratada;
- cookies/storage revistos;
- conteúdo remoto não recebe APIs nativas sensíveis.

## 9. Analytics

- eventos mínimos;
- sem áudio;
- sem letras/notas privadas;
- sem tokens;
- sem paths privados completos;
- IDs pseudónimos quando possível.

## 10. Delete/export

Se conta/cloud existir:

- fluxo para apagar conta/dados;
- política para backups;
- export quando produto/região exigir;
- refletir na política de privacidade.

## 11. Compras

- entitlement não pode depender só de `isPremium` local;
- validar recibo/estado com mecanismo confiável;
- cache offline com expiração/política definida;
- restore purchases.

## 12. Logs

Sanitizar:

- Authorization;
- cookies;
- query params sensíveis;
- paths;
- emails;
- IDs externos;
- tokens.

## 13. Supply chain

- lockfile;
- revisão de dependências;
- alertas de vulnerabilidade;
- pacote abandonado deve ser substituído;
- SBOM se viável.

## 14. Release security

- build release sem debug endpoints;
- sem menu QA exposto;
- sem test API key;
- sem certificados de desenvolvimento;
- minificação/ofuscação como camada adicional, nunca proteção principal.

## 15. Política de privacidade

Deve refletir comportamento real.

Não prometer “nunca coletamos X” se SDK de terceiros coleta.

## 16. Antes das lojas

Verificar versão atual dos requisitos para:

- privacy disclosures;
- data safety;
- tracking;
- microphone/background;
- subscriptions;
- account deletion;
- third-party SDK disclosures.
