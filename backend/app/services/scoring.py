"""
Pontuação e ranking derivados dos eventos/posses — nada fica em cache
inconsistente, tudo é recalculado na hora da consulta (RN11: o ranking
"deverá ser atualizado automaticamente sempre que houver alteração").

RN15 — território conquistado por equipe pontua para a equipe, não para o
usuário que estava correndo: por isso ScoreEvent guarda ou `user_id` ou
`team_id`, nunca os dois.
"""
from datetime import datetime

from sqlalchemy import func
from sqlalchemy.orm import Session, selectinload

from app.core.config import settings
from app.models import ScoreEvent, Team, TeamMember, TerritoryOwnership, User


def level_info(score: int) -> tuple[int, float, int]:
    """RF11 / RN10 — nível a partir da pontuação acumulada.

    Custo triangular: alcançar o nível N exige
    `step * (1 + 2 + ... + (N-1)) = step * N*(N-1)/2` pontos.
    Retorna (nível, progresso 0..1 até o próximo, pontos que faltam).
    """
    step = settings.level_step_points
    score = max(0, score)
    level = 1
    while step * (level * (level + 1)) // 2 <= score:
        level += 1

    floor_pts = step * (level * (level - 1)) // 2      # pontos para estar neste nível
    next_pts = step * (level * (level + 1)) // 2        # pontos para o próximo nível
    span = next_pts - floor_pts
    progress = (score - floor_pts) / span if span else 0.0
    return level, round(progress, 4), next_pts - score


# A base abre um anel de hexágonos por nível, e para de crescer no anel 4:
# 7 → 19 → 37 → 61 células. É regra de produto, não de geometria do app — a
# tela de equipe lê este número em vez de adivinhar.
MAX_BASE_RINGS = 4


def team_zone_capacity(level: int) -> int:
    """Quantas zonas a base da equipe comporta no nível."""
    rings = max(1, min(level, MAX_BASE_RINGS))
    return 1 + 3 * rings * (rings + 1)


# A trilha mostra o anel inteiro da base e alguns níveis à frente de quem já
# chegou longe — sem isso ela cresceria sem teto conforme a equipe pontua.
TRAIL_HORIZON = 2
MAX_TRAIL_STOPS = 12


def team_level_trail(score: int) -> list[dict]:
    """Paradas da trilha de nível da equipe: quanto custa e o que libera.

    O app desenha estas linhas sem calcular nada — a curva de pontos e a de
    zonas são regra do servidor.
    """
    step = settings.level_step_points
    level, _, _ = level_info(score)
    top = min(max(MAX_BASE_RINGS, level + TRAIL_HORIZON), MAX_TRAIL_STOPS)
    stops = []
    for n in range(1, top + 1):
        required = step * n * (n - 1) // 2
        stops.append(
            {
                "level": n,
                "points_required": required,
                "zone_capacity": team_zone_capacity(n),
                "reached": score >= required,
            }
        )
    return stops


def current_ownerships(db: Session) -> list[TerritoryOwnership]:
    """A posse atual é a última linha por data, com desempate estável por ID."""
    latest = db.query(
        TerritoryOwnership.id.label("ownership_id"),
        func.row_number().over(
            partition_by=TerritoryOwnership.territory_id,
            order_by=(TerritoryOwnership.conquered_at.desc(), TerritoryOwnership.id.desc()),
        ).label("rank"),
    ).subquery()
    return (
        db.query(TerritoryOwnership)
        .options(
            selectinload(TerritoryOwnership.owner_user),
            selectinload(TerritoryOwnership.owner_team),
        )
        .join(latest, TerritoryOwnership.id == latest.c.ownership_id)
        .filter(latest.c.rank == 1)
        .all()
    )


def current_owner_territory_ids(db: Session, user_id: str) -> set[str]:
    return {o.territory_id for o in current_ownerships(db) if o.owner_user_id == user_id}


def total_score(db: Session, user_id: str, since: datetime | None = None) -> int:
    query = db.query(func.coalesce(func.sum(ScoreEvent.delta), 0)).filter(
        ScoreEvent.user_id == user_id
    )
    if since is not None:
        query = query.filter(ScoreEvent.created_at >= since)
    result = query.scalar()
    return int(result or 0)


def total_team_score(db: Session, team_id: str, since: datetime | None = None) -> int:
    query = db.query(func.coalesce(func.sum(ScoreEvent.delta), 0)).filter(
        ScoreEvent.team_id == team_id
    )
    if since is not None:
        query = query.filter(ScoreEvent.created_at >= since)
    result = query.scalar()
    return int(result or 0)


