"""Spawn de boas-vindas: quem ainda não tem território sempre vê algo por perto.

Regra: bairro vazio (nada vivo num raio) + zero territórios → um spawn comum
da célula, compartilhado como os demais (quem fechar o laço primeiro consome
para todo mundo) e girando a cada hora.
"""
from datetime import datetime, timezone

from app.models import Territory, TerritoryOwnership, User
from app.services.spawns import (
    CELL_DEG,
    WELCOME_RADIUS_M,
    cell_id,
    hour_bucket,
    welcome_spawn_for,
)

NOW = datetime(2026, 5, 4, 12, 30, tzinfo=timezone.utc)
LAT, LNG = -23.5505, -46.6333
CELL = cell_id(LAT, LNG)


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def test_welcome_is_common_and_deterministic(monkeypatch):
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street", lambda *args: None
    )
    first = welcome_spawn_for(CELL, NOW)
    second = welcome_spawn_for(CELL, NOW)
    assert first == second
    assert first["key"].startswith(
        f"welcome:{CELL[0]}:{CELL[1]}:"
    )
    assert first["rarity"] == "comum"
    assert first["relevance"] == 1
    assert first["spawned_at"] == hour_bucket(NOW)
    assert (first["expires_at"] - first["spawned_at"]).total_seconds() == 3600
    assert CELL[0] * CELL_DEG <= first["lat"] <= (CELL[0] + 1) * CELL_DEG
    assert CELL[1] * CELL_DEG <= first["lng"] <= (CELL[1] + 1) * CELL_DEG


def test_welcome_key_rotates_per_cell_and_hour(monkeypatch):
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street", lambda *args: None
    )
    base = welcome_spawn_for(CELL, NOW)["key"]
    other_cell = (CELL[0] + 1, CELL[1])
    assert welcome_spawn_for(other_cell, NOW)["key"] != base
    later = NOW.replace(hour=13)
    assert welcome_spawn_for(CELL, later)["key"] != base


def test_welcome_uses_the_snapped_street_when_available(monkeypatch):
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street",
        lambda *args: (LAT + 0.001, LNG + 0.001),
    )
    spawn = welcome_spawn_for(CELL, NOW)
    assert (spawn["lat"], spawn["lng"]) == (LAT + 0.001, LNG + 0.001)


def test_rookie_always_sees_something_nearby(client, registered_user, monkeypatch):
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street", lambda *args: None
    )
    # Raio real do app: grade, pioneiros ou o boas-vindas cobrem o bairro.
    response = client.get(
        "/territories/wild?lat=-23.5&lng=-46.6&radius_km=2.0",
        headers=_auth(registered_user),
    )
    assert response.status_code == 200, response.text
    assert len(response.json()) >= 1


def test_welcome_is_shared_between_rookies(client, registered_user, monkeypatch):
    """Dois novatos nos mesmos parâmetros veem a mesma lista."""
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street", lambda *args: None
    )
    second = client.post("/auth/register", json={
        "full_name": "Second Runner",
        "username": "secondrunner",
        "email": "second@example.com",
        "password": "original123",
        "accept_terms": True,
    })
    assert second.status_code == 201
    other = {"Authorization": f"Bearer {second.json()['access_token']}"}
    params = "/territories/wild?lat=-23.5&lng=-46.6&radius_km=0.2"
    first = client.get(params, headers=_auth(registered_user)).json()
    again = client.get(params, headers=other).json()
    assert first == again


def test_owner_gets_no_welcome_spawn(client, registered_user, db_session, monkeypatch):
    monkeypatch.setattr(
        "app.services.spawns.snap_to_street", lambda *args: None
    )
    user = db_session.query(User).filter_by(email="runner@example.com").one()
    territory = Territory(
        name="Quintal",
        geojson='{"type":"Polygon","coordinates":[[[-46.6,-23.5],[-46.599,-23.5],[-46.599,-23.499],[-46.6,-23.499],[-46.6,-23.5]]]}',
        radius_m=80,
        center_lat=-23.5,
        center_lng=-46.6,
    )
    db_session.add(territory)
    db_session.flush()
    db_session.add(
        TerritoryOwnership(
            territory_id=territory.id, owner_user_id=user.id, points=100
        )
    )
    db_session.commit()
    response = client.get(
        "/territories/wild?lat=-23.5&lng=-46.6&radius_km=0.2",
        headers=_auth(registered_user),
    )
    assert response.status_code == 200, response.text
    assert all(
        not s["key"].startswith("welcome:") for s in response.json()
    )
    assert WELCOME_RADIUS_M == 500.0
