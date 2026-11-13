"""Free weather for Coach's Line.

Historical games use the Open-Meteo archive. It needs no key. Current games
use the National Weather Service when the stadium is in the United States,
and Open-Meteo's forecast otherwise. Both are free. No sportsbook is scraped.

Open-Meteo asks for attribution. The model file records it.
The weather service asks for a User-Agent that names the app.
"""

from __future__ import annotations

import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

USER_AGENT = "odds-edge/1.0 (https://github.com/AddversitY/odds-edge)"
ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
FORECAST = "https://api.open-meteo.com/v1/forecast"
GEOCODE = "https://geocoding-api.open-meteo.com/v1/search"
NWS = "https://api.weather.gov"
EASTERN = ZoneInfo("America/New_York")

# Current and former NFL stadiums. Aliases share a coordinate so one
# archive request covers every name the schedule has used.
STADIUMS: dict[str, tuple[float, float]] = {
    "AT&T Stadium": (32.7473, -97.0945),
    "Acrisure Stadium": (40.4468, -80.0158),
    "Heinz Field": (40.4468, -80.0158),
    "Allegiant Stadium": (36.0908, -115.1833),
    "Allianz Arena": (48.2188, 11.6247),
    "FC Bayern Munich Stadium": (48.2188, 11.6247),
    "Arena Corinthians": (-23.5456, -46.4742),
    "Arrowhead Stadium": (39.0489, -94.4839),
    "GEHA Field at Arrowhead Stadium": (39.0489, -94.4839),
    "Azteca Stadium": (19.3029, -99.1505),
    "Bank of America Stadium": (35.2258, -80.8528),
    "Bernabeu": (40.4531, -3.6883),
    "Caesars Superdome": (29.9511, -90.0812),
    "Mercedes-Benz Superdome": (29.9511, -90.0812),
    "CenturyLink Field": (47.5952, -122.3316),
    "Lumen Field": (47.5952, -122.3316),
    "Deutsche Bank Park": (50.0686, 8.6454),
    "Edward Jones Dome": (38.6328, -90.1885),
    "Empower Field at Mile High": (39.7439, -105.0201),
    "Sports Authority Field at Mile High": (39.7439, -105.0201),
    "EverBank Field": (30.3239, -81.6373),
    "EverBank Stadium": (30.3239, -81.6373),
    "TIAA Bank Stadium": (30.3239, -81.6373),
    "FedExField": (38.9078, -76.8645),
    "Northwest Stadium": (38.9078, -76.8645),
    "FirstEnergy Stadium": (41.5061, -81.6995),
    "Huntington Bank Field": (41.5061, -81.6995),
    "Ford Field": (42.3400, -83.0456),
    "Georgia Dome": (33.7573, -84.4006),
    "Gillette Stadium": (42.0909, -71.2643),
    "Hard Rock Stadium": (25.9580, -80.2389),
    "Sun Life Stadium": (25.9580, -80.2389),
    "Highmark Stadium": (42.7738, -78.7870),
    "New Era Field": (42.7738, -78.7870),
    "Ralph Wilson Stadium": (42.7738, -78.7870),
    "Lambeau Field": (44.5013, -88.0622),
    "Levi's Stadium": (37.4032, -121.9698),
    "Lincoln Financial Field": (39.9008, -75.1675),
    "Los Angeles Memorial Coliseum": (34.0141, -118.2879),
    "Lucas Oil Stadium": (39.7601, -86.1639),
    "M&T Bank Stadium": (39.2780, -76.6227),
    "Maracana Stadium": (-22.9121, -43.2302),
    "Melbourne Cricket Ground": (-37.8200, 144.9834),
    "Mercedes-Benz Stadium": (33.7554, -84.4008),
    "MetLife Stadium": (40.8135, -74.0745),
    "NRG Stadium": (29.6847, -95.4107),
    "Reliant Stadium": (29.6847, -95.4107),
    "Nissan Stadium": (36.1665, -86.7713),
    "LP Field": (36.1665, -86.7713),
    "O.co Coliseum": (37.7516, -122.2005),
    "Oakland-Alameda County Coliseum": (37.7516, -122.2005),
    "Ring Central Coliseum": (37.7516, -122.2005),
    "Paul Brown Stadium": (39.0955, -84.5161),
    "Paycor Stadium": (39.0955, -84.5161),
    "Qualcomm Stadium": (32.7831, -117.1196),
    "Raymond James Stadium": (27.9759, -82.5033),
    "SoFi Stadium": (33.9534, -118.3390),
    "Soldier Field": (41.8623, -87.6167),
    "Stade de France": (48.9244, 2.3601),
    "State Farm Stadium": (33.5276, -112.2626),
    "University of Phoenix Stadium": (33.5276, -112.2626),
    "StubHub Center": (33.8644, -118.2611),
    "TCF Bank Stadium": (44.9759, -93.2250),
    "Tottenham Hotspur Stadium": (51.6043, -0.0664),
    "Tottenham Stadium": (51.6043, -0.0664),
    "Twickenham Stadium": (51.4559, -0.3415),
    "U.S. Bank Stadium": (44.9737, -93.2577),
    "Wembley Stadium": (51.5560, -0.2796),
}


