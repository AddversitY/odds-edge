# Use the repository's pinned SDK without changing the machine's PATH.
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments)

$flutterCommand = Join-Path $PSScriptRoot '..\.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterCommand)) {
    throw 'Local Flutter SDK is missing. Run .\tools\setup.ps1 first.'
}
& $flutterCommand @FlutterArguments
exit $LASTEXITCODE
