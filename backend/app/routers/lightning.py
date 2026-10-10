"""Dominacao Relampago: partida curta da equipe.

So o dono ou admins abrem (15 ou 30 min); cada membro escolhe se participa
(opt-in). So contam os lacos fechados na janela por quem entrou. Sem cron:
o primeiro GET apos o fim finaliza de forma idempotente e paga o espolio
(metade dos pontos da janela de volta ao cofre).
"""
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import (
    LightningParticipant,
    LightningSession,
    ScoreEvent,
    Team,
    TeamAdmin,
    TeamMember,
    TerritoryOwnership,
    User,
)
from app.services.notifications import notify

router = APIRouter(tags=["relâmpago"])

LIGHTNING_DURATIONS = (15, 30)
BONUS_RATE = 0.5  # espólio imediato: metade dos pontos da janela ao cofre


class LightningOpen(BaseModel):
    duration_min: int


class LightningEntry(BaseModel):
    username: str
    takes: int
    points: int


class LightningBoard(BaseModel):
    id: str
    team_id: str
    team_name: str
    duration_min: int
    starts_at: datetime
    ends_at: datetime
    open: bool
    finalized: bool
    takes: int
    points: int
    bonus_points: int
    mvp: str | None
    participants: list[str]
    entries: list[LightningEntry]


class LightningSummary(BaseModel):
    id: str
    team_name: str
    duration_min: int
    starts_at: datetime
    ends_at: datetime
    open: bool
    finalized: bool
    takes: int
    points: int
    mvp: str | None


def _aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _get_team(db: Session, team_id: str) -> Team:
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    return team


def _membership(db: Session, team: Team, user_id: str) -> TeamMember:
    member = (
        db.query(TeamMember)
        .filter(TeamMember.team_id == team.id, TeamMember.user_id == user_id)
        .first()
    )
    if not member:
        raise HTTPException(403, "Só membros da equipe jogam o relâmpago.")
    return member


def _is_admin(db: Session, team: Team, user_id: str) -> bool:
    return team.creator_id == user_id or (
        db.query(TeamAdmin)
        .filter(TeamAdmin.team_id == team.id, TeamAdmin.user_id == user_id)
        .first()
        is not None
    )


def _open_session(db: Session, team_id: str) -> LightningSession | None:
    now = datetime.now(timezone.utc)
    return (
        db.query(LightningSession)
        .filter(
            LightningSession.team_id == team_id,
            LightningSession.ends_at > now,
        )
        .order_by(LightningSession.ends_at.desc())
        .first()
    )


def _stats(
    db: Session, session: LightningSession
) -> tuple[int, int, list[LightningEntry]]:
    participants = (
        db.query(User.username, User.id)
        .join(LightningParticipant, LightningParticipant.user_id == User.id)
        .filter(LightningParticipant.session_id == session.id)
        .order_by(LightningParticipant.joined_at, User.username)
        .all()
    )
    ids = [user_id for _, user_id in participants]
    takes = 0
    points = 0
    entries = []
    if ids:
        rows = (
            db.query(TerritoryOwnership)
            .filter(
                TerritoryOwnership.conquered_at >= _aware(session.starts_at),
                TerritoryOwnership.conquered_at <= _aware(session.ends_at),
                TerritoryOwnership.runner_user_id.in_(ids),
            )
            .all()
        )
        by_runner: dict[str, list] = {}
        for row in rows:
            by_runner.setdefault(row.runner_user_id, []).append(row)
        for username, user_id in participants:
            owned = by_runner.get(user_id, [])
            entry = LightningEntry(
                username=username,
                takes=len(owned),
                points=sum(o.points for o in owned),
            )
            entries.append(entry)
            takes += entry.takes
            points += entry.points
        entries.sort(key=lambda e: (-e.points, e.username))
    return takes, points, entries


def _finalize(
    db: Session, session: LightningSession, takes: int, points: int
) -> None:
    """Paga o espólio uma única vez, no primeiro GET após o fim."""
    if session.finalized:
        return
    lock_mutations(db)
    db.refresh(session)
    if session.finalized:
        return
    bonus = round(points * BONUS_RATE)
    if bonus > 0:
        db.add(
            ScoreEvent(
                team_id=session.team_id, delta=bonus, reason="relâmpago"
            )
        )
    session.finalized = True
    session.bonus_points = bonus
    db.commit()


