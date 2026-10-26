/// Full NFL club names and the abbreviations stored in the nflverse box scores.
const nflTeams = <String, String>{
  'Arizona Cardinals': 'ARI',
  'Atlanta Falcons': 'ATL',
  'Baltimore Ravens': 'BAL',
  'Buffalo Bills': 'BUF',
  'Carolina Panthers': 'CAR',
  'Chicago Bears': 'CHI',
  'Cincinnati Bengals': 'CIN',
  'Cleveland Browns': 'CLE',
  'Dallas Cowboys': 'DAL',
  'Denver Broncos': 'DEN',
  'Detroit Lions': 'DET',
  'Green Bay Packers': 'GB',
  'Houston Texans': 'HOU',
  'Indianapolis Colts': 'IND',
  'Jacksonville Jaguars': 'JAX',
  'Kansas City Chiefs': 'KC',
  'Las Vegas Raiders': 'LV',
  'Los Angeles Chargers': 'LAC',
  'Los Angeles Rams': 'LAR',
  'Miami Dolphins': 'MIA',
  'Minnesota Vikings': 'MIN',
  'New England Patriots': 'NE',
  'New Orleans Saints': 'NO',
  'New York Giants': 'NYG',
  'New York Jets': 'NYJ',
  'Philadelphia Eagles': 'PHI',
  'Pittsburgh Steelers': 'PIT',
  'San Francisco 49ers': 'SF',
  'Seattle Seahawks': 'SEA',
  'Tampa Bay Buccaneers': 'TB',
  'Tennessee Titans': 'TEN',
  'Washington Commanders': 'WAS',
};

/// Abbreviation used in the bundled box scores, or null when the name is not
/// one of the 32 clubs. Does not guess a team from a partial string.
String? canonicalTeam(String name) {
  final normalized = name.trim().toLowerCase();
  for (final team in nflTeams.entries) {
    if (team.key.toLowerCase() == normalized ||
        team.value.toLowerCase() == normalized) {
      return team.value;
    }
  }
  return const {
    'jax': 'JAX',
    'jac': 'JAX',
    'gbp': 'GB',
    'kcc': 'KC',
    'sfo': 'SF',
  }[normalized];
}

String? nflClubName(String abbreviation) {
  for (final team in nflTeams.entries) {
    if (team.value == abbreviation) return team.key;
  }
  return null;
}
