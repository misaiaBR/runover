"""Presença: o que o estado escolhido por cada corredor muda na prática.

Quatro chaves — "disponivel", "ausente", "nao_incomodar", "invisivel" — e duas
regras: quem está por aqui (online) e o que chega para quem pediu sossego. O
servidor guarda a chave; o app é que dá nome e cor a ela.
"""

from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models import LocationPing, User

# Janela de sinal vivo: batimento do app aberto ou ping de GPS recente.
ONLINE_WINDOW = timedelta(minutes=15)

# "Não perturbe" filtra a entrada, não silencia o corredor: o que tira
# território dele e o que a equipe pede continuam chegando. Todo o resto
# (conquista, nível, liga, ranking) espera o estado voltar.
ALWAYS_THROUGH = ("perda", "equipe")


def now_utc() -> datetime:
    """Agora em UTC naive — as colunas DateTime do esquema não guardam fuso."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def online_ids(db: Session, user_ids: list[str]) -> set[str]:
    """Os ids com sinal de atividade dentro da janela, menos quem é invisível.

    "ausente" continua contando: o estado diz que a resposta demora, não que a
    pessoa sumiu. "invisivel" sai da conta por escolha de quem corre.
    """
    if not user_ids:
        return set()
    visible = {
        uid
        for (uid,) in db.query(User.id)
        .filter(User.id.in_(user_ids), User.presence != "invisivel")
        .all()
    }
    if not visible:
        return set()
    cutoff = now_utc() - ONLINE_WINDOW
    seen = {
        uid
        for (uid,) in db.query(User.id)
        .filter(User.id.in_(visible), User.last_seen_at >= cutoff)
        .all()
    }
    pinged = {
        uid
        for (uid,) in db.query(LocationPing.user_id)
        .filter(
            LocationPing.user_id.in_(visible),
            LocationPing.recorded_at >= cutoff,
        )
        .distinct()
        .all()
    }
    return seen | pinged


def is_online(db: Session, user_id: str) -> bool:
    return bool(online_ids(db, [user_id]))


def delivers(type_: str, presence: str | None) -> bool:
    """A notificação deste tipo passa pelo estado de presença escolhido?"""
    return presence != "nao_incomodar" or type_ in ALWAYS_THROUGH
