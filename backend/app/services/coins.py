"""Economia das moedinhas: tudo é ganho correndo (servidor é autoridade).

Regras (tudo junto, como pedido):
- 10 moedas por km corrido (fração conta proporcionalmente).
- +50 por território conquistado na corrida.
- +20 na primeira corrida do dia (missão diária).
- Bônus de sequência (streak): +5 por dia consecutivo (teto +35).

Os dois bônus de dia — missão diária e sequência — são do **dia**, não da
corrida: saem uma única vez, na primeira corrida do dia local. Correr duas
vezes no mesmo dia paga a distância das duas e nenhum bônus duas vezes.

A janela do "dia" vem do fuso que o aparelho informa no pedido, e fuso é
dado do cliente: a trava final é o relógio do servidor — os bônus de dia
só abrem quando não há missão diária creditada nos últimos 24 h. Trocar o
offset entre corridas não reabre o bônus.

Todo movimento gera uma linha em `coin_transactions` (extrato auditável).
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models import CoinTransaction, Run, User

COINS_PER_KM = 10
CONQUEST_BONUS = 50
DAILY_FIRST_RUN_BONUS = 20
STREAK_PER_DAY = 5
STREAK_BONUS_CAP = 35
# Janela do servidor que fecha o "uma vez por dia" para quem mexe no fuso.
DAILY_BONUS_LOCK_HOURS = 24


def _utc_now() -> datetime:
    """Agora em UTC sem fuso, o padrão das colunas de data deste projeto."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def daily_bonus_locked(db: Session, user: User) -> bool:
    """Missão diária creditada há menos de 24 h: os bônus de dia estão travados."""
    since = _utc_now() - timedelta(hours=DAILY_BONUS_LOCK_HOURS)
    return (
        db.query(CoinTransaction.id)
        .filter(
            CoinTransaction.user_id == user.id,
            CoinTransaction.reason == "missao_diaria",
            CoinTransaction.created_at >= since,
        )
        .first()
        is not None
    )


def credit(db: Session, user: User, amount: int, reason: str) -> int:
    if amount <= 0:
        return 0
    user.coins_balance = (user.coins_balance or 0) + amount
    db.add(CoinTransaction(user_id=user.id, delta=amount, reason=reason))
    return amount


def debit(db: Session, user: User, amount: int, reason: str) -> None:
    if amount <= 0:
        return
    if (user.coins_balance or 0) < amount:
        from fastapi import HTTPException

        raise HTTPException(402, "Dracmas insuficientes.")
    user.coins_balance -= amount
    db.add(CoinTransaction(user_id=user.id, delta=-amount, reason=reason))


def earn_for_run(
    db: Session,
    user: User,
    *,
    distance_m: float,
    conquered: bool,
    started_at_utc_naive,
    utc_offset_minutes: int = 0,
) -> dict:
    """Credita as moedas de uma corrida recém-salva. Retorna o detalhamento."""
    distance_bonus = int(distance_m / 1000 * COINS_PER_KM)
    total = 0
    breakdown: dict[str, int] = {}
    if distance_bonus:
        total += credit(db, user, distance_bonus, "distancia")
        breakdown["distancia"] = distance_bonus
    if conquered:
        total += credit(db, user, CONQUEST_BONUS, "conquista")
        breakdown["conquista"] = CONQUEST_BONUS

    local_day = (started_at_utc_naive + timedelta(minutes=utc_offset_minutes)).date()
    day_start_utc = datetime.combine(local_day, datetime.min.time()) - timedelta(
        minutes=utc_offset_minutes
    )
    day_end_utc = day_start_utc + timedelta(days=1)
    same_day = (
        db.query(Run)
        .filter(
            Run.user_id == user.id,
            Run.started_at >= day_start_utc,
            Run.started_at < day_end_utc,
        )
        .count()
    )
    # A corrida atual já está salva: 1 = primeira do dia. É ela que abre os dois
    # bônus de dia; das outras corridas do mesmo dia só a distância conta. O dia
    # alegado pelo aparelho só vale se o servidor ainda não pagou bônus de dia
    # nas últimas 24 h — sem essa trava, mudar o fuso entre corridas reabri o
    # "dia" e pagava missão diária e sequência de novo a cada envio.
    first_of_day = same_day <= 1 and not daily_bonus_locked(db, user)
    if first_of_day:
        total += credit(db, user, DAILY_FIRST_RUN_BONUS, "missao_diaria")
        breakdown["missao_diaria"] = DAILY_FIRST_RUN_BONUS

    streak = 0
    if first_of_day:
        active_dates = {
            (started_at + timedelta(minutes=utc_offset_minutes)).date()
            for (started_at,) in db.query(Run.started_at)
            .filter(Run.user_id == user.id)
            .all()
        }
        cursor = local_day
        while cursor in active_dates:
            streak += 1
            cursor -= timedelta(days=1)
        streak_bonus = min(streak * STREAK_PER_DAY, STREAK_BONUS_CAP)
        if streak_bonus:
            total += credit(db, user, streak_bonus, "streak")
            breakdown["streak"] = streak_bonus
        # Só se sabe a sequência de quem abriu o dia: nas outras corridas o dia
        # já foi contado, e um 0 aqui leria "sem sequência" para quem tem.
        breakdown["streak_days"] = streak

    breakdown["total"] = total
    return breakdown
