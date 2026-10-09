"""Insígnias: catálogo versionado em código e registro de ganho.

Cada insígnia é uma métrica derivada do banco (corridas, conquistas,
distância, nível, equipe) comparada a um limiar fixo. Não há resgate: a
insígnia aparece quando a métrica alcança o limiar, e a data guardada é o
momento em que o servidor a viu cumprida pela primeira vez — quem correu
antes desta versão recebe a data do primeiro acesso, não a data real do
feito.

O catálogo fica em código (sem painel admin no MVP), como o da loja em
`app/services/shop.py`.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Run, TeamMember, TerritoryOwnership, User, UserBadge
from app.services.scoring import level_info, total_score


def _badge(
    badge_id: str,
    name: str,
    description: str,
    icon: str,
    metric: str,
    threshold: int,
) -> dict:
    return {
        "id": badge_id,
        "name": name,
        "description": description,
        "icon": icon,
        "metric": metric,
        "threshold": threshold,
    }


# As insígnias de `metric == "level"` são as recompensas estáticas de nível:
# não cópias do passe nem da loja, e concedidas pela própria regra.
CATALOG: list[dict] = [
    _badge("badge_primeira_corrida", "Primeira corrida", "Registre 1 corrida.", "run", "runs", 1),
    _badge("badge_cinco_corridas", "Cinco corridas", "Registre 5 corridas.", "run", "runs", 5),
    _badge("badge_dez_corridas", "Dez corridas", "Registre 10 corridas.", "run", "runs", 10),
    _badge("badge_primeira_conquista", "Primeira conquista", "Conquiste 1 território.", "flag", "conquests", 1),
    _badge("badge_cinco_conquistas", "Cinco territórios", "Conquiste 5 territórios.", "flag", "conquests", 5),
    _badge("badge_cinco_km", "5 km em um laço", "Corra 5 km em uma única corrida.", "route", "longest_km", 5),
    _badge("badge_dez_km", "10 km em um laço", "Corra 10 km em uma única corrida.", "route", "longest_km", 10),
    _badge("badge_meia_maratona", "Meia maratona", "Corra 21 km em uma única corrida.", "route", "longest_km", 21),
    _badge("badge_centenar", "100 km acumulados", "Some 100 km de corrida.", "route", "total_km", 100),
    _badge("badge_em_equipe", "Em uma equipe", "Participe de uma equipe.", "team", "team", 1),
    _badge("badge_nivel_3", "Selo de bronze", "Alcance o nível 3.", "level", "level", 3),
    _badge("badge_nivel_5", "Selo de prata", "Alcance o nível 5.", "level", "level", 5),
    _badge("badge_nivel_10", "Selo de ouro", "Alcance o nível 10.", "level", "level", 10),
    _badge("badge_nivel_15", "Selo de platina", "Alcance o nível 15.", "level", "level", 15),
]


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
    in_team = (
        db.query(TeamMember.id).filter(TeamMember.user_id == user_id).first() is not None
    )
    return {
        "runs": count,
        "conquests": conquests,
        "longest_km": round(longest / 1000, 2),
        "total_km": round(total / 1000, 2),
        "level": level_info(total_score(db, user_id))[0],
        "team": 1 if in_team else 0,
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
    """
    values = metric_values(db, user.id)
    earned_at = {
        row.badge_id: _as_utc(row.earned_at)
        for row in db.query(UserBadge).filter(UserBadge.user_id == user.id).all()
    }
    granted = False
    entries: list[dict] = []
    for badge in CATALOG:
        current = values[badge["metric"]]
        when = earned_at.get(badge["id"])
        # Registrada uma vez, a insígnia não volta a bloquear: o mural é a
        # memória do que já foi feito, não o estado do dia.
        achieved = when is not None or current >= badge["threshold"]
        if achieved and when is None:
            when = _grant(db, user.id, badge["id"])
            granted = True
        entries.append(
            {
                **badge,
                "progress": current,
                "earned": achieved,
                "earned_at": when,
            }
        )
    if granted:
        db.commit()
    return entries
