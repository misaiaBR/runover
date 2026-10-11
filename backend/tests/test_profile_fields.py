"""Campos do perfil sobrevivem ao roundtrip PATCH -> GET.

Regressão: o router passava pronouns/share_activities/
equipped_cosmetics ao UserProfile, mas o schema não os declarava e o
Pydantic os descartava em silêncio — parecia "não salvo".
"""


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def test_pronouns_roundtrip(client, registered_user):
    headers = _auth(registered_user)
    patched = client.patch(
        "/users/me", json={"pronouns": "ele/dele"}, headers=headers
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["pronouns"] == "ele/dele"
    assert client.get("/users/me", headers=headers).json()["pronouns"] == "ele/dele"

    cleared = client.patch("/users/me", json={"pronouns": ""}, headers=headers)
    assert cleared.json()["pronouns"] is None


def test_share_activities_roundtrip(client, registered_user):
    headers = _auth(registered_user)
    assert client.get("/users/me", headers=headers).json()["share_activities"] is True
    patched = client.patch(
        "/users/me", json={"share_activities": False}, headers=headers
    )
    assert patched.status_code == 200, patched.text
    assert patched.json()["share_activities"] is False
    assert client.get("/users/me", headers=headers).json()["share_activities"] is False


def test_profile_response_carries_all_private_fields(client, registered_user):
    body = client.get("/users/me", headers=_auth(registered_user)).json()
    for key in (
        "pronouns",
        "share_activities",
        "equipped_cosmetics",
        "coins_balance",
    ):
        assert key in body, f"resposta sem {key}"
