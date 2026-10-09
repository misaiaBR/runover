import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user, hash_password
from app.models import (
    ClaimReceipt,
    CoinTransaction,
    ConquestMark,
    LocationPing,
    Notification,
    OAuthIdentity,
    PasswordReset,
    PasswordResetToken,
    Run,
    ScoreEvent,
    Team,
    TeamAdmin,
    TeamJoinRequest,
    TeamMember,
    TerritoryOwnership,
    TeamItem,
    User,
    UserBadge,
    UserItem,
)
from app.schemas import HistoryEntry, ProfileUpdateRequest, UserProfile, UserPublic
from app.services.scoring import (
    current_owner_territory_ids,
    level_info,
    rank_position,
    total_score,
    user_team,
)
from app.routers.teams import transfer_ownership
from app.services.usernames import username_taken

router = APIRouter(tags=["usuários"])


def _emoticons_list(user: User) -> list[str]:
    return [e for e in (user.equipped_emoticons or "").split(",") if e]


def _mural_list(user: User) -> list[str]:
    from app.schemas import MURAL_WIDGETS

    raw = [w for w in (user.mural_widgets or "").split(",") if w]
    if not raw:
        return ["emoticons", "conquistas", "atividades", "estatisticas"]
    seen: list[str] = []
    for widget_id in raw:
        if widget_id in MURAL_WIDGETS and widget_id not in seen:
            seen.append(widget_id)
    return seen or ["emoticons", "conquistas", "atividades", "estatisticas"]


def _to_public(db: Session, user: User) -> UserPublic:
    team = user_team(db, user.id)
    score = total_score(db, user.id)
    level, progress, to_next = level_info(score)
    return UserPublic(
        username=user.username,
        photo_url=user.photo_url,
        total_score=score,
        territories_count=len(current_owner_territory_ids(db, user.id)),
        rank_position=rank_position(db, user.id),
        team_name=team.name if team else None,
        level=level,
        level_progress=progress,
        points_to_next_level=to_next,
        equipped_avatar=user.equipped_avatar,
        equipped_frame=user.equipped_frame,
        equipped_effect=user.equipped_effect,
        equipped_banner=user.equipped_banner,
        equipped_name_style=user.equipped_name_style,
        equipped_emoticons=_emoticons_list(user),
        mural_widgets=_mural_list(user),
        accent_color=user.accent_color,
    )


def _training_days_list(user: User) -> list[str]:
    return [d for d in (user.training_days or "").split(",") if d]


