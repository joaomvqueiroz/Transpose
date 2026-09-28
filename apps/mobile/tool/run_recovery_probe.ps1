#requires -Version 5.1
<#
.SYNOPSIS
Builds and runs one isolated phase of the Android recovery probe.
.DESCRIPTION
The Flutter DriverService can remember an APK identity before startApp rebuilds
the target. A cached production APK may therefore give its cleanup the wrong
package identity. Build first, verify the QA applicationId, then pass that exact
APK as --use-application-binary. Always keep the app installed/running afterward.

This wrapper never uninstalls, clears app data, deletes files, or force-stops an
app. Do not run another Android build against this workspace concurrently.
Seed waits for an external QA-only force-stop after READY_TO_KILL; its resulting
driver disconnect/nonzero exit is expected. Run verify with the same RunId.
.EXAMPLE
.\tool\run_recovery_probe.ps1 -Phase seed -RunId recovery-20260925-a -DeviceId R58YA16NDVM
.EXAMPLE
.\tool\run_recovery_probe.ps1 -Phase verify -RunId recovery-20260925-a -DeviceId R58YA16NDVM
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('seed', 'verify')]
    [string] $Phase,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_-]{1,64}$')]
    [string] $RunId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_.:-]+$')]
    [string] $DeviceId,

    [ValidateNotNullOrEmpty()]
    [string] $FlutterPath = (Join-Path $env:LOCALAPPDATA 'Codex\Toolchains\flutter\bin\flutter.bat')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mobileRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeTarget = 'integration_test/recovery_process_probe_test.dart'
$probeDriver = 'test_driver/recovery_process_probe_test.dart'
$qaApplicationId = 'com.example.transpose_mobile.qa'
$normalizedPhase = $Phase.ToLowerInvariant()

if (-not (Test-Path -LiteralPath $FlutterPath -PathType Leaf)) {
    throw "Flutter executable not found: $FlutterPath. Supply -FlutterPath explicitly."
}
$flutterExecutable = (Resolve-Path -LiteralPath $FlutterPath).Path
foreach ($requiredFile in @('pubspec.yaml', $probeTarget, $probeDriver)) {
    if (-not (Test-Path -LiteralPath (Join-Path $mobileRoot $requiredFile) -PathType Leaf)) {
        throw "Missing recovery probe input: $requiredFile"
    }
}

$defines = @(
    "--dart-define=RECOVERY_PROBE_PHASE=$normalizedPhase",
    "--dart-define=RECOVERY_PROBE_ID=$RunId"
)

Push-Location -LiteralPath $mobileRoot
try {
    $buildArguments = @('build', 'apk', '--profile', "--target=$probeTarget") + $defines
    Write-Host "Building isolated recovery probe: phase=$normalizedPhase run=$RunId"
    & $flutterExecutable @buildArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Recovery probe build failed (exit $LASTEXITCODE). No drive command was started."
    }

    $apkDirectory = Join-Path $mobileRoot 'build\app\outputs\apk\profile'
    $metadataPath = Join-Path $apkDirectory 'output-metadata.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw 'Missing APK output metadata. Refusing to install an unverified build.'
    }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.applicationId -cne $qaApplicationId) {
        throw "Unsafe applicationId '$($metadata.applicationId)'. Required: $qaApplicationId. Nothing was installed."
    }
    if ($metadata.variantName -cne 'profile' -or $metadata.artifactType.type -cne 'APK') {
        throw 'Unexpected build variant or artifact type. Nothing was installed.'
    }
    $elements = @($metadata.elements)
    if ($elements.Count -ne 1 -or @($elements[0].filters).Count -ne 0) {
        throw 'Expected one universal profile APK. Split or ambiguous APK output is not accepted.'
    }
    $outputFile = [string] $elements[0].outputFile
    if ([string]::IsNullOrWhiteSpace($outputFile) -or
        [System.IO.Path]::GetFileName($outputFile) -cne $outputFile -or
        [System.IO.Path]::GetExtension($outputFile) -cne '.apk') {
        throw 'Invalid APK filename in build metadata. Nothing was installed.'
    }
    $apkPath = Join-Path $apkDirectory $outputFile
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf) -or
        (Get-Item -LiteralPath $apkPath).Length -le 0) {
        throw 'Verified metadata does not have a corresponding nonempty APK.'
    }

    # Supplying the verified APK skips the drive rebuild and makes the driver
    # resolve the QA package identity before launching or retrying startApp.
    $driveArguments = @(
        'drive',
        '--profile',
        '--keep-app-running',
        '-d', $DeviceId,
        "--use-application-binary=$apkPath",
        "--target=$probeTarget",
        "--driver=$probeDriver"
    ) + $defines
    & (Join-Path $PSScriptRoot 'install_qa_apk_safely.ps1') -DeviceId $DeviceId -ApkPath $apkPath
    Write-Host "Verified compatible $qaApplicationId. Starting $normalizedPhase without automatic cleanup."
    if ($normalizedPhase -eq 'seed') {
        Write-Host 'Wait for READY_TO_KILL before externally force-stopping the QA package only.'
    }
    & $flutterExecutable @driveArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Recovery probe driver exited with $LASTEXITCODE. No cleanup was performed. A seed disconnect after READY_TO_KILL is expected; otherwise inspect the failure before continuing."
    }
} finally {
    Pop-Location
}
