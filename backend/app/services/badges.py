"""Insígnias: catálogo versionado em código e registro de ganho.

Cada insígnia é uma métrica derivada do banco (corridas, conquistas,
distância, equipe, temporada) comparada a um limiar fixo. Não há resgate: a
insígnia aparece quando a métrica alcança o limiar, e a data guardada é o
momento em que o servidor a viu cumprida pela primeira vez — quem correu
antes desta versão recebe a data do primeiro acesso, não a data real do
feito.

Cada regra também pertence a uma categoria (`corridas`, `territorios`,
`distancia`, `acumulados`, `equipe`, `temporada`). A tela agrupa por ela, e o
app dá nome e cor à chave — a mesma conveniência do `icon`: o servidor manda a
chave, só o app sabe desenhá-la.

O catálogo fica em código (sem painel admin no MVP), como o da loja em
`app/services/shop.py`.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import (
    PassPremium,
    Run,
    Team,
    TeamJoinRequest,
    TerritoryOwnership,
    User,
    UserBadge,
)
from app.services.pass_runover import seasonal_points, unlocked_tier
from app.services.scoring import TEAM_WEEK_GOAL_KM, user_team


def _badge(
    badge_id: str,
    name: str,
    description: str,
    icon: str,
    category: str,
    metric: str,
    threshold: int,
) -> dict:
    return {
        "id": badge_id,
        "name": name,
        "description": description,
        "icon": icon,
        "category": category,
        "metric": metric,
        "threshold": threshold,
    }


# As recompensas de nível (selos) foram substituídas pelo sistema de ligas
# (`app/services/leagues.py`): a escada competitiva vive lá, não no mural.
# O que a categoria "temporada" mede é o Passe de Temporada — tier alcançado e
# passe desbloqueado —, não o nível da conta.
CATALOG: list[dict] = [
    _badge("badge_primeira_corrida", "Primeira corrida", "Registre 1 corrida.", "run", "corridas", "runs", 1),
    _badge("badge_cinco_corridas", "Cinco corridas", "Registre 5 corridas.", "run", "corridas", "runs", 5),
    _badge("badge_dez_corridas", "Dez corridas", "Registre 10 corridas.", "run", "corridas", "runs", 10),
    _badge("badge_primeira_conquista", "Primeira conquista", "Conquiste 1 território.", "flag", "territorios", "conquests", 1),
    _badge("badge_cinco_conquistas", "Cinco territórios", "Conquiste 5 territórios.", "flag", "territorios", "conquests", 5),
    _badge("badge_dez_conquistas", "Dez territórios", "Conquiste 10 territórios.", "flag", "territorios", "conquests", 10),
    _badge("badge_cinco_km", "5 km em um laço", "Corra 5 km em uma única corrida.", "route", "distancia", "longest_km", 5),
    _badge("badge_dez_km", "10 km em um laço", "Corra 10 km em uma única corrida.", "route", "distancia", "longest_km", 10),
    _badge("badge_meia_maratona", "Meia maratona", "Corra 21 km em uma única corrida.", "route", "distancia", "longest_km", 21),
    _badge("badge_centenar", "100 km acumulados", "Some 100 km de corrida.", "sum", "acumulados", "total_km", 100),
    _badge("badge_em_equipe", "Em uma equipe", "Participe de uma equipe.", "team", "equipe", "team", 1),
    _badge("badge_criar_equipe", "Criar uma equipe", "Crie uma equipe.", "team", "equipe", "teams_created", 1),
    _badge("badge_primeiro_convite", "Primeiro convite", "Convide alguém para uma equipe.", "team", "equipe", "invites_sent", 1),
    _badge("badge_pit_stop", "Pit stop completo", "Bata a meta semanal de 30 km da equipe.", "team", "equipe", "pit_stop", 1),
    _badge("badge_subindo_temporada", "Subindo na temporada", "Alcance o tier 5 do passe em uma temporada.", "season", "temporada", "season_tier", 5),
    _badge("badge_passe_premium", "Passe premium", "Desbloqueie o passe de uma temporada.", "season", "temporada", "premium_pass", 1),
]


def _week_start(now: datetime) -> datetime:
    """Segunda 00:00 da semana-corrida, no mesmo UTC naive das colunas."""
    return (now - timedelta(days=now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def metric_values(db: Session, user_id: str) -> dict[str, float]:
    """O valor atual de cada métrica do catálogo, calculado na hora."""
    runs = db.query(Run).filter(Run.user_id == user_id)
    count, longest, total = runs.with_entities(
        func.count(Run.id),
        func.coalesce(func.max(Run.distance_m), 0),
        func.coalesce(func.sum(Run.distance_m), 0),
    ).one()
    conquests = (
        db.query(func.count(TerritoryOwnership.id))
        .filter(TerritoryOwnership.owner_user_id == user_id)
        .scalar()
        or 0
    )
    team = user_team(db, user_id)
    # Pit stop: a meta semanal é da equipe inteira — os km somados na semana
    # sob a bandeira dela, não os do corredor. A semana é a de UTC, o padrão
    # das regras periódicas do servidor (a temporada do passe é igual).
    pit_stop = 0
    if team is not None:
        week_start = _week_start(_utc_naive())
        team_km = (
            db.query(func.coalesce(func.sum(Run.distance_m), 0))
            .filter(
                Run.team_id == team.id,
                Run.started_at >= week_start,
                Run.started_at < week_start + timedelta(days=7),
            )
            .scalar()
            or 0
        ) / 1000
        pit_stop = 1 if team_km >= TEAM_WEEK_GOAL_KM else 0
    return {
        "runs": count,
        "conquests": conquests,
        "longest_km": round(longest / 1000, 2),
        "total_km": round(total / 1000, 2),
        "team": 1 if team is not None else 0,
        "teams_created": (
            db.query(func.count(Team.id)).filter(Team.creator_id == user_id).scalar() or 0
        ),
        "invites_sent": (
            db.query(func.count(TeamJoinRequest.id))
            .filter(TeamJoinRequest.invited_by == user_id)
            .scalar()
            or 0
        ),
        "pit_stop": pit_stop,
        "season_tier": unlocked_tier(seasonal_points(db, user_id)),
        "premium_pass": 1 if (
            db.query(PassPremium.id).filter(PassPremium.user_id == user_id).first()
            is not None
        ) else 0,
    }


def _utc_naive() -> datetime:
    """Agora em UTC sem fuso: o padrão das colunas de data deste banco."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _as_utc(value: datetime | None) -> datetime | None:
    """A coluna é timestamp sem fuso; a resposta ao app sempre declara UTC."""
    if value is None or value.tzinfo is not None:
        return value
    return value.replace(tzinfo=timezone.utc)


