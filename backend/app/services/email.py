import logging
import smtplib
import ssl
from email.message import EmailMessage
from html import escape

from app.core.config import settings

logger = logging.getLogger(__name__)


class EmailDeliveryError(RuntimeError):
    pass


def send_password_reset_email(email: str, username: str, code: str) -> None:
    """Send a reset code over SMTP (Gmail, Mailpit local ou Mailtrap).

    Porta 465 usa SSL direto; qualquer outra, STARTTLS quando
    `SMTP_STARTTLS` estiver ligado. Sem host, usuário ou remetente
    configurados, recusa de cara em vez de fingir que enviou.
    """
    host = (settings.smtp_host or "").strip()
    if not host or not settings.smtp_username or not settings.mail_from_email:
        raise EmailDeliveryError("Email delivery is not configured.")

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
                if settings.smtp_starttls:
                    smtp.starttls(context=ssl.create_default_context())
                if settings.smtp_username:
                    smtp.login(settings.smtp_username, settings.smtp_password)
                smtp.send_message(message)
    except (smtplib.SMTPException, OSError, ssl.SSLError) as exc:
        logger.warning("Password reset email delivery failed; check mail settings.")
        raise EmailDeliveryError("Could not deliver password reset email.") from exc
