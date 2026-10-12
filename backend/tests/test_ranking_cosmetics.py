"""Ranking reflete os cosméticos da loja (foto, nome e cards)."""
from auth_helpers import auth_headers


def _register(client, username, email):
    return auth_headers(client, username=username, email=email,
                        full_name=f"{username} Name", password="secret123")


def test_ranking_carries_shop_cosmetics(client, db_session):
    from app.models import ScoreEvent, UserItem

    owner = _register(client, "dono_rank", "dono_rank@example.com")
    member = _register(client, "membro_rank", "membro_rank@example.com")
    team_id = client.post("/teams", json={"name": "Time Vitrine"}, headers=owner).json()["id"]
    assert client.post(f"/teams/{team_id}/join", headers=member).status_code == 202
    requests = client.get(f"/teams/{team_id}/requests", headers=owner).json()
    assert client.post(
        f"/teams/{team_id}/requests/{requests[0]['id']}/approve", headers=owner
    ).status_code == 200

    owner_id = client.get("/users/me", headers=owner).json()["id"]
    member_id = client.get("/users/me", headers=member).json()["id"]
    db_session.add_all([
        ScoreEvent(user_id=owner_id, delta=3000, reason="conquista"),
        ScoreEvent(user_id=member_id, delta=3000, reason="conquista"),
        UserItem(user_id=owner_id, item_id="frame_bronze"),
    ])
    db_session.commit()
    assert client.post(
        "/shop/equip", json={"category": "frame", "item_id": "frame_bronze"}, headers=owner
    ).status_code == 200
    assert client.post(
        f"/teams/{team_id}/purchase", json={"item_id": "team_frame_ferro"}, headers=owner
    ).status_code == 200
    assert client.post(
        f"/teams/{team_id}/equip",
        json={"category": "frame", "item_id": "team_frame_ferro"},
        headers=owner,
    ).status_code == 200

    ranking = client.get("/ranking", headers=owner).json()
    by_name = {row["name"]: row for row in ranking}
    assert by_name["dono_rank"]["equipped_frame"] == "frame_bronze"
    team_row = by_name["Time Vitrine"]
    assert team_row["owner_type"] == "team"
    assert team_row["equipped_frame"] == "team_frame_ferro"

    # Lista de equipes também carrega os cosméticos dos cards.
    teams = client.get("/teams", headers=owner).json()
    mine = [t for t in teams if t["id"] == team_id][0]
    assert mine["equipped_frame"] == "team_frame_ferro"
