param([string]$Cutoff = '2026-10-18', [int]$CurrentSeason = 2026)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$schedulePath = Join-Path $PSScriptRoot 'nfl-games-source.csv'
$schedule = @{}
foreach ($game in (Import-Csv -LiteralPath $schedulePath)) { $schedule[$game.game_id] = $game }
$groups = @{
  passing = @('completions','attempts','passing_yards','passing_tds','passing_interceptions','sacks_suffered')
  rushing = @('carries','rushing_yards','rushing_tds','rushing_fumbles_lost')
  receiving = @('targets','receptions','receiving_yards','receiving_tds','receiving_yards_after_catch','receiving_fumbles_lost')
  defense = @('def_tackles_solo','def_tackles_with_assist','def_tackle_assists','def_sacks','def_interceptions','def_pass_defended','def_tds','def_fumbles_forced')
  kicking = @('fg_made','fg_att','pat_made','pat_att')
  punting = @('pt_att','pt_yards')
}
$allMetrics = @($groups.Values | ForEach-Object { $_ } | Sort-Object -Unique)
$rows = [Collections.Generic.List[object]]::new()
$sources = [Collections.Generic.List[object]]::new()
$seen = @{}
$excludedFuture = 0
$unattributed = 0
foreach ($year in (($CurrentSeason-3)..$CurrentSeason)) {
  $path = Join-Path $PSScriptRoot "nfl-player-source-$year.csv"
  $sourceRows = @(Import-Csv -LiteralPath $path)
  if ($sourceRows.Count -lt 500) { throw "Unexpected player source size for $year" }
  $sources.Add(@{season=$year; url="https://github.com/nflverse/nflverse-data/releases/download/stats_player/stats_player_week_$year.csv"; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash})
  foreach ($r in $sourceRows) {
    if (-not $r.player_id -or -not $r.player_display_name) { $unattributed++; continue }
    $g = $schedule[$r.game_id]
    if (-not $g) { throw "Unmatched game $($r.game_id); refresh schedule before importing." }
    if ([string]::CompareOrdinal($g.gameday, $Cutoff) -gt 0 -or $g.home_score -eq '' -or $g.away_score -eq '') { $excludedFuture++; continue }
    $scheduleType = if ($g.game_type -eq 'REG') { 'REG' } elseif ($g.game_type -in 'WC','DIV','CON','SB') { 'POST' } else { $g.game_type }
    if ($scheduleType -ne $r.season_type -or [int]$g.season -ne [int]$r.season -or [int]$g.week -ne [int]$r.week) { throw "Mismatched game metadata $($r.game_id)" }
    $opponent = if ($r.team -eq $g.home_team) { $g.away_team } elseif ($r.team -eq $g.away_team) { $g.home_team } else { throw 'Team does not match game' }
    if ($opponent -ne $r.opponent_team) { throw 'Opponent does not match game' }
    $key = "$($r.player_id)|$year|$($r.season_type)|$($r.week)"
    if ($seen.ContainsKey($key)) { throw "Duplicate player game $key" }; $seen[$key] = $true
    $stats = [Collections.Generic.List[object]]::new()
    foreach ($metric in $allMetrics) {
      $raw = $r.$metric
      if ($null -eq $raw -or $raw -eq '' -or $raw -eq 'NA') { $stats.Add($null); continue }
      $number = [double]::Parse($raw, $culture)
      if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw 'Nonfinite statistic' }
      $stats.Add($number)
    }
    $position = if ($r.position) { $r.position } else { 'Unknown' }
    $rows.Add(@{playerId=$r.player_id; name=$r.player_display_name; position=$position; team=$r.team; opponent=$r.opponent_team; season=[int]$r.season; week=[int]$r.week; date=$g.gameday; seasonType=$r.season_type; stats=$stats})
  }
}
$bundle = @{
  schema=1; sport='american_football'; league='NFL'; currentSeason=$CurrentSeason; cutoff=$Cutoff;
  retrievedAt=[DateTime]::UtcNow.ToString('o'); source='nflverse contributors — player box scores and schedules';
  sourceUrl='https://github.com/nflverse/nflverse-data/releases/tag/stats_player';
  dictionaryUrl='https://nflreadr.nflverse.com/articles/dictionary_player_stats.html';
  license='CC BY 4.0'; licenseUrl='https://creativecommons.org/licenses/by/4.0/';
  sourceFiles=$sources; scheduleSha256=(Get-FileHash -LiteralPath $schedulePath -Algorithm SHA256).Hash;
  changes='Selected four NFL seasons through cutoff; joined completed schedules by game ID; retained identity, historical teams, dates and additive box-score counts. All source zeroes retained; missing values stay null. Packed numeric arrays use statKeys to preserve metrics compactly. No headshots, odds, rates, injuries or projections. Regular season and postseason kept distinct.';
  coverage='Recorded player box-score rows, not a complete participation or DNP log. Current season and current week can be incomplete. Historical revisions may be present; not point-in-time replay.';
  excludedFutureOrUnfinished=$excludedFuture; excludedUnattributedRows=$unattributed; statKeys=$allMetrics; rows=$rows
}
$destination = Join-Path $PSScriptRoot '../assets/nfl-player-stats.json'
$bundle | ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $destination -Encoding utf8
@{rows=$rows.Count; players=@($rows | ForEach-Object { $_.playerId } | Sort-Object -Unique).Count; bytes=(Get-Item -LiteralPath $destination).Length; excluded=$excludedFuture} | ConvertTo-Json
