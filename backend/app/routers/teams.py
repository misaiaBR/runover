import secrets
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.models import (
    ConquestMark,
    Run,
    ScoreEvent,
    Team,
    TeamAdmin,
    TeamItem,
    TeamJoinRequest,
    TeamMember,
    Territory,
    TerritoryOwnership,
    User,
)
from app.schemas import (
    JOIN_MODES,
    EquipRequest,
    HistoryEntry,
    PurchaseRequest,
    TeamAdminRequest,
    TeamCreateRequest,
    TeamDetail,
    TeamInventory,
    TeamInviteRequest,
    TeamInvitationEntry,
    TeamJoinRequestEntry,
    TeamLeaveRequest,
    TeamLevelStop,
    TeamMemberInfo,
    TeamSummary,
    TeamTerritoryEntry,
    TeamUpdateRequest,
    TeamWallet,
)
from app.services.notifications import notify
from app.services.presence import online_ids
from app.services.scoring import (
    current_ownerships,
    level_info,
    team_level_trail,
    team_zone_capacity,
    total_team_score,
    user_team,
)
from app.services.shop import EQUIPPABLE, get_item
from app.services.team_shop import team_balance

router = APIRouter(prefix="/teams", tags=["equipes"])


def _is_owner(team: Team, user_id: str) -> bool:
    return team.creator_id == user_id


def _is_admin(db: Session, team: Team, user_id: str) -> bool:
    return _is_owner(team, user_id) or db.query(TeamAdmin).filter(
        TeamAdmin.team_id == team.id, TeamAdmin.user_id == user_id
    ).first() is not None


def _admin_ids(db: Session, team: Team) -> list[str]:
    ids = [a.user_id for a in db.query(TeamAdmin).filter(TeamAdmin.team_id == team.id).all()]
    return [team.creator_id] + [i for i in ids if i != team.creator_id]


def transfer_ownership(db: Session, team: Team, exclude_user_id: str | None = None) -> str | None:
    """Passa o dono ao membro mais antigo (por entrada). Sem membros, None.

    O novo dono vira admin automaticamente via `_is_admin` (dono implica
    admin), sem precisar de linha extra em TeamAdmin.
    """
    candidates = sorted(
        (m for m in team.members if m.user_id != exclude_user_id),
        key=lambda m: (m.joined_at, m.user_id),
    )
    if not candidates:
        return None
    team.creator_id = candidates[0].user_id
    db.flush()
    return team.creator_id


def _dissolve_team(db: Session, team: Team) -> None:
    """Dissolve com a mesma limpeza do disband: libera territórios e apaga vínculos."""
    for member in list(team.members):
        db.delete(member)
    db.query(TeamAdmin).filter(TeamAdmin.team_id == team.id).delete(
        synchronize_session=False
    )
    db.query(TeamJoinRequest).filter(
        TeamJoinRequest.team_id == team.id
    ).delete(synchronize_session=False)
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
    db.query(Run).filter(Run.team_id == team.id).update(
        {Run.team_id: None}, synchronize_session=False
    )
    db.delete(team)


def _team_territories(db: Session, team_id: str) -> list[TeamTerritoryEntry]:
    """As zonas que a equipe tem hoje, da primeira conquista para a última.

    É a posse atual, não o histórico: quem perde o território no mapa perde a
    célula na base junto.
    """
    owned = [o for o in current_ownerships(db) if o.owner_team_id == team_id]
    if not owned:
        return []
    names = {
        t.id: t.name
        for t in db.query(Territory)
        .filter(Territory.id.in_([o.territory_id for o in owned]))
        .all()
    }
    return [
        TeamTerritoryEntry(
            name=names.get(o.territory_id, "Território"),
            points=o.points,
            conquered_at=o.conquered_at,
        )
        for o in sorted(owned, key=lambda o: (o.conquered_at, o.id))
    ]


