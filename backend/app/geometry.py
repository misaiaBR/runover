"""
Regras geométricas da conquista de território — mecânica de laço fechado: o
usuário sai correndo livremente e, ao fechar o próprio trajeto (voltar perto
do ponto de partida), a área formada vira ou conquista um território (RN05:
"só poderá ser conquistado se o usuário completar uma forma geográfica").

No protótipo local trocamos PostGIS por Shapely + SQLite: a lógica é a mesma,
só migra de SQL para Python quando o projeto for para produção com
PostgreSQL + PostGIS.
"""
import json
import math

from shapely.geometry import Polygon, mapping, shape

from app.core.config import settings


def polygon_to_geojson(coords: list[tuple[float, float]]) -> str:
    """coords: lista de (lat, lng). Fecha o anel automaticamente."""
    ring = [(lng, lat) for lat, lng in coords]  # GeoJSON é (lng, lat)
    if ring[0] != ring[-1]:
        ring.append(ring[0])
    return json.dumps(mapping(Polygon(ring)))


def geojson_to_polygon(geojson_text: str) -> Polygon:
    return shape(json.loads(geojson_text))


def geojson_centroid(geojson_text: str) -> tuple[float, float]:
    """Retorna (lat, lng) do centro do território."""
    c = geojson_to_polygon(geojson_text).centroid
    return c.y, c.x