@dataclass(frozen=True)
class WeatherObs:
    wind: float | None
    temp_f: float | None
    precip: float | None
    source: str


def open_roof(value) -> bool:
    return str(value or "").strip().lower() in {"outdoors", "open"}


def _request(url: str, accept: str | None = None, timeout: int = 90) -> dict | None:
    headers = {"User-Agent": USER_AGENT}
    if accept:
        headers["Accept"] = accept
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, OSError):
        return None


def _cache_file(directory: Path, lat: float, lon: float) -> Path:
    # The day is in the name so a file from an earlier run cannot hide later games.
    return directory / f"archive_{lat:.3f}_{lon:.3f}_{date.today().isoformat()}.json"


def stadium_point(name: str, cache: Path) -> tuple[float, float] | None:
    if name in STADIUMS:
        return STADIUMS[name]
    key = "".join(ch.lower() if ch.isalnum() else "-" for ch in name).strip("-")
    path = cache / f"geocode_{key}.json"
    if path.exists():
        try:
            saved = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            saved = None
        if not saved:
            return None
        return float(saved["lat"]), float(saved["lon"])
    query = urllib.parse.urlencode({"name": name, "count": 1})
    payload = _request(f"{GEOCODE}?{query}")
    time.sleep(0.2)
    results = (payload or {}).get("results") or []
    path.parent.mkdir(parents=True, exist_ok=True)
    if not results:
        path.write_text("", encoding="utf-8")
        return None
    point = {"lat": results[0]["latitude"], "lon": results[0]["longitude"]}
    path.write_text(json.dumps(point), encoding="utf-8")
    return float(point["lat"]), float(point["lon"])


def _archive(lat: float, lon: float, cache: Path) -> dict | None:
    path = _cache_file(cache, lat, lon)
    if path.exists() and path.stat().st_size > 1000:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            path.unlink()
    query = urllib.parse.urlencode(
        {
            "latitude": f"{lat:.4f}",
            "longitude": f"{lon:.4f}",
            "start_date": "2014-08-01",
            "end_date": date.today().isoformat(),
            "hourly": "temperature_2m,precipitation,wind_speed_10m",
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "timezone": "America/New_York",
        }
    )
    payload = None
    for attempt in range(3):
        payload = _request(f"{ARCHIVE}?{query}", timeout=180)
        if payload and "hourly" in payload:
            break
        time.sleep(1.5 * (attempt + 1))
        payload = None
    time.sleep(0.2)
    if not payload:
        return None
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")
    return payload


def _index_hours(payload: dict) -> dict[str, tuple[float | None, float | None, float | None]]:
    hourly = payload.get("hourly") or {}
    times = hourly.get("time") or []
    temps = hourly.get("temperature_2m") or []
    winds = hourly.get("wind_speed_10m") or []
    rains = hourly.get("precipitation") or []
    indexed = {}
    for index, stamp in enumerate(times):
        def cell(values):
            if index >= len(values) or values[index] is None:
                return None
            return float(values[index])

        indexed[stamp] = (cell(temps), cell(winds), cell(rains))
    return indexed


def _at_kickoff(indexed: dict, played_on: date, hour: int) -> WeatherObs | None:
    hours = []
    for offset in range(4):
        stamp = f"{played_on.isoformat()}T{(hour + offset) % 24:02d}:00"
        reading = indexed.get(stamp)
        if reading is not None:
            hours.append(reading)
    if not hours:
        return None
    temp, wind, _ = hours[0]
    precip = 0.0
    saw_precip = False
    for _, _, rain in hours:
        if rain is not None:
            precip += rain
            saw_precip = True
    return WeatherObs(
        wind=wind,
        temp_f=temp,
        precip=precip if saw_precip else None,
        source="open-meteo-archive",
    )


def historical_weather(games: list[dict], cache: Path) -> dict[str, WeatherObs]:
    """Kickoff weather for open-roof games. `games` rows need id, stadium, roof, date, hour, temp, wind.

    A missing archive hour falls back to the temperature and wind already in the
    nflverse schedule. Precipitation is then unknown and treated as none.
    """
    by_point: dict[tuple[float, float], list[dict]] = {}
    for game in games:
        if not open_roof(game.get("roof")):
            continue
        point = stadium_point(str(game.get("stadium") or ""), cache)
        if point is None:
            continue
        by_point.setdefault(point, []).append(game)
    found: dict[str, WeatherObs] = {}
    for point, slate in by_point.items():
        payload = _archive(point[0], point[1], cache)
        indexed = _index_hours(payload) if payload else {}
        del payload
        for game in slate:
            reading = _at_kickoff(indexed, game["date"], int(game["hour"])) if indexed else None
            if reading is None:
                temp = game.get("temp")
                wind = game.get("wind")
                if temp is None and wind is None:
                    found[game["id"]] = WeatherObs(None, None, None, "missing")
                else:
                    found[game["id"]] = WeatherObs(
                        None if wind is None else float(wind),
                        None if temp is None else float(temp),
                        None,
                        "nflverse-fallback",
                    )
            else:
                found[game["id"]] = reading
        del indexed
    return found