def user_team(db: Session, user_id: str) -> Team | None:
    membership = db.query(TeamMember).filter(TeamMember.user_id == user_id).first()
    return membership.team if membership else None


# Meta semanal do Pit stop: os quilômetros que a equipe soma na semana-corrida.
# Uma única fonte — o card do Pit stop (`GET /runs/progress`) e a insígnia
# "Pit stop completo" comparam contra o mesmo número.
TEAM_WEEK_GOAL_KM = 30


class RankingRow:
    def __init__(
        self,
        owner_type: str,
        name: str,
        photo_url: str | None,
        score: int,
        territories: int,
        equipped_avatar: str | None = None,
        equipped_frame: str | None = None,
        equipped_effect: str | None = None,
        equipped_banner: str | None = None,
        equipped_name_style: str | None = None,
        trophies: int = 0,
    ):
        self.owner_type = owner_type
        self.name = name
        self.photo_url = photo_url
        self.score = score
        self.territories = territories
        self.equipped_avatar = equipped_avatar
        self.equipped_frame = equipped_frame
        self.equipped_effect = equipped_effect
        self.equipped_banner = equipped_banner
        self.equipped_name_style = equipped_name_style
        self.level = level_info(score)[0]  # RF11 / RN10
        # RR de quem é listado; equipes não disputam a escada, ficam em 0.
        self.trophies = trophies


def _score_maps(db: Session, since: datetime | None = None) -> tuple[dict[str, int], dict[str, int]]:
    """{user_id: pontos} e {team_id: pontos} em uma única consulta agregada."""
    query = db.query(
        ScoreEvent.user_id,
        ScoreEvent.team_id,
        func.coalesce(func.sum(ScoreEvent.delta), 0),
    )
    if since is not None:
        query = query.filter(ScoreEvent.created_at >= since)
    user_scores: dict[str, int] = {}
    team_scores: dict[str, int] = {}
    for user_id, team_id, total in query.group_by(
        ScoreEvent.user_id, ScoreEvent.team_id
    ).all():
        if user_id:
            user_scores[user_id] = int(total or 0)
        elif team_id:
            team_scores[team_id] = int(total or 0)
    return user_scores, team_scores


def full_ranking(db: Session, since: datetime | None = None) -> list[RankingRow]:
    """RF12/RN11 — jogadores e equipes juntos, ordenados por pontuação."""
    ownerships = current_ownerships(db)
    user_scores, team_scores = _score_maps(db, since)
    user_counts: dict[str, int] = {}
    team_counts: dict[str, int] = {}
    for o in ownerships:
        if o.owner_user_id:
            user_counts[o.owner_user_id] = user_counts.get(o.owner_user_id, 0) + 1
        elif o.owner_team_id:
            team_counts[o.owner_team_id] = team_counts.get(o.owner_team_id, 0) + 1

    rows: list[RankingRow] = []
    for u in db.query(User).all():
        rows.append(RankingRow(
            "user", u.username, u.photo_url, user_scores.get(u.id, 0), user_counts.get(u.id, 0),
            equipped_avatar=u.equipped_avatar,
            equipped_frame=u.equipped_frame,
            equipped_effect=u.equipped_effect,
            equipped_banner=u.equipped_banner,
            equipped_name_style=u.equipped_name_style,
            trophies=u.trophies,
        ))
    for t in db.query(Team).all():
        rows.append(RankingRow(
            "team", t.name, t.photo_url, team_scores.get(t.id, 0), team_counts.get(t.id, 0),
            equipped_avatar=t.equipped_avatar,
            equipped_frame=t.equipped_frame,
            equipped_effect=t.equipped_effect,
            equipped_banner=t.equipped_banner,
            equipped_name_style=t.equipped_name_style,
        ))

    rows.sort(key=lambda r: (-r.score, r.name.lower()))
    return rows


def rank_position(db: Session, user_id: str) -> int | None:
    user = db.get(User, user_id)
    if not user:
        return None
    for i, row in enumerate(full_ranking(db), start=1):
        if row.owner_type == "user" and row.name == user.username:
            return i
    return None


def user_rank_positions(db: Session) -> dict[str, int]:
    """{user_id: posição} no ranking combinado (usuários + equipes), para todos
    os usuários — usado para detectar quem mudou de posição após uma conquista
    (RF18 / RN11)."""
    id_by_name = {u.username: u.id for u in db.query(User).all()}
    positions: dict[str, int] = {}
    for i, row in enumerate(full_ranking(db), start=1):
        if row.owner_type == "user" and row.name in id_by_name:
            positions[id_by_name[row.name]] = i
    return positions