def _to_detail(db: Session, team: Team, viewer_id: str | None = None) -> TeamDetail:
    members = db.query(TeamMember).filter(TeamMember.team_id == team.id).all()
    # Uma consulta de presença para a lista de membros e para a contagem.
    online = online_ids(db, [m.user_id for m in members])
    admin_ids = set(_admin_ids(db, team))
    viewer_admin = viewer_id is not None and (
        team.creator_id == viewer_id or viewer_id in admin_ids
    )
    score = total_team_score(db, team.id)
    level, progress, to_next = level_info(score)
    territories = _team_territories(db, team.id)
    pending: list[TeamJoinRequestEntry] = []
    my_request: str | None = None
    if viewer_id is not None:
        if _is_admin(db, team, viewer_id):
            pending = [
                TeamJoinRequestEntry(
                    id=r.id,
                    username=r.user.username,
                    photo_url=r.user.photo_url,
                    created_at=r.created_at,
                )
                for r in db.query(TeamJoinRequest).filter(
                    TeamJoinRequest.team_id == team.id,
                    TeamJoinRequest.status == "pending",
                ).order_by(TeamJoinRequest.created_at).all()
            ]
        else:
            mine = db.query(TeamJoinRequest).filter(
                TeamJoinRequest.team_id == team.id,
                TeamJoinRequest.user_id == viewer_id,
                TeamJoinRequest.status == "pending",
            ).first()
            my_request = "pending" if mine else None
    return TeamDetail(
        id=team.id,
        name=team.name,
        photo_url=team.photo_url,
        creator_username=team.creator.username,
        member_count=len(members),
        members=[
            TeamMemberInfo(
                username=m.user.username,
                photo_url=m.user.photo_url,
                is_admin=m.user_id in admin_ids,
                is_online=m.user_id in online,
            )
            for m in members
        ],
        total_score=score,
        territories_count=len(territories),
        territories=territories,
        zone_capacity=team_zone_capacity(level),
        level_trail=[
            TeamLevelStop(**stop) for stop in team_level_trail(score)
        ],
        level=level,
        level_progress=progress,
        points_to_next_level=to_next,
        join_mode=team.join_mode or "approval",
        listed=bool(team.listed),
        notify_risk=bool(team.notify_risk),
        notify_requests=bool(team.notify_requests),
        invite_token=team.invite_token if viewer_admin else None,
        is_owner=viewer_id is not None and _is_owner(team, viewer_id),
        is_admin=viewer_id is not None and _is_admin(db, team, viewer_id),
        my_request=my_request,
        pending_requests=pending,
        online_count=len(online),
        team_balance=team_balance(db, team)[0],
        team_spent=team.spent_points or 0,
        equipped_avatar=team.equipped_avatar,
        equipped_frame=team.equipped_frame,
        equipped_effect=team.equipped_effect,
        equipped_banner=team.equipped_banner,
        equipped_name_style=team.equipped_name_style,
    )


