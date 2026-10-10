from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import User
from app.services.presence import now_utc

router = APIRouter(prefix="/presence", tags=["presença"])


@router.post("", status_code=204)
def heartbeat(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """App aberto: marca o corredor como visto agora, sem exigir GPS.

    É o sinal de presença de quem está no RUNOVER sem correr. A equipe soma
    batimento e ping de GPS para dizer quantos estão por aqui; o estado
    "invisivel" fica de fora dessa conta.
    """
    lock_mutations(db)
    current_user.last_seen_at = now_utc()
    db.commit()
