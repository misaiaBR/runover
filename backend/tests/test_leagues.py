"""Ligas: escada, status de posição e movimentação de troféus (RR)."""

from app.models import User
from app.services.leagues import (
    LADDER,
    apply_trophies,
    badge_for,
    conquest_reward,
    defeat_penalty,
    league_changed,
    loss_penalty,
    status_for,
)


def _register(client, username, email):
    response = client.post("/auth/register", json={
        "full_name": f"{username} Name", "username": username, "email": email,
        "password": "secret123", "accept_terms": True,
    })
    assert response.status_code == 201, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_ladder_has_seven_leagues_three_divisions_plus_lenda():
    assert [league["key"] for league in LADDER] == [
        "largada", "trote", "ritmo", "podio", "turbo", "elite", "mestre", "lenda",
    ]
    for league in LADDER[:-1]:
        assert [tier["division"] for tier in league["tiers"]] == [1, 2, 3]
    assert LADDER[-1]["tiers"][0]["division"] is None


def test_status_floor_is_largada_division_1():
    status = status_for(0)
    assert status["league"] == "largada"
    assert status["division"] == 1
    assert status["rr"] == 0
    assert status["rr_to_next"] == 100
    assert status["next"]["league"] == "largada"
    assert status["next"]["division"] == 2


def test_status_crosses_league_boundary_at_300():
    status = status_for(300)
    assert status["league"] == "trote"
    assert status["division"] == 1
    assert status["rr"] == 0


def test_status_lenda_has_no_next():
    status = status_for(2100)
    assert status["league"] == "lenda"
    assert status["division"] is None
    assert status["rr_to_next"] is None
    assert status["next"] is None


def test_rewards_and_penalties_stay_in_the_season_band():
    assert conquest_reward(0, 1) == 12
    assert conquest_reward(5_000, 2) == 19
    assert conquest_reward(20_000, 5) == 40
    assert conquest_reward(40_000, 5) == 50  # teto de vitória
    assert defeat_penalty(0) == 10
    assert defeat_penalty(25_000) == 30  # teto de derrota
    assert loss_penalty(1) == 12
    assert loss_penalty(50) == 30  # teto de perda


def test_apply_never_goes_below_zero(db_session, registered_user, client):
    user = db_session.query(User).filter(User.email == registered_user["email"]).one()
    move = apply_trophies(db_session, user, -50, "perda")
    assert move["delta"] == 0  # piso em 0: nada efetivo, saldo segue 0
    assert user.trophies == 0


def test_apply_accumulates_and_reports_league_change(db_session, registered_user, client):
    user = db_session.query(User).filter(User.email == registered_user["email"]).one()
    move = apply_trophies(db_session, user, 120, "conquista")
    assert move["delta"] == 120
    assert user.trophies == 120
    assert move["after"]["league"] == "largada"
    assert move["after"]["division"] == 2
    changed, message = league_changed(move)
    assert changed
    assert message == "Você subiu para Largada 2!"


def test_league_changed_is_quiet_within_the_same_division(db_session, registered_user, client):
    user = db_session.query(User).filter(User.email == registered_user["email"]).one()
    apply_trophies(db_session, user, 120, "conquista")
    move = apply_trophies(db_session, user, 10, "conquista")
    changed, _ = league_changed(move)
    assert not changed
    assert move["after"]["division"] == 2  # 130 RR ainda é Largada 2


def test_leagues_endpoint_returns_me_and_ladder(client, registered_user):
    headers = {"Authorization": f"Bearer {registered_user['token']}"}
    response = client.get("/leagues", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["me"]["trophies"] == 0
    assert body["me"]["league"] == "largada"
    assert len(body["ladder"]) == 8
    lenda = body["ladder"][-1]
    assert lenda["key"] == "lenda"
    assert lenda["tiers"][0]["at"] == 2100


def test_badge_for_exposes_only_the_emblem():
    assert badge_for(0) == {
        "league": "largada", "name": "Largada", "color": "#8A94A6",
        "shape": "circle", "division": 1,
    }
    turbo = badge_for(1300)
    assert (turbo["league"], turbo["division"]) == ("turbo", 2)
    lenda = badge_for(2400)
    assert lenda["division"] is None and lenda["shape"] == "star"
    # O rival vê a liga, nunca o saldo: sem RR e sem próximo degrau.
    assert "trophies" not in turbo and "rr" not in turbo and "next" not in turbo


def test_public_profile_and_ranking_carry_the_same_badge(client, db_session):
    rival = _register(client, "rival_liga", "rival_liga@example.com")
    viewer = _register(client, "veja_liga", "veja_liga@example.com")
    user = db_session.query(User).filter(User.username == "rival_liga").one()
    user.trophies = 1300  # Turbo 2
    db_session.commit()

    public = client.get("/users/rival_liga", headers=viewer).json()
    assert public["league"] == badge_for(1300)
    # O próprio perfil lê a mesma liga que o /leagues dele.
    mine = client.get("/leagues", headers=rival).json()["me"]
    assert (mine["league"], mine["division"]) == (
        public["league"]["league"], public["league"]["division"],
    )

    team = client.post("/teams", json={"name": "Time Escada"}, headers=rival)
    assert team.status_code == 201
    ranking = {row["name"]: row for row in client.get("/ranking", headers=viewer).json()}
    assert ranking["rival_liga"]["league"] == badge_for(1300)
    # Equipe não disputa a escada: fica sem emblema.
    assert ranking["Time Escada"]["owner_type"] == "team"
    assert ranking["Time Escada"]["league"] is None
