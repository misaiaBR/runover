"""Posse sem dono e derrota que paga: dois cantos do núcleo de conquista.

A exclusão de conta e a dissolução de equipe anulam de propósito as colunas de
dono da posse — o território volta a ficar livre e o histórico fica. A leitura,
porém, tratava a linha como se sempre tivesse um titular, e a derrota no desafio
também devolve um `claim` (é o recibo do desafio, com `challenge_won` falso,
zero pontos e sem troca de posse), que era contado como conquista.
"""

import math
import uuid
from datetime import datetime, timedelta, timezone

from app.models import (
    CoinTransaction,
    ScoreEvent,
    Territory,
    TerritoryOwnership,
    User,
)
from tests.auth_helpers import auth_headers

LAT, LNG = -23.55, -46.63  # um bairro real não é requisito; só evita bordo de mapa
# O servidor só aceita corrida dos últimos 7 dias e nenhuma no futuro: as
# trilhas partem de dois dias atrás e somam um dia entre a conquista e o ataque.
BASE = datetime.now(timezone.utc) - timedelta(days=2)


def _square(step_m: float, *, walk_seconds: int, start: datetime) -> list[dict]:
    """Laço quadrado fechado de `step_m` metros de lado, em 4 vértices + volta."""
    d_lat = step_m / 111_320
    d_lng = step_m / (111_320 * math.cos(math.radians(LAT)))
    corners = [
        (LAT, LNG),
        (LAT + d_lat, LNG),
        (LAT + d_lat, LNG + d_lng),
        (LAT, LNG + d_lng),
        (LAT, LNG),
    ]
    leg = walk_seconds // (len(corners) - 1)
    return [
        {
            "lat": lat,
            "lng": lng,
            "timestamp": (start + timedelta(seconds=leg * i)).isoformat(),
            "segment": 0,
            "accuracy": 5.0,
        }
        for i, (lat, lng) in enumerate(corners)
    ]


def _run(client, headers, *, track, name, conquer=True, challenge=None, team_id=None):
    body = {
        "id": str(uuid.uuid4()),
        "request_id": uuid.uuid4().hex,
        "name": name,
        "track": track,
        "conquer": conquer,
    }
    if challenge:
        body["challenge"] = challenge
    if team_id:
        body["team_id"] = team_id
    response = client.post("/runs", json=body, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_territory_of_deleted_account_is_free_on_the_map(client, db_session):
    """Dono excluído não pode travar o mapa nem aparecer como dono."""
    victim = auth_headers(client, username="saiudo", email="saiudo@example.com")
    watcher = auth_headers(client, username="olhando", email="olhando@example.com")

    territory = Territory(
        name="Praça Livre",
        geojson=(
            '{"type":"Polygon","coordinates":[[[-46.63,-23.55],[-46.629,-23.55],'
            '[-46.629,-23.549],[-46.63,-23.549],[-46.63,-23.55]]]}'
        ),
        radius_m=60,
        relevance=1,
        center_lat=LAT,
        center_lng=LNG,
    )
    db_session.add(territory)
    db_session.flush()
    owner = db_session.query(User).filter(User.username == "saiudo").one()
    db_session.add(TerritoryOwnership(
        territory_id=territory.id, owner_user_id=owner.id, points=50,
    ))
    db_session.commit()

    assert client.delete("/users/me", headers=victim).status_code == 204

    listed = client.get("/territories", headers=watcher)
    assert listed.status_code == 200, listed.text
    entry = next(t for t in listed.json() if t["id"] == territory.id)
    assert entry["status"] == "disponivel", entry
    assert entry["owner_display"] is None, entry

    detail = client.get(f"/territories/{territory.id}", headers=watcher)
    assert detail.status_code == 200, detail.text
    assert detail.json()["status"] == "disponivel", detail.json()
    assert detail.json()["history"] == [], detail.json()


def test_losing_a_challenge_pays_nothing_and_is_not_a_conquest(client, db_session):
    """Derrota no desafio salva a corrida, mas não é conquista."""
    owner = auth_headers(client, username="dono", email="dono@example.com")
    rival = auth_headers(client, username="rival", email="rival@example.com")
    now = BASE

    first = _run(client, owner, track=_square(120, walk_seconds=180, start=now),
                 name="meu laço")
    assert first["claim"]["created_new"] is True

    lost = _run(
        client, rival,
        track=_square(120, walk_seconds=600, start=now + timedelta(days=1)),
        name="tentativa lenta", challenge="pace",
    )
    assert lost["claim"]["challenge_won"] is False, lost["claim"]
    assert lost["claim"]["points_awarded"] == 0

    rival_id = db_session.query(User).filter(User.username == "rival").one().id
    reasons = [
        row.reason
        for row in db_session.query(CoinTransaction)
        .filter(CoinTransaction.user_id == rival_id)
        .all()
    ]
    assert "conquista" not in reasons, reasons
    assert db_session.query(ScoreEvent).filter(
        ScoreEvent.user_id == rival_id
    ).count() == 0, "derrota não pode pontuar"

    progress = client.get("/runs/progress", headers=rival).json()
    goal = next(g for g in progress["goals"] if g["unit"] == "conquistas")
    assert goal["value"] == 0, progress["goals"]
    first_badge = next(b for b in progress["badges"] if b["name"] == "Primeira conquista")
    assert first_badge["earned"] is False, progress["badges"]
