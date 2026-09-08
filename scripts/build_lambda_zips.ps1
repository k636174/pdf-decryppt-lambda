param(
    [string]$PythonLauncher = "py"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$deployDir = Join-Path $repoRoot "deploy"
$packageDir = Join-Path $deployDir "package"
$requirements = Join-Path $repoRoot "requirements.txt"
$unlockHandler = Join-Path $repoRoot "lambda_function.py"
$extractorHandler = Join-Path $repoRoot "email_extractor.py"
$unlockZip = Join-Path $deployDir "pdf-unlock-function.zip"
$extractorZip = Join-Path $deployDir "email-extractor.zip"

New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

& $PythonLauncher -3.13 -m pip install `
    --requirement $requirements `
    --target $packageDir `
    --platform manylinux2014_x86_64 `
    --implementation cp `
    --python-version 3.13 `
    --only-binary=:all:

Copy-Item -LiteralPath $unlockHandler -Destination $packageDir

Compress-Archive `
    -Path (Join-Path $packageDir "*") `
    -DestinationPath $unlockZip `
    -Force

Compress-Archive `
    -LiteralPath $extractorHandler `
    -DestinationPath $extractorZip `
    -Force

Write-Host "Created $unlockZip"
Write-Host "Created $extractorZip"
