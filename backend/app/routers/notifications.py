from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import Notification, User
from app.schemas import NotificationEntry

router = APIRouter(prefix="/notifications", tags=["notificações"])


@router.get("", response_model=list[NotificationEntry])
def list_notifications(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    items = (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .all()
    )
    return [
        NotificationEntry(id=n.id, message=n.message, type=n.type, is_read=n.is_read, created_at=n.created_at)
        for n in items
    ]


@router.patch("/{notification_id}/read", response_model=NotificationEntry)
def mark_as_read(
    notification_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    n = db.get(Notification, notification_id)
    if not n or n.user_id != current_user.id:
        raise HTTPException(404, "Notificação não encontrada.")
    n.is_read = True  # UC "Marca notificação como lida"
    lock_mutations(db)
    db.commit()
    return NotificationEntry(id=n.id, message=n.message, type=n.type, is_read=n.is_read, created_at=n.created_at)
