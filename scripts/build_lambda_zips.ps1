param(
    [string]$PythonLauncher = "python"
)

$ErrorActionPreference = "Stop"

$pythonCommand = (Get-Command $PythonLauncher -ErrorAction Stop).Source
$repoRoot = Split-Path -Parent $PSScriptRoot
$deployDir = Join-Path $repoRoot "deploy"
$packageDir = Join-Path $deployDir "package"
$requirements = Join-Path $repoRoot "requirements.txt"
$unlockHandler = Join-Path $repoRoot "lambdas/pdf_unlock/lambda_function.py"
$extractorHandler = Join-Path $repoRoot "lambdas/email_extractor/email_extractor.py"
$unlockZip = Join-Path $deployDir "pdf-unlock-function.zip"
$extractorZip = Join-Path $deployDir "email-extractor.zip"

New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

& $pythonCommand -m pip install `
    --requirement $requirements `
    --target $packageDir `
    --platform manylinux2014_x86_64 `
    --implementation cp `
    --python-version 3.13 `
    --only-binary=:all:

if ($LASTEXITCODE -ne 0) {
    throw "Failed to install Lambda dependencies (pip exit code: $LASTEXITCODE)."
}

Copy-Item -LiteralPath $unlockHandler -Destination $packageDir

Remove-Item -LiteralPath $unlockZip -Force -ErrorAction SilentlyContinue
Push-Location $packageDir
try {
    $archiveEntries = Get-ChildItem -Force | Select-Object -ExpandProperty Name
    & $pythonCommand -m zipfile -c $unlockZip @archiveEntries
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the PDF unlock Lambda ZIP (exit code: $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

Remove-Item -LiteralPath $extractorZip -Force -ErrorAction SilentlyContinue
Push-Location (Split-Path -Parent $extractorHandler)
try {
    & $pythonCommand -m zipfile -c $extractorZip (Split-Path -Leaf $extractorHandler)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create the email extractor Lambda ZIP (exit code: $LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

Write-Host "Created $unlockZip"
Write-Host "Created $extractorZip"
