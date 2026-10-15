from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.models import CoinTransaction, UserItem
from app.services import coins
from app.services.shop import (
    CATALOG,
    EFFECT_KINDS,
    FRAME_STYLES,
    PLATE_STYLES,
    SCOPES,
    _VOCABULARIES,
    get_item,
)


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


def test_each_shop_lists_only_its_own_scope(client):
    """As três lojas são independentes, e juntas são o catálogo inteiro.

    O Mercado pede `scope=user`, a Loja da equipe `scope=team`, o Passe
    `scope=pass`. Item de outro escopo na lista é vitrine mentirosa: o toque
    chega no servidor e a compra recusa. E item que não aparece em escopo
    nenhum é item que não existe para ninguém.
    """
    ids_by_scope: dict[str, set[str]] = {}
    for scope in SCOPES:
        items = client.get("/shop/catalog", params={"scope": scope}).json()
        assert items, scope
        assert {item["scope"] for item in items} == {scope}
        ids_by_scope[scope] = {item["id"] for item in items}

    scopes = list(SCOPES)
    for index, left in enumerate(scopes):
        for right in scopes[index + 1:]:
            assert not (ids_by_scope[left] & ids_by_scope[right]), (left, right)
    assert set().union(*ids_by_scope.values()) == {item["id"] for item in CATALOG}


def test_catalog_rejects_an_unknown_scope(client):
    response = client.get("/shop/catalog", params={"scope": "equipe"})
    assert response.status_code == 400
    assert response.json()["detail"] == "Escopo inválido."


def test_everything_is_animated(client):
    for scope in (None, "user", "team"):
        params = {} if scope is None else {"scope": scope}
        items = client.get("/shop/catalog", params=params).json()
        assert items
        assert all(i["payload"].get("animated") is True for i in items)


# Chaves que não mudam o desenho: a política de "tudo animado", o degrau da
# escada de animação e a coleção da vitrine. O resto do payload é o que a loja
# mostra — e é isso que não pode se repetir.
_NOT_VISUAL = {"animated", "tier", "collection"}


def _look(item):
    """O que o app desenha do payload — dois itens com o mesmo `look` são o
    mesmo item repetido na vitrine, mesmo com id e nome diferentes."""
    return tuple(sorted(
        (key, str(value)) for key, value in item["payload"].items()
        if key not in _NOT_VISUAL
    ))


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


def test_every_visual_family_is_on_the_shelf(client):
    """O vocabulário inteiro chega à vitrine pessoal.

    Não basta o catálogo conhecer dezenove efeitos: se a loja só mostra faíscas
    e chamas, a variedade é da tabela e não da prateleira.
    """
    items = client.get("/shop/catalog", params={"scope": "user"}).json()
    kinds = {i["payload"]["kind"] for i in items if i["category"] == "effect"}
    assert kinds == set(EFFECT_KINDS)
    styles = {i["payload"].get("style") for i in items if i["category"] == "frame"}
    assert styles >= set(FRAME_STYLES)
    plates = {i["payload"].get("plate") for i in items if i["category"] == "banner"}
    assert plates >= set(PLATE_STYLES)


def test_no_item_announces_an_unknown_renderer(client):
    """Todo renderizador nomeado num payload existe na tabela do serviço.

    É a mesma checagem do boot, vista pela API: um `kind` ou `style` fora da
    lista seria um item que a loja anuncia e o app não sabe desenhar.
    """
    for item in client.get("/shop/catalog").json():
        for key, value in item["payload"].items():
            allowed = _VOCABULARIES.get((item["category"], key))
            if allowed is None or not isinstance(value, str):
                continue
            assert value in allowed, f"{item['id']}: {item['category']}.{key}={value!r}"


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


def _track_at(start, num_points=70):
    """O percurso de `_track`, mas começando em `start`.

    Dois envios no mesmo dia precisam de trilha diferente: `track_hash` é
    única na tabela.
    """
    base_lat, base_lng = -23.6489, -46.8523
    step = 200 / 111_320
    return [
        {
            "lat": base_lat + i * step,
            "lng": base_lng,
            "timestamp": (start + timedelta(seconds=60 * i)).isoformat(),
        }
        for i in range(num_points)
    ]


def _send_track(client, headers, track, utc_offset_minutes=0):
    run_id = str(uuid4())
    response = client.post("/runs", json={
        "id": run_id, "request_id": run_id, "track": track, "conquer": False,
        "utc_offset_minutes": utc_offset_minutes,
    }, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_day_bonus_does_not_follow_the_reported_offset(client, registered_user):
    """Trocar o fuso entre corridas não reabre os bônus de dia.

    O dia é o do aparelho, mas o aparelho é quem manda no pedido: sem a trava
    de 24 h do servidor, o segundo envio alegando outro fuso parece outra manhã
    e paga missão diária e sequência outra vez — o extrato vira uma torneira.
    """
    headers = _auth(registered_user)
    day = (datetime.now(timezone.utc) - timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    _send_track(client, headers, _track_at(day))
    # 12:00 UTC com o aparelho alegando UTC+14: outro dia local, outra "manhã".
    second = _send_track(
        client, headers,
        _track_at(day + timedelta(hours=12)),
        utc_offset_minutes=840,
    )
    assert second["coins_earned"] == int(
        second["distance_m"] / 1000 * coins.COINS_PER_KM
    )


def test_streak_and_daily_bonus_pay_once_per_day(client, registered_user, db_session):
    """Segunda corrida do mesmo dia só paga a distância.

    A sequência é um bônus por dia consecutivo e a missão diária é a primeira
    corrida do dia. Creditados a cada envio, quem corre duas vezes no dia recebia
    os dois de novo, e o extrato mostrava duas linhas "Sequência de dias" no
    mesmo dia.
    """
    headers = _auth(registered_user)
    my_id = client.get("/users/me", headers=headers).json()["id"]
    # Ontem, de madrugada: os dois envios caem no mesmo dia UTC e nenhum fica
    # no futuro nem fora da janela de 7 dias.
    day = (datetime.now(timezone.utc) - timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    first = _send_track(client, headers, _track_at(day))
    second = _send_track(client, headers, _track_at(day + timedelta(hours=2)))

    distance = int(first["distance_m"] / 1000 * coins.COINS_PER_KM)
    assert first["coins_earned"] == (
        distance + coins.DAILY_FIRST_RUN_BONUS + coins.STREAK_PER_DAY
    )
    assert second["coins_earned"] == int(
        second["distance_m"] / 1000 * coins.COINS_PER_KM
    )

    reasons = [
        row.reason
        for row in db_session.query(CoinTransaction)
        .filter_by(user_id=my_id)
        .order_by(CoinTransaction.created_at)
        .all()
    ]
    assert reasons.count("streak") == 1, reasons
    assert reasons.count("missao_diaria") == 1, reasons


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
