"""Quem pode ser desafiado, o que defende um território livre e em nome de quem
o ranking fala.

* posição no ranking é do corredor, não do nome que ele usa — usuário tem nome
  único, equipe não tem restrição em relação aos nomes de usuário;
* território seu ou da sua equipe não é alvo — bloqueava só pessoal→pessoal e
  equipe→equipe, então transferir a própria posse pagava a si mesmo a penalidade
  de perda e somava RR por cima da marca que o próprio corredor deixou;
* marca de dono só defende território com dono — liberada a posse, o recorde de
  quem saiu do jogo não pode ser exigência contra um "disponível";
* alvo declarado no mapa é o território desafiado — sem ele, fechar o laço na
  divisa de dois territórios desafiava o que a sobreposição escolhesse.
"""

import math
from datetime import timedelta

from app.geometry import polygon_to_geojson
from app.models import (
    ConquestMark,
    ScoreEvent,
    Territory,
    TerritoryOwnership,
    User,
)
from tests.auth_helpers import auth_headers
from tests.run_helpers import BASE, LAT, LNG, square_track, submit_run


def _square_geojson(step_m: float, *, at=(LAT, LNG)):
    """Anel do mesmo quadrado de `square_track`, como o território é guardado."""
    lat, lng = at
    d_lat = step_m / 111_320
    d_lng = step_m / (111_320 * math.cos(math.radians(lat)))
    return polygon_to_geojson([
        (lat, lng),
        (lat + d_lat, lng),
        (lat + d_lat, lng + d_lng),
        (lat, lng + d_lng),
    ])


def _territory(db_session, name, step_m, *, owner_id=None, team_id=None,
               mark=None, at=(LAT, LNG)):
    territory = Territory(
        name=name,
        geojson=_square_geojson(step_m, at=at),
        radius_m=step_m / 2,
        relevance=1,
        center_lat=at[0],
        center_lng=at[1],
    )
    db_session.add(territory)
    db_session.flush()
    if owner_id or team_id:
        db_session.add(TerritoryOwnership(
            territory_id=territory.id,
            owner_user_id=owner_id,
            owner_team_id=team_id,
            points=100,
        ))
    if mark is not None:
        db_session.add(ConquestMark(
            territory_id=territory.id,
            owner_user_id=owner_id,
            owner_team_id=team_id,
            pace_seconds_per_km=mark,
            distance_m=100,
            duration_seconds=100,
        ))
    db_session.commit()
    return territory


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


def test_own_territory_is_not_a_target_even_when_running_for_the_team(
    client, db_session
):
    """Conquistar para a equipe o que já é seu não é desafio, é transferência."""
    runner = auth_headers(client, username="corredor", email="corredor@example.com")
    first = submit_run(
        client, runner, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço pessoal",
    )
    territory_id = first["claim"]["territory"]["id"]
    team = client.post("/teams", json={"name": "Esquadrão"}, headers=runner)
    assert team.status_code == 201, team.text

    moved = submit_run(
        client, runner,
        track=square_track(120, walk_seconds=120, start=BASE + timedelta(days=1)),
        name="agora pela equipe", challenge="pace", team_id=team.json()["id"],
    )
    assert moved["claim"] is None, moved["claim"]
    assert "já é seu ou da sua equipe" in moved["claim_error"], moved["claim_error"]

    db_session.expire_all()
    owner = db_session.query(TerritoryOwnership).filter_by(
        territory_id=territory_id
    ).order_by(TerritoryOwnership.conquered_at.desc()).first()
    assert owner.owner_user_id == _user_id(db_session, "corredor")
    assert owner.owner_team_id is None


def test_team_territory_is_not_a_target_for_its_own_member(client, db_session):
    """Nem o membro toma o território do próprio clube com a conta pessoal."""
    runner = auth_headers(client, username="sócio", email="sociao@example.com")
    team = client.post("/teams", json={"name": "Clube"}, headers=runner)
    assert team.status_code == 201, team.text
    team_id = team.json()["id"]

    held = submit_run(
        client, runner, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço do clube", team_id=team_id,
    )
    assert held["claim"]["created_new"] is True
    assert held["claim"]["territory"]["owner_type"] == "team"

    personal = submit_run(
        client, runner,
        track=square_track(120, walk_seconds=120, start=BASE + timedelta(days=1)),
        name="laço pessoal", challenge="pace",
    )
    assert personal["claim"] is None, personal["claim"]
    assert "já é seu ou da sua equipe" in personal["claim_error"], personal["claim_error"]


def test_released_territory_is_taken_without_beating_a_ghost_record(
    client, db_session
):
    """Território livre não exige desafio contra marca de quem não existe mais."""
    victim = auth_headers(client, username="antigo", email="antigo@example.com")
    rival = auth_headers(client, username="novo", email="novo@example.com")
    conquered = submit_run(
        client, victim, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço de quem sai",
    )
    territory_id = conquered["claim"]["territory"]["id"]
    assert client.delete("/users/me", headers=victim).status_code == 204

    detail = client.get(f"/territories/{territory_id}", headers=rival).json()
    assert detail["status"] == "disponivel", detail
    assert detail["owner_pace_seconds_per_km"] is None, detail

    taken = submit_run(
        client, rival,
        track=square_track(120, walk_seconds=600, start=BASE + timedelta(days=1)),
        name="laço sem desafio",
    )
    claim = taken["claim"]
    assert claim is not None, taken["claim_error"]
    assert claim["created_new"] is False, claim
    assert claim["challenge_won"] is None, claim
    assert claim["territory"]["owner_display"] == "novo", claim


def test_declared_target_is_the_territory_challenged(client, db_session):
    """O alvo escolhido no mapa manda sobre o empate da sobreposição."""
    rival = auth_headers(client, username="desafiante", email="desaf@example.com")
    small = _territory(db_session, "Praça pequena", 120)
    big = _territory(db_session, "Quadra grande", 170)

    # Sem alvo declarado a sobreposição decide: o laço de 120 m cobre 100% da
    # praça e metade da quadra, então a praça seria o alvo automático.
    auto = submit_run(
        client, rival, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço sem alvo",
    )
    assert auto["claim"]["territory"]["id"] == small.id, auto["claim"]

    aimed = submit_run(
        client, rival,
        track=square_track(120, walk_seconds=120, start=BASE + timedelta(days=1)),
        name="laço mirado", target_territory_id=big.id,
    )
    assert aimed["claim"]["territory"]["id"] == big.id, aimed["claim"]


def test_declared_target_outside_the_loop_saves_the_run_without_the_claim(
    client, db_session
):
    """Alvo que o laço não cobre é erro de conquista, não perda da corrida."""
    rival = auth_headers(client, username="cegueira", email="cega@example.com")
    far = _territory(db_session, "Longe", 120, at=(LAT + 0.05, LNG))

    result = submit_run(
        client, rival, track=square_track(120, walk_seconds=180, start=BASE),
        name="laço errado", target_territory_id=far.id,
    )
    assert result["claim"] is None, result["claim"]
    assert "não fechou sobre o território desafiado" in result["claim_error"]
    assert result["distance_m"] > 0, result
