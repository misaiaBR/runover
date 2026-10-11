from html import escape

import httpx

from app.core.config import settings


class EmailDeliveryError(RuntimeError):
    pass


def send_password_reset_email(email: str, username: str, code: str) -> None:
    """Send a reset code via Brevo's transactional email API (HTTPS).

    Funciona no plano gratuito do Render (só HTTPS sai; SMTP direto nas
    portas 25/465/587 é bloqueado). O remetente precisa estar verificado
    na Brevo — vale endereço individual, sem domínio próprio.
    """
    if not settings.brevo_api_key or not settings.mail_from_email:
        raise EmailDeliveryError("Email delivery is not configured.")

    escaped_name = escape(username)
    escaped_code = escape(code)
    payload = {
        "sender": {
            "name": settings.mail_from_name,
            "email": settings.mail_from_email,
        },
        "to": [{"email": email}],
        "subject": "Código para redefinir sua senha do RUNOVER!",
        "textContent": (
            f"Olá, {username}. Seu código para redefinir a senha é {code}. "
            f"Ele expira em {settings.password_reset_expire_minutes} minutos. "
            "Se você não solicitou a redefinição, ignore esta mensagem."
        ),
        "htmlContent": (
            f"<p>Olá, {escaped_name}.</p><p>Seu código para redefinir a senha é:</p>"
            f"<p style='font-size:24px;font-weight:bold'>{escaped_code}</p>"
            f"<p>Ele expira em {settings.password_reset_expire_minutes} minutos. "
            "Se você não solicitou a redefinição, ignore esta mensagem.</p>"
        ),
    }
    try:
        response = httpx.post(
            "https://api.brevo.com/v3/smtp/email",
            headers={"api-key": settings.brevo_api_key},
            json=payload,
            timeout=settings.api_timeout_seconds,
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("messageId"):
            raise EmailDeliveryError("Brevo did not accept the email.")
    except (httpx.HTTPError, ValueError) as exc:
        raise EmailDeliveryError("Could not deliver password reset email.") from exc
