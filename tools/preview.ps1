[CmdletBinding()]
param([ValidateRange(1024, 65535)][int]$Port = 8765)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $projectRoot 'build\web'
$pythonCommand = Join-Path $projectRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonCommand)) { throw 'Run .\tools\setup.ps1 first.' }
if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'index.html'))) {
    throw 'Build the preview first: .\tools\flutter.ps1 build web --release --no-pub'
}
$logRoot = Join-Path $projectRoot 'build\review'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$previewProcess = Start-Process -FilePath $pythonCommand -ArgumentList @(
    '-m', 'http.server', "$Port", '--bind', '127.0.0.1', '--directory', ('"' + $webRoot + '"')
) -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput (Join-Path $logRoot 'preview.out.log') `
  -RedirectStandardError (Join-Path $logRoot 'preview.err.log')
$previewUrl = "http://127.0.0.1:$Port/"
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $previewProcess.Refresh()
    if ($previewProcess.HasExited) { throw "Preview exited. See $logRoot\preview.err.log (the port may already be in use)." }
    try {
        $response = Invoke-WebRequest -Uri $previewUrl -UseBasicParsing
        if ($response.StatusCode -eq 200 -and $response.Content.Contains('flutter_bootstrap.js')) {
            Set-Content -LiteralPath (Join-Path $projectRoot '.tools\preview.pid') -Value $previewProcess.Id
            Write-Host "Preview ready: $previewUrl (local to this computer; sample mode by default)."
            return
        }
    } catch { }
    Start-Sleep -Milliseconds 200
}
throw "Preview did not become ready. See $logRoot\preview.err.log."
