# Interface visual — painéis nativos

As seis referências fornecidas continuam a orientar o visual:

| Referência | Tela no app | Navegação |
| --- | --- | --- |
| `PlayerPrincipal` | Player | Aba Player |
| `PaineldePratica` | Prática | Aba Prática |
| `AcordeSincronizado` | Acordes | Aba Acordes |
| `ModoPalco` | Palco | Aba Palco |
| `SidebarMenuLateral` | Menu lateral | Botão de menu |
| `PlayerFullscreen` | Tela cheia | Ícone de tela cheia no Player |

Após a primeira revisão no Android, as capturas `screen.png` de 390 px foram
retiradas da interface do app: a ampliação tornava textos e botões desfocados.
Agora texto, cartões, ícones, barras e botões são widgets Flutter renderizados
na resolução do dispositivo. Não há `BoxFit.fill` nas telas. A imagem de
concerto é um recurso independente de 941 × 1672 px e usa `BoxFit.cover`,
que preserva a proporção e recorta as bordas quando necessário; a fotografia
não deve ser descrita como Full HD nativo.

As abas, o menu e a tela cheia navegam. O botão central do Player visual abre
o player funcional anterior, preservando o trabalho de áudio existente. Os
outros controles visuais continuam reservados para a etapa funcional.

**Limite desta fase:** faixa, acordes, velocidade, progresso, setlist e valores
na tela cheia continuam exemplos estáticos, não dados reais da sessão. A arte
fotográfica gerada é um substituto visual para a imagem original de 512 ×
279 px; não pretende representar um músico real específico.

Verificação: `flutter analyze`, `flutter test test` (incluindo larguras de
320 e 430 dp), APK release no Samsung SM-A165F e inspeção visual das quatro
abas, do menu e da tela cheia. As capturas do aparelho estão temporariamente
em `apps/mobile/build/`.
