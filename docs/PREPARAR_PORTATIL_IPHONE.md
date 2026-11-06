# Preparar um portátil Windows para instalar o Transpono no iPhone

Feito e testado neste portátil (Windows 11) entre 05 e 06/11/2026. Segue a ordem.
Os passos marcados **[João]** têm de ser feitos por ti (palavras-passe, cliques no
iPhone, pedidos de administrador).

## 1. Programas a instalar

Todos vêm do **winget** e a verificação de hash passou em todos. Corre num PowerShell normal:

```powershell
winget install --id GitHub.cli   --exact --silent --accept-package-agreements --accept-source-agreements
winget install --id Apple.iTunes --exact --silent --accept-package-agreements --accept-source-agreements
```

O iTunes também instala o **Bonjour** e o **Suporte para Aplicações Apple** (32 e 64 bits).

Depois, **como administrador**: abre o PowerShell com «Executar como administrador» ou
aceita o pedido UAC.

```powershell
winget install --id RileyTestut.AltServer --exact --silent --accept-package-agreements --accept-source-agreements
```

Isto instala também o **iCloud (Legacy) 7.21.0.23**, a versão de fora da Microsoft Store
que o AltServer exige.

| Programa | Versão | Para quê |
|---|---|---|
| GitHub CLI (`gh`) | 2.103.3 | Ver os builds e descarregar os IPAs |
| iTunes | 12.13.12.3 | Drivers do iPhone e sincronização por Wi-Fi |
| iCloud (Legacy) | 7.21.0.23 | Exigido pelo AltServer |
| AltServer | 1.8.00 | Assina e instala os IPAs no iPhone |

### Problemas que apareceram e a solução

- **iCloud falha com o erro 1603** («Não dispõe de privilégios suficientes»): o instalador
  não pede administrador sozinho. Repete o comando do AltServer num PowerShell de administrador.
- **AltServer falha com `InternetOpenUrl() failed` / `0x80072EE7`**: foi uma falha de rede
  momentânea a resolver `cdn.altstore.io`. Basta repetir.
- **O Sideloadly (`iOSGods.Sideloadly`) foi recusado** («Installer hash does not match»). Não
  forces. O AltServer substitui-o.

## 2. Apple Mobile Device Support (faltou e é essencial)

O iTunes do winget **não instalou** o *Apple Mobile Device Support*. Sem ele, o AltServer
diz que não há dispositivos ligados, e o Windows só vê o iPhone como câmara de fotos.

Para verificar:

```powershell
Get-Service 'Apple Mobile Device Service'
```

Se não existir, tira-o do instalador do iTunes:

