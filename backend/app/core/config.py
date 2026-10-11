from pydantic import Field
from pydantic_settings import BaseSettings


def normalize_database_url(url: str) -> str:
    """Render/Heroku entregam a URL como "postgres://...". O SQLAlchemy 2.x
    precisa de "postgresql+psycopg://" para usar o driver psycopg 3."""
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


class Settings(BaseSettings):
    app_name: str = "RUNOVER! API"
    secret_key: str = Field(
        default="dev-secret-troque-em-producao-runover-2026",
        min_length=32,
    )
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 dias, conveniente para o protótipo
    database_url: str = "sqlite:///./runover.db"

    reset_token_minutes: int = 15
    mail_backend: str = "disabled"  # disabled | smtp | gmail
    mail_from: str = ""
    smtp_host: str = "127.0.0.1"
    smtp_port: int = 1025
    smtp_starttls: bool = True
    smtp_username: str = ""
    smtp_password: str = ""
    gmail_client_id: str = ""
    gmail_client_secret: str = ""
    gmail_refresh_token: str = ""
    brevo_api_key: str = ""
    mail_from_email: str = ""
    mail_from_name: str = "RUNOVER!"
    password_reset_expire_minutes: int = 30
    password_reset_cooldown_seconds: int = 60
    public_app_url: str = ""
    api_timeout_seconds: float = 15.0

    # OAuth client IDs accepted by the API, comma-separated.
    google_oauth_client_ids: str = ""
    cors_allowed_origins: str = "https://runover.onrender.com"

    # RNF17 / RN18 — anti-fraude de geolocalização
    max_plausible_speed_mps: float = 8.3          # ~30 km/h, generoso para corrida/sprint

    # RN05 — mecânica de laço fechado: fechar o próprio trajeto forma o território
    # O fechamento acompanha a incerteza dos dois pontos extremos: 30 m fixos
    # eram menores que a acurácia que o próprio app aceita (50 m), e nenhum laço
    # medido no pulso fechava.
    closed_loop_tolerance_m: float = 30.0         # piso, sem acurácia reportada
    max_closed_loop_tolerance_m: float = 120.0    # teto, por pior que seja o sinal
    # Uma pausa preserva o laço se a retomada for onde você parou. Acima disso o
    # deslocamento vira aresta do traçado e a área deixa a ser sua corrida.
    max_pause_gap_m: float = 100.0
    min_track_points: int = 4
    min_loop_area_m2: float = 100.0
    max_loop_area_m2: float = 25_000_000
    min_overlap_ratio: float = 0.35         # % do território existente que o novo laço precisa cobrir pra retomá-lo

    # RN09 — pontuação (por área do território conquistado/criado)
    base_conquest_points: int = 50
    points_per_m2: float = 0.01             # bônus de pontos proporcional à área do laço
    loss_penalty_points: int = 30

    # RF11 / RN10 — progressão: o nível sai da pontuação acumulada.
    # O custo de cada nível cresce de forma triangular: subir para o nível N
    # exige `level_step_points * (N-1)` pontos a mais que o nível anterior.
    # Ex. (step=150): N2=150, N3=450, N4=900, N5=1500 pontos acumulados.
    level_step_points: int = 150


settings = Settings()
