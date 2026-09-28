#requires -Version 5.1
<#
.SYNOPSIS
Checks that a verified QA APK can replace the installed QA app without data loss.
.DESCRIPTION
ADB install -r preserves app data on a compatible signature and fails without
uninstalling on a signature mismatch. Call this before Flutter Drive, which may
otherwise uninstall an incompatible package while trying to start the test.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_.:-]+$')]
    [string] $DeviceId,
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $ApkPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
    elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
    else { 'C:\Android\sdk' }
$adbExecutable = Join-Path $sdkRoot 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adbExecutable -PathType Leaf)) {
    throw "ADB executable not found: $adbExecutable"
}
& $adbExecutable -s $DeviceId install -r $ApkPath
if ($LASTEXITCODE -ne 0) {
    throw 'QA replace install failed (possibly different signer). Existing app was not removed; Flutter Drive was not started.'
}
