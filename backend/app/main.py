import logging
import math
import os
import random
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.database import SessionLocal, initialize_database
from app.geometry import polygon_to_geojson
from app.legal import privacy_response
from app.h3cells import cell_for
from app.models import Territory
from app.routers import (
    auth, badges, location, notifications, ranking, shop, teams, territories,
    users, runs, pass_runover,
)

initialize_database()

if not (settings.smtp2go_api_key and settings.mail_from_email):
    # Diagnóstico de "não recebi o código": sem essas variáveis o
    # forgot-password gera o código mas nenhum e-mail sai.
    logging.getLogger(__name__).warning(
        "Password reset email is not configured "
        "(SMTP2GO_API_KEY/MAIL_FROM_EMAIL); reset codes will be "
        "generated but never delivered."
    )


def _irregular_polygon(
    center_lat: float,
    center_lng: float,
    base_radius_m: float,
    *,
    seed: str,
    vertices: int = 8,
) -> list[tuple[float, float]]:
    """Polígono orgânico ao redor de um ponto — visual do protótipo do RF06
    usa áreas com contorno irregular (tipo Ingress), não quadrados perfeitos."""
    rng = random.Random(seed)
    m_per_deg_lat = 111_320
    m_per_deg_lng = 111_320 * 0.92  # ajuste grosseiro de latitude ~-23.6°

    points: list[tuple[float, float]] = []
    angle = 0.0
    for _ in range(vertices):
        angle += (360 / vertices) * rng.uniform(0.7, 1.3)
        r = base_radius_m * rng.uniform(0.55, 1.15)
        rad = math.radians(angle)
        d_lat = (r * math.cos(rad)) / m_per_deg_lat
        d_lng = (r * math.sin(rad)) / m_per_deg_lng
        points.append((center_lat + d_lat, center_lng + d_lng))
    return points


def seed_territories() -> None:
    db = SessionLocal()
    try:
        if db.query(Territory).count() > 0:
            return

        # Embu das Artes (pesquisa de campo do TCC) + Parque Ibirapuera (protótipo original)
        # (nome, lat, lng, raio de conquista em metros, relevância — RN09)
        samples = [
            ("Largo 21 de Abril", -23.6489, -46.8523, 80, 1),
            ("Feira de Artesanato", -23.6503, -46.8541, 70, 1),
            ("Praça da Matriz", -23.6522, -46.8517, 60, 1),
            ("Pq. Ibirapuera — Portão 3", -23.5874, -46.6576, 90, 2),
            ("Pq. Ibirapuera — Marquise", -23.5889, -46.6600, 100, 2),
            ("Jardim Luzitânia", -23.5920, -46.6555, 65, 1),
        ]
        for name, lat, lng, radius, relevance in samples:
            coords = _irregular_polygon(lat, lng, radius, seed=name)
            db.add(Territory(
                name=name,
                geojson=polygon_to_geojson(coords),
                radius_m=radius,
                relevance=relevance,
                center_lat=lat,
                center_lng=lng,
                h3_cell=cell_for(lat, lng),
            ))
        db.commit()
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    seed_territories()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

cors_origins = [
    origin.strip()
    for origin in settings.cors_allowed_origins.split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(badges.router)
app.include_router(shop.router)
app.include_router(pass_runover.router)
app.include_router(teams.router)
app.include_router(territories.router)
app.include_router(ranking.router)
app.include_router(shop.router)
app.include_router(notifications.router)
app.include_router(location.router)
app.include_router(runs.router)


@app.get("/health")
def health():
    return {"status": "ok", "app": settings.app_name}


@app.get("/privacidade")
def privacidade():
    return privacy_response()


web_directory = Path(
    os.environ.get("RUNOVER_WEB_DIR", str(Path(__file__).resolve().parents[1] / "static"))
)
if (web_directory / "index.html").is_file():
    app.mount("/", StaticFiles(directory=web_directory, html=True), name="web")