def _board(db: Session, session: LightningSession) -> LightningBoard:
    now = datetime.now(timezone.utc)
    takes, points, entries = _stats(db, session)
    if not session.finalized and _aware(session.ends_at) <= now:
        _finalize(db, session, takes, points)
        takes, points, entries = _stats(db, session)
    team = db.get(Team, session.team_id)
    return LightningBoard(
        id=session.id,
        team_id=session.team_id,
        team_name=team.name if team else "",
        duration_min=session.duration_min,
        starts_at=_aware(session.starts_at),
        ends_at=_aware(session.ends_at),
        open=_aware(session.ends_at) > now and not session.finalized,
        finalized=session.finalized,
        takes=takes,
        points=points,
        bonus_points=session.bonus_points,
        mvp=entries[0].username if entries and entries[0].points > 0 else None,
        participants=[e.username for e in entries],
        entries=entries,
    )


@router.post("/teams/{team_id}/lightning", response_model=LightningBoard)
def open_lightning(
    team_id: str,
    data: LightningOpen,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Só dono ou admins abrem o relâmpago (15 ou 30 min)."""
    if data.duration_min not in LIGHTNING_DURATIONS:
        raise HTTPException(400, "Duração inválida: 15 ou 30 minutos.")
    lock_mutations(db)
    team = _get_team(db, team_id)
    _membership(db, team, current_user.id)
    if not _is_admin(db, team, current_user.id):
        raise HTTPException(403, "Só o dono ou admins abrem o relâmpago.")
    if _open_session(db, team.id):
        raise HTTPException(409, "Já existe um relâmpago aberto.")
    now = datetime.now(timezone.utc)
    minutes = data.duration_min
    session = LightningSession(
        team_id=team.id,
        created_by=current_user.id,
        duration_min=minutes,
        starts_at=now,
        ends_at=now + timedelta(minutes=minutes),
    )
    db.add(session)
    db.flush()
    db.add(
        LightningParticipant(session_id=session.id, user_id=current_user.id)
    )
    for member in (
        db.query(TeamMember).filter(TeamMember.team_id == team.id).all()
    ):
        if member.user_id != current_user.id:
            notify(
                db,
                member.user_id,
                f"Relâmpago aberto na {team.name}! Toque em Participar.",
                "equipe",
            )
    db.commit()
    db.refresh(session)
    return _board(db, session)


@router.post("/lightning/{session_id}/join", response_model=LightningBoard)
def join_lightning(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Opt-in: o membro escolhe participar. Quem não entra, não pontua."""
    lock_mutations(db)
    session = db.get(LightningSession, session_id)
    if not session:
        raise HTTPException(404, "Relâmpago não encontrado.")
    team = _get_team(db, session.team_id)
    _membership(db, team, current_user.id)
    now = datetime.now(timezone.utc)
    if _aware(session.ends_at) <= now:
        raise HTTPException(400, "Este relâmpago já terminou.")
    exists = (
        db.query(LightningParticipant)
        .filter(
            LightningParticipant.session_id == session.id,
            LightningParticipant.user_id == current_user.id,
        )
        .first()
    )
    if not exists:
        db.add(
            LightningParticipant(
                session_id=session.id, user_id=current_user.id
            )
        )
        db.commit()
        db.refresh(session)
    return _board(db, session)


@router.get("/lightning/{session_id}", response_model=LightningBoard)
def get_lightning(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    session = db.get(LightningSession, session_id)
    if not session:
        raise HTTPException(404, "Relâmpago não encontrado.")
    _membership(db, _get_team(db, session.team_id), current_user.id)
    return _board(db, session)


@router.get("/teams/{team_id}/lightning", response_model=list[LightningSummary])
def list_lightning(
    team_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Histórico do mais novo para o mais antigo."""
    team = _get_team(db, team_id)
    _membership(db, team, current_user.id)
    out = []
    for session in (
        db.query(LightningSession)
        .filter(LightningSession.team_id == team.id)
        .order_by(LightningSession.starts_at.desc())
        .all()
    ):
        board = _board(db, session)
        out.append(
            LightningSummary(
                id=board.id,
                team_name=board.team_name,
                duration_min=board.duration_min,
                starts_at=board.starts_at,
                ends_at=board.ends_at,
                open=board.open,
                finalized=board.finalized,
                takes=board.takes,
                points=board.points,
                mvp=board.mvp,
            )
        )
    return out
