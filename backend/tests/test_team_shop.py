"""Loja da equipe: cofre = soma dos pontos dos integrantes, sem tirar nada.

Compra e equipamento só pelo dono ou admins; preços altos em pontos;
ninguém perde nível, ranking ou moedas ao comprar para a equipe.
"""

from app.models import ScoreEvent
from app.services.scoring import total_score
from auth_helpers import auth_headers


def _register(client, username, email):
    return auth_headers(client, username=username, email=email,
                        full_name=f"{username} Name", password="secret123")


def _team_with_member(client, db_session):
    owner = _register(client, "donoeq", "dono@example.com")
    member = _register(client, "membroeq", "membro@example.com")
    team = client.post("/teams", json={"name": "Equipe Cofre"}, headers=owner).json()
    team_id = team["id"]
    assert client.post(f"/teams/{team_id}/join", headers=member).status_code == 202
    requests = client.get(f"/teams/{team_id}/requests", headers=owner).json()
    assert client.post(
        f"/teams/{team_id}/requests/{requests[0]['id']}/approve", headers=owner
    ).status_code == 200
    return team_id, owner, member


def _give_points(db_session, client, headers, points):
    user_id = client.get("/users/me", headers=headers).json()["id"]
    db_session.add(ScoreEvent(user_id=user_id, delta=points, reason="conquista"))
    db_session.commit()


def _prices(client):
    items = client.get("/shop/catalog", params={"scope": "team"}).json()
    return {i["id"]: i["price"] for i in items}


def test_catalog_scope_filter_lists_only_team_items(client):
    scoped = client.get("/shop/catalog", params={"scope": "team"}).json()
    assert scoped, "catálogo team não pode estar vazio"
    assert {i["scope"] for i in scoped} == {"team"}
    assert all(i["price"] > 0 for i in scoped)
    everything = client.get("/shop/catalog").json()
    assert len(everything) > len(scoped)
    assert client.get("/shop/catalog", params={"scope": "invalido"}).status_code == 400


def test_wallet_sums_member_points(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 3000)
    _give_points(db_session, client, member, 2000)
    wallet = client.get(f"/teams/{team_id}/wallet", headers=owner).json()
    assert wallet == {"balance": 5000, "spent_points": 0, "members_points": 5000}


def test_purchase_uses_vault_and_preserves_member_scores(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 3000)
    _give_points(db_session, client, member, 3000)
    price = _prices(client)["team_frame_ferro"]

    bought = client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_frame_ferro"}, headers=owner
    )
    assert bought.status_code == 200, bought.text
    assert "team_frame_ferro" in bought.json()["owned"]

    wallet = client.get(f"/teams/{team_id}/wallet", headers=owner).json()
    assert wallet["spent_points"] == price
    assert wallet["balance"] == 6000 - price

    # Ninguém perdeu pontos, nível ou moedas: o gasto é só do cofre.
    for headers in (owner, member):
        me = client.get("/users/me", headers=headers).json()
        assert me["total_score"] == 3000
        assert me["coins_balance"] == 0
    owner_id = client.get("/users/me", headers=owner).json()["id"]
    assert total_score(db_session, owner_id) == 3000


def test_purchase_insufficient_is_402_without_spending(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 1000)
    price = _prices(client)["team_frame_ouro"]
    assert price > 1000
    denied = client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_frame_ouro"}, headers=owner
    )
    assert denied.status_code == 402
    wallet = client.get(f"/teams/{team_id}/wallet", headers=owner).json()
    assert wallet["spent_points"] == 0


def test_purchase_duplicate_is_409(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 20000)
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_effect_faisca"}, headers=owner
    ).status_code == 200
    again = client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_effect_faisca"}, headers=owner
    )
    assert again.status_code == 409


def test_member_cannot_purchase_but_admin_can(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 20000)
    _give_points(db_session, client, member, 20000)
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_effect_faisca"}, headers=member
    ).status_code == 403
    # Promovido a admin, pode comprar.
    assert client.post(
        f"/teams/{team_id}/admins", json={"username": "membroeq"}, headers=owner
    ).status_code == 200
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_effect_faisca"}, headers=member
    ).status_code == 200


def test_scopes_do_not_cross(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 20000)
    # Item pessoal na loja da equipe dá 400.
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "frame_bronze"}, headers=owner
    ).status_code == 400
    # Item da equipe na loja pessoal dá 400 (sem gastar moedas).
    assert client.post(
        "/shop/purchase", json={"item_id": "team_frame_ferro"}, headers=owner
    ).status_code == 400


def test_equip_and_unequip_flow(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 20000)
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_frame_ferro"}, headers=owner
    ).status_code == 200

    equipped = client.post(
        f"/teams/{team_id}/equip",
        json={"category": "frame", "item_id": "team_frame_ferro"},
        headers=owner,
    )
    assert equipped.status_code == 200
    assert equipped.json()["equipped_frame"] == "team_frame_ferro"
    detail = client.get(f"/teams/{team_id}", headers=member).json()
    assert detail["equipped_frame"] == "team_frame_ferro"
    assert detail["team_balance"] == 20000 - 5000
    assert detail["team_spent"] == 5000

    cleared = client.post(
        f"/teams/{team_id}/equip",
        json={"category": "frame", "item_id": None},
        headers=owner,
    )
    assert cleared.json()["equipped_frame"] is None

    # Equipar sem possuir dá 403; membro comum não equipa (403).
    assert client.post(
        f"/teams/{team_id}/equip",
        json={"category": "frame", "item_id": "team_frame_ouro"},
        headers=owner,
    ).status_code == 403
    assert client.post(
        f"/teams/{team_id}/equip",
        json={"category": "frame", "item_id": "team_frame_ferro"},
        headers=member,
    ).status_code == 403


def test_bundle_purchase_grants_team_items(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 100000)
    bought = client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_pacote_batalha"}, headers=owner
    )
    assert bought.status_code == 200, bought.text
    owned = set(bought.json()["owned"])
    assert {"team_pacote_batalha", "team_frame_ferro", "team_effect_faisca", "team_banner_bau"} <= owned
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_pacote_batalha"}, headers=owner
    ).status_code == 409


def test_member_leaving_shrinks_vault_without_debt(client, db_session):
    team_id, owner, member = _team_with_member(client, db_session)
    _give_points(db_session, client, owner, 3000)
    _give_points(db_session, client, member, 3000)
    price = _prices(client)["team_frame_ferro"]
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_frame_ferro"}, headers=owner
    ).status_code == 200
    # Membro sai: soma cai para 3000, já gasto continua → saldo zera, sem dívida.
    assert client.post("/teams/leave", headers=member).status_code == 204
    wallet = client.get(f"/teams/{team_id}/wallet", headers=owner).json()
    assert wallet["members_points"] == 3000
    assert wallet["spent_points"] == price
    assert wallet["balance"] == 0
    expensive = [i for i, p in _prices(client).items() if p > 0][0]
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": expensive}, headers=owner
    ).status_code in (402, 409)
