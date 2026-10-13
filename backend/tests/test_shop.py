from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.models import CoinTransaction, UserItem
from app.services import coins
from app.services.shop import CATALOG, get_item


def _track(num_points=70, offset_minutes=0):
    """Percurso de ~200 m por ponto, 1 ponto/min (~3,3 m/s, ritmo plausível)."""
    start = datetime.now(timezone.utc) - timedelta(minutes=num_points + offset_minutes)
    base_lat, base_lng = -23.6489, -46.8523
    step = 200 / 111_320  # ~200 m em graus de latitude
    return [
        {
            "lat": base_lat + i * step,
            "lng": base_lng + (offset_minutes * step / 10),
            "timestamp": (start + timedelta(seconds=60 * i)).isoformat(),
        }
        for i in range(num_points)
    ]


def _save_run(client, headers, **kwargs):
    run_id = str(uuid4())
    response = client.post("/runs", json={
        "id": run_id, "request_id": run_id, "track": _track(**kwargs), "conquer": False,
    }, headers=headers)
    assert response.status_code == 200, response.text
    return response


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def test_catalog_lists_all_categories(client):
    response = client.get("/shop/catalog")
    assert response.status_code == 200
    items = response.json()
    assert len(items) == len(CATALOG)
    categories = {i["category"] for i in items}
    assert {"avatar", "frame", "effect", "banner", "name_style", "emoticon"} <= categories


def test_everything_is_animated(client):
    for scope in (None, "user", "team"):
        params = {} if scope is None else {"scope": scope}
        items = client.get("/shop/catalog", params=params).json()
        assert items
        assert all(i["payload"].get("animated") is True for i in items)


def _look(item):
    """O que o app desenha do payload — dois itens com o mesmo `look` são o
    mesmo item repetido na vitrine, mesmo com id e nome diferentes."""
    payload = item["payload"]
    category = item["category"]
    if category == "avatar":
        return ("avatar", payload.get("generated"), payload.get("asset"),
                payload.get("seed"))
    if category == "effect":
        return ("effect", payload.get("kind"), payload.get("density"),
                payload.get("cycle_ms"))
    if category == "emoticon":
        return ("emoticon", tuple(sorted(payload.get("emoji") or ())))
    if category == "bundle":
        return ("bundle", tuple(sorted(payload.get("grants") or ())))
    return (category, tuple(payload.get("colors") or ()),
            bool(payload.get("glow")))


def test_no_two_items_look_the_same(client):
    """A loja se mostra uma categoria de cada vez, em um escopo só."""
    for scope in ("user", "team", "pass"):
        items = client.get("/shop/catalog", params={"scope": scope}).json()
        assert items
        seen = {}
        for item in items:
            key = (item["category"], _look(item))
            assert key not in seen, (
                f"{scope}/{key[0]}: {seen.get(key)!r} e {item['name']!r} "
                "desenham a mesma coisa"
            )
            seen[key] = item["name"]


def test_animation_tier_follows_the_price(client):
    """Quanto mais alto o tipo, mais animação: dentro da mesma categoria e
    escopo, o `tier` nunca diminui quando o preço sobe."""
    for scope in ("user", "team"):
        items = client.get("/shop/catalog", params={"scope": scope}).json()
        by_category: dict[str, list[dict]] = {}
        for item in items:
            by_category.setdefault(item["category"], []).append(item)
        for category, group in by_category.items():
            ordered = sorted(group, key=lambda i: (i["price"], i["id"]))
            tiers = [i["payload"].get("tier") for i in ordered]
            assert tiers == sorted(tiers), f"{scope}/{category}: {tiers}"
            assert all(1 <= tier <= 4 for tier in tiers)
            if len(group) >= 4:
                assert set(tiers) == {1, 2, 3, 4}, f"{scope}/{category}: {set(tiers)}"


def test_run_credits_coins(client, registered_user, db_session):
    run_id = str(uuid4())
    response = client.post("/runs", json={
        "id": run_id, "request_id": run_id, "track": _track(), "conquer": False,
    }, headers=_auth(registered_user))
    assert response.status_code == 200, response.text
    earned = response.json()["coins_earned"]
    assert earned > 0  # distância + primeira do dia + streak
    wallet = client.get("/shop/wallet", headers=_auth(registered_user)).json()
    assert wallet["balance"] == earned
    assert wallet["transactions"], "extrato não pode estar vazio"
    me = client.get("/users/me", headers=_auth(registered_user)).json()
    assert me["coins_balance"] == earned


def test_wallet_carries_the_earning_rates(client, registered_user):
    """A folha "como ganhar" do app lê as taxas daqui.

    Taxa repetida no app é taxa que diverge quando o serviço muda, então o
    payload devolve exatamente as constantes que creditam a corrida.
    """
    wallet = client.get("/shop/wallet", headers=_auth(registered_user)).json()
    assert wallet["rates"] == {
        "per_km": coins.COINS_PER_KM,
        "conquest": coins.CONQUEST_BONUS,
        "daily_first_run": coins.DAILY_FIRST_RUN_BONUS,
        "streak_per_day": coins.STREAK_PER_DAY,
        "streak_cap": coins.STREAK_BONUS_CAP,
    }
    assert all(value > 0 for value in wallet["rates"].values())


