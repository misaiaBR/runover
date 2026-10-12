from html import escape

import httpx

from app.core.config import settings


class EmailDeliveryError(RuntimeError):
    pass


_BREVO_ENDPOINT = "https://api.brevo.com/v3/smtp/email"


def _send_code_email(email: str, username: str, code: str, *, subject: str, action: str, minutes: int, closing: str) -> None:
    """Entrega um código de dígitos por e-mail transacional (HTTPS).

    Funciona no plano gratuito do Render (só HTTPS sai; SMTP direto nas
    portas 25/465/587 é bloqueado). O remetente precisa estar verificado —
    vale endereço individual, sem domínio próprio.

    `action` é o que o código faz ("redefinir a senha", "confirmar o e-mail"),
    e o resto do texto é compartilhado: os dois fluxos são o mesmo problema —
    um número com validade curta que a pessoa digita no aplicativo.
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
        "subject": subject,
        "textContent": (
            f"Olá, {username}. Seu código para {action} é {code}. "
            f"Ele expira em {minutes} minutos. {closing}"
        ),
        "htmlContent": (
            f"<p>Olá, {escaped_name}.</p><p>Seu código para {action} é:</p>"
            f"<p style='font-size:24px;font-weight:bold'>{escaped_code}</p>"
            f"<p>Ele expira em {minutes} minutos. {closing}</p>"
            "<p>Se a mensagem não aparecer na caixa de entrada, procure em "
            "spam e promoções.</p>"
        ),
    }
    try:
        response = httpx.post(
            _BREVO_ENDPOINT,
            headers={"api-key": settings.brevo_api_key},
            json=payload,
            timeout=settings.api_timeout_seconds,
        )
        response.raise_for_status()
        data = response.json()
        if not data.get("messageId"):
            raise EmailDeliveryError("Brevo did not accept the email.")
    except (httpx.HTTPError, ValueError) as exc:
        raise EmailDeliveryError(f"Could not deliver {action} email.") from exc


def send_password_reset_email(email: str, username: str, code: str) -> None:
    _send_code_email(
        email,
        username,
        code,
        subject="Código para redefinir sua senha do RUNOVER!",
        action="redefinir a senha",
        minutes=settings.password_reset_expire_minutes,
        closing="Se você não solicitou a redefinição, ignore esta mensagem.",
    )


def send_email_verification_email(email: str, username: str, code: str) -> None:
    """Código que abre a porta do aplicativo pela primeira vez.

    Diferente do de recuperação, este aqui não tem segunda chance óbvia: sem
    ele o cadastro não entra. Por isso o texto avisa do spam e diz o que fazer
    se o endereço estiver errado.
    """
    _send_code_email(
        email,
        username,
        code,
        subject="Confirme seu e-mail para entrar no RUNOVER!",
        action="confirmar seu e-mail",
        minutes=settings.email_verification_expire_minutes,
        closing=(
            "Se este endereço não é seu, volte ao cadastro e corrija o e-mail "
            "antes de continuar."
        ),
    )