def _parse_wind(text: str) -> float | None:
    numbers = [float(piece) for piece in re.findall(r"\d+(?:\.\d+)?", text or "")]
    if not numbers:
        return None
    return sum(numbers) / len(numbers)


def _precip_from_words(summary: str, chance: float | None) -> float:
    text = (summary or "").lower()
    wet = any(word in text for word in ("rain", "snow", "storm", "drizzle", "shower"))
    pop = 0.0 if chance is None else float(chance)
    if "heavy" in text or (wet and pop >= 80):
        return 4.0
    if wet and pop >= 50:
        return 1.5
    if wet or pop >= 60:
        return 0.4
    return 0.0


def _kickoff(played_on: date, hour: int, minute: int) -> datetime:
    return datetime(
        played_on.year,
        played_on.month,
        played_on.day,
        hour,
        minute,
        tzinfo=EASTERN,
    )


def _nws(lat: float, lon: float, when: datetime) -> WeatherObs | None:
    if not (20 < lat < 55 and -130 < lon < -60):
        return None
    points = _request(
        f"{NWS}/points/{lat:.4f},{lon:.4f}",
        accept="application/geo+json",
    )
    if not points:
        return None
    hourly_url = ((points.get("properties") or {}).get("forecastHourly"))
    if not hourly_url:
        return None
    time.sleep(0.2)
    hourly = _request(hourly_url, accept="application/geo+json")
    periods = ((hourly or {}).get("properties") or {}).get("periods") or []
    best = None
    best_gap = None
    for period in periods:
        stamp = period.get("startTime")
        if not stamp:
            continue
        try:
            start = datetime.fromisoformat(stamp)
        except ValueError:
            continue
        gap = abs((start - when).total_seconds())
        if best_gap is None or gap < best_gap:
            best = period
            best_gap = gap
    if best is None or best_gap is None or best_gap > 90 * 60:
        return None
    pop = (best.get("probabilityOfPrecipitation") or {}).get("value")
    summary = str(best.get("shortForecast") or "")
    return WeatherObs(
        wind=_parse_wind(str(best.get("windSpeed") or "")),
        temp_f=None if best.get("temperature") is None else float(best["temperature"]),
        precip=_precip_from_words(summary, None if pop is None else float(pop)),
        source="nws",
    )


def _open_meteo_forecast(lat: float, lon: float, when: datetime) -> WeatherObs | None:
    query = urllib.parse.urlencode(
        {
            "latitude": f"{lat:.4f}",
            "longitude": f"{lon:.4f}",
            "hourly": "temperature_2m,precipitation,wind_speed_10m",
            "temperature_unit": "fahrenheit",
            "wind_speed_unit": "mph",
            "timezone": "America/New_York",
            "forecast_days": 16,
        }
    )
    payload = _request(f"{FORECAST}?{query}")
    if not payload:
        return None
    indexed = _index_hours(payload)
    local = when.astimezone(EASTERN)
    reading = _at_kickoff(indexed, local.date(), local.hour)
    if reading is None:
        return None
    return WeatherObs(reading.wind, reading.temp_f, reading.precip, "open-meteo-forecast")


def forecast_at(lat: float, lon: float, when: datetime) -> WeatherObs | None:
    """The kickoff forecast. The weather service first inside the United States."""
    reading = _nws(lat, lon, when)
    if reading is not None and reading.temp_f is not None:
        return reading
    time.sleep(0.2)
    return _open_meteo_forecast(lat, lon, when)


def forecast_games(games: list[dict], cache: Path) -> list[dict]:
    """One forecast per upcoming game. `games` need home, away, stadium, roof, date, hour, minute."""
    out = []
    for game in games:
        point = stadium_point(str(game.get("stadium") or ""), cache)
        if point is None:
            continue
        when = _kickoff(game["date"], int(game["hour"]), int(game.get("minute") or 0))
        reading = forecast_at(point[0], point[1], when)
        if reading is None:
            continue
        out.append(
            {
                "home": game["home"],
                "away": game["away"],
                "stadium": game.get("stadium") or "",
                "openRoof": open_roof(game.get("roof")),
                "windMph": None if reading.wind is None else round(reading.wind, 1),
                "tempF": None if reading.temp_f is None else round(reading.temp_f, 1),
                "precipMm": None if reading.precip is None else round(reading.precip, 2),
                "source": reading.source,
                "at": when.astimezone(timezone.utc).replace(microsecond=0).isoformat(),
                "longitude": round(point[1], 4),
            }
        )
        time.sleep(0.2)
    return out
