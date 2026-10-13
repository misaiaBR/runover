"""Posição no ranking é do corredor, não do nome que ele usa.

Usuário tem nome único no sistema; equipe não tem restrição nenhuma em relação
aos nomes de usuário. Uma equipe chamada como um corredor fazia a posição da
equipe ser devolvida no perfil dele.
"""

from app.models import ScoreEvent, User
from tests.auth_helpers import auth_headers


def _user_id(db_session, username):
    return db_session.query(User).filter(User.username == username).one().id


def test_team_named_like_a_player_does_not_steal_his_position(client, db_session):
    """Posição no ranking é do id; nome de equipe não é chave de nada."""
    headers = auth_headers(client, username="atlas", email="atlas@example.com")
    team = client.post("/teams", json={"name": "atlas"}, headers=headers)
    assert team.status_code == 201, team.text
    uid = _user_id(db_session, "atlas")
    db_session.add(ScoreEvent(user_id=uid, delta=500, reason="conquista"))
    db_session.add(ScoreEvent(team_id=team.json()["id"], delta=900, reason="conquista"))
    db_session.commit()

    profile = client.get("/users/atlas", headers=headers).json()
    assert profile["rank_position"] == 2, profile
    ranking = client.get("/ranking", headers=headers).json()
    rows = [(e["owner_type"], e["name"], e["position"]) for e in ranking]
    assert ("team", "atlas", 1) in rows, rows
    assert ("user", "atlas", 2) in rows, rows