@router.get("/users/me", response_model=UserProfile)
def get_my_profile(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    public = _to_public(db, current_user)
    return UserProfile(
        **public.model_dump(),
        id=current_user.id,
        full_name=current_user.full_name,
        email=current_user.email,
        created_at=current_user.created_at,
        is_public=current_user.is_public,
        share_activities=current_user.share_activities,
        pronouns=current_user.pronouns,
        coin_balance=current_user.coin_balance,
        equipped_cosmetics=[
            item for item in (current_user.equipped_cosmetics or "").split(",") if item
        ],
        play_seconds=current_user.play_seconds,
        coins_balance=current_user.coins_balance or 0,
        distance_units=current_user.distance_units or "km",
        weekly_frequency=current_user.weekly_frequency,
        training_days=_training_days_list(current_user),
        activity_level=current_user.activity_level,
    )


@router.patch("/users/me", response_model=UserProfile)
def update_my_profile(
    data: ProfileUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if data.username and data.username != current_user.username:
        if username_taken(db, data.username, exclude_id=current_user.id):
            raise HTTPException(400, "Esse nome de usuário já está em uso.")
        current_user.username = data.username
    if data.full_name:
        current_user.full_name = data.full_name
    if "photo_url" in data.model_fields_set:
        current_user.photo_url = data.photo_url
    if data.password:
        current_user.password_hash = hash_password(data.password)
        db.query(PasswordReset).filter(PasswordReset.user_id == current_user.id).delete()
    if data.is_public is not None:
        current_user.is_public = data.is_public  # RF05 — configuração de privacidade
    if data.share_activities is not None:
        current_user.share_activities = data.share_activities
    if "pronouns" in data.model_fields_set:
        current_user.pronouns = data.pronouns.strip() if data.pronouns else None
    if "accent_color" in data.model_fields_set:
        current_user.accent_color = data.accent_color
    if data.distance_units is not None:
        current_user.distance_units = data.distance_units
    if "weekly_frequency" in data.model_fields_set:
        current_user.weekly_frequency = data.weekly_frequency
    if "training_days" in data.model_fields_set:
        current_user.training_days = ",".join(data.training_days or [])
    if "activity_level" in data.model_fields_set:
        current_user.activity_level = data.activity_level
    if data.mural_widgets is not None:
        from app.schemas import MURAL_WIDGETS

        unknown = [w for w in data.mural_widgets if w not in MURAL_WIDGETS]
        if unknown:
            raise HTTPException(400, f"Widgets de mural inválidos: {', '.join(unknown)}.")
        seen: list[str] = []
        for widget_id in data.mural_widgets:
            if widget_id not in seen:
                seen.append(widget_id)
        current_user.mural_widgets = ",".join(seen)

    db.commit()
    db.refresh(current_user)
    return get_my_profile(db, current_user)


@router.post("/users/me/deactivate", status_code=204)
def deactivate_my_account(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Desativação temporária: a conta some para os outros e o login é
    bloqueado, mas nada é apagado — reative em POST /auth/reactivate."""
    from datetime import datetime, timezone

    current_user.is_active = False
    current_user.deactivated_at = datetime.now(timezone.utc)
    db.commit()
    return None


@router.delete("/users/me", status_code=204)
def delete_my_account(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Exclusão de conta (LGPD): apaga dados pessoais e libera territórios.

    Territórios voltam a ficar livres (dono anulado, histórico preservado
    sem titular). Sair do time transfere o dono ao membro mais antigo, então
    quem já saiu não fica preso: times órfãos de regras antigas são
    transferidos na hora em vez de bloquear.
    """
    lock_mutations(db)
    uid = current_user.id
    member_of = db.query(TeamMember).filter(TeamMember.user_id == uid).all()
    created = db.query(Team).filter(Team.creator_id == uid).all()
    for team in created:
        if any(m.user_id == uid for m in team.members):
            others = [m for m in team.members if m.user_id != uid]
            if others:
                raise HTTPException(
                    409,
                    "Transfira ou dissolva sua equipe antes de excluir a conta.",
                )
        else:
            # Legado: criador já saiu do time. Transfere ao membro mais
            # antigo em vez de travar a exclusão para sempre.
            transfer_ownership(db, team)
    if any(m.team.creator_id != uid for m in member_of):
        raise HTTPException(
            409, "Saia da sua equipe antes de excluir a conta."
        )
    for team in created:
        if team.creator_id != uid:
            continue  # dono já transferido acima
        # Time só com o dono: dissolve junto com a conta.
        for member in list(team.members):
            db.delete(member)
        db.query(TeamItem).filter(TeamItem.team_id == team.id).delete(
            synchronize_session=False
        )
        db.query(TerritoryOwnership).filter(
            TerritoryOwnership.owner_team_id == team.id
        ).update({TerritoryOwnership.owner_team_id: None})
        db.query(ConquestMark).filter(
            ConquestMark.owner_team_id == team.id
        ).update({ConquestMark.owner_team_id: None})
        db.query(ScoreEvent).filter(ScoreEvent.team_id == team.id).update(
            {ScoreEvent.team_id: None}
        )
        db.delete(team)
    db.query(TerritoryOwnership).filter(
        TerritoryOwnership.owner_user_id == uid
    ).update({TerritoryOwnership.owner_user_id: None})
    db.query(ConquestMark).filter(
        ConquestMark.owner_user_id == uid
    ).update({ConquestMark.owner_user_id: None})
    for model in (
        Run,
        ClaimReceipt,
        CoinTransaction,
        UserItem,
        UserBadge,
        ScoreEvent,
        Notification,
        LocationPing,
        PasswordReset,
        PasswordResetToken,
        OAuthIdentity,
        TeamJoinRequest,
    ):
        db.query(model).filter(model.user_id == uid).delete(
            synchronize_session=False
        )
    db.delete(current_user)
    db.commit()
    return None


@router.get("/users/{username}", response_model=UserPublic)
def get_public_profile(
    username: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    user = db.query(User).filter(User.username == username).first()
    if not user or (not user.is_active and user.id != current_user.id):
        raise HTTPException(404, "Usuário não encontrado.")
    if not user.is_public and user.id != current_user.id:
        # RF05 / RN13 — perfil privado: só o próprio dono enxerga
        raise HTTPException(403, "Este perfil é privado.")
    return _to_public(db, user)  # RF17 — só dados públicos


@router.get("/users/me/history", response_model=list[HistoryEntry])
def get_my_history(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    events = (
        db.query(ScoreEvent)
        .filter(ScoreEvent.user_id == current_user.id)
        .order_by(ScoreEvent.created_at.desc())
        .all()
    )
    return [
        HistoryEntry(
            territory_name=e.territory.name if e.territory else None,
            delta=e.delta,
            reason=e.reason,
            created_at=e.created_at,
        )
        for e in events
    ]


def _iso(value) -> str | None:
    return value.isoformat() if value is not None else None


@router.get("/users/me/export")
def export_my_data(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Portabilidade LGPD: todos os dados pessoais em um JSON."""
    uid = current_user.id
    try:
        runs = [
            {
                "id": r.id,
                "name": r.name,
                "started_at": _iso(r.started_at),
                "ended_at": _iso(r.ended_at),
                "distance_m": r.distance_m,
                "duration_seconds": r.duration_seconds,
                "track": json.loads(r.track_json),
                "created_at": _iso(r.created_at),
            }
            for r in db.query(Run).filter(Run.user_id == uid).all()
        ]
    except ValueError:
        raise HTTPException(500, "Não foi possível montar a exportação.")
    return {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "account": {
            "full_name": current_user.full_name,
            "username": current_user.username,
            "email": current_user.email,
            "photo_url": current_user.photo_url,
            "is_public": current_user.is_public,
            "share_activities": current_user.share_activities,
            "pronouns": current_user.pronouns,
            "accent_color": current_user.accent_color,
            "coin_balance": current_user.coin_balance,
            "equipped_cosmetics": [
                item for item in (current_user.equipped_cosmetics or "").split(",") if item
            ],
            "play_seconds": current_user.play_seconds,
            "coins_balance": current_user.coins_balance or 0,
            "equipped_avatar": current_user.equipped_avatar,
            "equipped_frame": current_user.equipped_frame,
            "equipped_effect": current_user.equipped_effect,
            "equipped_banner": current_user.equipped_banner,
            "equipped_name_style": current_user.equipped_name_style,
            "equipped_emoticons": _emoticons_list(current_user),
            "mural_widgets": _mural_list(current_user),
            "distance_units": current_user.distance_units,
            "weekly_frequency": current_user.weekly_frequency,
            "training_days": _training_days_list(current_user),
            "activity_level": current_user.activity_level,
            "created_at": _iso(current_user.created_at),
        },
        "runs": runs,
        "score_events": [
            {
                "delta": e.delta,
                "reason": e.reason,
                "territory_id": e.territory_id,
                "created_at": _iso(e.created_at),
            }
            for e in db.query(ScoreEvent).filter(ScoreEvent.user_id == uid).all()
        ],
        "notifications": [
            {
                "message": n.message,
                "type": n.type,
                "is_read": n.is_read,
                "created_at": _iso(n.created_at),
            }
            for n in db.query(Notification).filter(Notification.user_id == uid).all()
        ],
        "location_pings": [
            {
                "latitude": p.latitude,
                "longitude": p.longitude,
                "recorded_at": _iso(p.recorded_at),
            }
            for p in db.query(LocationPing).filter(LocationPing.user_id == uid).all()
        ],
        "teams": [
            {"team_id": m.team_id, "joined_at": _iso(m.joined_at)}
            for m in db.query(TeamMember).filter(TeamMember.user_id == uid).all()
        ],
        "oauth_providers": [
            o.provider
            for o in db.query(OAuthIdentity).filter(OAuthIdentity.user_id == uid).all()
        ],
        "coin_transactions": [
            {
                "delta": t.delta,
                "reason": t.reason,
                "created_at": _iso(t.created_at),
            }
            for t in db.query(CoinTransaction)
            .filter(CoinTransaction.user_id == uid)
            .order_by(CoinTransaction.created_at.desc())
            .all()
        ],
        "owned_items": [
            i.item_id
            for i in db.query(UserItem).filter(UserItem.user_id == uid).all()
        ],
    }
