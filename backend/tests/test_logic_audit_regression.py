"""Posse liberada não quebra a leitura; loja externa não equipa outros escopos.

- Dissolver a equipe (ou excluir a conta) anula o dono da posse sem apagar
  a linha; listar/detalhar o território deve responder "disponivel".
- Itens de escopo `pass`/`team` só saem pelos fluxos próprios (resgate do
  passe, cofre da equipe): equipar direto deve recusar sem conceder.
- A meta semanal do badge Pit-stop usa o fuso do aparelho, como o progresso.
- A lista de equipes expõe o efeito equipado, como o detalhe e o ranking.
- Frequência semanal de treino só aceita 1..7 dias (0 não é frequência).
"""
from datetime import datetime, timedelta, timezone

from app.models import Territory, TerritoryOwnership, User
from app.services.shop import EQUIPPABLE

_SQUARE = (
    '{"type":"Polygon","coordinates":[[[-46.6600,-23.5900],'
    '[-46.6590,-23.5900],[-46.6590,-23.5890],'
    '[-46.6600,-23.5890],[-46.6600,-23.5900]]]}'
)


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def _now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def test_freed_territory_lists_as_available(client, registered_user, db_session):
    headers = _auth(registered_user)
    user = db_session.query(User).filter(
        User.email == "runner@example.com"
    ).one()
    territory = Territory(
        name="Largo Liberado", geojson=_SQUARE, radius_m=80, relevance=1,
    )
    db_session.add(territory)
    db_session.flush()
    db_session.add(TerritoryOwnership(
        territory_id=territory.id, owner_user_id=user.id, points=10,
        conquered_at=_now() - timedelta(hours=2),
    ))
    # Mesmo estado que o disband/exclusão produz: linha atual sem dono.
    db_session.add(TerritoryOwnership(
        territory_id=territory.id, owner_user_id=None, owner_team_id=None,
        points=0, conquered_at=_now(),
    ))
    db_session.commit()

    listing = client.get("/territories", headers=headers)
    assert listing.status_code == 200, listing.text
    entry = next(e for e in listing.json() if e["id"] == territory.id)
    assert entry["status"] == "disponivel"
    assert entry["owner_type"] is None
    assert entry["owner_display"] is None

    detail = client.get(f"/territories/{territory.id}", headers=headers)
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["owner_type"] is None
    assert body["conquered_at"] is None
    # O dono anterior continua no histórico; a linha liberada não entra.
    assert len(body["history"]) == 1
    assert body["history"][0]["owner_type"] == "user"
    assert body["history"][0]["owner_display"] == user.username


def test_equip_rejects_pass_scope_without_granting(client, registered_user):
    headers = _auth(registered_user)
    response = client.post("/shop/equip", json={
        "category": "banner", "item_id": "pass_banner_pioneiro",
    }, headers=headers)
    assert response.status_code == 404, response.text
    inventory = client.get("/shop/inventory", headers=headers).json()
    assert "pass_banner_pioneiro" not in inventory["owned"]
    assert inventory["equipped_banner"] is None


def test_equip_allows_pass_item_after_claim(client, registered_user, db_session):
    from app.models import ScoreEvent
    headers = _auth(registered_user)
    user_id = client.get("/users/me", headers=headers).json()["id"]
    db_session.add(ScoreEvent(user_id=user_id, delta=2000, reason="conquista"))
    db_session.commit()
    claimed = client.post(
        "/pass/claim", json={"tier": 10, "track": "free"}, headers=headers,
    )
    assert claimed.status_code == 200, claimed.text
    equipped = client.post("/shop/equip", json={
        "category": "banner", "item_id": "pass_banner_pioneiro",
    }, headers=headers)
    assert equipped.status_code == 200, equipped.text
    assert equipped.json()["equipped_banner"] == "pass_banner_pioneiro"


def test_equip_rejects_team_scope_without_granting(client, registered_user):
    headers = _auth(registered_user)
    catalog = client.get("/shop/catalog", params={"scope": "team"}).json()
    item = next(i for i in catalog if i["category"] in EQUIPPABLE)
    response = client.post("/shop/equip", json={
        "category": item["category"], "item_id": item["id"],
    }, headers=headers)
    assert response.status_code == 404, response.text
    inventory = client.get("/shop/inventory", headers=headers).json()
    assert item["id"] not in inventory["owned"]


def test_badges_accept_device_timezone(client, registered_user):
    headers = _auth(registered_user)
    response = client.get(
        "/badges", params={"utc_offset_minutes": -180}, headers=headers,
    )
    assert response.status_code == 200, response.text
    assert isinstance(response.json(), list)


def test_badges_rejects_out_of_range_timezone(client, registered_user):
    headers = _auth(registered_user)
    response = client.get(
        "/badges", params={"utc_offset_minutes": 9999}, headers=headers,
    )
    assert response.status_code == 422, response.text


def test_team_list_exposes_equipped_effect(client, registered_user):
    headers = _auth(registered_user)
    created = client.post("/teams", json={"name": "Efeito Visível"}, headers=headers)
    assert created.status_code == 201, created.text
    listing = client.get("/teams", headers=headers)
    assert listing.status_code == 200, listing.text
    entry = next(t for t in listing.json() if t["id"] == created.json()["id"])
    assert "equipped_effect" in entry


def test_weekly_frequency_zero_is_rejected(client, registered_user):
    headers = _auth(registered_user)
    response = client.patch(
        "/users/me", json={"weekly_frequency": 0}, headers=headers,
    )
    assert response.status_code == 422, response.text
