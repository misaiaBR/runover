"""Ajustes da equipe: modo de entrada, visibilidade, avisos e convite.

Cobre os campos novos de TeamDetail no roundtrip PATCH -> GET (mesma
lição da regressão `pronouns`: campo devolvido pelo router precisa estar
declarado no schema), o convite regenerável, os fluxos de entrada por
modo e o filtro da descoberta.
"""


from auth_helpers import create_verified_user


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _register(client, username, email):
    return create_verified_user(client, username=username, email=email,
                                full_name=username.title())


def _owner_and_team(client, registered_user, name="Time Ajustes"):
    headers = _auth(registered_user["token"])
    created = client.post("/teams", json={"name": name}, headers=headers)
    assert created.status_code == 201, created.text
    return headers, created.json()["id"]


def test_defaults_on_create(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    body = client.get(f"/teams/{team_id}", headers=headers).json()
    assert body["join_mode"] == "approval"
    assert body["listed"] is True
    assert body["notify_risk"] is True
    assert body["notify_requests"] is True
    assert body["invite_token"] is None


def test_patch_settings_roundtrip(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    patched = client.patch(f"/teams/{team_id}", json={
        "join_mode": "invite_only",
        "listed": False,
        "notify_risk": False,
        "notify_requests": False,
    }, headers=headers)
    assert patched.status_code == 200, patched.text
    for key, value in (
        ("join_mode", "invite_only"),
        ("listed", False),
        ("notify_risk", False),
        ("notify_requests", False),
    ):
        assert patched.json()[key] == value
    mine = client.get("/teams/mine", headers=headers).json()
    for key, value in (
        ("join_mode", "invite_only"),
        ("listed", False),
        ("notify_risk", False),
        ("notify_requests", False),
    ):
        assert mine[key] == value, f"resposta sem {key}"


def test_patch_requires_admin(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    outsider = _auth(_register(client, "visitante", "visitante@example.com"))
    response = client.patch(
        f"/teams/{team_id}", json={"listed": False}, headers=outsider,
    )
    assert response.status_code == 403, response.text
    assert client.get(f"/teams/{team_id}", headers=headers).json()["listed"] is True


def test_invalid_join_mode_is_rejected(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    response = client.patch(
        f"/teams/{team_id}", json={"join_mode": "porteira"}, headers=headers,
    )
    assert response.status_code == 400, response.text
    assert response.json()["detail"].endswith(".")


def test_regenerate_invite_rotates_token(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    first = client.post(f"/teams/{team_id}/invite/regenerate", headers=headers)
    assert first.status_code == 200, first.text
    assert first.json()["invite_token"]
    second = client.post(f"/teams/{team_id}/invite/regenerate", headers=headers)
    assert second.status_code == 200, second.text
    assert second.json()["invite_token"] != first.json()["invite_token"]


def test_regenerate_invite_requires_admin(client, registered_user):
    _, team_id = _owner_and_team(client, registered_user)
    outsider = _auth(_register(client, "visitante", "visitante@example.com"))
    response = client.post(f"/teams/{team_id}/invite/regenerate", headers=outsider)
    assert response.status_code == 403, response.text


def test_invite_token_hidden_from_non_admins(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    token = client.post(
        f"/teams/{team_id}/invite/regenerate", headers=headers,
    ).json()["invite_token"]
    assert token
    outsider = _auth(_register(client, "visitante", "visitante@example.com"))
    assert client.get(f"/teams/{team_id}", headers=outsider).json()["invite_token"] is None


def test_open_team_joins_directly(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    patched = client.patch(
        f"/teams/{team_id}", json={"join_mode": "open"}, headers=headers,
    )
    assert patched.status_code == 200, patched.text
    applicant = _auth(_register(client, "corredor", "corredor@example.com"))
    joined = client.post(f"/teams/{team_id}/join", headers=applicant)
    assert joined.status_code == 201, joined.text
    mine = client.get("/teams/mine", headers=applicant)
    assert mine.status_code == 200, mine.text
    assert mine.json()["id"] == team_id


def test_invite_only_rejects_direct_join(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    client.patch(f"/teams/{team_id}", json={"join_mode": "invite_only"}, headers=headers)
    applicant = _auth(_register(client, "corredor", "corredor@example.com"))
    response = client.post(f"/teams/{team_id}/join", headers=applicant)
    assert response.status_code == 403, response.text


def test_join_by_token_enters_any_mode(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    client.patch(f"/teams/{team_id}", json={"join_mode": "invite_only"}, headers=headers)
    token = client.post(
        f"/teams/{team_id}/invite/regenerate", headers=headers,
    ).json()["invite_token"]
    applicant = _auth(_register(client, "convidado", "convidado@example.com"))
    joined = client.post(f"/teams/join/{token}", headers=applicant)
    assert joined.status_code == 201, joined.text
    assert client.get("/teams/mine", headers=applicant).json()["id"] == team_id


def test_join_by_invalid_token_is_missing(client, registered_user):
    applicant = _auth(_register(client, "convidado", "convidado@example.com"))
    response = client.post("/teams/join/convite-que-nao-existe", headers=applicant)
    assert response.status_code == 404, response.text


def test_unlisted_team_hidden_from_discovery(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    client.patch(f"/teams/{team_id}", json={"listed": False}, headers=headers)
    outsider = _auth(_register(client, "visitante", "visitante@example.com"))
    discovered = client.get("/teams", headers=outsider).json()
    assert [t for t in discovered if t["id"] == team_id] == []
    own = client.get("/teams", headers=headers).json()
    assert [t for t in own if t["id"] == team_id] != []


def test_request_notification_follows_toggle(client, registered_user):
    headers, team_id = _owner_and_team(client, registered_user)
    client.patch(
        f"/teams/{team_id}", json={"notify_requests": False}, headers=headers,
    )
    applicant = _auth(_register(client, "corredor", "corredor@example.com"))
    assert client.post(f"/teams/{team_id}/join", headers=applicant).status_code == 202
    silent = client.get("/notifications", headers=headers).json()
    assert not [n for n in silent if "pediu para entrar" in n.get("message", "")]

    client.patch(
        f"/teams/{team_id}", json={"notify_requests": True}, headers=headers,
    )
    other = _auth(_register(client, "outro", "outro@example.com"))
    assert client.post(f"/teams/{team_id}/join", headers=other).status_code == 202
    noisy = client.get("/notifications", headers=headers).json()
    assert [n for n in noisy if "pediu para entrar" in n.get("message", "")]