def polygon_to_latlng(geojson_text: str) -> list[dict]:
    poly = geojson_to_polygon(geojson_text)
    return [{"lat": lat, "lng": lng} for lng, lat in poly.exterior.coords]


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distância em metros entre dois pontos GPS."""
    r = 6_371_000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(d_lambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(min(1.0, max(0.0, a))))


class TrackValidationError(ValueError):
    pass


def validate_track_for_fraud(points: list[tuple[float, float, float]]) -> None:
    """RNF17/RN18 — rejeita saltos de posição incompatíveis com uma corrida real.

    points: lista de (lat, lng, timestamp_epoch_seconds), em ordem.
    """
    for (lat1, lng1, t1), (lat2, lng2, t2) in zip(points, points[1:]):
        dt = t2 - t1
        if dt <= 0:
            raise TrackValidationError("Os horários do percurso devem estar em ordem crescente.")
        speed = haversine_m(lat1, lng1, lat2, lng2) / dt
        if speed > settings.max_plausible_speed_mps:
            # RNF17/RN18 — a mensagem nomeia a causa. O caso mais comum não é
            # fraude: é corrida gravada dentro de ônibus ou trem, e "verifique as
            # permissões de localização" mandava o corredor atrás de um ajuste
            # que não tinha nada a ver com o problema dele.
            raise TrackValidationError(
                "Há movimento mais rápido do que uma corrida alcança no "
                "percurso. Se você estava em veículo, a corrida não pode ser "
                "registrada; se estava a pé, o GPS falhou nesse trecho."
            )


def validate_track_by_segment(
    points: list[tuple[float, float, float]], segments: list[int]
) -> None:
    """Valida a velocidade dentro de cada trecho contíguo, não no trajeto inteiro.

    O vão entre uma pausa e a retomada não é movimento — ele já fica fora da
    distância e da duração somadas, e um buraco de GPS nesse vão derrubava a
    corrida inteira com 400 antes de ela ser salva.
    """
    for (_, _, t1), (_, _, t2) in zip(points, points[1:]):
        if t2 <= t1:
            raise TrackValidationError(
                "Os horários do percurso devem estar em ordem crescente."
            )
    start = 0
    for i in range(1, len(points) + 1):
        if i < len(points) and segments[i] == segments[start]:
            continue
        validate_track_for_fraud(points[start:i])
        start = i


def loop_closure_tolerance_m(
    accuracy_start: float | None, accuracy_end: float | None
) -> float:
    """Distância início↔fim que ainda conta como laço fechado, em metros.

    Cada ponto GPS chega com a incerteza que o aparelho mede; somar as duas
    pontas (em quadratura) é o que o fechamento realmente suporta. Sem
    acurácia reportada — app antigo ou trilha sem o campo — vale o piso.
    """
    if accuracy_start is None or accuracy_end is None:
        return settings.closed_loop_tolerance_m
    uncertainty = math.sqrt(
        max(0.0, float(accuracy_start)) ** 2 + max(0.0, float(accuracy_end)) ** 2
    )
    return min(
        settings.max_closed_loop_tolerance_m,
        max(settings.closed_loop_tolerance_m, uncertainty),
    )


def build_track_polygon(
    points: list[tuple[float, float]],
    accuracies: list[float | None] | None = None,
    segments: list[int] | None = None,
) -> Polygon:
    """RN05 — o percurso só forma um território se fechar um laço (início ≈ fim).

    `accuracies` (metros, um por ponto) deriva a tolerância do fechamento.
    `segments` marca as pausas: retomar longe de onde parou deixaria o traçado
    com uma aresta que não foi corrida, então o laço não vale.
    """
    if len(points) < settings.min_track_points:
        raise TrackValidationError(
            f"É preciso pelo menos {settings.min_track_points} pontos de GPS para fechar um território."
        )

    lat1, lng1 = points[0]
    lat2, lng2 = points[-1]
    gap = haversine_m(lat1, lng1, lat2, lng2)
    tolerance = loop_closure_tolerance_m(
        accuracies[0] if accuracies else None,
        accuracies[-1] if accuracies else None,
    )
    if gap > tolerance:
        raise TrackValidationError(
            "Percurso não fechado — volte para perto do ponto de partida para completar o "
            f"domínio (faltam ~{gap - tolerance:.0f}m)."
        )

    if segments is not None:
        for (p1, s1), (p2, s2) in zip(zip(points, segments), zip(points[1:], segments[1:])):
            if s1 == s2:
                continue
            jump = haversine_m(p1[0], p1[1], p2[0], p2[1])
            if jump > settings.max_pause_gap_m:
                raise TrackValidationError(
                    "Você retomou a corrida longe de onde parou — o território precisa "
                    f"ser um traçado contínuo (a pausa pulou ~{jump:.0f}m)."
                )

    ring = [(lng, lat) for lat, lng in points]
    ring.append(ring[0])
    poly = Polygon(ring)
    if not poly.is_valid:
        poly = poly.buffer(0)  # corrige auto-interseções leves do traçado
    if poly.is_empty or poly.geom_type != "Polygon" or not poly.is_valid:
        raise TrackValidationError("O trajeto precisa formar uma única área válida.")
    area = polygon_area_m2(poly)
    if area > settings.max_loop_area_m2:
        raise TrackValidationError(
            f"O território deve ter no máximo {settings.max_loop_area_m2 / 1_000_000:g} km²."
        )
    if area < settings.min_loop_area_m2:
        raise TrackValidationError(
            f"A área do território deve ter pelo menos {settings.min_loop_area_m2:g} m²."
        )
    return poly


def polygon_area_m2(poly: Polygon) -> float:
    """Área aproximada em m² (projeção equirretangular simples, suficiente para escala de bairro)."""
    if poly.is_empty or poly.geom_type != "Polygon":
        raise TrackValidationError("O trajeto não forma uma área válida.")
    lat0 = poly.centroid.y
    m_per_deg_lat = 111_320
    m_per_deg_lng = 111_320 * math.cos(math.radians(lat0))
    projected = Polygon([(x * m_per_deg_lng, y * m_per_deg_lat) for x, y in poly.exterior.coords])
    return abs(projected.area)


def shapely_polygon_to_geojson(poly: Polygon) -> str:
    return json.dumps(mapping(poly))


def overlap_ratio(track_polygon: Polygon, territory_polygon: Polygon) -> float:
    """Fração da área do território existente coberta pelo novo laço."""
    if territory_polygon.area == 0:
        return 0.0
    intersection = track_polygon.intersection(territory_polygon)
    return intersection.area / territory_polygon.area
