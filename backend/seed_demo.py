r"""
Popula o banco com um cenário de demonstração para testar o app pelo navegador
sem precisar sair correndo com o celular.

Uso (com o back-end rodando em http://127.0.0.1:8000):

    .\venv\Scripts\python.exe seed_demo.py

Cria 3 jogadores e uma equipe, e simula corridas (trajetos GPS) que conquistam
territórios. Depois é só abrir http://127.0.0.1:5000 e entrar com:

    e-mail: demo@runover.com     senha: demo12345    (2 territórios, nível 2+)
    e-mail: rival@runover.com    senha: demo12345    (1 território)
    e-mail: colega@runover.com   senha: demo12345    (na equipe "Os Corredores")
"""
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = "http://127.0.0.1:8000"


def call(method, path, token=None, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
    )
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def register_or_login(full_name, username, email, photo=None):
    st, body = call("POST", "/auth/register", body={
        "full_name": full_name, "username": username, "email": email,
        "password": "demo12345", "photo_url": photo, "accept_terms": True,
    })
    if st == 201:
        # Cadastro novo não devolve token: confirma o e-mail primeiro. Em
        # desenvolvimento o código vem na resposta (MAIL_CONSOLE_FALLBACK).
        code = body.get("debug_code")
        if not code:
            sys.exit(
                f"Enviamos um código para {email}. Rode a API com "
                "MAIL_CONSOLE_FALLBACK=true para popular o banco de demonstração "
                "sem caixa de correio."
            )
        st, verified = call("POST", "/auth/verify-email", body={"email": email, "code": code})
        if st != 200:
            sys.exit(f"Falha ao confirmar {email}: {verified}")
        return verified["access_token"]
    st, body = call("POST", "/auth/login", body={"email": email, "password": "demo12345"})
    if st != 200:
        sys.exit(f"Falha ao entrar como {email}: {body}")
    return body["access_token"]


def ring_track(coords, start):
    """Transforma o anel do polígono num trajeto com carimbo de tempo
    (40s entre pontos — velocidade plausível, passa na checagem anti-fraude)."""
    return [
        {"lat": c["lat"], "lng": c["lng"],
         "timestamp": (start + timedelta(seconds=i * 40)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")}
        for i, c in enumerate(coords)
    ]


def main():
    st, _ = call("GET", "/health")
    if st != 200:
        sys.exit("Back-end não respondeu em http://127.0.0.1:8000 — suba o uvicorn primeiro.")

    now = datetime.now(timezone.utc)
    demo = register_or_login("Demo da Silva", "demo", "demo@runover.com",
                             "https://i.pravatar.cc/150?img=12")
    rival = register_or_login("Rival Souza", "rival", "rival@runover.com",
                              "https://i.pravatar.cc/150?img=32")
    colega = register_or_login("Colega Lima", "colega", "colega@runover.com")

    st, terr = call("GET", "/territories", demo)
    if st != 200 or len(terr) < 5:
        sys.exit(f"Não consegui listar territórios: {terr}")

    # demo conquista dois territórios (sobe de nível, entra no ranking)
    call("POST", "/territories/claim", demo, {"track": ring_track(terr[0]["coordinates"], now)})
    call("POST", "/territories/claim", demo, {"track": ring_track(terr[3]["coordinates"], now)})

    # rival conquista um (aparece no ranking como 2º)
    call("POST", "/territories/claim", rival, {"track": ring_track(terr[1]["coordinates"], now)})

    # equipe: demo cria, colega entra, e a equipe conquista um território
    st, team = call("POST", "/teams", demo, {"name": "Os Corredores"})
    if st == 201:
        call("POST", f"/teams/{team['id']}/join", colega)
        call("POST", "/territories/claim", demo,
             {"track": ring_track(terr[2]["coordinates"], now), "team_id": team["id"]})

    st, rank = call("GET", "/ranking", demo)
    st, me = call("GET", "/users/me", demo)
    print("Cenário de demonstração criado.\n")
    print(f"  demo  -> nível {me['level']}, {me['total_score']} pts, "
          f"{me['territories_count']} territórios, {me['play_seconds']}s de jogo")
    print("  Ranking:")
    for row in rank:
        marca = "@" if row["owner_type"] == "user" else "[equipe] "
        print(f"    {row['position']}. {marca}{row['name']}  "
              f"Nv{row['level']}  {row['total_score']} pts")
    print("\nEntre no app (http://127.0.0.1:5000) com  demo@runover.com / demo12345")


if __name__ == "__main__":
    main()
