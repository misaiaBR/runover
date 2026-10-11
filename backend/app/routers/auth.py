import hashlib
import logging
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db, lock_mutations
from app.core.security import create_access_token, hash_password, verify_password
from app.models import AuthAttempt, OAuthIdentity, PasswordResetToken, User
from app.schemas import ForgotPasswordRequest, LoginRequest, OAuthLoginRequest, RegisterRequest, ResetPasswordRequest, TokenResponse
from app.services.oauth import create_unique_username, verify_identity
from app.services.usernames import username_taken
from app.services.email import EmailDeliveryError, send_password_reset_email

router = APIRouter(prefix="/auth", tags=["autenticação"])
logger = logging.getLogger(__name__)
_GENERIC_RESET = {"message": "Se esse e-mail estiver cadastrado, enviaremos um código de recuperação. Verifique também o spam."}


def _token_digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _deliver_password_reset(email: str, username: str, code: str) -> None:
    try:
        send_password_reset_email(email, username, code)
    except EmailDeliveryError:
        logger.warning("Password reset email delivery failed; check mail settings.")


def throttle(db, key, limit, minutes=15):
    now = datetime.utcnow()
    digest = hashlib.sha256(key.encode()).hexdigest()
    lock_mutations(db)
    db.query(AuthAttempt).filter(AuthAttempt.window_start < now - timedelta(days=1)).delete()
    row = db.get(AuthAttempt, digest)
    if row is None:
        row = AuthAttempt(key=digest, count=0, window_start=now)
        db.add(row)
    elif row.window_start <= now - timedelta(minutes=minutes):
        row.window_start, row.count = now, 0
    row.count += 1
    allowed = row.count <= limit
    db.commit()
    return allowed


def client_key(request):
    # Only use the trusted ASGI client, never arbitrary X-Forwarded-For headers.
    return request.client.host if request.client else "unknown"


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(data: RegisterRequest, request: Request, db: Session = Depends(get_db)):
    if not throttle(db, "register:" + client_key(request), 20):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    lock_mutations(db)
    if username_taken(db, data.username):
        raise HTTPException(400, "Esse nome de usuário já está em uso.")
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(400, "Já existe uma conta com esse e-mail.")
    user = User(full_name=data.full_name, username=data.username, email=data.email,
                password_hash=hash_password(data.password), photo_url=data.photo_url or None)
    db.add(user)
    db.commit()
    return TokenResponse(access_token=create_access_token(user.id, user.password_hash))


@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    request_client = client_key(request)
    if not throttle(db, "login-ip:" + request_client, 60) or not throttle(
        db, "login:" + data.email + ":" + request_client, 15
    ):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    user = db.query(User).filter(User.email == data.email).first()
    if len(data.password.encode()) > 72 or not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "E-mail ou senha incorretos.")
    if not user.is_active:
        raise HTTPException(403, "Esta conta está desativada. Reative-a para continuar.")
    return TokenResponse(access_token=create_access_token(user.id, user.password_hash))


