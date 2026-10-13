"""Private activities, atomic conquest and repeatable upload responses."""
import hashlib
import json
from datetime import datetime, time, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session, defer

from app.core.database import get_db, lock_mutations
from app.core.security import get_current_user
from app.geometry import (
    haversine_m,
    validate_track_by_segment,
    TrackValidationError,
)
from app.models import DailyChallengeClaim, Run, ScoreEvent, User
from app.schemas import (
    DailyChallengeClaimRequest,
    DailyChallengeList,
    RunDetail,
    RunProgress,
    RunRequest,
    RunSummary,
)
from app.routers.territories import apply_claim
from app.services.coins import DAILY_FIRST_RUN_BONUS, credit, earn_for_run
from app.services.daily_challenges import (
    Challenge,
    day_key,
    draw,
    local_day,
    measure,
    summarize,
)
from app.services.scoring import TEAM_WEEK_GOAL_KM, user_team

router = APIRouter(prefix="/runs", tags=["corridas"])


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def claim_won(claim) -> bool:
    """A corrida trocou de dono, de fato?

    O recibo de um desafio perdido também vem em `claim` — é a resposta da
    retomada, com `challenge_won` falso, pontos zero e sem troca de posse. Contar
    esse recibo como conquista pagaria o bônus de quem perdeu e enchia a meta
    semanal e o selo "Primeira conquista" com derrotas.
    """
    return bool(claim) and claim.get("challenge_won") is not False


def serialize(run, detail=False):
    value = {"id": run.id, "name": run.name, "started_at": run.started_at.replace(tzinfo=timezone.utc).isoformat(),
             "distance_m": run.distance_m, "duration_seconds": run.duration_seconds,
             "pace_seconds_per_km": round(run.duration_seconds / (run.distance_m / 1000)) if run.distance_m >= 10 else None,
             **json.loads(run.result_json)}
    if detail:
        value["track"] = json.loads(run.track_json)
    return value


