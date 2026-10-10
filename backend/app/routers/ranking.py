from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.security import get_current_user
from app.models import User
from app.schemas import RankingEntry
from app.services.leagues import badge_for
from app.services.scoring import full_ranking

router = APIRouter(tags=["ranking"])


@router.get("/ranking", response_model=list[RankingEntry])
def get_ranking(
    period: Literal["week", "month", "all"] = "all",
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if period == "week":
        since = (now - timedelta(days=now.weekday())).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
    elif period == "month":
        since = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    else:
        since = None
    return [
        RankingEntry(
            position=i,
            owner_type=row.owner_type,
            name=row.name,
            photo_url=row.photo_url,
            total_score=row.score,
            territories_count=row.territories,
            level=row.level,
            equipped_avatar=row.equipped_avatar,
            equipped_frame=row.equipped_frame,
            equipped_effect=row.equipped_effect,
            equipped_banner=row.equipped_banner,
            equipped_name_style=row.equipped_name_style,
            # Emblema da liga de quem corre; equipe não tem troféu, então não
            # tem liga — o app deixa o espaço vazio.
            league=badge_for(row.trophies) if row.owner_type == "user" else None,
        )
        for i, row in enumerate(full_ranking(db, since=since), start=1)
    ]  # RF12 / RN11 — jogadores e equipes juntos