@router.post("/reactivate", response_model=TokenResponse)
def reactivate(data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Reativa uma conta desativada temporariamente (volta tudo como estava)."""
    request_client = client_key(request)
    if not throttle(db, "reactivate-ip:" + request_client, 60) or not throttle(
        db, "reactivate:" + data.email + ":" + request_client, 15
    ):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    user = db.query(User).filter(User.email == data.email).first()
    if len(data.password.encode()) > 72 or not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "E-mail ou senha incorretos.")
    if user.is_active:
        raise HTTPException(400, "Esta conta já está ativa. Entre normalmente.")
    lock_mutations(db)
    user.is_active = True
    user.deactivated_at = None
    db.commit()
    return TokenResponse(access_token=create_access_token(user.id, user.password_hash))


@router.post("/oauth/{provider}", response_model=TokenResponse)
def oauth_login(
    provider: str,
    data: OAuthLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    if not throttle(db, "oauth:" + provider + ":" + client_key(request), 40):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    try:
        identity = verify_identity(provider, data.id_token)
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(401, str(exc)) from exc

    lock_mutations(db)
    linked = db.query(OAuthIdentity).filter_by(
        provider=provider, subject=identity["subject"]
    ).first()
    if linked:
        if not linked.user.is_active:
            raise HTTPException(403, "Esta conta está desativada. Reative-a para continuar.")
        return TokenResponse(
            access_token=create_access_token(linked.user_id, linked.user.password_hash)
        )

    if not identity.get("email"):
        db.rollback()
        raise HTTPException(
            401,
            "O provedor não retornou um e-mail verificado para criar a conta pela primeira vez.",
        )

    # Never auto-link by e-mail: linking an existing account needs proof of both credentials.
    if db.query(User).filter_by(email=identity["email"]).first():
        db.rollback()
        raise HTTPException(
            409,
            "Este e-mail já tem uma conta RUNOVER. Entre com ela para evitar vincular contas sem autorização.",
        )

    full_name = (identity.get("full_name") or identity["email"].split("@", 1)[0]).strip()
    if len(full_name) < 2:
        full_name = "Corredor RUNOVER"
    user = User(
        full_name=full_name[:120],
        username=create_unique_username(db, identity["email"]),
        email=identity["email"],
        password_hash=hash_password(secrets.token_urlsafe(40)),
        photo_url=identity.get("photo_url"),
    )
    db.add(user)
    db.flush()
    db.add(OAuthIdentity(user_id=user.id, provider=provider, subject=identity["subject"]))
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        linked = db.query(OAuthIdentity).filter_by(
            provider=provider, subject=identity["subject"]
        ).first()
        if linked:
            if not linked.user.is_active:
                raise HTTPException(403, "Esta conta está desativada. Reative-a para continuar.")
            return TokenResponse(
                access_token=create_access_token(linked.user_id, linked.user.password_hash)
            )
        raise HTTPException(409, "Não foi possível criar a conta social.") from exc
    return TokenResponse(access_token=create_access_token(user.id, user.password_hash))


@router.post("/oauth/{provider}/reactivate", response_model=TokenResponse)
def oauth_reactivate(provider: str, data: OAuthLoginRequest, request: Request, db: Session = Depends(get_db)):
    """Reativa conta desativada a partir da identidade social verificada.

    Nunca cria conta nem vincula e-mail: só reativa um vínculo existente.
    O token provado aqui é a mesma prova do login social.
    """
    request_client = client_key(request)
    if not throttle(db, "oauth-reactivate-ip:" + request_client, 60) or not throttle(
        db, "oauth-reactivate:" + provider + ":" + request_client, 15
    ):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    try:
        identity = verify_identity(provider, data.id_token)
    except RuntimeError as exc:
        raise HTTPException(503, str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(401, str(exc)) from exc

    lock_mutations(db)
    linked = db.query(OAuthIdentity).filter_by(
        provider=provider, subject=identity["subject"]
    ).first()
    if not linked:
        raise HTTPException(
            404,
            "Nenhuma conta vinculada a este login social. Entre com e-mail e senha.",
        )
    if linked.user.is_active:
        raise HTTPException(400, "Esta conta já está ativa. Entre normalmente.")
    linked.user.is_active = True
    linked.user.deactivated_at = None
    db.commit()
    return TokenResponse(
        access_token=create_access_token(linked.user_id, linked.user.password_hash)
    )


@router.post("/forgot-password")
def forgot_password(
    data: ForgotPasswordRequest,
    request: Request,
    tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    if not throttle(db, "reset-ip:" + client_key(request), 20):
        return _GENERIC_RESET
    if not throttle(db, "reset-mail:" + data.email, 3):
        return _GENERIC_RESET
    lock_mutations(db)
    user = db.query(User).filter(User.email == data.email).first()
    if not user:
        return _GENERIC_RESET

    now = datetime.now(timezone.utc)
    cooldown_start = now - timedelta(seconds=settings.password_reset_cooldown_seconds)
    recent = db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.created_at >= cooldown_start,
    ).first()
    if recent:
        return _GENERIC_RESET

    code = f"{secrets.randbelow(1_000_000_000_000):012d}"
    db.query(PasswordResetToken).filter(
        PasswordResetToken.user_id == user.id,
        PasswordResetToken.used_at.is_(None),
    ).delete(synchronize_session=False)
    db.add(PasswordResetToken(
        user_id=user.id,
        token_hash=_token_digest(code),
        expires_at=now + timedelta(minutes=settings.password_reset_expire_minutes),
    ))
    db.commit()
    tasks.add_task(_deliver_password_reset, user.email, user.username, code)
    return _GENERIC_RESET


@router.post("/reset-password")
def reset_password(data: ResetPasswordRequest, request: Request, db: Session = Depends(get_db)):
    if not throttle(db, "reset-use:" + client_key(request), 20):
        raise HTTPException(429, "Muitas tentativas. Aguarde 15 minutos.")
    lock_mutations(db)
    reset = db.query(PasswordResetToken).join(User).filter(
        User.email == data.email,
        PasswordResetToken.token_hash == _token_digest(data.reset_code),
        PasswordResetToken.used_at.is_(None),
    ).with_for_update().first()
    if not reset:
        active_reset = db.query(PasswordResetToken).join(User).filter(
            User.email == data.email,
            PasswordResetToken.used_at.is_(None),
        ).order_by(PasswordResetToken.created_at.desc()).with_for_update().first()
        if active_reset:
            active_reset.attempts += 1
            if active_reset.attempts >= 5:
                active_reset.used_at = datetime.now(timezone.utc)
            db.commit()
        raise HTTPException(400, "Token de redefinição inválido ou já utilizado.")

    expires_at = reset.expires_at
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    if expires_at <= datetime.now(timezone.utc):
        reset.used_at = datetime.now(timezone.utc)
        db.commit()
        raise HTTPException(400, "Código de redefinição expirado.")

    user = db.get(User, reset.user_id)
    if not user:
        raise HTTPException(400, "Token de redefinição inválido ou já utilizado.")

    user.password_hash = hash_password(data.new_password)
    reset.used_at = datetime.now(timezone.utc)
    db.commit()
    return {"message": "Senha redefinida. Entre novamente com a nova senha."}
