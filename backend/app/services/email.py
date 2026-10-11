import logging
import smtplib
import ssl
from email.message import EmailMessage
from html import escape

from app.core.config import settings

logger = logging.getLogger(__name__)

_LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


class EmailDeliveryError(RuntimeError):
    pass


def _is_local_host(host: str) -> bool:
    return host.strip().lower() in _LOCAL_HOSTS


def email_configured() -> bool:
    """Há remetente suficiente para tentar o envio (usado no aviso de boot)."""
    host = (settings.smtp_host or "").strip()
    if not host or not settings.mail_from_email:
        return False
    if _is_local_host(host):
        return True
    return bool(settings.smtp_username and settings.smtp_password)


def send_password_reset_email(email: str, username: str, code: str) -> None:
    """Send a reset code over SMTP (Gmail, Mailtrap ou Mailpit local).

    Porta 465 usa SSL direto; qualquer outra, STARTTLS quando
    `SMTP_STARTTLS` estiver ligado. Autenticação só acontece em conexão
    criptografada — sem TLS, recusa em vez de vazar a credencial — exceto
    para destino local confiável (Mailpit), que dispensa login. Sem
    configuração suficiente, recusa de cara em vez de fingir que enviou.
    """
    host = (settings.smtp_host or "").strip()
    if not email_configured():
        raise EmailDeliveryError("Email delivery is not configured.")
    local = _is_local_host(host)

    escaped_name = escape(username)
    escaped_code = escape(code)
    sender = settings.mail_from_email
    if settings.mail_from_name.strip():
        sender = f"{settings.mail_from_name.strip()} <{sender}>"
    message = EmailMessage()
    message["From"] = sender
    message["To"] = email
    message["Subject"] = "Código para redefinir sua senha do RUNOVER!"
    message.set_content(
        f"Olá, {username}. Seu código para redefinir a senha é {code}. "
        f"Ele expira em {settings.password_reset_expire_minutes} minutos. "
        "Se você não solicitou a redefinição, ignore esta mensagem."
    )
    message.add_alternative(
        f"<p>Olá, {escaped_name}.</p><p>Seu código para redefinir a senha é:</p>"
        f"<p style='font-size:24px;font-weight:bold'>{escaped_code}</p>"
        f"<p>Ele expira em {settings.password_reset_expire_minutes} minutos. "
        "Se você não solicitou a redefinição, ignore esta mensagem.</p>",
        subtype="html",
    )
    try:
        if settings.smtp_port == 465:
            context = ssl.create_default_context()
            with smtplib.SMTP_SSL(
                host, settings.smtp_port, timeout=settings.api_timeout_seconds,
                context=context,
            ) as smtp:
                smtp.login(settings.smtp_username, settings.smtp_password)
                smtp.send_message(message)
        else:
            with smtplib.SMTP(
                host, settings.smtp_port, timeout=settings.api_timeout_seconds
            ) as smtp:
                encrypted = False
                if settings.smtp_starttls and not local:
                    smtp.starttls(context=ssl.create_default_context())
                    encrypted = True
                if not encrypted and not local:
                    raise EmailDeliveryError(
                        "SMTP exige TLS para autenticar."
                    )
                if not local:
                    smtp.login(settings.smtp_username, settings.smtp_password)
                smtp.send_message(message)
    except (smtplib.SMTPException, OSError, ssl.SSLError) as exc:
        logger.warning("Password reset email delivery failed; check mail settings.")
        raise EmailDeliveryError("Could not deliver password reset email.") from exc
