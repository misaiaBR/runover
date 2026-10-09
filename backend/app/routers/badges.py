"""Insígnias: o catálogo completo com o estado e a data de cada regra."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import User
from app.schemas import Badge
from app.services.badges import list_badges

router = APIRouter(prefix="/badges", tags=["insígnias"])


@router.get("", response_model=list[Badge])
def badges(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Consultar concede o que a regra já alcançou — não há botão de resgate."""
    return list_badges(db, current_user)
