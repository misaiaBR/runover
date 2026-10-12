from auth_helpers import auth_headers


def _auth(registered_user):
    return {"Authorization": f"Bearer {registered_user['token']}"}


def test_deactivate_blocks_login_and_reactivate_restores(client, registered_user):
    headers = _auth(registered_user)

    assert client.post("/users/me/deactivate", headers=headers).status_code == 204

    # Sessão antiga passa a ser recusada.
    assert client.get("/users/me", headers=headers).status_code == 403

    # Login direto é bloqueado com 403.
    login = client.post("/auth/login", json={
        "email": registered_user["email"], "password": "original123",
    })
    assert login.status_code == 403

    # Reativação com senha errada não passa.
    bad = client.post("/auth/reactivate", json={
        "email": registered_user["email"], "password": "wrongpass1",
    })
    assert bad.status_code == 401

    # Reativação correta devolve sessão válida.
    reactivated = client.post("/auth/reactivate", json={
        "email": registered_user["email"], "password": "original123",
    })
    assert reactivated.status_code == 200, reactivated.text
    fresh = {"Authorization": f"Bearer {reactivated.json()['access_token']}"}
    assert client.get("/users/me", headers=fresh).status_code == 200

    # Conta ativa não pode "reativar".
    assert client.post("/auth/reactivate", json={
        "email": registered_user["email"], "password": "original123",
    }).status_code == 400


def test_deactivated_profile_hidden_from_others(client, registered_user, db_session):
    from app.models import User

    other_headers = auth_headers(
        client, username="otherperson", email="other@example.com",
        full_name="Other Person", password="otherpass123",
    )

    assert client.post("/users/me/deactivate", headers=_auth(registered_user)).status_code == 204
    assert client.get("/users/testrunner", headers=other_headers).status_code == 404

    db_user = db_session.query(User).filter_by(email=registered_user["email"]).one()
    assert db_user.is_active is False
