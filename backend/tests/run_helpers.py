"""Trilha de laço fechado e envio de corrida: as duas peças que todo teste do
núcleo de conquista precisa montar.

A trilha é um quadrado que volta ao ponto de partida — o mínimo que o servidor
aceita como território (RN05). O envio passa por `POST /runs`, o único caminho
que existe hoje para conquistar: a corrida é salva e a conquista vem dentro
dela, como erro legível quando não dá certo.
"""

import math
import uuid
from datetime import datetime, timedelta, timezone

LAT, LNG = -23.55, -46.63  # um bairro real não é requisito; só evita bordo de mapa

# O servidor só aceita corrida dos últimos 7 dias e nenhuma no futuro: as trilhas
# partem de dois dias atrás, e os ataques somam um dia sobre a conquista.
BASE = datetime.now(timezone.utc) - timedelta(days=2)


def square_track(step_m: float, *, walk_seconds: int, start: datetime,
                 at: tuple[float, float] = (LAT, LNG)) -> list[dict]:
    """Laço quadrado fechado de `step_m` metros de lado, em 4 vértices + volta."""
    lat, lng = at
    d_lat = step_m / 111_320
    d_lng = step_m / (111_320 * math.cos(math.radians(lat)))
    corners = [
        (lat, lng),
        (lat + d_lat, lng),
        (lat + d_lat, lng + d_lng),
        (lat, lng + d_lng),
        (lat, lng),
    ]
    leg = walk_seconds // (len(corners) - 1)
    return [
        {
            "lat": c_lat,
            "lng": c_lng,
            "timestamp": (start + timedelta(seconds=leg * i)).isoformat(),
            "segment": 0,
            "accuracy": 5.0,
        }
        for i, (c_lat, c_lng) in enumerate(corners)
    ]


def submit_run(client, headers, *, track, name, conquer=True, challenge=None,
               team_id=None, target_territory_id=None):
    """`POST /runs` já desenrolado: falha de envio é falha de teste."""
    body = {
        "id": str(uuid.uuid4()),
        "request_id": uuid.uuid4().hex,
        "name": name,
        "track": track,
        "conquer": conquer,
    }
    if challenge:
        body["challenge"] = challenge
    if team_id:
        body["team_id"] = team_id
    if target_territory_id:
        body["target_territory_id"] = target_territory_id
    response = client.post("/runs", json=body, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()
