# Free, project-local tools. Does not configure live providers or API keys.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    if (-not (Test-Path -LiteralPath '.tools\flutter')) {
        New-Item -ItemType Directory -Path '.tools' -Force | Out-Null
        git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git .tools/flutter
        if ($LASTEXITCODE -ne 0) { throw 'Flutter download failed.' }
    }
    $sdkTag = git -C .tools/flutter describe --tags --exact-match
    if ($LASTEXITCODE -ne 0 -or $sdkTag -ne '3.47.7') {
        throw 'Expected Flutter 3.47.7. Inspect the existing .tools/flutter folder before changing it.'
    }
    & .\.tools\flutter\bin\flutter.bat pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency setup failed.' }
    if (-not (Test-Path -LiteralPath '.venv\Scripts\python.exe')) {
        python -m venv .venv
        if ($LASTEXITCODE -ne 0) { throw 'Python environment setup failed.' }
    }
    & .\.venv\Scripts\python.exe -m pip install -r model/requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Python dependency setup failed.' }
    Write-Host 'Ready. Start the sample app with .\tools\flutter.ps1 run -d windows'
} finally {
    Pop-Location
}
