#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9_.:-]+$')]
    [string] $DeviceId,
    [ValidateSet('debug', 'release')]
    [string] $Mode = 'debug',
    [switch] $Personal,
    [switch] $BuildOnly,
    [string] $FlutterPath = (Join-Path $env:LOCALAPPDATA 'Codex\Toolchains\flutter\bin\flutter.bat'),
    [string] $AndroidSdk = (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mobileRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $FlutterPath)) { throw "Flutter not found: $FlutterPath" }
if (-not $BuildOnly -and -not $DeviceId) { throw 'Specify -DeviceId or -BuildOnly.' }
if (-not $BuildOnly -and -not (Test-Path -LiteralPath $adb)) { throw "ADB not found: $adb" }
$keyPath = $env:TRANSPONO_DEV_KEYSTORE
if (-not $keyPath) { $keyPath = Join-Path $env:USERPROFILE '.android\transpono-dev.keystore' }
if (-not (Test-Path -LiteralPath $keyPath)) {
    $keytool = (Get-Command keytool -ErrorAction Stop).Source
    New-Item -ItemType Directory -Force -Path (Split-Path $keyPath) | Out-Null
    & $keytool -genkeypair -keystore $keyPath -storepass android -keypass android `
        -alias transponodev -keyalg RSA -keysize 2048 -validity 10000 `
        -dname 'CN=Transpono Development, OU=Development, O=Transpono, C=PT'
    if ($LASTEXITCODE -ne 0) { throw 'Development key creation failed.' }
}
$previousSdk = $env:ANDROID_HOME
$previousKey = $env:TRANSPONO_DEV_KEYSTORE
Push-Location -LiteralPath $mobileRoot
try {
    $env:ANDROID_HOME = $AndroidSdk
    $env:TRANSPONO_DEV_KEYSTORE = $keyPath
    $buildVariant = if ($Personal) { 'transponoPersonal=true' } else { 'transponoDev=true' }
    $expectedPackage = if ($Personal) { 'com.example.transpose_mobile.personal' } else { 'com.example.transpose_mobile.dev' }
    & $FlutterPath build apk "--$Mode" --target=lib/main.dart --dart-define=TRANSPONO_PERSONAL_RHYTHM=true "--android-project-arg=$buildVariant"
    if ($LASTEXITCODE -ne 0) { throw 'Development build failed. Nothing was installed.' }
    $apkDirectory = Join-Path $mobileRoot "build\app\outputs\apk\$Mode"
    $metadata = Get-Content -Raw -LiteralPath (Join-Path $apkDirectory 'output-metadata.json') | ConvertFrom-Json
    if ($metadata.applicationId -cne $expectedPackage -or
        $metadata.variantName -cne $Mode -or $metadata.elements.Count -ne 1) {
        throw 'Unexpected APK identity or variant. Nothing was installed.'
    }
    $outputFile = $metadata.elements[0].outputFile
    if ([IO.Path]::GetFileName($outputFile) -cne $outputFile -or [IO.Path]::GetExtension($outputFile) -cne '.apk') {
        throw 'Unexpected APK filename. Nothing was installed.'
    }
    $apk = Join-Path $apkDirectory $outputFile
    if ($BuildOnly) { Write-Output "Development APK: $apk"; return }
    & $adb -s $DeviceId install -r $apk
    if ($LASTEXITCODE -ne 0) { throw 'Install failed. No automatic uninstall will be attempted.' }
    & $adb -s $DeviceId shell am start -W -n "$expectedPackage/com.example.transpose_mobile.MainActivity"
    if ($LASTEXITCODE -ne 0) { throw 'Development app launch failed.' }
} finally {
    Pop-Location
    $env:ANDROID_HOME = $previousSdk
    $env:TRANSPONO_DEV_KEYSTORE = $previousKey
}
