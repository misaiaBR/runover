"""Ligas: a escada competitiva completa com a posição atual do jogador."""

from fastapi import APIRouter, Depends

from app.core.security import get_current_user
from app.models import User
from app.schemas import LeaguesResponse
from app.services.leagues import ladder_payload, status_for

router = APIRouter(prefix="/leagues", tags=["ligas"])


@router.get("", response_model=LeaguesResponse)
def leagues(current_user: User = Depends(get_current_user)):
    """Troféus e posição na escada; a escada vem do servidor para os
    números da temporada poderem mudar sem atualizar o app."""
    return {"me": status_for(current_user.trophies), "ladder": ladder_payload()}
