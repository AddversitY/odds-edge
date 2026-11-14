"""Build this app's public NFL schedule snapshot; no odds key or odds requests.

Only normalized, attributed nflverse schedule fields are exported. The exporter
does not turn historical closing lines into current sportsbook prices.
"""
import argparse
import csv
import io
import json
import sys
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

SOURCE = 'https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv'
TEAMS = dict(zip(
    'ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GB HOU IND JAX KC LV LAC LAR MIA MIN NE NO NYG NYJ PHI PIT SF SEA TB TEN WAS'.split(),
    ['Arizona Cardinals','Atlanta Falcons','Baltimore Ravens','Buffalo Bills','Carolina Panthers','Chicago Bears','Cincinnati Bengals','Cleveland Browns','Dallas Cowboys','Denver Broncos','Detroit Lions','Green Bay Packers','Houston Texans','Indianapolis Colts','Jacksonville Jaguars','Kansas City Chiefs','Las Vegas Raiders','Los Angeles Chargers','Los Angeles Rams','Miami Dolphins','Minnesota Vikings','New England Patriots','New Orleans Saints','New York Giants','New York Jets','Philadelphia Eagles','Pittsburgh Steelers','San Francisco 49ers','Seattle Seahawks','Tampa Bay Buccaneers','Tennessee Titans','Washington Commanders']))
ALIASES = {'LA':'LAR','OAK':'LV','SD':'LAC','STL':'LAR'}

def iso(at):
    return at.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')

def build_snapshot(rows, now):
    if now.tzinfo is None:
        raise ValueError('A UTC-aware research time is required.')
    events, seen = [], set()
    for row in rows:
        if row.get('home_score', '').strip() or row.get('away_score', '').strip():
            continue
        day, clock = row.get('gameday', '').strip(), row.get('gametime', '').strip()
        if not day or not clock:
            continue
        try:
            kick = datetime.strptime(day + ' ' + clock, '%Y-%m-%d %H:%M').replace(tzinfo=ZoneInfo('America/New_York')).astimezone(timezone.utc)
            away, home = [ALIASES.get(row.get(k), row.get(k)) for k in ['away_team','home_team']]
            if away not in TEAMS or home not in TEAMS or away == home:
                continue
            if not now <= kick < now + timedelta(days=14):
                continue
            event_id = 'nflverse:' + row['game_id']
            if event_id in seen:
                raise ValueError('Duplicate NFL schedule identity.')
            seen.add(event_id)
            events.append(dict(id=event_id, away=TEAMS[away], home=TEAMS[home], startsAt=iso(kick), sport='american_football', league='NFL'))
        except (KeyError, ValueError) as error:
            if isinstance(error, ValueError) and str(error).startswith('Duplicate'):
                raise
            continue
    events.sort(key=lambda e: (e['startsAt'], e['id']))
    notice = 'Actual NFL schedule from nflverse. Sportsbook prices are not connected; no prices are filled in.'
    board = dict(events=events, quotes=[], fetchedAt=iso(now), demo=False, notices=[notice])
    return dict(schemaVersion=1, generatedAt=iso(now),
        schedule=dict(source='nflverse', sourceUrl=SOURCE, license='CC BY 4.0', licenseUrl='https://creativecommons.org/licenses/by/4.0/', fetchedAt=iso(now), windowDays=14),
        odds=dict(status='not_configured', message='Sportsbook prices are not connected.'), board=board, props=board)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    request = urllib.request.Request(SOURCE, headers={'User-Agent':'OddsEdge schedule preview'})
    with urllib.request.urlopen(request, timeout=45) as response:
        raw = response.read(20_000_001)
    if len(raw) > 20_000_000:
        raise ValueError('Unexpected schedule file size.')
    rows = list(csv.DictReader(io.StringIO(raw.decode('utf-8-sig'))))
    required = {'game_id','gameday','gametime','home_team','away_team','home_score','away_score'}
    if not rows or not required.issubset(rows[0]):
        raise ValueError('NFL schedule schema is unavailable; preserve the previous deployment.')
    now = datetime.now(timezone.utc)
    snapshot = build_snapshot(rows, now)
    # A stale upstream season is not a current empty slate during NFL season.
    latest_day = max((r.get('gameday','') for r in rows), default='')
    if now.month in [9,10,11,12,1] and latest_day < (now - timedelta(days=14)).date().isoformat():
        raise ValueError('Upstream schedule is outdated; preserve the previous deployment.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(snapshot, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(f'Published {len(snapshot["board"]["events"])} scheduled games; sportsbook prices unavailable; zero odds credits.')

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Schedule snapshot failed: {error}', file=sys.stderr)
        raise SystemExit(1)
