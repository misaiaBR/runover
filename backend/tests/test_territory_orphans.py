"""Posse sem dono e derrota que paga: dois cantos do núcleo de conquista.

A exclusão de conta e a dissolução de equipe anulam de propósito as colunas de
dono da posse — o território volta a ficar livre e o histórico fica. A leitura,
porém, tratava a linha como se sempre tivesse um titular, e a derrota no desafio
também devolve um `claim` (é o recibo do desafio, com `challenge_won` falso,
zero pontos e sem troca de posse), que era contado como conquista. E retomar um
território pontuava pela área do laço, não pela área que mudou de mão.
"""

import math
from datetime import timedelta

from app.geometry import geojson_to_polygon, polygon_area_m2
from app.models import (
    CoinTransaction,
    ScoreEvent,
    Territory,
    TerritoryOwnership,
    User,
)
from tests.auth_helpers import auth_headers
from tests.run_helpers import BASE, square_track, submit_run


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
        center_lat=-23.5495,
        center_lng=-46.6295,
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

    first = submit_run(
        client, owner, track=square_track(120, walk_seconds=180, start=BASE),
        name="meu laço",
    )
    assert first["claim"]["created_new"] is True

    lost = submit_run(
        client, rival,
        track=square_track(120, walk_seconds=600, start=BASE + timedelta(days=1)),
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


def test_retake_scores_the_territory_area_not_the_loop_area(client, db_session):
    """Quem retoma um território leva os pontos daquele território, não os da
    volta olímpica que deu por cima dele."""
    owner = auth_headers(client, username="defensor", email="defensor@example.com")
    rival = auth_headers(client, username="atacante", email="atacante@example.com")

    created = submit_run(
        client, owner, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço pequeno",
    )
    territory_id = created["claim"]["territory"]["id"]
    territory = db_session.get(Territory, territory_id)
    held_m2 = polygon_area_m2(geojson_to_polygon(territory.geojson))

    giant = submit_run(
        client, rival,
        track=square_track(1200, walk_seconds=1200, start=BASE + timedelta(days=1)),
        name="laço gigante", challenge="pace",
    )
    claim = giant["claim"]
    assert claim["created_new"] is False, claim
    assert claim["challenge_won"] is True, claim
    assert claim["territory"]["id"] == territory_id
    # O laço gigante tem ~100x a área do território; o que muda de mão é o
    # território. A pontuação tem de acompanhar isso.
    assert math.isclose(claim["area_m2"], held_m2, rel_tol=1e-6), (
        claim["area_m2"], held_m2,
    )
    assert claim["points_awarded"] <= created["claim"]["points_awarded"] + 1, (
        claim["points_awarded"], created["claim"]["points_awarded"],
    )
