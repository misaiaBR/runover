from sqlalchemy.orm import Session

from app.models import Notification, User
from app.services.presence import delivers


def notify(db: Session, user_id: str, message: str, type_: str) -> None:
    """UC "Receber Notificação" — "Gera a notificação" / "Envia notificação ao usuário".

    O estado de presença de quem recebe decide se o recado entra: ver
    app/services/presence.py.
    """
    presence = db.query(User.presence).filter(User.id == user_id).scalar()
    if not delivers(type_, presence):
        return
    db.add(Notification(user_id=user_id, message=message, type=type_))
