"""Reativação via login social: só com vínculo existente e verificado."""

from app.models import OAuthIdentity, User
from auth_helpers import auth_headers


def _auth_headers(client, email="social@example.com"):
    return auth_headers(client, username="socialrunner", email=email,
                        full_name="Social Runner", password="secret123")


def _link(db_session, client, headers, subject="google-sub-123"):
    user_id = client.get("/users/me", headers=headers).json()["id"]
    db_session.add(OAuthIdentity(user_id=user_id, provider="google", subject=subject))
    db_session.commit()
    return user_id


def _fake_verify(monkeypatch, subject="google-sub-123"):
    monkeypatch.setattr(
        "app.routers.auth.verify_identity",
        lambda provider, token: {
            "subject": subject,
            "email": "social@example.com",
            "full_name": "Social Runner",
            "photo_url": None,
        },
    )


def test_oauth_login_blocked_until_reactivated(client, registered_user, db_session, monkeypatch):
    _fake_verify(monkeypatch)
    headers = _auth_headers(client)
    user_id = _link(db_session, client, headers)
    assert client.post("/users/me/deactivate", headers=headers).status_code == 204

    blocked = client.post("/auth/oauth/google", json={"id_token": "fake-token-0123456789"})
    assert blocked.status_code == 403

    revived = client.post("/auth/oauth/google/reactivate", json={"id_token": "fake-token-0123456789"})
    assert revived.status_code == 200, revived.text
    token = revived.json()["access_token"]
    me = client.get("/users/me", headers={"Authorization": f"Bearer {token}"}).json()
    assert me["id"] == user_id

    # Conta ativa: reativar de novo dá 400, login social volta a funcionar.
    assert client.post(
        "/auth/oauth/google/reactivate", json={"id_token": "fake-token-0123456789"}
    ).status_code == 400
    assert client.post("/auth/oauth/google", json={"id_token": "fake-token-0123456789"}).status_code == 200


def test_reactivate_unknown_subject_creates_nothing(client, db_session, monkeypatch):
    _fake_verify(monkeypatch, subject="nobody-sub")
    before = db_session.query(User).count()
    missing = client.post("/auth/oauth/google/reactivate", json={"id_token": "fake-token-0123456789"})
    assert missing.status_code == 404
    assert db_session.query(User).count() == before
    assert db_session.query(OAuthIdentity).count() == 0


def test_reactivate_invalid_token_is_401(client, monkeypatch):
    monkeypatch.setattr(
        "app.routers.auth.verify_identity",
        lambda provider, token: (_ for _ in ()).throw(ValueError("Token inválido.")),
    )
    assert client.post(
        "/auth/oauth/google/reactivate", json={"id_token": "fake-bad-token-0123456789"}
    ).status_code == 401
