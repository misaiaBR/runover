from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import LocationPing, User
from app.schemas import LocationPingRequest

router = APIRouter(prefix="/location", tags=["geolocalização"])


@router.post("", status_code=204)
def ping_location(
    data: LocationPingRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """RF14/RNF20 — registra a posição do usuário para auditoria e mapa em tempo real."""
    lock_mutations(db)
    db.add(LocationPing(user_id=current_user.id, latitude=data.lat, longitude=data.lng))
    db.commit()
