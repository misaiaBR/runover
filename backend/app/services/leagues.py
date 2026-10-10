"""Ligas competitivas: troféus (RR), escada e movimentação.

Modelo no espírito de ranked de FPS: cada conquista de território é uma
vitória que soma RR (10–50 conforme o desempenho do laço), cada desafio
perdido ou território próprio perdido subtrai uma quantia parecida. Cada
divisão pede 100 RR; a liga nunca fica abaixo de 0 (Largada 1 é o piso).

Os números deste módulo são os da temporada atual e podem ser reajustados
aqui sem migration — o app sempre lê a escada pronta do servidor.
"""

from __future__ import annotations

from sqlalchemy.orm import Session

from app.models import User

# Divisão 3 é a mais alta dentro de cada liga; a Lenda não tem divisões.
# `shape` é a forma desenhada no hexágono do ícone (lado do app).
LADDER: list[dict] = [
    {
        "key": "largada",
        "name": "Largada",
        "color": "#8A94A6",
        "shape": "circle",
        "tiers": [
            {"division": 1, "at": 0},
            {"division": 2, "at": 100},
            {"division": 3, "at": 200},
        ],
    },
    {
        "key": "trote",
        "name": "Trote",
        "color": "#D9822B",
        "shape": "triangle",
        "tiers": [
            {"division": 1, "at": 300},
            {"division": 2, "at": 400},
            {"division": 3, "at": 500},
        ],
    },
    {
        "key": "ritmo",
        "name": "Ritmo",
        "color": "#C9CFD6",
        "shape": "diamond",
        "tiers": [
            {"division": 1, "at": 600},
            {"division": 2, "at": 700},
            {"division": 3, "at": 800},
        ],
    },
    {
        "key": "podio",
        "name": "Pódio",
        "color": "#FFB020",
        "shape": "pentagon",
        "tiers": [
            {"division": 1, "at": 900},
            {"division": 2, "at": 1000},
            {"division": 3, "at": 1100},
        ],
    },
    {
        "key": "turbo",
        "name": "Turbo",
        "color": "#22D3EE",
        "shape": "hexagon",
        "tiers": [
            {"division": 1, "at": 1200},
            {"division": 2, "at": 1300},
            {"division": 3, "at": 1400},
        ],
    },
    {
        "key": "elite",
        "name": "Elite",
        "color": "#A78BFA",
        "shape": "octagon",
        "tiers": [
            {"division": 1, "at": 1500},
            {"division": 2, "at": 1600},
            {"division": 3, "at": 1700},
        ],
    },
    {
        "key": "mestre",
        "name": "Mestre",
        "color": "#34D399",
        "shape": "gem",
        "tiers": [
            {"division": 1, "at": 1800},
            {"division": 2, "at": 1900},
            {"division": 3, "at": 2000},
        ],
    },
    {
        "key": "lenda",
        "name": "Lenda",
        "color": "#F472B6",
        "shape": "star",
        "tiers": [{"division": None, "at": 2100}],
    },
]


def _flat_tiers() -> list[tuple[dict, dict]]:
    """[(liga, degrau)] na ordem crescente de RR, para comparar posições."""
    return [(league, tier) for league in LADDER for tier in league["tiers"]]


def _tier_for(trophies: int) -> tuple[dict, dict]:
    """Liga e degrau atuais: o degrau mais alto cujo limiar o saldo alcança."""
    found = _flat_tiers()[0]
    for league, tier in _flat_tiers():
        if trophies >= tier["at"]:
            found = (league, tier)
    return found


def status_for(trophies: int) -> dict:
    """Posição atual na escada + progresso para o próximo degrau."""
    league, tier = _tier_for(trophies)
    flat = _flat_tiers()
    index = flat.index((league, tier))
    if index + 1 < len(flat):
        next_league, next_tier = flat[index + 1]
        next_info = {
            "league": next_league["key"],
            "name": next_league["name"],
            "division": next_tier["division"],
        }
        rr_to_next = next_tier["at"] - trophies
    else:
        next_info = None
        rr_to_next = None
    return {
        "trophies": trophies,
        "league": league["key"],
        "name": league["name"],
        "color": league["color"],
        "division": tier["division"],
        "rr": trophies - tier["at"],
        "rr_to_next": rr_to_next,
        "next": next_info,
    }


def badge_for(trophies: int) -> dict:
    """A liga de quem é visto por fora: emblema e rótulo, nada de saldo.

    O RR e o próximo degrau só saem em GET /leagues, para o dono. Assim o
    ranking e o perfil público mostram a posição de cada corredor sem expor a
    contagem dele, e os números continuam vindo desta mesma escada.
    """
    league, tier = _tier_for(trophies)
    return {
        "league": league["key"],
        "name": league["name"],
        "color": league["color"],
        "shape": league["shape"],
        "division": tier["division"],
    }


def ladder_payload() -> list[dict]:
    """A escada completa como o app desenha (Largada → Lenda)."""
    return [
        {
            "key": league["key"],
            "name": league["name"],
            "color": league["color"],
            "shape": league["shape"],
            "tiers": [
                {"division": tier["division"], "at": tier["at"]}
                for tier in league["tiers"]
            ],
        }
        for league in LADDER
    ]


def apply_trophies(db: Session, user: User, delta: int, reason: str) -> dict:
    """Aplica o RR com piso em 0 e devolve antes/depois para notificar.

    O delta efetivo pode ser menor que o pedido no piso (perder com saldo
    baixo só desce até 0). `reason` fica para auditoria futura — por ora o
    histórico de RR é o histórico de corridas/conquistas, sem tabela nova.
    """
    del reason  # temporário: sem tabela de histórico na v1
    before = status_for(user.trophies)
    effective = max(0, user.trophies + delta) - user.trophies
    user.trophies += effective
    db.flush()
    after = status_for(user.trophies)
    return {"delta": effective, "before": before, "after": after}


def league_changed(move: dict) -> tuple[bool, str]:
    """(mudou?, mensagem em pt-BR) comparando o status antes/depois."""
    before, after = move["before"], move["after"]
    key_b, key_a = (before["league"], before["division"]), (
        after["league"],
        after["division"],
    )
    if key_b == key_a:
        return False, ""
    flat = _flat_tiers()
    pos_b = next(
        i for i, (league, tier) in enumerate(flat)
        if (league["key"], tier["division"]) == key_b
    )
    pos_a = next(
        i for i, (league, tier) in enumerate(flat)
        if (league["key"], tier["division"]) == key_a
    )
    verb = "subiu" if pos_a > pos_b else "caiu"
    if after["division"] is None:
        return True, f"Você {verb} para a liga Lenda!"
    return True, f"Você {verb} para {after['name']} {after['division']}!"


def conquest_reward(distance_m: float, relevance: int) -> int:
    """Vitória: 10 base + 1 por km corrido + 2 por relevância, teto 50."""
    km = round(distance_m / 1000)
    return min(50, 10 + km + 2 * min(relevance, 10))


def defeat_penalty(distance_m: float) -> int:
    """Desafio perdido: 10 + 1 por km da tentativa, teto 30."""
    return min(30, 10 + round(distance_m / 1000))


def loss_penalty(relevance: int) -> int:
    """Território próprio perdido: 10 + 2 por relevância dele, teto 30."""
    return min(30, 10 + 2 * min(relevance, 10))