```powershell
$d = "$env:TEMP\itunes"; New-Item -ItemType Directory -Force $d | Out-Null
winget download --id Apple.iTunes --exact --download-directory $d --accept-package-agreements --accept-source-agreements
Push-Location $d; Start-Process (Get-ChildItem $d -Filter iTunes*.exe).FullName -ArgumentList '/extract' -WorkingDirectory $d -Wait; Pop-Location
$m = "$d\AppleMobileDeviceSupport64.msi"
Get-AuthenticodeSignature $m   # tem de dar Valid, CN=Apple Inc.
Start-Process msiexec.exe -Verb RunAs -ArgumentList '/i',"`"$m`"",'/qn','/norestart' -Wait
Get-Service 'Apple Mobile Device Service'   # deve estar Running
```

## 3. AltServer a correr e visível

- O winget instala o AltServer mas não o abre. Abre-o pelo menu Iniciar ou em
  `C:\Program Files (x86)\AltServer\AltServer.exe`. Não tem janela: só um ◆ junto ao relógio.
- Para o ◆ ficar sempre à vista: **Definições → Personalização → Barra de tarefas → Outros
  ícones da barra de tarefas → AltServer: ativado**.
- Para arrancar com o Windows, que é necessário para a renovação automática: `Win + R` →
  `shell:startup` → cria lá um atalho para o `AltServer.exe`.
- Se instalares o Apple Mobile Device Support depois de o AltServer estar aberto, fecha o
  AltServer e volta a abri-lo.

## 4. Contas **[João]**

1. **iCloud:** abre o iCloud no Windows e inicia sessão com o teu Apple ID. Se não souberes a
   palavra-passe, muda-a no iPhone em Definições → [o teu nome] → Início de sessão e
   segurança → Alterar palavra-passe. Só precisas do código do iPhone.
2. **GitHub CLI:** corre `gh auth login` → GitHub.com → HTTPS → Login with a web browser.
   O **código de 8 caracteres aparece no terminal**, não no browser. Copia-o para a página
   do GitHub e carrega em Authorize.

## 5. iPhone e AltStore **[João]**

1. Liga o iPhone por cabo, desbloqueia-o e toca em **Confiar** neste computador.
2. No **iTunes**: ícone do iPhone → Resumo → Opções → **Sincronizar com este iPhone por
   Wi-Fi** → Aplicar.
3. ◆ do AltServer → **Install AltStore** → o iPhone → Apple ID e palavra-passe. Se o iPhone
   mostrar um código de 6 dígitos, escreve-o no AltServer.
4. No iPhone:
   - Definições → Geral → **VPN e gestão de dispositivos** → o teu Apple ID → **Confiar**.
   - Definições → Privacidade e segurança → **Modo de programador** → ativar → reiniciar →
     confirmar **Ativar** depois do reinício.

Limites da conta gratuita: assinatura válida 7 dias (o AltStore renova por Wi-Fi com o
AltServer aberto), no máximo 3 apps ativas contando com o AltStore, e 10 IDs de app novos
por semana. As extensões, como a `Transpono Helper.appex`, contam como ID.

## 6. Instalar um IPA

1. iPhone ligado por cabo e desbloqueado.
2. **Shift + clique** no ◆ do AltServer → **Sideload .ipa…** → o iPhone → escolhe o IPA.
3. Se perguntar pelas App Extensions, **mantém-nas**.
4. Se aparecer o erro **−80046**, não insistas, porque pode bloquear a conta.

Instalar por cima de uma versão com o mesmo bundle id (`com.example.transposeMobile`)
substitui-a e mantém os dados da app.

## 7. Obter os IPAs

Os builds iOS são feitos no GitHub Actions. Não há Mac neste portátil.

```powershell
# Transpono com Gecko (Release, >100 MB)
gh release download ios-gecko-test-1 -R joaomvqueiroz/Transpose -D "$env:USERPROFILE\Downloads\Transpono-iOS-Gecko"
Get-FileHash "$env:USERPROFILE\Downloads\Transpono-iOS-Gecko\*.ipa" -Algorithm SHA256
#   Transpono-Gecko.ipa  DA6140658FA54044AE45BAC6D61C288693C30B3385779DCB78DC45D9E277EBC8
#   Reynard.ipa          6EBC53836A232D0BB1B655C97DD7B44156E1EE6CA0889EF383069FC7B0A1C1EA

# Artefacto do último build de um branch
gh run list -R joaomvqueiroz/Transpose --branch ios-gecko --limit 3
gh run download <id> -R joaomvqueiroz/Transpose -D "$env:USERPROFILE\Downloads\Transpono-iOS"
```

## 8. Extra: APK Android com os motores nativos (opcional)

Para o APK «Transpono Pessoal» com Rubber Band e Demucs são precisos o Flutter, o Android
SDK/NDK e as fontes em `.third_party` (`rubberband-v4.0.0` e `demucs.cpp`, criadas por
`apps/mobile/tool/setup_stems.ps1`). Não uses o `run_dev.ps1` no PowerShell 5.1: um aviso do
SDK no stderr faz o script parar. Corre o Flutter diretamente:

```bash
cd apps/mobile
export TRANSPOSE_RUBBERBAND_SOURCE_DIR='C:\Transpono\.third_party\rubberband-v4.0.0'
export TRANSPOSE_DEMUCS_SOURCE_DIR='C:\Transpono\.third_party\demucs.cpp'
flutter build apk --release --target=lib/main.dart --dart-define=TRANSPONO_PERSONAL_RHYTHM=true --android-project-arg=transponoPersonal=true
```