def _grant(db: Session, user_id: str, badge_id: str) -> datetime:
    """Registra a insígnia e devolve a data guardada (a de quem chegou antes)."""
    moment = _utc_naive()
    try:
        with db.begin_nested():
            db.add(UserBadge(user_id=user_id, badge_id=badge_id, earned_at=moment))
            db.flush()
    except IntegrityError:
        stored = (
            db.query(UserBadge.earned_at)
            .filter(UserBadge.user_id == user_id, UserBadge.badge_id == badge_id)
            .scalar()
        )
        return _as_utc(stored) or moment
    return _as_utc(moment)


def list_badges(db: Session, user: User) -> list[dict]:
    """Catálogo completo com estado, progresso e data; grava o que é novo.

    O app não tem botão de resgate: consultar já concede o que a regra
    alcançou. `user_badges` é único por (usuário, insígnia), então duas
    requisições simultâneas não duplicam nem derrubam a resposta.

    Só escreve e faz `flush`: quem chama decide quando a transação fecha.
    """
    values = metric_values(db, user.id)
    earned_at = {
        row.badge_id: _as_utc(row.earned_at)
        for row in db.query(UserBadge).filter(UserBadge.user_id == user.id).all()
    }
    entries: list[dict] = []
    for badge in CATALOG:
        current = values[badge["metric"]]
        when = earned_at.get(badge["id"])
        # Registrada uma vez, a insígnia não volta a bloquear: o mural é a
        # memória do que já foi feito, não o estado do dia.
        achieved = when is not None or current >= badge["threshold"]
        if achieved and when is None:
            when = _grant(db, user.id, badge["id"])
        entries.append(
            {
                **badge,
                "progress": current,
                "earned": achieved,
                "earned_at": when,
            }
        )
    return entries