@router.get("", response_model=list[TeamSummary])
def list_teams(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    mine = user_team(db, current_user.id)
    mine_id = mine.id if mine else None
    query = db.query(Team).options(selectinload(Team.creator))
    # Equipes ocultas ("listed=False") somem da descoberta, mas quem já
    # é membro continua vendo a própria.
    if mine_id is None:
        query = query.filter(Team.listed.is_(True))
    else:
        query = query.filter((Team.listed.is_(True)) | (Team.id == mine_id))
    teams = query.all()
    member_counts = dict(
        db.query(TeamMember.team_id, func.count(TeamMember.user_id))
        .group_by(TeamMember.team_id)
        .all()
    )
    team_territories: dict[str, int] = {}
    for ownership in current_ownerships(db):
        if ownership.owner_team_id:
            team_territories[ownership.owner_team_id] = (
                team_territories.get(ownership.owner_team_id, 0) + 1
            )
    return [
        TeamSummary(
            id=t.id,
            name=t.name,
            photo_url=t.photo_url,
            creator_username=t.creator.username,
            member_count=member_counts.get(t.id, 0),
            territories_count=team_territories.get(t.id, 0),
            created_at=t.created_at,
            equipped_avatar=t.equipped_avatar,
            equipped_frame=t.equipped_frame,
            equipped_banner=t.equipped_banner,
            equipped_name_style=t.equipped_name_style,
        )
        for t in teams
    ]  # UC12b — "Pesquisa equipes disponíveis"


@router.post("", response_model=TeamDetail, status_code=201)
def create_team(
    data: TeamCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    lock_mutations(db)
    if user_team(db, current_user.id):
        raise HTTPException(400, "Você já faz parte de uma equipe. Saia dela antes de criar outra.")
    if db.query(Team).filter(Team.name == data.name).first():
        raise HTTPException(400, "Já existe uma equipe com esse nome.")

    team = Team(name=data.name, creator_id=current_user.id)
    db.add(team)
    db.flush()
    db.add(TeamMember(team_id=team.id, user_id=current_user.id))  # UC12a — "Define usuário como líder"
    db.commit()
    db.refresh(team)
    return _to_detail(db, team, current_user.id)


@router.get("/mine", response_model=TeamDetail)
def get_my_team(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = user_team(db, current_user.id)
    if not team:
        raise HTTPException(404, "Você ainda não participa de uma equipe.")
    return _to_detail(db, team, current_user.id)


@router.get("/invites", response_model=list[TeamInvitationEntry])
def list_my_invites(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Convites pendentes para mim — quem decide sou eu, não o admin da equipe."""
    rows = (
        db.query(TeamJoinRequest)
        .filter(
            TeamJoinRequest.user_id == current_user.id,
            TeamJoinRequest.status == "pending",
            TeamJoinRequest.invited_by.is_not(None),
        )
        .order_by(TeamJoinRequest.created_at)
        .all()
    )
    return [
        TeamInvitationEntry(
            id=r.id,
            team_id=r.team_id,
            team_name=r.team.name,
            invited_by_username=r.inviter.username if r.inviter else None,
            created_at=r.created_at,
        )
        for r in rows
    ]


@router.post("/invites/{request_id}/accept", response_model=TeamDetail)
def accept_invite(request_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    lock_mutations(db)
    req = _my_pending_invite(db, request_id, current_user)
    team = req.team
    if user_team(db, current_user.id):
        raise HTTPException(400, "Você já faz parte de uma equipe. Saia dela antes de entrar em outra.")

    db.add(TeamMember(team_id=team.id, user_id=current_user.id))
    req.status = "approved"
    req.decided_at = datetime.now(timezone.utc)
    # Convites e pedidos do mesmo jogador em outras equipes caducam juntos.
    db.query(TeamJoinRequest).filter(
        TeamJoinRequest.user_id == current_user.id,
        TeamJoinRequest.status == "pending",
        TeamJoinRequest.id != req.id,
    ).delete(synchronize_session=False)
    if req.inviter:
        notify(db, req.inviter.id, f"@{current_user.username} aceitou o convite para {team.name}.", "equipe")
    db.commit()
    return _to_detail(db, team, current_user.id)


@router.post("/invites/{request_id}/decline", status_code=204)
def decline_invite(request_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    lock_mutations(db)
    req = _my_pending_invite(db, request_id, current_user)
    req.status = "declined"
    req.decided_at = datetime.now(timezone.utc)
    if req.inviter:
        notify(
            db,
            req.inviter.id,
            f"@{current_user.username} recusou o convite para {req.team.name}.",
            "equipe",
        )
    db.commit()


@router.get("/{team_id}", response_model=TeamDetail)
def get_team(team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    return _to_detail(db, team, current_user.id)


@router.post("/{team_id}/join", response_model=TeamDetail, status_code=202)
def join_team(
    team_id: str,
    response: Response,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Pede para entrar: dono/admins aprovam depois.

    Equipe aberta entra na hora (201); só por convite recusa o pedido
    direto e pede o link (403).
    """
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")  # UC12b — "[não encontrada]"
    lock_mutations(db)
    if user_team(db, current_user.id):
        raise HTTPException(400, "Você já faz parte de uma equipe. Saia dela antes de entrar em outra.")
    if (team.join_mode or "approval") == "invite_only":
        raise HTTPException(403, "Essa equipe só aceita quem tem o link de convite.")
    if (team.join_mode or "approval") == "open":
        db.add(TeamMember(team_id=team.id, user_id=current_user.id))
        db.commit()
        db.refresh(team)
        response.status_code = 201
        return _to_detail(db, team, current_user.id)
    existing = db.query(TeamJoinRequest).filter(
        TeamJoinRequest.team_id == team.id,
        TeamJoinRequest.user_id == current_user.id,
        TeamJoinRequest.status == "pending",
    ).first()
    if existing:
        raise HTTPException(409, "Seu pedido já está aguardando aprovação.")

    db.add(TeamJoinRequest(team_id=team.id, user_id=current_user.id))
    try:
        db.flush()
    except IntegrityError:
        raise HTTPException(409, "Seu pedido já está aguardando aprovação.")
    if team.notify_requests:
        for admin_id in _admin_ids(db, team):
            notify(db, admin_id, f"@{current_user.username} pediu para entrar em {team.name}.", "equipe")
    db.commit()
    db.refresh(team)
    return _to_detail(db, team, current_user.id)


@router.post("/join/{token}", response_model=TeamDetail, status_code=201)
def join_by_invite(token: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Entra pelo link de convite: vale em qualquer modo de entrada."""
    lock_mutations(db)
    team = db.query(Team).filter(Team.invite_token == token).first()
    if not team:
        raise HTTPException(404, "Convite inválido.")
    if user_team(db, current_user.id):
        raise HTTPException(400, "Você já faz parte de uma equipe. Saia dela antes de entrar em outra.")
    db.add(TeamMember(team_id=team.id, user_id=current_user.id))
    db.commit()
    db.refresh(team)
    return _to_detail(db, team, current_user.id)


def _require_admin(db: Session, team_id: str, user: User) -> Team:
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_admin(db, team, user.id):
        raise HTTPException(403, "Só o dono ou admins decidem pedidos.")
    return team


@router.get("/{team_id}/requests", response_model=list[TeamJoinRequestEntry])
def list_join_requests(team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = _require_admin(db, team_id, current_user)
    return [
        TeamJoinRequestEntry(
            id=r.id,
            username=r.user.username,
            photo_url=r.user.photo_url,
            created_at=r.created_at,
        )
        for r in db.query(TeamJoinRequest).filter(
            TeamJoinRequest.team_id == team.id,
            TeamJoinRequest.status == "pending",
        ).order_by(TeamJoinRequest.created_at).all()
    ]


def _decide_request(db: Session, team: Team, request_id: str, approve: bool) -> TeamJoinRequest:
    req = db.query(TeamJoinRequest).filter(
        TeamJoinRequest.id == request_id,
        TeamJoinRequest.team_id == team.id,
        TeamJoinRequest.status == "pending",
    ).first()
    if not req:
        raise HTTPException(404, "Pedido não encontrado ou já decidido.")
    if approve:
        if user_team(db, req.user_id):
            raise HTTPException(409, "O jogador já entrou em outra equipe.")
        db.add(TeamMember(team_id=team.id, user_id=req.user_id))
        req.status = "approved"
        # Pedidos do mesmo jogador em outras equipes caducam juntos.
        db.query(TeamJoinRequest).filter(
            TeamJoinRequest.user_id == req.user_id,
            TeamJoinRequest.status == "pending",
            TeamJoinRequest.id != req.id,
        ).delete(synchronize_session=False)
        notify(db, req.user_id, f"Bem-vindo a {team.name}! Seu pedido foi aceito.", "equipe")
    else:
        req.status = "rejected"
        notify(db, req.user_id, f"Seu pedido para {team.name} foi recusado.", "equipe")
    req.decided_at = datetime.now(timezone.utc)
    return req


@router.post("/{team_id}/requests/{request_id}/approve", response_model=TeamDetail)
def approve_request(team_id: str, request_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    lock_mutations(db)
    team = _require_admin(db, team_id, current_user)
    _decide_request(db, team, request_id, True)
    db.commit()
    return _to_detail(db, team, current_user.id)


@router.post("/{team_id}/requests/{request_id}/reject", response_model=TeamDetail)
def reject_request(team_id: str, request_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    lock_mutations(db)
    team = _require_admin(db, team_id, current_user)
    _decide_request(db, team, request_id, False)
    db.commit()
    return _to_detail(db, team, current_user.id)


def _my_pending_invite(db: Session, request_id: str, user: User) -> TeamJoinRequest:
    req = db.query(TeamJoinRequest).filter(
        TeamJoinRequest.id == request_id,
        TeamJoinRequest.user_id == user.id,
        TeamJoinRequest.status == "pending",
        TeamJoinRequest.invited_by.is_not(None),
    ).first()
    if not req:
        raise HTTPException(404, "Convite não encontrado ou já respondido.")
    return req


@router.post("/{team_id}/invites", response_model=TeamDetail)
def invite_player(team_id: str, data: TeamInviteRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Convidar por @usuário: abre o pedido em nome do convidado e avisa ele.

    Quem decide é o convidado (`/teams/invites/...`), então o convite não
    entra sozinho em ninguém.
    """
    lock_mutations(db)
    team = _require_admin(db, team_id, current_user)
    target = db.query(User).filter(User.username == data.username).first()
    if not target:
        raise HTTPException(404, "Usuário não encontrado.")
    if db.query(TeamMember).filter(
        TeamMember.team_id == team.id, TeamMember.user_id == target.id
    ).first():
        raise HTTPException(400, "Essa pessoa já está na equipe.")
    if user_team(db, target.id):
        raise HTTPException(400, "Essa pessoa já participa de outra equipe.")

    existing = db.query(TeamJoinRequest).filter(
        TeamJoinRequest.team_id == team.id,
        TeamJoinRequest.user_id == target.id,
        TeamJoinRequest.status == "pending",
    ).first()
    if existing:
        raise HTTPException(409, "Já existe um pedido pendente dessa pessoa.")

    db.add(
        TeamJoinRequest(
            team_id=team.id, user_id=target.id, invited_by=current_user.id
        )
    )
    try:
        db.flush()
    except IntegrityError:
        raise HTTPException(409, "Já existe um pedido pendente dessa pessoa.")
    notify(db, target.id, f"@{current_user.username} convidou você para {team.name}.", "equipe")
    db.commit()
    return _to_detail(db, team, current_user.id)


@router.post("/{team_id}/admins", response_model=TeamDetail)
def promote_admin(team_id: str, data: TeamAdminRequest, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Só o dono promove."""
    lock_mutations(db)
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_owner(team, current_user.id):
        raise HTTPException(403, "Só o dono escolhe admins.")
    target = db.query(User).filter(User.username == data.username).first()
    if not target:
        raise HTTPException(404, "Usuário não encontrado.")
    if not db.query(TeamMember).filter(
        TeamMember.team_id == team.id, TeamMember.user_id == target.id
    ).first():
        raise HTTPException(400, "Só membros podem virar admin.")
    if not _is_admin(db, team, target.id):
        db.add(TeamAdmin(team_id=team.id, user_id=target.id, granted_by=current_user.id))
    db.commit()
    return _to_detail(db, team, current_user.id)


@router.delete("/{team_id}/admins/{username}", response_model=TeamDetail)
def demote_admin(team_id: str, username: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    lock_mutations(db)
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_owner(team, current_user.id):
        raise HTTPException(403, "Só o dono remove admins.")
    if username == team.creator.username:
        raise HTTPException(400, "O dono não pode deixar de ser dono.")
    row = db.query(TeamAdmin).join(User, TeamAdmin.user_id == User.id).filter(
        TeamAdmin.team_id == team.id, User.username == username
    ).first()
    if row:
        db.delete(row)
    db.commit()
    return _to_detail(db, team, current_user.id)


def _team_inventory_of(db: Session, team: Team) -> TeamInventory:
    owned = [
        item_id
        for (item_id,) in db.query(TeamItem.item_id)
        .filter(TeamItem.team_id == team.id)
        .all()
    ]
    return TeamInventory(
        owned=owned,
        equipped_avatar=team.equipped_avatar,
        equipped_frame=team.equipped_frame,
        equipped_effect=team.equipped_effect,
        equipped_banner=team.equipped_banner,
        equipped_name_style=team.equipped_name_style,
    )


@router.get("/{team_id}/wallet", response_model=TeamWallet)
def team_wallet(team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Cofre da equipe: soma dos pontos dos integrantes menos o já gasto."""
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    balance, earned = team_balance(db, team)
    return TeamWallet(
        balance=balance,
        spent_points=team.spent_points or 0,
        members_points=earned,
    )


@router.get("/{team_id}/history", response_model=list[HistoryEntry])
def team_history(team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    """Extrato de pontos da equipe: o que soma o total do card "Pontos".

    Só entram os eventos da própria equipe (`team_id`), nunca os dos
    integrantes correndo por conta.
    """
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    events = (
        db.query(ScoreEvent)
        .filter(ScoreEvent.team_id == team.id)
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


@router.get("/{team_id}/inventory", response_model=TeamInventory)
def team_inventory(team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    return _team_inventory_of(db, team)


def _purchase_team_bundle(db: Session, team: Team, bundle: dict) -> None:
    """Pacote da equipe: libera cada `grant` de escopo team ainda sem dono."""
    grants = [
        g for g in bundle["payload"].get("grants", [])
        if (get_item(g) or {}).get("scope") == "team"
    ]
    if not grants:
        raise HTTPException(400, "Pacote inválido.")
    owned_ids = {
        item_id
        for (item_id,) in db.query(TeamItem.item_id)
        .filter(TeamItem.team_id == team.id)
        .all()
    }
    if all(g in owned_ids for g in grants):
        raise HTTPException(409, "A equipe já possui todos os itens do pacote.")
    for item_id in grants:
        if item_id not in owned_ids:
            db.add(TeamItem(team_id=team.id, item_id=item_id))
    db.add(TeamItem(team_id=team.id, item_id=bundle["id"]))


@router.post("/{team_id}/purchase", response_model=TeamInventory)
def team_purchase(
    team_id: str,
    data: PurchaseRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Compra para a equipe com o cofre (soma dos pontos dos integrantes).
    Só dono ou admins; ninguém perde pontos, nível ou moedas."""
    lock_mutations(db)
    team = _require_admin(db, team_id, current_user)
    db.refresh(team)
    item = get_item(data.item_id)
    if item is None:
        raise HTTPException(404, "Item não encontrado.")
    if item.get("scope") != "team":
        raise HTTPException(400, "Este item é da loja pessoal, não da equipe.")
    existing = (
        db.query(TeamItem)
        .filter(TeamItem.team_id == team.id, TeamItem.item_id == item["id"])
        .first()
    )
    if existing and item["category"] != "bundle":
        raise HTTPException(409, "A equipe já possui este item.")
    balance, _ = team_balance(db, team)
    if balance < item["price"]:
        raise HTTPException(402, "Pontos da equipe insuficientes.")
    if item["category"] == "bundle":
        _purchase_team_bundle(db, team, item)
    else:
        db.add(TeamItem(team_id=team.id, item_id=item["id"]))
    team.spent_points = (team.spent_points or 0) + item["price"]
    db.commit()
    db.refresh(team)
    return _team_inventory_of(db, team)


@router.post("/{team_id}/equip", response_model=TeamInventory)
def team_equip(
    team_id: str,
    data: EquipRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Equipa cosmético da equipe. Só dono ou admins."""
    lock_mutations(db)
    team = _require_admin(db, team_id, current_user)
    db.refresh(team)
    category = data.category
    if category not in EQUIPPABLE:
        raise HTTPException(400, "Categoria inválida.")
    column = f"equipped_{category}"
    if data.item_id is None:
        setattr(team, column, None)
        db.commit()
        db.refresh(team)
        return _team_inventory_of(db, team)
    item = get_item(data.item_id)
    if item is None or item["category"] != category or item.get("scope") != "team":
        raise HTTPException(404, "Item não encontrado nesta categoria.")
    owned = (
        db.query(TeamItem)
        .filter(TeamItem.team_id == team.id, TeamItem.item_id == item["id"])
        .first()
    )
    if owned is None:
        raise HTTPException(403, "Compre para a equipe antes de equipar.")
    setattr(team, column, item["id"])
    db.commit()
    db.refresh(team)
    return _team_inventory_of(db, team)


@router.post("/{team_id}/invite/regenerate", response_model=TeamDetail)
def regenerate_invite(
    team_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Gera um novo link de convite: o antigo deixa de funcionar."""
    lock_mutations(db)
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_admin(db, team, current_user.id):
        raise HTTPException(403, "Só o dono ou admins gerenciam convites.")
    team.invite_token = secrets.token_urlsafe(32)
    db.commit()
    db.refresh(team)
    return _to_detail(db, team, current_user.id)


@router.patch("/{team_id}", response_model=TeamDetail)
def update_team(
    team_id: str,
    data: TeamUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Foto, nome e ajustes: dono e admins. Nome continua único."""
    lock_mutations(db)
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_admin(db, team, current_user.id):
        raise HTTPException(403, "Só o dono ou admins editam a equipe.")
    if data.name and data.name != team.name:
        if db.query(Team).filter(Team.name == data.name).first():
            raise HTTPException(400, "Já existe uma equipe com esse nome.")
        team.name = data.name
    if "photo_url" in data.model_fields_set:
        team.photo_url = data.photo_url
    if data.join_mode is not None:
        if data.join_mode not in JOIN_MODES:
            raise HTTPException(400, "Modo de entrada inválido. Use por aprovação, aberta ou só por convite.")
        team.join_mode = data.join_mode
    if data.listed is not None:
        team.listed = data.listed
    if data.notify_risk is not None:
        team.notify_risk = data.notify_risk
    if data.notify_requests is not None:
        team.notify_requests = data.notify_requests
    db.commit()
    db.refresh(team)
    return _to_detail(db, team, current_user.id)


@router.delete("/{team_id}", status_code=204)
def disband_team(
    team_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)
):
    """Dissolve a equipe. Só o dono; avisa os membros."""
    lock_mutations(db)
    team = db.get(Team, team_id)
    if not team:
        raise HTTPException(404, "Equipe não encontrada.")
    if not _is_owner(team, current_user.id):
        raise HTTPException(403, "Só o dono dissolve a equipe.")
    member_ids = [
        m.user_id
        for m in db.query(TeamMember).filter(TeamMember.team_id == team.id).all()
    ]
    db.query(TeamMember).filter(TeamMember.team_id == team.id).delete(
        synchronize_session=False
    )
    db.query(TeamAdmin).filter(TeamAdmin.team_id == team.id).delete(
        synchronize_session=False
    )
    db.query(TeamJoinRequest).filter(
        TeamJoinRequest.team_id == team.id
    ).delete(synchronize_session=False)
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
    db.query(Run).filter(Run.team_id == team.id).update({Run.team_id: None})
    for uid in member_ids:
        if uid != current_user.id:
            notify(db, uid, f"A equipe {team.name} foi dissolvida.", "equipe")
    db.delete(team)
    db.commit()
    return None


@router.post("/leave", status_code=204)
def leave_team(
    data: TeamLeaveRequest | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Sair da equipe. O dono com membros escolhe o sucessor ou dissolve
    (sem herdeiro automático): sem um dos dois, a saída é recusada.

    Dono sozinho dissolve o time (equivale a dissolver antes de sair).
    """
    lock_mutations(db)
    membership = db.query(TeamMember).filter(TeamMember.user_id == current_user.id).first()
    if not membership:
        raise HTTPException(400, "Você não participa de nenhuma equipe.")
    team = db.get(Team, membership.team_id)
    data = data or TeamLeaveRequest()
    if team is not None and team.creator_id == current_user.id:
        others = [m for m in team.members if m.user_id != current_user.id]
        if others:
            if data.dissolve:
                member_ids = [m.user_id for m in others]
                team_name = team.name
                _dissolve_team(db, team)
                for uid in member_ids:
                    notify(db, uid, f"A equipe {team_name} foi dissolvida.", "equipe")
                db.commit()
                return None
            if not data.successor_username:
                raise HTTPException(
                    409, "Escolha um sucessor ou dissolva a equipe para sair."
                )
            successor = db.query(User).filter(
                User.username == data.successor_username
            ).first()
            if successor is None or successor.id == current_user.id or not any(
                m.user_id == successor.id for m in others
            ):
                raise HTTPException(400, "O sucessor precisa ser um membro da equipe.")
            team.creator_id = successor.id
            db.flush()
            notify(db, successor.id, f"Você agora é dono de {team.name}.", "equipe")
        else:
            _dissolve_team(db, team)
            db.commit()
            return None
    db.delete(membership)
    db.query(TeamAdmin).filter(TeamAdmin.user_id == current_user.id).delete(synchronize_session=False)
    db.commit()
