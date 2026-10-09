"""Insígnias: catálogo, concessão pela regra e data de ganho."""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.models import Run, ScoreEvent, Territory, TerritoryOwnership, UserBadge
from app.services.badges import CATALOG
from app.services.shop import CATALOG as SHOP_CATALOG


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def _user_id(client, headers):
    return client.get("/users/me", headers=headers).json()["id"]


def _add_run(db_session, user_id, distance_m):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    db_session.add(Run(
        id=str(uuid4()),
        user_id=user_id,
        request_hash=str(uuid4()),
        track_hash=str(uuid4()),
        track_json="[]",
        started_at=now - timedelta(minutes=40),
        ended_at=now,
        distance_m=distance_m,
        duration_seconds=2400,
        name="Laço de teste",
        result_json='{"claim": null, "claim_error": null}',
    ))
    db_session.commit()


def _by_id(entries):
    return {entry["id"]: entry for entry in entries}


def test_fresh_user_sees_the_catalog_locked(client, registered_user):
    response = client.get("/badges", headers=_auth(registered_user))
    assert response.status_code == 200
    entries = response.json()
    assert len(entries) == len(CATALOG)
    assert {e["id"] for e in entries} == {b["id"] for b in CATALOG}
    assert all(e["earned"] is False for e in entries)
    assert all(e["earned_at"] is None for e in entries)


def test_getting_badges_requires_no_claim(client, registered_user, db_session):
    headers = _auth(registered_user)
    _add_run(db_session, _user_id(client, headers), 5200)
    earned = {e["id"] for e in client.get("/badges", headers=headers).json() if e["earned"]}
    assert earned == {"badge_primeira_corrida", "badge_cinco_km"}


def test_progress_reports_the_metric_against_the_threshold(client, registered_user, db_session):
    headers = _auth(registered_user)
    _add_run(db_session, _user_id(client, headers), 5200)
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_dez_km"]["earned"] is False
    assert badges["badge_dez_km"]["progress"] == 5.2
    assert badges["badge_dez_km"]["threshold"] == 10
    assert badges["badge_primeira_corrida"]["progress"] == 1


def test_earned_date_is_stable_and_stored_once(client, registered_user, db_session):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    _add_run(db_session, user_id, 900)
    first = _by_id(client.get("/badges", headers=headers).json())
    second = _by_id(client.get("/badges", headers=headers).json())
    assert first["badge_primeira_corrida"]["earned_at"] is not None
    assert second["badge_primeira_corrida"]["earned_at"] == first["badge_primeira_corrida"]["earned_at"]
    rows = (
        db_session.query(UserBadge)
        .filter(UserBadge.user_id == user_id, UserBadge.badge_id == "badge_primeira_corrida")
        .all()
    )
    assert len(rows) == 1


def test_conquest_and_team_rules(client, registered_user, db_session):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    territory = Territory(
        name='Praça Insígnia',
        geojson='{"type":"Point","coordinates":[0,0]}',
        radius_m=50,
        relevance=1,
    )
    db_session.add(territory)
    db_session.flush()
    db_session.add(TerritoryOwnership(
        territory_id=territory.id, owner_user_id=user_id, points=10,
    ))
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_primeira_conquista"]["earned"] is True
    assert badges["badge_cinco_conquistas"]["earned"] is False
    assert badges["badge_em_equipe"]["earned"] is False


def test_level_badges_come_from_the_account_level(client, registered_user, db_session):
    """As recompensas de nível são estáticas: liberam pelo nível, sem resgate."""
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    db_session.add(ScoreEvent(user_id=user_id, delta=450, reason="conquista"))
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_nivel_3"]["earned"] is True
    assert badges["badge_nivel_3"]["progress"] == 3
    assert badges["badge_nivel_5"]["earned"] is False


def test_level_badges_are_not_shop_or_pass_items(client):
    """As insígnias não são cópias do que a loja ou o passe entregam."""
    headers = client.post(
        "/auth/register",
        json={
            "full_name": "Ana Teste", "username": "anabadge",
            "email": "ana@example.com", "password": "original123",
            "accept_terms": True,
        },
    ).json()["access_token"]
    owned = {item["id"] for item in SHOP_CATALOG}
    badge_ids = {badge["id"] for badge in CATALOG}
    assert owned.isdisjoint(badge_ids)
    assert client.get("/badges", headers={"Authorization": f"Bearer {headers}"}).status_code == 200


def test_badges_are_removed_with_the_account(client, registered_user, db_session):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    _add_run(db_session, user_id, 900)
    assert client.get("/badges", headers=headers).status_code == 200
    assert client.delete("/users/me", headers=headers).status_code == 204
    assert db_session.query(UserBadge).filter(UserBadge.user_id == user_id).count() == 0


def test_badges_need_the_token(client):
    assert client.get("/badges").status_code == 401
