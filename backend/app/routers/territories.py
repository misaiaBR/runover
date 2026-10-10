import math
import hashlib
import json
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from shapely.geometry import Point
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.security import get_current_user
from app.geometry import (
    TrackValidationError,
    build_track_polygon,
    geojson_centroid,
    geojson_to_polygon,
    haversine_m,
    overlap_ratio,
    polygon_area_m2,
    polygon_to_latlng,
    shapely_polygon_to_geojson,
    validate_track_by_segment,
)
from app.h3cells import cell_for, covering_cells
from app.models import ClaimReceipt, ConquestMark, ScoreEvent, SpawnClaim, Team, TeamMember, Territory, TerritoryOwnership, User
from app.schemas import ClaimRequest, ClaimResponse, TerritoryDetail, TerritorySummary, WildSpawn
from app.services.notifications import notify
from app.services.leagues import (
    apply_trophies,
    conquest_reward,
    defeat_penalty,
    league_changed,
    loss_penalty,
)
from app.services.scoring import (
    current_ownerships,
    level_info,
    total_score,
    total_team_score,
    user_rank_positions,
)
from app.services.spawns import wild_spawns_for, wild_spawns_in_bounds

router = APIRouter(prefix="/territories", tags=["territórios"])


def _latest_ownership_map(db: Session) -> dict[str, TerritoryOwnership]:
    return {o.territory_id: o for o in current_ownerships(db)}


def _takeover_counts(db: Session, territory_id: str | None = None) -> dict[str, int]:
    query = db.query(TerritoryOwnership.territory_id, func.count(TerritoryOwnership.id))
    if territory_id:
        query = query.filter(TerritoryOwnership.territory_id == territory_id)
    rows = query.group_by(TerritoryOwnership.territory_id).all()
    return {tid: max(count - 1, 0) for tid, count in rows}


def _owner_fields(owner: TerritoryOwnership | None) -> tuple[str | None, str | None]:
    if owner is None:
        return None, None
    if owner.owner_team_id:
        return "team", owner.owner_team.name
    return "user", owner.owner_user.username


def _current_mark(db: Session, territory_id: str) -> ConquestMark | None:
    """Marca do dono atual — o laço que conquistou por último."""
    return (
        db.query(ConquestMark)
        .filter(ConquestMark.territory_id == territory_id)
        .order_by(ConquestMark.created_at.desc())
        .first()
    )


def _loop_pace(distance_m: float, duration_seconds: int) -> int:
    return round(duration_seconds / (distance_m / 1000))


def _challenge_won(
    challenge: str, mark: ConquestMark, distance_m: float, duration_seconds: int
) -> bool:
    """Ritmo: laço com ritmo médio mais rápido.
    Distância: mais quilômetros em tempo igual ou menor. Empate perde."""
    if challenge == "pace":
        return _loop_pace(distance_m, duration_seconds) < mark.pace_seconds_per_km
    return distance_m > mark.distance_m and duration_seconds <= mark.duration_seconds


def _to_summary(t: Territory, owner: TerritoryOwnership | None, takeovers: int = 0) -> TerritorySummary:
    lat, lng = geojson_centroid(t.geojson)
    owner_type, owner_display = _owner_fields(owner)
    return TerritorySummary(
        id=t.id,
        name=t.name,
        coordinates=polygon_to_latlng(t.geojson),
        center={"lat": lat, "lng": lng},
        radius_m=t.radius_m,
        status="conquistado" if owner else "disponivel",  # RF07 / enum `status` do diagrama de classes
        owner_type=owner_type,
        owner_display=owner_display,
        takeovers=takeovers,
    )


