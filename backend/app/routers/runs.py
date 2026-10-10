"""Private activities, atomic conquest and repeatable upload responses."""
import hashlib
import json
from datetime import datetime, timedelta, timezone

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
from app.models import Run, User
from app.schemas import RunDetail, RunProgress, RunRequest, RunSummary
from app.routers.territories import apply_claim
from app.services.coins import earn_for_run
from app.services.scoring import TEAM_WEEK_GOAL_KM, user_team

router = APIRouter(prefix="/runs", tags=["corridas"])


def digest(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


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
        conquered=result["claim"] is not None,
        started_at_utc_naive=start,
        utc_offset_minutes=data.utc_offset_minutes,
    )
    db.commit()
    detail = serialize(run, detail=True)
    detail["coins_earned"] = breakdown["total"]
    return detail


@router.get("", response_model=list[RunSummary])
def list_runs(offset: int = Query(0, ge=0), limit: int = Query(20, ge=1, le=100),
              db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    items = db.query(Run).options(defer(Run.track_json)).filter(Run.user_id == user.id).order_by(Run.started_at.desc(), Run.id).offset(offset).limit(limit).all()
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
    claims = sum(bool(json.loads(result_json).get("claim")) for _, _, result_json in weekly)
    # Personal milestones only; no extra score that could encourage farming.
    first_claim = any(json.loads(result_json).get("claim") for (result_json,) in base.with_entities(Run.result_json).all())
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
            "goals":goals, "badges":badges, "team":team_progress}


@router.get("/{run_id}", response_model=RunDetail)
def get_run(run_id: str, db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    run = db.get(Run, run_id)
    if run is None or run.user_id != user.id:
        raise HTTPException(404, "Corrida não encontrada.")
    return serialize(run, detail=True)
