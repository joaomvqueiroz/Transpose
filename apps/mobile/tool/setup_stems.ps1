#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source = Join-Path $root '.third_party/demucs.cpp'
$commit = 'f1206e9adeea103aef4a636b9e62297cf1f8e34e'
if (-not (Test-Path -LiteralPath $source)) {
    & git clone https://github.com/sevagh/demucs.cpp.git $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not obtain Demucs source.' }
    & git -C $source checkout --detach $commit
    if ($LASTEXITCODE -ne 0) { throw 'Could not select pinned source.' }
}
$actual = & git -C $source rev-parse HEAD
if ($actual -cne $commit) { throw 'Existing source differs from the pinned revision; it was preserved.' }
& git -C $source submodule update --init --depth 1 vendor/eigen
if ($LASTEXITCODE -ne 0) { throw 'Could not obtain pinned Eigen source.' }
$model = Join-Path $root '.third_party/ggml-model-htdemucs-6s-f16.bin'
$hash = '09704F4CEAE204E56E77D5EEFD6AC71D7275BE81FD507E6913371D59ABCEE856'
if (-not (Test-Path -LiteralPath $model)) {
    $download = "$model.$([guid]::NewGuid().ToString('N')).partial"
    Invoke-WebRequest -Uri 'https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/8f58ac0491bbea657275bcd3e38af1ab3a27bfc9/ggml-model-htdemucs-6s-f16.bin' -OutFile $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -cne $hash) {
        throw "Model checksum mismatch. Unused download retained: $download"
    }
    Move-Item -LiteralPath $download -Destination $model
}
if ((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -cne $hash) {
    throw 'Existing model checksum mismatch; it was preserved and must not be loaded.'
}
Write-Output "Pinned source and verified 54,855,129-byte six-stem model ready: $source"