@router.get("", response_model=list[TerritorySummary])
def list_territories(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    owners = _latest_ownership_map(db)
    takeovers = _takeover_counts(db)
    territories = db.query(Territory).all()
    return [_to_summary(t, owners.get(t.id), takeovers.get(t.id, 0)) for t in territories]  # RF06/RF07


@router.get("/nearby", response_model=list[TerritorySummary])
def nearby_territories(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
    radius_km: float = Query(25.0, gt=0, le=200),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Territórios cujo centro está a até `radius_km` de um ponto (busca por proximidade)."""
    owners = _latest_ownership_map(db)
    takeovers = _takeover_counts(db)
    # Pré-filtro pela célula H3 indexada (igualdade de string); o haversine
    # exato decide em Python. Raios grandes demais para o disco de cobertura
    # e linhas sem célula (anteriores à migração 0003) usam a caixa
    # delimitadora legada — os resultados são os mesmos.
    cells = covering_cells(lat, lng, radius_km * 1000)
    if cells is not None:
        candidates = (
            db.query(Territory)
            .filter(or_(
                Territory.h3_cell.is_(None),
                Territory.h3_cell.in_(cells),
            ))
            .all()
        )
    else:
        lat_window = radius_km * 1000 / 111_320
        lng_window = radius_km * 1000 / (111_320 * max(0.2, math.cos(math.radians(lat))))
        candidates = (
            db.query(Territory)
            .filter(or_(
                Territory.center_lat.is_(None),
                Territory.center_lng.is_(None),
                (Territory.center_lat >= lat - lat_window)
                & (Territory.center_lat <= lat + lat_window)
                & (Territory.center_lng >= lng - lng_window)
                & (Territory.center_lng <= lng + lng_window),
            ))
            .all()
        )
    results = []
    for t in candidates:
        if t.center_lat is not None and t.center_lng is not None:
            center_lat, center_lng = t.center_lat, t.center_lng
        else:
            center_lat, center_lng = geojson_centroid(t.geojson)
        if haversine_m(lat, lng, center_lat, center_lng) <= radius_km * 1000:
            results.append(_to_summary(t, owners.get(t.id), takeovers.get(t.id, 0)))
    return results


def _live_spawn_keys(db: Session, now: datetime) -> set[str]:
    db.query(SpawnClaim).filter(
        SpawnClaim.claimed_at < now - timedelta(hours=2)
    ).delete(synchronize_session=False)
    return {row[0] for row in db.query(SpawnClaim.spawn_key).all()}


@router.get("/wild", response_model=list[WildSpawn])
def wild_territories(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
    radius_km: float = Query(2.0, gt=0, le=200),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Spawns selvagens ao redor — somem ao fim da hora ou quando conquistados."""
    now = datetime.now(timezone.utc)
    claimed = _live_spawn_keys(db, now)
    activity = [
        (row[0], row[1], row[2])
        for row in db.query(
            Territory.center_lat, Territory.center_lng, Territory.radius_m
        ).filter(
            Territory.center_lat.isnot(None),
            Territory.center_lng.isnot(None),
        ).all()
    ]
    return [
        WildSpawn(
            key=s["key"],
            center={"lat": s["lat"], "lng": s["lng"]},
            radius_m=s["radius_m"],
            relevance=s["relevance"],
            rarity=s["rarity"],
            spawned_at=s["spawned_at"],
            expires_at=s["expires_at"],
        )
        for s in wild_spawns_for(lat, lng, radius_km, now, activity=activity)
        if s["key"] not in claimed
    ]


@router.get("/{territory_id}", response_model=TerritoryDetail)
def get_territory(territory_id: str, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    t = db.get(Territory, territory_id)
    if not t:
        raise HTTPException(404, "Território não encontrado.")
    owner = _latest_ownership_map(db).get(territory_id)
    mark = _current_mark(db, territory_id)
    summary = _to_summary(t, owner, _takeover_counts(db, territory_id).get(territory_id, 0))
    previous = (
        db.query(TerritoryOwnership)
        .filter(TerritoryOwnership.territory_id == territory_id)
        .order_by(TerritoryOwnership.conquered_at.desc(), TerritoryOwnership.id.desc())
        .all()
    )
    history = []
    for o in previous:
        if owner and o.id == owner.id:
            continue
        owner_type, owner_display = _owner_fields(o)
        history.append({"owner_type": owner_type, "owner_display": owner_display, "conquered_at": o.conquered_at})
    return TerritoryDetail(
        **summary.model_dump(),
        conquered_at=owner.conquered_at if owner else None,
        points_value=owner.points if owner else round(settings.base_conquest_points * t.relevance),
        history=history,
        owner_pace_seconds_per_km=mark.pace_seconds_per_km if mark else None,
        owner_distance_m=mark.distance_m if mark else None,
        owner_duration_seconds=mark.duration_seconds if mark else None,
    )


@router.post("/claim")
def legacy_claim(_: User = Depends(get_current_user)):
    raise HTTPException(410, "Atualize o aplicativo para salvar corridas com segurança.")


def apply_claim(
    data: ClaimRequest,
    db: Session,
    current_user: User,
    distance_m: float,
    duration_seconds: int,
):
    """Mecânica de laço fechado: o usuário fecha o próprio trajeto (RN05).
    Se o laço sobrepõe um território existente o suficiente, ele é
    retomado; senão, um território novo nasce ali.

    A retomada é um desafio: contra território com marca, o rival
    precisa vencer o dono no critério escolhido — ritmo mais rápido
    ou mais distância em tempo igual ou menor."""
    payload_hash = hashlib.sha256(json.dumps(
        data.model_dump(mode="json", exclude={"request_id"}),
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    prior_receipt = db.query(ClaimReceipt).filter_by(
        user_id=current_user.id, request_id=data.request_id
    ).first()
    if prior_receipt:
        if prior_receipt.payload_hash != payload_hash:
            raise HTTPException(409, "Este identificador já foi usado em outra corrida.")
        return ClaimResponse.model_validate_json(prior_receipt.response_json)

    # Serialize claims made by one account on PostgreSQL. The unique receipt
    # below remains the final guard for SQLite and concurrent retries.
    db.execute(select(User).where(User.id == current_user.id).with_for_update())
    prior_receipt = db.query(ClaimReceipt).filter_by(
        user_id=current_user.id, request_id=data.request_id
    ).first()
    if prior_receipt:
        if prior_receipt.payload_hash != payload_hash:
            raise HTTPException(409, "Este identificador já foi usado em outra corrida.")
        return ClaimResponse.model_validate_json(prior_receipt.response_json)

    team: Team | None = None
    if data.team_id:
        team = db.get(Team, data.team_id)
        if not team:
            raise HTTPException(404, "Equipe não encontrada.")
        if not db.query(TeamMember).filter(
            TeamMember.team_id == team.id, TeamMember.user_id == current_user.id
        ).first():
            raise HTTPException(403, "Você não pertence a essa equipe.")

    if not data.track:
        raise HTTPException(400, "Envie o trajeto percorrido para fechar o território.")

    track_tuples = [(p.lat, p.lng, p.timestamp.timestamp()) for p in data.track]
    segments = [p.segment for p in data.track]
    try:
        validate_track_by_segment(track_tuples, segments)  # RNF17 / RN18
        loop_polygon = build_track_polygon(  # RN05
            [(p.lat, p.lng) for p in data.track],
            accuracies=[p.accuracy for p in data.track],
            segments=segments,
        )
    except TrackValidationError as exc:
        raise HTTPException(400, str(exc))

    area_m2 = polygon_area_m2(loop_polygon)

    # Estado ANTES da conquista — usado para detectar mudança de nível (RF11)
    # e de posição no ranking (RF18) e disparar notificações (RN16).
    user_score_before = total_score(db, current_user.id)
    ranks_before = user_rank_positions(db)
    team_score_before = total_team_score(db, team.id) if team else 0


    # Procura o território existente mais coberto pelo novo laço.
    owners = _latest_ownership_map(db)
    best_match: Territory | None = None
    best_ratio = 0.0
    for t in db.query(Territory).all():
        ratio = overlap_ratio(loop_polygon, geojson_to_polygon(t.geojson))
        if ratio > best_ratio:
            best_ratio, best_match = ratio, t

    created_new = best_match is None or best_ratio < settings.min_overlap_ratio

    # Spawns selvagens cobertos pelo laço (centro dentro do polígono).
    # Vale a lista crua, sem filtro de rua/atividade: o filtro decide o que
    # APARECE no mapa; aqui só importa o que o laço cobriu de fato.
    now = datetime.now(timezone.utc)
    claimed_keys = _live_spawn_keys(db, now)
    bounds = loop_polygon.bounds  # (min_lng, min_lat, max_lng, max_lat)
    covered = [
        s
        for s in wild_spawns_in_bounds(
            bounds[1], bounds[3], bounds[0], bounds[2], now
        )
        if s["key"] not in claimed_keys
        and Point(s["lng"], s["lat"]).within(loop_polygon)
    ]

    if created_new:
        area_relevance = max(1, round(area_m2 / 5000))  # laços maiores valem mais (RN09)
        # Bônus selvagem: o território herda a maior raridade coberta.
        relevance = max(
            [area_relevance] + [s["relevance"] for s in covered]
        )
        centroid = loop_polygon.centroid  # shapely usa (lng, lat)
        territory = Territory(
            name=data.name or f"Território de @{current_user.username}",
            geojson=shapely_polygon_to_geojson(loop_polygon),
            radius_m=math.sqrt(area_m2 / math.pi),
            relevance=relevance,
            center_lat=centroid.y,
            center_lng=centroid.x,
            h3_cell=cell_for(centroid.y, centroid.x),
        )
        db.add(territory)
        db.flush()
        current_owner = None
        current_mark = None
    else:
        territory = best_match
        # Lock the matched territory and recompute ownership after acquiring
        # the lock so simultaneous claims cannot both debit the same owner.
        db.execute(select(Territory).where(Territory.id == territory.id).with_for_update())
        owners = _latest_ownership_map(db)
        relevance = territory.relevance
        current_owner = owners.get(territory.id)
        already_mine = current_owner and (
            (team and current_owner.owner_team_id == team.id)
            or (not team and current_owner.owner_user_id == current_user.id)
        )
        if already_mine:
            raise HTTPException(400, "Este território já é seu.")  # RN07

        # Desafio de conquista: sem vencer a marca do dono, o território fica.
        current_mark = _current_mark(db, territory.id)
        if current_mark is not None:
            if data.challenge is None:
                raise HTTPException(
                    400, "Escolha o desafio deste território: ritmo ou distância."
                )
            if not _challenge_won(
                data.challenge, current_mark, distance_m, duration_seconds
            ):
                # Derrota: a corrida é salva, mas sem pontos nem troca de dono.
                # Para a liga, porém, desafio perdido é derrota de verdade: RR.
                rr = apply_trophies(
                    db, current_user, -defeat_penalty(distance_m), "derrota_desafio"
                )
                changed, message = league_changed(rr)
                if changed:
                    notify(db, current_user.id, message, "liga")
                total = (
                    total_team_score(db, team.id)
                    if team
                    else total_score(db, current_user.id)
                )
                lost = ClaimResponse(
                    territory=get_territory(territory.id, db, current_user),
                    created_new=False,
                    points_awarded=0,
                    area_m2=area_m2,
                    new_total_score=total,
                    new_level=level_info(total)[0],
                    leveled_up=False,
                    challenge=data.challenge,
                    challenge_won=False,
                    beaten_pace_seconds_per_km=current_mark.pace_seconds_per_km,
                    beaten_distance_m=current_mark.distance_m,
                )
                db.add(ClaimReceipt(
                    user_id=current_user.id,
                    request_id=data.request_id,
                    payload_hash=payload_hash,
                    response_json=lost.model_dump_json(),
                ))
                db.flush()
                return lost

    points = round(settings.base_conquest_points * relevance + area_m2 * settings.points_per_m2)  # RN09

    if not created_new and current_owner:
        if current_owner.owner_team_id:
            db.add(ScoreEvent(team_id=current_owner.owner_team_id, territory_id=territory.id,
                               delta=-settings.loss_penalty_points, reason="perda"))
            losing = db.get(Team, current_owner.owner_team_id)
            if losing is None or losing.notify_risk:
                for m in db.query(TeamMember).filter(TeamMember.team_id == current_owner.owner_team_id).all():
                    notify(db, m.user_id, f"Sua equipe perdeu o território {territory.name}.", "perda")
        else:
            db.add(ScoreEvent(user_id=current_owner.owner_user_id, territory_id=territory.id,
                               delta=-settings.loss_penalty_points, reason="perda"))
            notify(db, current_owner.owner_user_id, f"Você perdeu o território {territory.name}.", "perda")
            # Liga: perder território próprio é derrota — RR individual. Perda
            # de território da equipe não move RR (seria de qual membro?).
            owner = db.get(User, current_owner.owner_user_id)
            if owner is not None:
                rr = apply_trophies(db, owner, -loss_penalty(territory.relevance), "perda_territorio")
                changed, message = league_changed(rr)
                if changed:
                    notify(db, owner.id, message, "liga")

    latest_claim_at = current_owner.conquered_at if current_owner else None
    claim_time = datetime.now(timezone.utc)
    if latest_claim_at is not None:
        if latest_claim_at.tzinfo is None:
            latest_claim_at = latest_claim_at.replace(tzinfo=timezone.utc)
        claim_time = max(claim_time, latest_claim_at + timedelta(microseconds=1))
    db.add(TerritoryOwnership(
        territory_id=territory.id,
        owner_user_id=None if team else current_user.id,
        owner_team_id=team.id if team else None,
        points=points,
        conquered_at=claim_time,
    ))

    # Consome os spawns cobertos: somem para todo mundo.
    for s in covered:
        db.add(SpawnClaim(
            spawn_key=s["key"],
            territory_id=territory.id,
            claimed_at=claim_time,
        ))

    # Marca do novo dono: ritmo e distância do laço que conquistou.
    db.add(ConquestMark(
        territory_id=territory.id,
        owner_user_id=None if team else current_user.id,
        owner_team_id=team.id if team else None,
        pace_seconds_per_km=_loop_pace(distance_m, duration_seconds),
        distance_m=distance_m,
        duration_seconds=duration_seconds,
    ))

    verb = "criou e dominou" if created_new else "dominou"
    # Liga: a vitória é do usuário que correu — vale RR em conquista pessoal
    # ou de equipe. (A perda do dono anterior foi tratada acima, quando há.)
    rr = apply_trophies(db, current_user, conquest_reward(distance_m, relevance), "conquista")
    changed, message = league_changed(rr)
    if changed:
        notify(db, current_user.id, message, "liga")
    if team:
        # RN15 — pontuação vai para a equipe, não para o usuário individualmente
        db.add(ScoreEvent(team_id=team.id, territory_id=territory.id, delta=points, reason="conquista"))
        for m in db.query(TeamMember).filter(TeamMember.team_id == team.id).all():
            notify(db, m.user_id, f"Sua equipe {verb} o território {territory.name}! +{points} pontos.", "conquista")
    else:
        db.add(ScoreEvent(user_id=current_user.id, territory_id=territory.id, delta=points, reason="conquista"))
        notify(db, current_user.id, f"Você {verb} o território {territory.name}! +{points} pontos.", "conquista")

    # Torna os ScoreEvents acima visíveis para o recálculo de nível/ranking
    # abaixo, sem fechar a transação ainda.
    db.flush()

    if team:
        team_level_before = level_info(team_score_before)[0]
        team_level_after = level_info(total_team_score(db, team.id))[0]
        leveled_up = team_level_after > team_level_before
        response_level = team_level_after
        if leveled_up:  # RF11 / RN16
            for m in db.query(TeamMember).filter(TeamMember.team_id == team.id).all():
                notify(db, m.user_id, f"Sua equipe {team.name} alcançou o nível {team_level_after}!", "nivel")
    else:
        user_level_before = level_info(user_score_before)[0]
        user_level_after = level_info(total_score(db, current_user.id))[0]
        leveled_up = user_level_after > user_level_before
        response_level = user_level_after
        if leveled_up:  # RF11 / RN16
            notify(db, current_user.id, f"Você alcançou o nível {user_level_after}!", "nivel")

    # RF18 / RN11 — quem mudou de posição no ranking por causa desta conquista
    # recebe notificação (o próprio conquistador e também quem foi ultrapassado).
    ranks_after = user_rank_positions(db)
    for uid, after in ranks_after.items():
        before = ranks_before.get(uid)
        if before == after:
            continue
        if before is None:
            msg = f"Você entrou no ranking na {after}ª posição!"
        elif after < before:
            msg = f"Você subiu para a {after}ª posição no ranking!"
        else:
            msg = f"Você caiu para a {after}ª posição no ranking."
        notify(db, uid, msg, "ranking")

    db.flush()

    updated = get_territory(territory.id, db, current_user)
    result = ClaimResponse(
        territory=updated,
        created_new=created_new,
        points_awarded=points,
        area_m2=area_m2,
        new_total_score=total_team_score(db, team.id) if team else total_score(db, current_user.id),
        new_level=response_level,
        leveled_up=leveled_up,
        challenge=data.challenge,
        challenge_won=None if current_mark is None else True,
        beaten_pace_seconds_per_km=None if current_mark is None else current_mark.pace_seconds_per_km,
        beaten_distance_m=None if current_mark is None else current_mark.distance_m,
    )
    db.add(ClaimReceipt(
        user_id=current_user.id,
        request_id=data.request_id,
        payload_hash=payload_hash,
        response_json=result.model_dump_json(),
    ))
    db.flush()
    return result