def test_purchase_and_equip_flow(client, registered_user, db_session):
    headers = _auth(registered_user)
    # Dá saldo: salva uma corrida longa (mais km = mais moedas).
    run_id = str(uuid4())
    assert client.post("/runs", json={
        "id": run_id, "request_id": run_id, "track": _track(), "conquer": False,
    }, headers=headers).status_code == 200
    balance = client.get("/shop/wallet", headers=headers).json()["balance"]
    assert balance >= 100

    # Compra a moldura bronze.
    bought = client.post("/shop/purchase", json={"item_id": "frame_bronze"}, headers=headers)
    assert bought.status_code == 200, bought.text
    assert "frame_bronze" in bought.json()["owned"]
    after = client.get("/shop/wallet", headers=headers).json()["balance"]
    assert after == balance - get_item("frame_bronze")["price"]

    # Recompra dá 409.
    assert client.post("/shop/purchase", json={"item_id": "frame_bronze"}, headers=headers).status_code == 409
    # Item inexistente dá 404.
    assert client.post("/shop/purchase", json={"item_id": "nao_existe"}, headers=headers).status_code == 404

    # Equipa e aparece no perfil público.
    equipped = client.post(
        "/shop/equip", json={"category": "frame", "item_id": "frame_bronze"}, headers=headers,
    )
    assert equipped.status_code == 200
    assert equipped.json()["equipped_frame"] == "frame_bronze"
    me = client.get("/users/me", headers=headers).json()
    assert me["equipped_frame"] == "frame_bronze"

    # Equipar sem possuir dá 403.
    forbidden = client.post(
        "/shop/equip", json={"category": "frame", "item_id": "frame_ouro"}, headers=headers,
    )
    assert forbidden.status_code == 403

    # Desequipar limpa.
    cleared = client.post("/shop/equip", json={"category": "frame", "item_id": None}, headers=headers)
    assert cleared.json()["equipped_frame"] is None


def test_bundle_purchase_grants_all_items(client, registered_user):
    headers = _auth(registered_user)
    _save_run(client, headers, num_points=85)
    _save_run(client, headers, num_points=85, offset_minutes=90)
    balance = client.get("/shop/wallet", headers=headers).json()["balance"]
    assert balance >= 350, balance

    bought = client.post("/shop/purchase", json={"item_id": "pacote_iniciante"}, headers=headers)
    assert bought.status_code == 200, bought.text
    owned = bought.json()["owned"]
    assert {"pacote_iniciante", "avatar_coroa", "frame_bronze", "banner_oceano"} <= set(owned)

    # Comprou tudo do pacote: recomprar dá 409.
    again = client.post("/shop/purchase", json={"item_id": "pacote_iniciante"}, headers=headers)
    assert again.status_code == 409

    # Dá para equipar um item vindo do pacote sem comprar separado.
    equipped = client.post(
        "/shop/equip", json={"category": "frame", "item_id": "frame_bronze"}, headers=headers,
    )
    assert equipped.status_code == 200
    assert equipped.json()["equipped_frame"] == "frame_bronze"


def test_catalog_has_partner_collection(client):
    items = client.get("/shop/catalog").json()
    partners = [i for i in items if i["payload"].get("collection") == "parceria"]
    assert len(partners) >= 3
    bundles = [i for i in items if i["category"] == "bundle"]
    assert len(bundles) >= 2


def test_mural_widgets_update_and_validation(client, registered_user):
    headers = _auth(registered_user)
    default = client.get("/users/me", headers=headers).json()["mural_widgets"]
    assert default == ["emoticons", "conquistas", "atividades", "estatisticas"]

    updated = client.patch(
        "/users/me", json={"mural_widgets": ["atividades", "cosmeticos"]}, headers=headers,
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["mural_widgets"] == ["atividades", "cosmeticos"]

    invalid = client.patch("/users/me", json={"mural_widgets": ["naves"]}, headers=headers)
    assert invalid.status_code == 400


def test_emoticons_equip_on_profile(client, registered_user, db_session):
    headers = _auth(registered_user)
    run_id = str(uuid4())
    assert client.post("/runs", json={
        "id": run_id, "request_id": run_id, "track": _track(), "conquer": False,
    }, headers=headers).status_code == 200
    assert client.post("/shop/purchase", json={"item_id": "emoticon_troféu"}, headers=headers).status_code == 200
    equipped = client.post(
        "/shop/equip", json={"category": "emoticon", "item_id": "emoticon_troféu"}, headers=headers,
    )
    assert equipped.status_code == 200
    assert "🏆" in equipped.json()["equipped_emoticons"]
    me = client.get("/users/me", headers=headers).json()
    assert "🏆" in me["equipped_emoticons"]
    assert db_session.query(UserItem).count() >= 1
    assert db_session.query(CoinTransaction).count() >= 2
