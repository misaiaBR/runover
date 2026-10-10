"""Insígnias: catálogo, concessão pela regra e data de ganho."""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.models import (
    PassPremium,
    Run,
    ScoreEvent,
    Team,
    TeamJoinRequest,
    TeamMember,
    Territory,
    TerritoryOwnership,
    UserBadge,
)
from app.services.badges import CATALOG
from app.services.pass_runover import current_season
from app.services.scoring import TEAM_WEEK_GOAL_KM
from app.services.shop import CATALOG as SHOP_CATALOG


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def _user_id(client, headers):
    return client.get("/users/me", headers=headers).json()["id"]


def _add_run(db_session, user_id, distance_m, team_id=None, started_at=None):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    db_session.add(Run(
        id=str(uuid4()),
        user_id=user_id,
        team_id=team_id,
        request_hash=str(uuid4()),
        track_hash=str(uuid4()),
        track_json="[]",
        started_at=started_at or now - timedelta(minutes=40),
        ended_at=started_at or now,
        distance_m=distance_m,
        duration_seconds=2400,
        name="Laço de teste",
        result_json='{"claim": null, "claim_error": null}',
    ))
    db_session.commit()


def _add_team(db_session, creator_id, member_ids=()):
    team = Team(id=str(uuid4()), name="Equipe de teste", creator_id=creator_id)
    db_session.add(team)
    db_session.flush()
    for member_id in (creator_id, *member_ids):
        db_session.add(TeamMember(
            id=str(uuid4()), team_id=team.id, user_id=member_id
        ))
    db_session.commit()
    return team


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


def test_every_badge_is_grouped_in_a_category(client, registered_user):
    """A tela agrupa por categoria: nenhuma regra pode chegar solta."""
    entries = client.get("/badges", headers=_auth(registered_user)).json()
    assert len(entries) == len(CATALOG)
    assert all(entry["category"] for entry in entries)
    assert len({entry["category"] for entry in entries}) == 6
    by_id = {entry["id"]: entry for entry in entries}
    assert by_id["badge_primeira_corrida"]["category"] == "corridas"
    assert by_id["badge_dez_conquistas"]["category"] == "territorios"
    assert by_id["badge_meia_maratona"]["category"] == "distancia"
    assert by_id["badge_centenar"]["category"] == "acumulados"
    assert by_id["badge_pit_stop"]["category"] == "equipe"
    assert by_id["badge_passe_premium"]["category"] == "temporada"


def _register(client, username, email):
    body = {
        "full_name": f"Conta {username}", "username": username, "email": email,
        "password": "original123", "accept_terms": True,
    }
    token = client.post("/auth/register", json=body).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    return headers, client.get("/users/me", headers=headers).json()["id"]


def test_ten_territories_is_its_own_rule(client, registered_user, db_session):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    for index in range(10):
        territory = Territory(
            name=f'Praça {index}', geojson='{"type":"Point","coordinates":[0,0]}',
            radius_m=50, relevance=1,
        )
        db_session.add(territory)
        db_session.flush()
        db_session.add(TerritoryOwnership(
            territory_id=territory.id, owner_user_id=user_id, points=10,
        ))
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_dez_conquistas"]["progress"] == 10
    assert badges["badge_dez_conquistas"]["earned"] is True


def test_team_category_tracks_creating_inviting_and_the_pit_stop(
    client, registered_user, db_session
):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    _, guest_id = _register(client, "convidado", "convidado@example.com")
    team = _add_team(db_session, user_id)
    db_session.add(TeamJoinRequest(
        id=str(uuid4()), team_id=team.id, user_id=guest_id,
        invited_by=user_id, status="pending",
    ))
    _add_run(db_session, user_id, TEAM_WEEK_GOAL_KM * 1000, team_id=team.id)
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    for badge in ("badge_em_equipe", "badge_criar_equipe", "badge_primeiro_convite", "badge_pit_stop"):
        assert badges[badge]["earned"] is True, badge


def test_pit_stop_needs_the_whole_team_goal_of_the_current_week(
    client, registered_user, db_session
):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    team = _add_team(db_session, user_id)
    # 12 km nesta semana e 40 km na passada: nenhuma delas fecha o pit stop.
    _add_run(db_session, user_id, 12_000, team_id=team.id)
    last_week = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=9)
    _add_run(db_session, user_id, 40_000, team_id=team.id, started_at=last_week)
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_pit_stop"]["earned"] is False
    assert badges["badge_pit_stop"]["progress"] == 0
    # Completando a meta, a insígnia entra — e fica, mesmo na semana seguinte.
    _add_run(db_session, user_id, (TEAM_WEEK_GOAL_KM - 12) * 1000, team_id=team.id)
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_pit_stop"]["earned"] is True


def test_season_category_measures_the_pass_not_the_account_level(
    client, registered_user, db_session
):
    headers = _auth(registered_user)
    user_id = _user_id(client, headers)
    # 1.000 pontos na temporada = tier 5 (200 por tier).
    db_session.add(ScoreEvent(user_id=user_id, delta=1000, reason="conquista"))
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_subindo_temporada"]["progress"] == 5
    assert badges["badge_subindo_temporada"]["earned"] is True
    assert badges["badge_passe_premium"]["earned"] is False
    db_session.add(PassPremium(user_id=user_id, season_id=current_season()))
    db_session.commit()
    badges = _by_id(client.get("/badges", headers=headers).json())
    assert badges["badge_passe_premium"]["earned"] is True
