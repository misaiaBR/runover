"""Convite pendente não pode sobreviver ao time que sumiu.

Dissolver a equipe tem dois caminhos no servidor — `DELETE /teams/{id}` e a
exclusão da conta do dono — e os dois escrevem a mesma limpeza de tabelas.
Um convite que fica sem time é a caixa de entrada mostrando um convite que a
pessoa não pode aceitar (aceitar arrebenta no `r.team.name`) e uma linha de
`team_join_requests` apontando para uma equipe que não existe mais.
"""

from auth_helpers import auth_headers
from app.models import TeamJoinRequest


def _user(client, username):
    return auth_headers(client, username=username, email=f"{username}@example.com")


def _team_with_pending_invite(client, owner, guest):
    created = client.post(
        "/teams", json={"name": "Time Convite"}, headers=owner,
    )
    assert created.status_code == 201, created.text
    team_id = created.json()["id"]
    invited = client.post(
        f"/teams/{team_id}/invites", json={"username": "convidado"}, headers=owner,
    )
    assert invited.status_code == 200, invited.text
    inbox = client.get("/teams/invites", headers=guest).json()
    assert len(inbox) == 1, inbox
    return team_id


def test_disband_withdraws_the_pending_invite(client, db_session):
    owner = _user(client, "dono")
    guest = _user(client, "convidado")
    team_id = _team_with_pending_invite(client, owner, guest)

    assert client.delete(f"/teams/{team_id}", headers=owner).status_code == 204

    after = client.get("/teams/invites", headers=guest)
    assert after.status_code == 200, after.text
    assert after.json() == []
    assert db_session.query(TeamJoinRequest).count() == 0


def test_account_deletion_withdraws_the_pending_invite(client, db_session):
    owner = _user(client, "dono")
    guest = _user(client, "convidado")
    _team_with_pending_invite(client, owner, guest)

    assert client.delete("/users/me", headers=owner).status_code == 204

    after = client.get("/teams/invites", headers=guest)
    assert after.status_code == 200, after.text
    assert after.json() == []
    # A caixa de entrada não vê o convite porque ele ficou sem quem convidou,
    # mas a linha continua apontando para uma equipe que não existe mais — no
    # Postgres essa exclusão morre na chave estrangeira antes de chegar aqui.
    assert db_session.query(TeamJoinRequest).count() == 0
