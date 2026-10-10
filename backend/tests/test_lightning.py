"""Dominacao Relampago: partida curta da equipe.

So dono/admin abre (15 ou 30 min); cada membro escolhe participar (opt-in) e
so o laco de quem entrou conta. O primeiro GET apos o fim finaliza de forma
idempotente e paga metade dos pontos da janela ao cofre.
"""
from datetime import datetime, timedelta, timezone

from app.models import ScoreEvent, Territory, TerritoryOwnership, User


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def _register(client, username, email):
    response = client.post("/auth/register", json={
        "full_name": username,
        "username": username,
        "email": email,
        "password": "original123",
        "accept_terms": True,
    })
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _team(client, headers, name="Trovão"):
    response = client.post("/teams", json={"name": name}, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()["id"]


def _join_team(client, db_session, team_id, email):
    """Membro direto (sem passar pelo fluxo de pedido/aprovação)."""
    from app.models import TeamMember

    user = db_session.query(User).filter_by(email=email).one()
    db_session.add(TeamMember(team_id=team_id, user_id=user.id))
    db_session.commit()


def _conquest(db_session, user_email, points=100, when=None, team_id=None):
    user = db_session.query(User).filter_by(email=user_email).one()
    territory = Territory(
        name="Pedaço",
        geojson='{"type":"Polygon","coordinates":[[[0,0],[0.001,0],[0.001,0.001],[0,0.001],[0,0]]]}',
        radius_m=80,
    )
    db_session.add(territory)
    db_session.flush()
    db_session.add(
        TerritoryOwnership(
            territory_id=territory.id,
            owner_user_id=None if team_id else user.id,
            owner_team_id=team_id,
            points=points,
            conquered_at=when or datetime.now(timezone.utc),
            runner_user_id=user.id,
        )
    )
    db_session.commit()


def test_open_needs_admin_and_valid_duration(client, registered_user, db_session):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    other = _register(client, "colega", "colega@example.com")
    _join_team(client, db_session, team_id, "colega@example.com")

    denied = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=other
    )
    assert denied.status_code == 403, denied.text

    outsider = _register(client, "fora", "fora@example.com")
    missing = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=outsider
    )
    assert missing.status_code == 403, missing.text

    bad = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 60}, headers=owner
    )
    assert bad.status_code == 400, bad.text


def test_open_autojoin_creator_and_rejects_second(client, registered_user):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    opened = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=owner
    )
    assert opened.status_code == 200, opened.text
    body = opened.json()
    assert body["open"] is True
    assert body["participants"] == ["testrunner"]
    assert body["duration_min"] == 15

    again = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 30}, headers=owner
    )
    assert again.status_code == 409, again.text


def test_join_is_opt_in_and_idempotent(client, registered_user, db_session):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    other = _register(client, "colega", "colega@example.com")
    _join_team(client, db_session, team_id, "colega@example.com")
    session_id = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=owner
    ).json()["id"]

    joined = client.post(f"/lightning/{session_id}/join", headers=other)
    assert joined.status_code == 200, joined.text
    assert sorted(joined.json()["participants"]) == ["colega", "testrunner"]

    repeat = client.post(f"/lightning/{session_id}/join", headers=other)
    assert repeat.status_code == 200, repeat.text
    assert sorted(repeat.json()["participants"]) == ["colega", "testrunner"]

    outsider = _register(client, "fora", "fora@example.com")
    denied = client.post(f"/lightning/{session_id}/join", headers=outsider)
    assert denied.status_code == 403, denied.text


def test_only_participant_loops_score(client, registered_user, db_session):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    other = _register(client, "colega", "colega@example.com")
    _join_team(client, db_session, team_id, "colega@example.com")
    session_id = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=owner
    ).json()["id"]

    _conquest(db_session, "runner@example.com", points=100)
    # Colega é membro mas não entrou: o laço dele não conta.
    _conquest(db_session, "colega@example.com", points=100)
    # Fora da janela: não conta mesmo participando.
    _conquest(
        db_session,
        "runner@example.com",
        points=100,
        when=datetime.now(timezone.utc) - timedelta(hours=2),
    )

    board = client.get(f"/lightning/{session_id}", headers=owner).json()
    assert board["takes"] == 1
    assert board["points"] == 100
    assert board["mvp"] == "testrunner"
    assert board["entries"] == [
        {"username": "testrunner", "takes": 1, "points": 100}
    ]


def test_finalize_pays_bonus_once(client, registered_user, db_session):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    session_id = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=owner
    ).json()["id"]
    # Dentro da janela que vamos fechar no passado.
    _conquest(
        db_session,
        "runner@example.com",
        points=100,
        when=datetime.now(timezone.utc) - timedelta(minutes=10),
    )

    from app.models import LightningSession

    db_session.query(LightningSession).filter_by(id=session_id).update({
        "starts_at": datetime.now(timezone.utc) - timedelta(minutes=20),
        "ends_at": datetime.now(timezone.utc) - timedelta(minutes=5),
    })
    db_session.commit()

    first = client.get(f"/lightning/{session_id}", headers=owner).json()
    assert first["finalized"] is True
    assert first["open"] is False
    assert first["bonus_points"] == 50
    second = client.get(f"/lightning/{session_id}", headers=owner).json()
    assert second["bonus_points"] == 50

    bonus = (
        db_session.query(ScoreEvent)
        .filter_by(team_id=team_id, reason="relâmpago")
        .all()
    )
    assert [e.delta for e in bonus] == [50]


def test_history_lists_newest_first(client, registered_user, db_session):
    owner = _auth(registered_user)
    team_id = _team(client, owner)
    first_id = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 15}, headers=owner
    ).json()["id"]

    from app.models import LightningSession

    db_session.query(LightningSession).filter_by(id=first_id).update({
        "starts_at": datetime.now(timezone.utc) - timedelta(hours=2),
        "ends_at": datetime.now(timezone.utc) - timedelta(hours=1),
    })
    db_session.commit()
    client.get(f"/lightning/{first_id}", headers=owner)

    second_id = client.post(
        f"/teams/{team_id}/lightning", json={"duration_min": 30}, headers=owner
    ).json()["id"]
    history = client.get(
        f"/teams/{team_id}/lightning", headers=owner
    ).json()
    assert [s["id"] for s in history] == [second_id, first_id]
    assert history[1]["finalized"] is True
