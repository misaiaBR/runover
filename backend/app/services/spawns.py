"""Territórios selvagens estilo Pokémon GO: aparecem sozinhos no mapa.

Cada célula da grade gera de 0 a 2 spawns por hora UTC, com seed só de
célula + hora — todos os jogadores veem os mesmos, sem nada armazenado.
Quem fechar um laço cobrindo o centro primeiro fica com o território
(e registra a marca); a conquista consome o spawn para todo mundo.

Onde nascer (como o PoGo, que usa dados do OSM + atividade):
1. grudado em via (rua/calçada/trilha) via Overpass, com cache de 1h;
2. sem via por perto, só onde já se correu (centros de territórios);
3. sem nada, quase nunca (pioneiro esparso, para áreas novas não morrerem).
"""
import hashlib
import math
import random
import time
from datetime import datetime, timedelta, timezone

import httpx

from app.geometry import haversine_m

CELL_DEG = 0.005  # ~550 m — grade compartilhada (papel das células S2 no PoGo)
BUCKET_HOURS = 1  # rotação horária, tipo 1x60 do PoGo
MAX_RESULTS = 100
STREET_RADIUS_M = 150
STREET_TTL_SECONDS = 3600
ACTIVITY_RADIUS_M = 1000.0  # até onde um território ancora spawns
PIONEER_KEEP = 0.08  # fração mantida sem rua nem atividade

# Vias onde dá para correr — calçadas e trilhas primeiro.
_STREET_QUERY = (
    '[out:json][timeout:10];'
    'way["highway"~"^(footway|path|cycleway|pedestrian|living_street|'
    'residential|service|unclassified|tertiary|secondary|primary)$"]'
    "(around:{radius},{lat},{lng});out geom;"
)
_PREFERRED_HIGHWAYS = {"footway", "path", "cycleway", "pedestrian"}
_STREET_CACHE: dict[tuple[float, float], tuple[float, list]] = {}

RARITY = {1: "comum", 2: "raro", 3: "épico"}


def hour_bucket(now: datetime) -> datetime:
    return now.astimezone(timezone.utc).replace(minute=0, second=0, microsecond=0)


def cell_id(lat: float, lng: float) -> tuple[int, int]:
    return math.floor(lat / CELL_DEG), math.floor(lng / CELL_DEG)


def _rng(*parts: str) -> random.Random:
    digest = hashlib.sha256("|".join(parts).encode()).hexdigest()
    return random.Random(int(digest, 16) % (2 ** 63))


def cell_spawns(cell: tuple[int, int], bucket: datetime) -> list[dict]:
    rng = _rng("wild", f"{cell[0]},{cell[1]}", bucket.isoformat())
    roll = rng.random()
    count = 0 if roll < 0.45 else 1 if roll < 0.80 else 2
    spawns = []
    for i in range(count):
        lat = (cell[0] + rng.random()) * CELL_DEG
        lng = (cell[1] + rng.random()) * CELL_DEG
        tier = rng.random()
        spawns.append({
            "key": f"{cell[0]}:{cell[1]}:{bucket.strftime('%Y%m%d%H')}:{i}",
            "lat": lat,
            "lng": lng,
            "radius_m": round(rng.uniform(60, 150)),
            "relevance": 1 if tier < 0.60 else 2 if tier < 0.90 else 3,
            "spawned_at": bucket,
            "expires_at": bucket + timedelta(hours=BUCKET_HOURS),
        })
    for s in spawns:
        s["rarity"] = RARITY[s["relevance"]]
    return spawns


def fetch_street_ways(
    lat: float, lng: float, radius_m: int = STREET_RADIUS_M
) -> list[tuple[str, list[tuple[float, float]]]]:
    """Vias próximas via Overpass (cache 1h por ~100 m). Falha vira []."""
    key = (round(lat, 3), round(lng, 3))
    cached = _STREET_CACHE.get(key)
    if cached and time.time() - cached[0] < STREET_TTL_SECONDS:
        return cached[1]
    ways: list[tuple[str, list[tuple[float, float]]]] = []
    try:
        response = httpx.post(
            "https://overpass-api.de/api/interpreter",
            data={
                "data": _STREET_QUERY.format(radius=radius_m, lat=lat, lng=lng)
            },
            timeout=8.0,
        )
        response.raise_for_status()
        elements = response.json().get("elements", [])
    except Exception:
        elements = []
    for element in elements:
        points = [
            (p["lat"], p["lon"])
            for p in element.get("geometry", [])
            if "lat" in p and "lon" in p
        ]
        if len(points) >= 2:
            ways.append((element.get("tags", {}).get("highway", ""), points))
    _STREET_CACHE[key] = (time.time(), ways)
    return ways


