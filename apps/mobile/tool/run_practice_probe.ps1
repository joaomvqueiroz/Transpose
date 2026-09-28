#requires -Version 5.1
<#
.SYNOPSIS
Builds and runs the isolated Android progressive-practice probe.
.DESCRIPTION
Prebuilds the target, verifies the QA package, and supplies the exact binary to
Flutter Driver. Never uninstalls, clears data, or force-stops an app. Do not run
another Android build in this workspace concurrently.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_.:-]+$')]
    [string] $DeviceId,
    [ValidateNotNullOrEmpty()]
    [string] $FlutterPath = (Join-Path $env:LOCALAPPDATA 'Codex\Toolchains\flutter\bin\flutter.bat')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mobileRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeTarget = 'integration_test/practice_progression_probe_test.dart'
$probeDriver = 'test_driver/practice_progression_probe_test.dart'
$qaApplicationId = 'com.example.transpose_mobile.qa'
if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterPath"
}
$flutterExecutable = (Resolve-Path -LiteralPath $FlutterPath).Path
foreach ($requiredFile in @('pubspec.yaml', $probeTarget, $probeDriver)) {
    if (-not (Test-Path -LiteralPath (Join-Path $mobileRoot $requiredFile) -PathType Leaf)) {
        throw "Missing practice probe input: $requiredFile"
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
    Write-Host "Verified compatible $qaApplicationId; driver automatic cleanup is disabled."
    & $flutterExecutable drive --profile --keep-app-running -d $DeviceId `
        "--use-application-binary=$apkPath" "--target=$probeTarget" "--driver=$probeDriver"
    if ($LASTEXITCODE -ne 0) { throw 'Practice probe failed. No cleanup was performed.' }
} finally {
    Pop-Location
}
