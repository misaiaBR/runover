"""Envio de código de recuperação via Brevo (sem rede: httpx mockado)."""
import httpx
import pytest

from app.core.config import settings
from app.services.email import EmailDeliveryError, send_password_reset_email


class _FakeResponse:
    def __init__(self, payload=None, error=None):
        self._payload = payload
        self._error = error

    def raise_for_status(self):
        if self._error is not None:
            raise self._error

    def json(self):
        if isinstance(self._payload, Exception):
            raise self._payload
        return self._payload


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(settings, "brevo_api_key", "xkeysib-test-key")
    monkeypatch.setattr(settings, "mail_from_email", "contato@example.com")
    monkeypatch.setattr(settings, "mail_from_name", "RUNOVER!")
    return settings


def test_missing_key_or_sender_raises(monkeypatch):
    monkeypatch.setattr(settings, "brevo_api_key", "")
    with pytest.raises(EmailDeliveryError):
        send_password_reset_email("a@example.com", "ana", "123")


def test_success_posts_api_key_and_payload(monkeypatch, configured):
    calls = {}

    def fake_post(url, headers=None, json=None, timeout=None):
        calls.update(url=url, headers=headers, json=json)
        return _FakeResponse({"messageId": "msg-123"})

    monkeypatch.setattr(httpx, "post", fake_post)
    send_password_reset_email("a@example.com", "ana", "000111")

    assert calls["url"] == "https://api.brevo.com/v3/smtp/email"
    assert calls["headers"]["api-key"] == "xkeysib-test-key"
    assert calls["json"]["to"] == [{"email": "a@example.com"}]
    assert calls["json"]["sender"] == {
        "name": "RUNOVER!",
        "email": "contato@example.com",
    }
    assert "000111" in calls["json"]["htmlContent"]


def test_http_error_raises_without_leaking_key(monkeypatch, configured):
    def fake_post(*args, **kwargs):
        return _FakeResponse(error=httpx.HTTPError("boom"))

    monkeypatch.setattr(httpx, "post", fake_post)
    with pytest.raises(EmailDeliveryError) as exc:
        send_password_reset_email("a@example.com", "ana", "123")
    assert "xkeysib-test-key" not in str(exc.value)


def test_missing_id_or_bad_json_raises(monkeypatch, configured):
    monkeypatch.setattr(
        httpx, "post", lambda *args, **kwargs: _FakeResponse({"nope": True})
    )
    with pytest.raises(EmailDeliveryError):
        send_password_reset_email("a@example.com", "ana", "123")

    monkeypatch.setattr(
        httpx, "post", lambda *args, **kwargs: _FakeResponse(ValueError("x"))
    )
    with pytest.raises(EmailDeliveryError):
        send_password_reset_email("a@example.com", "ana", "123")