def snap_to_street(lat: float, lng: float, key: str) -> tuple[float, float] | None:
    """Gruda o spawn na via mais plausível (determinístico por spawn)."""
    ways = fetch_street_ways(lat, lng)
    if not ways:
        return None
    rng = _rng("snap", key)
    preferred = [w for w in ways if w[0] in _PREFERRED_HIGHWAYS] or ways
    _, points = rng.choice(preferred)
    i = rng.randrange(len(points) - 1)
    (a_lat, a_lng), (b_lat, b_lng) = points[i], points[i + 1]
    t = rng.random()
    return (
        a_lat + (b_lat - a_lat) * t + rng.uniform(-0.0001, 0.0001),
        a_lng + (b_lng - a_lng) * t + rng.uniform(-0.0001, 0.0001),
    )


def _near_activity(
    spawn: dict, activity: list[tuple[float, float, float]]
) -> bool:
    for center_lat, center_lng, radius_m in activity:
        if (
            haversine_m(spawn["lat"], spawn["lng"], center_lat, center_lng)
            <= max(ACTIVITY_RADIUS_M, radius_m + 300)
        ):
            return True
    return False


def _pioneer_keep(key: str, probability: float) -> bool:
    return _rng("pioneer", key).random() < probability


def _cells_in_bounds(
    min_lat: float, max_lat: float, min_lng: float, max_lng: float
) -> list[tuple[int, int]]:
    lat0, _ = cell_id(min_lat, 0)
    lat1, _ = cell_id(max_lat, 0)
    _, lng0 = cell_id(0, min_lng)
    _, lng1 = cell_id(0, max_lng)
    return [
        (a, b)
        for a in range(min(lat0, lat1), max(lat0, lat1) + 1)
        for b in range(min(lng0, lng1), max(lng0, lng1) + 1)
    ]


def wild_spawns_in_bounds(
    min_lat: float,
    max_lat: float,
    min_lng: float,
    max_lng: float,
    now: datetime,
) -> list[dict]:
    bucket = hour_bucket(now)
    out = []
    for cell in _cells_in_bounds(min_lat, max_lat, min_lng, max_lng):
        out.extend(cell_spawns(cell, bucket))
    return out


def wild_spawns_for(
    lat: float,
    lng: float,
    radius_km: float,
    now: datetime,
    activity: list[tuple[float, float, float]] | None = None,
    pioneer_keep: float = PIONEER_KEEP,
) -> list[dict]:
    lat_window = radius_km * 1000 / 111_320
    lng_window = radius_km * 1000 / (111_320 * max(0.2, math.cos(math.radians(lat))))
    out = []
    for s in wild_spawns_in_bounds(
        lat - lat_window,
        lat + lat_window,
        lng - lng_window,
        lng + lng_window,
        now,
    ):
        s = {**s, "distance_m": haversine_m(lat, lng, s["lat"], s["lng"])}
        if s["distance_m"] > radius_km * 1000:
            continue
        snapped = snap_to_street(s["lat"], s["lng"], s["key"])
        if snapped is not None:
            s = {
                **s,
                "lat": snapped[0],
                "lng": snapped[1],
                "distance_m": haversine_m(lat, lng, snapped[0], snapped[1]),
            }
            if s["distance_m"] > radius_km * 1000:
                continue
            out.append(s)
        elif activity is None or _near_activity(s, activity):
            out.append(s)
        elif _pioneer_keep(s["key"], pioneer_keep):
            out.append(s)
    out.sort(key=lambda s: s["distance_m"])
    return out[:MAX_RESULTS]


WELCOME_RADIUS_M = 500.0  # sem nada vivo até aqui, o novato ganha um spawn


def welcome_spawn_for(cell: tuple[int, int], now: datetime) -> dict:
    """Spawn de boas-vindas da célula: comum, determinístico por célula + hora.

    Como os demais spawns, é compartilhado (todos os novatos veem o mesmo e
    quem fechar o laço primeiro consome para todo mundo) e gira a cada hora.
    A posição é sorteada dentro da célula e grudada na via mais próxima — sem
    rua por perto (ou com o Overpass fora), fica no ponto sorteado.
    """
    bucket = hour_bucket(now)
    key = f"welcome:{cell[0]}:{cell[1]}:{bucket.strftime('%Y%m%d%H')}"
    rng = _rng("welcome-spot", key)
    lat = (cell[0] + rng.random()) * CELL_DEG
    lng = (cell[1] + rng.random()) * CELL_DEG
    snapped = snap_to_street(lat, lng, key)
    if snapped is not None:
        lat, lng = snapped
    return {
        "key": key,
        "lat": lat,
        "lng": lng,
        "radius_m": 80,
        "relevance": 1,
        "rarity": "comum",
        "spawned_at": bucket,
        "expires_at": bucket + timedelta(hours=BUCKET_HOURS),
    }
