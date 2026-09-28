#requires -Version 5.1
<#
.SYNOPSIS
Runs the synthetic beat scheduler or acoustic click probe on one Android QA device.
.DESCRIPTION
Builds and verifies the isolated QA package before installation. It never
opens YouTube, reads media, clears app data, or touches the production package.
The acoustic mode uses the QA microphone for generated clicks only and must
be run only with the device owner's explicit authorization.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_.:-]+$')]
    [string] $DeviceId,
    [ValidateSet('scheduler', 'acoustic')]
    [string] $Probe = 'scheduler',
    [ValidateNotNullOrEmpty()]
    [string] $FlutterPath = (Join-Path $env:LOCALAPPDATA 'Codex\Toolchains\flutter\bin\flutter.bat')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mobileRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeTarget = if ($Probe -eq 'acoustic') {
    'integration_test/native_beat_acoustic_probe_test.dart'
} else { 'integration_test/youtube_beat_native_probe_test.dart' }
$probeDriver = if ($Probe -eq 'acoustic') {
    'test_driver/native_beat_acoustic_probe_test.dart'
} else { 'test_driver/youtube_beat_native_probe_test.dart' }
$qaApplicationId = 'com.example.transpose_mobile.qa'
if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterPath"
}
$flutterExecutable = (Resolve-Path -LiteralPath $FlutterPath).Path
foreach ($requiredFile in @('pubspec.yaml', $probeTarget, $probeDriver)) {
    if (-not (Test-Path -LiteralPath (Join-Path $mobileRoot $requiredFile) -PathType Leaf)) {
        throw "Missing beat probe input: $requiredFile"
    }
}
Push-Location -LiteralPath $mobileRoot
try {
    & $flutterExecutable build apk --profile "--target=$probeTarget"
    if ($LASTEXITCODE -ne 0) { throw 'Probe build failed. Nothing was installed.' }
    $apkDirectory = Join-Path $mobileRoot 'build\app\outputs\apk\profile'
    $metadataPath = Join-Path $apkDirectory 'output-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw 'Missing APK metadata. Nothing was installed.'
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.applicationId -cne $qaApplicationId -or
        $metadata.variantName -cne 'profile' -or $metadata.artifactType.type -cne 'APK') {
        throw 'Unsafe package, variant or artifact type. Nothing was installed.'
    }
    $elements = @($metadata.elements)
    if ($elements.Count -ne 1 -or @($elements[0].filters).Count -ne 0) {
        throw 'Expected one universal QA APK. Nothing was installed.'
    }
    $outputFile = [string] $elements[0].outputFile
    if ([string]::IsNullOrWhiteSpace($outputFile) -or
        [System.IO.Path]::GetFileName($outputFile) -cne $outputFile -or
        [System.IO.Path]::GetExtension($outputFile) -cne '.apk') {
        throw 'Unsafe APK filename. Nothing was installed.'
    }
    $apkPath = Join-Path $apkDirectory $outputFile
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf) -or
        (Get-Item -LiteralPath $apkPath).Length -le 0) {
        throw 'Missing or empty verified APK. Nothing was installed.'
    }
    & (Join-Path $PSScriptRoot 'install_qa_apk_safely.ps1') -DeviceId $DeviceId -ApkPath $apkPath
    Write-Host "Verified compatible $qaApplicationId; production package remains untouched."
    & $flutterExecutable drive --profile --keep-app-running -d $DeviceId `
        "--use-application-binary=$apkPath" "--target=$probeTarget" "--driver=$probeDriver"
    if ($LASTEXITCODE -ne 0) { throw 'Beat probe failed. No cleanup was performed.' }
} finally {
    Pop-Location
}
