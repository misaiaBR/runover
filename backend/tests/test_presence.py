"""Presença: o estado que o corredor escolhe e o online que a equipe vê.

Quatro estados ("disponivel", "ausente", "nao_incomodar", "invisivel"), um
batimento de app aberto e a leitura disso no painel da equipe.
"""

from datetime import datetime, timedelta, timezone

from app.models import LocationPing, User
from app.services.notifications import notify


def _register(client, username, email):
    response = client.post("/auth/register", json={
        "full_name": f"{username.title()} Silva", "username": username, "email": email,
        "password": "secret123", "accept_terms": True,
    })
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def _me(client, headers):
    response = client.get("/users/me", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _team_with_two_members(client):
    """Dono + membro aceito por convite; devolve (headers, headers, team_id)."""
    owner = _register(client, "dono", "dono@example.com")
    mate = _register(client, "parceiro", "parceiro@example.com")
    team = client.post("/teams", json={"name": "Time Presença"}, headers=owner)
    assert team.status_code == 201, team.text
    team_id = team.json()["id"]
    invited = client.post(
        f"/teams/{team_id}/invites", json={"username": "parceiro"}, headers=owner,
    )
    assert invited.status_code == 200, invited.text
    pending = client.get("/teams/invites", headers=mate).json()
    assert len(pending) == 1
    accepted = client.post(
        f"/teams/invites/{pending[0]['id']}/accept", headers=mate,
    )
    assert accepted.status_code == 200, accepted.text
    return owner, mate, team_id


def _member(team_json, username):
    return next(m for m in team_json["members"] if m["username"] == username)


def test_presence_defaults_to_disponivel(client):
    headers = _register(client, "novato", "novato@example.com")
    assert _me(client, headers)["presence"] == "disponivel"


def test_patch_accepts_each_of_the_four_states(client):
    headers = _register(client, "pill", "pill@example.com")
    for state in ("ausente", "nao_incomodar", "invisivel", "disponivel"):
        response = client.patch("/users/me", json={"presence": state}, headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()["presence"] == state


def test_patch_rejects_an_unknown_state(client):
    headers = _register(client, "estranho", "estranho@example.com")
    response = client.patch("/users/me", json={"presence": "modo_turbo"}, headers=headers)
    assert response.status_code == 422, response.text
    # O estado anterior continua de pé: nada foi gravado pela metade.
    assert _me(client, headers)["presence"] == "disponivel"


def test_presence_is_not_a_public_field(client):
    headers = _register(client, "discreto", "discreto@example.com")
    client.patch("/users/me", json={"presence": "invisivel"}, headers=headers)
    viewer = _register(client, "visitante", "visitante@example.com")
    public = client.get("/users/discreto", headers=viewer)
    assert public.status_code == 200, public.text
    # O pill é preferência de quem corre: não sai para os outros.
    assert "presence" not in public.json()


def test_heartbeat_stamps_the_runner(client, db_session):
    headers = _register(client, "batida", "batida@example.com")
    response = client.post("/presence", headers=headers)
    assert response.status_code == 204, response.text
    assert response.content == b""
    user = db_session.query(User).filter(User.username == "batida").first()
    assert user.last_seen_at is not None
    # Coluna naive em UTC: perto de agora, nem de longe.
    delta = datetime.now(timezone.utc).replace(tzinfo=None) - user.last_seen_at
    assert timedelta(minutes=-1) < delta < timedelta(minutes=1)


def test_heartbeat_needs_credentials(client):
    assert client.post("/presence").status_code == 401


def test_own_profile_reports_the_online_dot(client):
    headers = _register(client, "verde", "verde@example.com")
    # Sem sinal nenhum ainda não há ponto verde: nada de inventar presença.
    assert _me(client, headers)["online"] is False
    assert client.post("/presence", headers=headers).status_code == 204
    assert _me(client, headers)["online"] is True


def test_invisible_runner_has_no_online_dot_even_for_yourself(client):
    headers = _register(client, "fantasma", "fantasma@example.com")
    client.patch("/users/me", json={"presence": "invisivel"}, headers=headers)
    assert client.post("/presence", headers=headers).status_code == 204
    assert _me(client, headers)["online"] is False


def test_heartbeat_makes_the_member_online_for_the_team(client):
    owner, mate, team_id = _team_with_two_members(client)
    before = client.get(f"/teams/{team_id}", headers=owner).json()
    assert before["online_count"] == 0
    assert _member(before, "parceiro")["is_online"] is False

    assert client.post("/presence", headers=mate).status_code == 204
    after = client.get(f"/teams/{team_id}", headers=owner).json()
    assert after["online_count"] == 1
    assert _member(after, "parceiro")["is_online"] is True
    assert _member(after, "dono")["is_online"] is False


def test_gps_ping_still_counts_as_online(client, db_session):
    """Quem está correndo continua aparecendo mesmo sem bater o app aberto."""
    owner, mate, team_id = _team_with_two_members(client)
    mate_id = _me(client, mate)["id"]
    db_session.add(
        LocationPing(
            user_id=mate_id,
            latitude=-23.55,
            longitude=-46.63,
            recorded_at=datetime.now(timezone.utc).replace(tzinfo=None),
        )
    )
    db_session.commit()
    team = client.get(f"/teams/{team_id}", headers=owner).json()
    assert team["online_count"] == 1
    assert _member(team, "parceiro")["is_online"] is True


def test_stale_signals_leave_the_team(client, db_session):
    owner, mate, team_id = _team_with_two_members(client)
    assert client.post("/presence", headers=mate).status_code == 204
    mate_id = _me(client, mate)["id"]
    user = db_session.query(User).filter(User.id == mate_id).first()
    # Fora da janela de 15 minutos: o app esteve aberto, mas não está agora.
    user.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
        minutes=20
    )
    db_session.commit()
    team = client.get(f"/teams/{team_id}", headers=owner).json()
    assert team["online_count"] == 0
    assert _member(team, "parceiro")["is_online"] is False


def test_invisible_runner_is_out_of_the_online_count(client):
    owner, mate, team_id = _team_with_two_members(client)
    assert client.patch("/users/me", json={"presence": "invisivel"}, headers=mate).status_code == 200
    assert client.post("/presence", headers=mate).status_code == 204
    team = client.get(f"/teams/{team_id}", headers=owner).json()
    assert team["online_count"] == 0
    assert _member(team, "parceiro")["is_online"] is False


def test_ausente_still_counts_as_online(client):
    owner, mate, team_id = _team_with_two_members(client)
    assert client.patch("/users/me", json={"presence": "ausente"}, headers=mate).status_code == 200
    assert client.post("/presence", headers=mate).status_code == 204
    team = client.get(f"/teams/{team_id}", headers=owner).json()
    assert team["online_count"] == 1
    assert _member(team, "parceiro")["is_online"] is True


def _types_seen(client, headers):
    response = client.get("/notifications", headers=headers)
    assert response.status_code == 200, response.text
    return {n["type"] for n in response.json()}


def test_nao_incomodar_deixa_passar_so_risco_e_equipe(client, db_session):
    headers = _register(client, "quieto", "quieto@example.com")
    user_id = _me(client, headers)["id"]
    client.patch("/users/me", json={"presence": "nao_incomodar"}, headers=headers)
    for message, type_ in (
        ("Você perdeu o território Praça.", "perda"),
        ("@dono te convidou para o Time Presença.", "equipe"),
        ("Você alcançou o nível 4!", "nivel"),
        ("Você conquistou o território Praça!", "conquista"),
        ("Você subiu no ranking.", "ranking"),
        ("Você está em Turbo 2.", "liga"),
    ):
        notify(db_session, user_id, message, type_)
    db_session.commit()
    assert _types_seen(client, headers) == {"perda", "equipe"}


def test_o_outro_estado_recebe_tudo(client, db_session):
    headers = _register(client, "falante", "falante@example.com")
    user_id = _me(client, headers)["id"]
    for message, type_ in (
        ("Você alcançou o nível 4!", "nivel"),
        ("Você conquistou o território Praça!", "conquista"),
    ):
        notify(db_session, user_id, message, type_)
    db_session.commit()
    assert _types_seen(client, headers) == {"nivel", "conquista"}
