$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot 'nfl-games-source.csv'
$games = @(Import-Csv -LiteralPath $sourcePath | Where-Object {
  [int]$_.season -ge 2022 -and [int]$_.season -le 2026 -and $_.game_type -eq 'REG' -and $_.home_score -ne '' -and $_.away_score -ne '' -and [datetime]$_.gameday -le [datetime]'2026-10-18'
} | ForEach-Object {
  @{ id=$_.game_id; season=[int]$_.season; week=[int]$_.week; date=$_.gameday; home=$_.home_team; away=$_.away_team; homeScore=[int]$_.home_score; awayScore=[int]$_.away_score }
})
if ($games.Count -lt 800) { throw 'Unexpectedly incomplete source; no asset written.' }
$bundle = @{
  source='nflverse schedules'; sourceUrl='https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv';
  license='CC BY 4.0'; licenseUrl='https://creativecommons.org/licenses/by/4.0/';
  retrievedAt=[DateTime]::UtcNow.ToString('o'); sourceSha256=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash;
  changes='Selected completed 2022–2026 regular-season games through 2026-10-18; retained weeks, dates, teams and final scores only. Historical odds and injury data excluded. Current week may be incomplete.';
  games=$games
}
$destination = Join-Path $PSScriptRoot '../assets/nfl-history.json'
$bundle | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $destination -Encoding utf8
Write-Output "Imported $($games.Count) completed games."
