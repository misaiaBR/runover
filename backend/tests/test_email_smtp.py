"""Envio de código de recuperação por SMTP (Gmail/Mailtrap), sem rede."""
import smtplib
import ssl

import pytest

from app.core.config import settings
from app.services.email import EmailDeliveryError, send_password_reset_email


class _FakeSMTP:
    instances = []

    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs
        self.started_tls = False
        self.logged_in = None
        self.sent = []
        _FakeSMTP.instances.append(self)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def starttls(self, context=None):
        self.started_tls = True

    def login(self, username, password):
        if username == "bad":
            raise smtplib.SMTPAuthenticationError(535, b"nope")
        self.logged_in = (username, password)

    def send_message(self, message):
        self.sent.append(message)


@pytest.fixture
def configured(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "smtp.gmail.com")
    monkeypatch.setattr(settings, "smtp_port", 465)
    monkeypatch.setattr(settings, "smtp_username", "runover@gmail.com")
    monkeypatch.setattr(settings, "smtp_password", "app-pass")
    monkeypatch.setattr(settings, "smtp_starttls", True)
    monkeypatch.setattr(settings, "mail_from_email", "runover@gmail.com")
    monkeypatch.setattr(settings, "mail_from_name", "RUNOVER!")
    _FakeSMTP.instances.clear()
    return settings


def test_missing_config_raises(monkeypatch):
    monkeypatch.setattr(settings, "smtp_host", "")
    with pytest.raises(EmailDeliveryError):
        send_password_reset_email("a@example.com", "ana", "123")


def test_ssl_port_uses_smtp_ssl_and_logs_in(monkeypatch, configured):
    monkeypatch.setattr(smtplib, "SMTP_SSL", _FakeSMTP)
    send_password_reset_email("a@example.com", "ana", "000111")

    (server,) = _FakeSMTP.instances
    assert server.args[0] == "smtp.gmail.com"
    assert server.logged_in == ("runover@gmail.com", "app-pass")
    (message,) = server.sent
    assert message["To"] == "a@example.com"
    assert "RUNOVER! <runover@gmail.com>" in message["From"]
    assert "000111" in message.as_string()


def test_starttls_port_upgrades_and_sends(monkeypatch, configured):
    monkeypatch.setattr(settings, "smtp_port", 587)
    monkeypatch.setattr(smtplib, "SMTP", _FakeSMTP)
    send_password_reset_email("a@example.com", "ana", "123")

    (server,) = _FakeSMTP.instances
    assert server.started_tls is True
    assert server.logged_in is not None
    assert len(server.sent) == 1


def test_auth_failure_raises_without_password(monkeypatch, configured):
    monkeypatch.setattr(settings, "smtp_username", "bad")
    monkeypatch.setattr(smtplib, "SMTP_SSL", _FakeSMTP)
    with pytest.raises(EmailDeliveryError) as exc:
        send_password_reset_email("a@example.com", "ana", "123")
    assert "app-pass" not in str(exc.value)


def test_ssl_error_raises(monkeypatch, configured, tmp_path):
    def explode(*args, **kwargs):
        raise ssl.SSLError("boom")

    monkeypatch.setattr(smtplib, "SMTP_SSL", explode)
    with pytest.raises(EmailDeliveryError):
        send_password_reset_email("a@example.com", "ana", "123")