@router.post("", response_model=RunDetail, status_code=200)
def save_run(data: RunRequest, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    return create_run(db, user, data)


def create_run(db: Session, user: User, data: RunRequest) -> dict:
    """Salva uma corrida com todas as validações. Retorna o detalhe serializado."""
    payload = data.model_dump(mode="json")
    request_hash = digest(payload)
    # This database lock also covers new territories, which have no row to lock yet.
    lock_mutations(db)
    existing = db.get(Run, str(data.id))
    if existing:
        if existing.user_id != user.id or existing.request_hash != request_hash:
            raise HTTPException(409, "Esta identificação já pertence a outra corrida ou conteúdo.")
        return serialize(existing, detail=True)
    track = payload["track"]
    track_hash = digest([{k: p[k] for k in ("lat", "lng", "timestamp")} for p in track])
    if db.query(Run).filter(Run.track_hash == track_hash).first():
        raise HTTPException(409, "Este percurso já foi registrado.")
    now = datetime.now(timezone.utc)
    first, last = data.track[0].timestamp, data.track[-1].timestamp
    if first < now - timedelta(days=7) or last > now + timedelta(minutes=2):
        raise HTTPException(400, "Envie corridas dos últimos 7 dias, com o relógio do aparelho correto.")
    if not 1 <= (last - first).total_seconds() <= 21600:
        raise HTTPException(400, "A corrida deve durar entre 1 segundo e 6 horas.")
    try:
        validate_track_by_segment(
            [(p.lat, p.lng, p.timestamp.timestamp()) for p in data.track],
            [p.segment for p in data.track],
        )
    except TrackValidationError as exc:
        raise HTTPException(400, str(exc))
    if any(b.segment < a.segment or b.segment > a.segment + 1 for a, b in zip(data.track, data.track[1:])):
        raise HTTPException(400, "Pausas fora de ordem.")
    start, end = first.replace(tzinfo=None), last.replace(tzinfo=None)
    if db.query(Run).filter(Run.user_id == user.id, Run.started_at < end, Run.ended_at > start).first():
        raise HTTPException(409, "Já existe uma corrida registrada nesse período.")
    pairs = [(a,b) for a,b in zip(data.track, data.track[1:]) if a.segment == b.segment]
    distance = sum(haversine_m(a.lat,a.lng,b.lat,b.lng) for a,b in pairs)
    duration = int(sum((b.timestamp-a.timestamp).total_seconds() for a,b in pairs))
    if distance < 10 or duration < 1:
        raise HTTPException(400, "Registre ao menos 10 metros de movimento para salvar a corrida.")
    team = user_team(db, user.id)
    if data.team_id and (team is None or data.team_id != team.id):
        raise HTTPException(403, "Você não pertence à equipe selecionada.")
    result = {"claim": None, "claim_error": None}
    if data.conquer:
        try:
            with db.begin_nested():
                result["claim"] = apply_claim(
                    data, db, user,
                    distance_m=distance, duration_seconds=duration,
                ).model_dump(mode="json")
        except HTTPException as exc:
            if exc.status_code != 400:
                raise
            result["claim_error"] = str(exc.detail)
    # Claim failure must not discard a valid activity or partially mutate ownership.
    db.refresh(user)
    user.play_seconds += duration
    run = Run(id=str(data.id), user_id=user.id, team_id=team.id if team else None,
              request_hash=request_hash, track_hash=track_hash, track_json=json.dumps(track),
              started_at=start, ended_at=end, distance_m=distance, duration_seconds=duration,
              name=data.name or "Minha corrida", result_json=json.dumps(result))
    db.add(run)
    db.commit()
    # Moedinhas: crédito após a corrida salva (servidor é autoridade).
    db.refresh(user)
    breakdown = earn_for_run(
        db, user,
        distance_m=distance,
        conquered=claim_won(result["claim"]),
        started_at_utc_naive=start,
        utc_offset_minutes=data.utc_offset_minutes,
    )
    db.commit()
    detail = serialize(run, detail=True)
    detail["coins_earned"] = breakdown["total"]
    return detail


@router.get("", response_model=list[RunSummary])
def list_runs(offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100),
              since: datetime | None = Query(None),
              db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    # `since` é o corte do filtro de período do app ("Este mês"). O histórico é
    # paginado, então filtrar no aparelho mostraria um mês incompleto.
    base = db.query(Run).options(defer(Run.track_json)).filter(Run.user_id == user.id)
    if since is not None:
        # `Run.started_at` é UTC ingênuo; um corte com fuso vira UTC antes da comparação.
        cutoff = since.astimezone(timezone.utc).replace(tzinfo=None) if since.tzinfo else since
        base = base.filter(Run.started_at >= cutoff)
    items = base.order_by(Run.started_at.desc(), Run.id).offset(offset).limit(limit).all()
    return [serialize(r) for r in items]


@router.get("/progress", response_model=RunProgress)
def progress(
    utc_offset_minutes: int = Query(0, ge=-720, le=840),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    user_timezone = timezone(timedelta(minutes=utc_offset_minutes))
    local_now = datetime.now(timezone.utc).astimezone(user_timezone)
    local_week_start = (local_now - timedelta(days=local_now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    week = local_week_start.astimezone(timezone.utc).replace(tzinfo=None)
    week_end = week + timedelta(days=7)
    base = db.query(Run).filter(Run.user_id == user.id)
    count, total, longest = base.with_entities(func.count(Run.id), func.coalesce(func.sum(Run.distance_m), 0), func.coalesce(func.max(Run.distance_m), 0)).one()
    weekly = base.with_entities(Run.distance_m, Run.started_at, Run.result_json).filter(Run.started_at >= week, Run.started_at < week_end).all()
    km = sum(distance_m for distance_m, _, _ in weekly) / 1000
    days = len({(started_at + timedelta(minutes=utc_offset_minutes)).date() for _, started_at, _ in weekly})
    claims = sum(claim_won(json.loads(result_json).get("claim")) for _, _, result_json in weekly)
    # Personal milestones only; no extra score that could encourage farming.
    first_claim = any(claim_won(json.loads(result_json).get("claim")) for (result_json,) in base.with_entities(Run.result_json).all())
    goals = [{"name":"Correr 10 km nesta semana", "value":round(km,2), "target":10, "unit":"km"},
             {"name":"Correr em 3 dias nesta semana", "value":days, "target":3, "unit":"dias"},
             {"name":"Conquistar 3 territórios nesta semana", "value":claims, "target":3, "unit":"conquistas"}]
    badges = [{"name":"Primeira corrida", "earned":count > 0}, {"name":"Primeira conquista", "earned":first_claim},
              {"name":"5 km em uma corrida", "earned":longest >= 5000}, {"name":"10 corridas", "earned":count >= 10}]
    team = user_team(db, user.id)
    team_progress = None
    if team:
        contributions = db.query(User.username, func.sum(Run.distance_m)).join(Run, Run.user_id == User.id).filter(
            Run.team_id == team.id, Run.started_at >= week, Run.started_at < week_end).group_by(User.id, User.username).order_by(func.sum(Run.distance_m).desc()).all()
        team_progress = {"name":team.name, "target_km":TEAM_WEEK_GOAL_KM, "distance_km":round(sum(d for _,d in contributions)/1000,2),
                         "contributors":[{"username":name,"distance_km":round(d/1000,2)} for name,d in contributions]}
    # Sequência (streak): dias consecutivos com ao menos 1 corrida, no
    # fuso do aparelho. Se hoje ainda não tem corrida, a sequência segue
    # valendo a partir de ontem; se nem ontem tem, é 0.
    active_dates = {
        (started_at + timedelta(minutes=utc_offset_minutes)).date()
        for (started_at,) in base.with_entities(Run.started_at).all()
    }
    today = local_now.date()
    streak_days = 0
    cursor = today
    if cursor not in active_dates:
        cursor = cursor - timedelta(days=1)
        if cursor not in active_dates:
            active_dates = set()
    while cursor in active_dates:
        streak_days += 1
        cursor = cursor - timedelta(days=1)
    return {"week_start":week.isoformat()+"Z", "runs_count":count, "distance_km":round(total/1000,2),
            "longest_run_km":round(longest/1000,2), "streak_days":streak_days,
            # O bônus da primeira corrida do dia vem da economia do servidor, a
            # tela só repete o número. `pending` é hoje ainda não ter corrida.
            "daily_bonus": DAILY_FIRST_RUN_BONUS,
            "daily_bonus_pending": today not in active_dates,
            "goals":goals, "badges":badges, "team":team_progress}


def _todays_challenges(db: Session, user: User, utc_offset_minutes: int):
    """(dia local, sorteio de hoje, resumo, ids das corridas do dia).

    O sorteio muda à meia-noite, então o "Longão pessoal" congela o alvo com o
    histórico que existia até o início do dia: correr hoje não pode deixar o
    desafio de hoje mais difícil no meio do caminho. O resumo segue a mesma
    meia-noite local e mede só as corridas do dia.

    Os ids voltam junto porque o resgate precisa do recibo: o fuso é do
    aparelho, e a mesma corrida pode caber em dois "dias" se o cliente trocar o
    offset entre um resgate e outro.
    """
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    day = local_day(now, utc_offset_minutes)
    day_start = datetime.combine(day, time.min) - timedelta(minutes=utc_offset_minutes)
    total_m, longest_m = (
        db.query(Run)
        .filter(Run.user_id == user.id, Run.started_at < day_start)
        .with_entities(
            func.coalesce(func.sum(Run.distance_m), 0),
            func.coalesce(func.max(Run.distance_m), 0),
        )
        .one()
    )
    challenges = draw(user.username, day, float(total_m) / 1000, float(longest_m) / 1000)
    day_runs = (
        db.query(Run.id, Run.started_at, Run.distance_m, Run.duration_seconds)
        .filter(Run.user_id == user.id, Run.started_at >= day_start, Run.started_at < day_start + timedelta(days=1))
        .all()
    )
    summary = summarize(
        [(run.started_at, run.distance_m, run.duration_seconds) for run in day_runs],
        day,
        utc_offset_minutes,
    )
    return day, challenges, summary, [run.id for run in day_runs]


def _challenge_status(db: Session, user: User, utc_offset_minutes: int) -> dict:
    day, challenges, summary, _runs = _todays_challenges(db, user, utc_offset_minutes)
    claimed = {
        challenge_id
        for (challenge_id,) in db.query(DailyChallengeClaim.challenge_id)
        .filter(
            DailyChallengeClaim.user_id == user.id,
            DailyChallengeClaim.day == day_key(day),
        )
        .all()
    }
    return {
        "day": day_key(day),
        "challenges": [
            {
                "id": challenge.id,
                "title": challenge.title,
                "detail": challenge.detail,
                "unit": challenge.unit,
                "target": challenge.target,
                "rarity": challenge.rarity,
                "kind": challenge.kind,
                "value": value,
                "done": done,
                "points": challenge.points,
                "coins": challenge.coins,
                "claimed": challenge.id in claimed,
            }
            for challenge in challenges
            for value, done in [measure(challenge, summary)]
        ],
    }


@router.get("/challenges", response_model=DailyChallengeList)
def daily_challenges(
    utc_offset_minutes: int = Query(0, ge=-720, le=840),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Os três desafios do dia, já medidos contra as corridas salvas."""
    return _challenge_status(db, user, utc_offset_minutes)


@router.post("/challenges/claim", response_model=DailyChallengeList)
def claim_daily_challenge(
    data: DailyChallengeClaimRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Resgata um desafio concluído: pontos de temporada e dracmas, uma vez por dia."""
    lock_mutations(db)
    db.refresh(user)
    day, challenges, summary, day_run_ids = _todays_challenges(
        db, user, data.utc_offset_minutes
    )
    challenge: Challenge | None = next(
        (item for item in challenges if item.id == data.challenge_id), None
    )
    if challenge is None:
        raise HTTPException(404, "Este desafio não está no seu sorteio de hoje.")
    if not measure(challenge, summary)[1]:
        raise HTTPException(400, "Complete o desafio antes de resgatar.")
    already = (
        db.query(DailyChallengeClaim)
        .filter(
            DailyChallengeClaim.user_id == user.id,
            DailyChallengeClaim.day == day_key(day),
            DailyChallengeClaim.challenge_id == challenge.id,
        )
        .first()
    )
    if already:
        raise HTTPException(409, "Este desafio já foi resgatado hoje.")
    # Uma corrida paga um único dia. Sem esta trava, o fuso enviado pelo
    # cliente (-720 a +840, 26 horas) faria a mesma corrida render resgates em
    # dois dias seguidos, cada um com o próprio sorteio e a própria recompensa.
    paid = {
        run_id
        for (stored,) in db.query(DailyChallengeClaim.run_ids)
        .filter(
            DailyChallengeClaim.user_id == user.id,
            DailyChallengeClaim.day != day_key(day),
        )
        .all()
        for run_id in json.loads(stored or "[]")
    }
    if paid & set(day_run_ids):
        raise HTTPException(
            409, "Estas corridas já pagaram um desafio de outro dia."
        )
    db.add(
        DailyChallengeClaim(
            user_id=user.id,
            day=day_key(day),
            challenge_id=challenge.id,
            points=challenge.points,
            coins=challenge.coins,
            run_ids=json.dumps(sorted(day_run_ids)),
        )
    )
    if challenge.points:
        db.add(ScoreEvent(user_id=user.id, delta=challenge.points, reason="desafio do dia"))
    if challenge.coins:
        credit(db, user, challenge.coins, f"desafio:{day_key(day)}:{challenge.id}")
    db.commit()
    return _challenge_status(db, user, data.utc_offset_minutes)


@router.get("/{run_id}", response_model=RunDetail)
def get_run(run_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    run = db.get(Run, run_id)
    if run is None or run.user_id != user.id:
        raise HTTPException(404, "Corrida não encontrada.")
    return serialize(run, detail=True)
