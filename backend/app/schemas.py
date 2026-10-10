import base64
import binascii
import math
import re
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator, model_validator


def _validate_password(v: str) -> str:
    # RN03 — mínimo 8 caracteres, letras e números
    if len(v) < 8 or not any(c.isalpha() for c in v) or not any(c.isdigit() for c in v):
        raise ValueError("A senha deve ter no mínimo 8 caracteres, incluindo letras e números.")
    if len(v.encode("utf-8")) > 72:
        raise ValueError("A senha deve ter no máximo 72 bytes em UTF-8.")
    return v


# ---------- Autenticação (RF01-RF04) ----------

class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2)
    username: str = Field(min_length=3, max_length=24)
    email: EmailStr
    password: str
    photo_url: str | None = None  # RF01 — foto de perfil (opcional)
    accept_terms: bool  # RF02 / RN01

    @field_validator("password")
    @classmethod
    def validate_password(cls, v: str) -> str:
        return _validate_password(v)

    @field_validator("accept_terms")
    @classmethod
    def validate_terms(cls, v: bool) -> bool:
        if not v:
            raise ValueError("É necessário aceitar os termos de uso e a política de privacidade.")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class OAuthLoginRequest(BaseModel):
    id_token: str = Field(min_length=20, max_length=8192)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr | None = None
    reset_code: str | None = Field(default=None, min_length=6, max_length=128)
    reset_token: str | None = Field(default=None, min_length=20, max_length=128)
    new_password: str

    @model_validator(mode="after")
    def validate_reset_credential(self):
        if self.reset_token is None and (self.email is None or self.reset_code is None):
            raise ValueError("Informe o e-mail e o código de recuperação.")
        return self

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        return _validate_password(v)


# ---------- Usuário / Perfil (RF05, RF17, RF19) ----------

WEEKDAYS = ("seg", "ter", "qua", "qui", "sex", "sab", "dom")
ACTIVITY_LEVELS = ("iniciante", "baixo_impacto", "moderado", "cardio")


def validate_image_data_uri(value: str | None) -> str | None:
    """Foto em data URI (JPG/PNG/WebP, até 400 KB), ou URL/nulo."""
    if value is None or not value.startswith("data:"):
        return value
    match = re.fullmatch(
        r"data:(image/(?:jpeg|png|webp));base64,([A-Za-z0-9+/]*={0,2})",
        value,
    )
    if not match:
        raise ValueError("A foto deve ser JPG, PNG ou WebP válida.")
    try:
        content = base64.b64decode(match.group(2), validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("A foto enviada não é válida.") from exc
    if not content or len(content) > 400 * 1024:
        raise ValueError("A foto deve ter no máximo 400 KB.")
    mime = match.group(1)
    if mime == "image/jpeg":
        valid_header = content.startswith(b"\xff\xd8\xff")
    elif mime == "image/png":
        valid_header = content.startswith(b"\x89PNG\r\n\x1a\n")
    else:
        valid_header = content.startswith(b"RIFF") and content[8:12] == b"WEBP"
    if not valid_header:
        raise ValueError("O conteúdo não corresponde ao formato da foto.")
    return value


# Presença: o servidor guarda a chave, o app dá nome e cor.
# "ausente" continua contando como online; "nao_incomodar" deixa passar só o
# risco de perda e os pedidos da equipe; "invisivel" some da contagem.
PRESENCE_STATES = ("disponivel", "ausente", "nao_incomodar", "invisivel")


class ProfileUpdateRequest(BaseModel):
    full_name: str | None = Field(default=None, min_length=2, max_length=120)
    username: str | None = Field(default=None, min_length=3, max_length=24)
    photo_url: str | None = Field(default=None, max_length=560_000)
    password: str | None = None
    is_public: bool | None = None
    share_activities: bool | None = None
    pronouns: str | None = Field(default=None, max_length=80)
    # Preferências de treino
    distance_units: Literal["km", "mi"] | None = None
    weekly_frequency: int | None = Field(default=None, ge=0, le=7)
    training_days: list[Literal["seg", "ter", "qua", "qui", "sex", "sab", "dom"]] | None = None
    activity_level: Literal["iniciante", "baixo_impacto", "moderado", "cardio"] | None = None
    mural_widgets: list[str] | None = None
    # Presença (o pill do perfil): só os quatro estados conhecidos passam.
    presence: Literal["disponivel", "ausente", "nao_incomodar", "invisivel"] | None = None

    @field_validator("photo_url")
    @classmethod
    def validate_photo_url(cls, value: str | None) -> str | None:
        return validate_image_data_uri(value)

    @field_validator("password")
    @classmethod
    def validate_password(cls, value):
        return _validate_password(value) if value is not None else None

    @field_validator("training_days")
    @classmethod
    def validate_training_days(cls, value):
        if value is None:
            return None
        # Remove duplicados, mantendo a ordem Seg..Dom.
        return [d for d in WEEKDAYS if d in set(value)]


# A liga vista de fora: quem olha um perfil ou o ranking precisa do emblema e
# do rótulo de outra pessoa, não do saldo de RR nem do próximo degrau dele
# (isso continua só em GET /leagues, para o dono). Definida cedo porque o
# perfil público e o ranking a incorporam; a escada fica na seção Ligas.
class LeagueBadge(BaseModel):
    league: str  # chave da liga em app/services/leagues.py
    name: str
    color: str
    shape: str  # forma desenhada no hexágono (lado do app)
    division: int | None  # None = Lenda, que não tem divisões


class UserPublic(BaseModel):
    username: str
    photo_url: str | None
    total_score: int
    territories_count: int
    rank_position: int | None
    team_name: str | None = None
    # RF11 / RN10 — progressão
    level: int
    level_progress: float  # 0..1 — fração até o próximo nível
    points_to_next_level: int
    # Cosméticos equipados (visíveis para todos)
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_effect: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None
    equipped_emoticons: list[str] = []
    # Mural: ids dos widgets que o dono exibe no perfil, em ordem.
    mural_widgets: list[str] = ["emoticons", "conquistas", "atividades", "estatisticas"]
    # Liga atual, para o emblema aparecer onde outros jogadores são listados.
    league: LeagueBadge


class UserProfile(UserPublic):
    id: str
    full_name: str
    email: str
    created_at: datetime
    is_public: bool  # RF05
    share_activities: bool = True
    pronouns: str | None = None
    # Presença escolhida por quem corre. Só no próprio perfil: o pill do
    # cabeçalho é uma preferência, não um dado público.
    presence: str = "disponivel"
    # Ponto verde do avatar: sinal vivo (batimento do app ou GPS) dentro da
    # janela, e falso para quem está "invisivel".
    online: bool = False
    coin_balance: int = 0
    equipped_cosmetics: list[str] = []
    play_seconds: int  # RF19 — tempo de jogo
    coins_balance: int = 0
    # Preferências de treino (privadas: só no próprio perfil)
    distance_units: str = "km"
    weekly_frequency: int | None = None
    training_days: list[str] = []
    activity_level: str | None = None


# ---------- Equipes (RF16, RN14, RN15) ----------

class TeamCreateRequest(BaseModel):
    name: str = Field(min_length=2, max_length=40)


JOIN_MODES = ("approval", "open", "invite_only")


class TeamUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=40)
    photo_url: str | None = Field(default=None, max_length=560_000)
    join_mode: str | None = None
    listed: bool | None = None
    notify_risk: bool | None = None
    notify_requests: bool | None = None

    @field_validator("photo_url")
    @classmethod
    def validate_photo_url(cls, value: str | None) -> str | None:
        return validate_image_data_uri(value)


class TeamAdminRequest(BaseModel):
    username: str = Field(min_length=3, max_length=24)


class TeamLeaveRequest(BaseModel):
    """Saída da equipe: o dono com membros escolhe o sucessor ou dissolve.

    Membro comum e dono sozinho ignoram o corpo. Sem sucessor nem
    dissolução, a saída do dono com membros é recusada (409).
    """

    successor_username: str | None = Field(default=None, min_length=3, max_length=24)
    dissolve: bool = False


class TeamMemberInfo(BaseModel):
    username: str
    photo_url: str | None
    is_admin: bool = False
    # Sinal de atividade dentro da janela, descontando quem está "invisivel".
    is_online: bool = False


class TeamJoinRequestEntry(BaseModel):
    id: str
    username: str
    photo_url: str | None
    created_at: datetime


class TeamInviteRequest(BaseModel):
    """Convite pelo @usuário: quem recebe decide, não o admin."""

    username: str = Field(min_length=3, max_length=24)


class TeamInvitationEntry(BaseModel):
    id: str
    team_id: str
    team_name: str
    invited_by_username: str | None
    created_at: datetime


class TeamTerritoryEntry(BaseModel):
    """Uma zona acesa na base da equipe: um território em posse da equipe.

    A base não tem regra própria — ela é a leitura das conquistas reais, na
    ordem em que aconteceram.
    """

    name: str
    points: int
    conquered_at: datetime


class TeamLevelStop(BaseModel):
    """Uma parada da trilha de nível da equipe."""

    level: int
    points_required: int
    zone_capacity: int
    reached: bool


class TeamSummary(BaseModel):
    id: str
    name: str
    photo_url: str | None = None
    creator_username: str
    member_count: int
    territories_count: int = 0
    created_at: datetime | None = None
    # Cosméticos da loja visíveis na lista e no ranking.
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None


class TeamDetail(TeamSummary):
    members: list[TeamMemberInfo]
    total_score: int
    territories_count: int
    # As zonas conquistadas em ordem de conquista: a primeira é a célula
    # central da base e cada conquista seguinte acende a próxima.
    territories: list[TeamTerritoryEntry] = []
    # Quantas células a base tem no nível atual — quem desenha decide o layout,
    # o servidor decide o número.
    zone_capacity: int
    # A trilha inteira que a equipe percorre, do nível 1 para cima.
    level_trail: list[TeamLevelStop] = []
    # RF11 / RN10 — progressão da equipe (mesma curva do jogador)
    level: int
    level_progress: float
    points_to_next_level: int
    # Ajustes da equipe (tela de configurações): quem pode entrar,
    # visibilidade na descoberta, avisos e token de convite (só admins).
    join_mode: str = "approval"
    listed: bool = True
    notify_risk: bool = True
    notify_requests: bool = True
    invite_token: str | None = None
    # Visão de quem consulta: poder e pendências.
    is_owner: bool = False
    is_admin: bool = False
    my_request: str | None = None  # "pending" quando pedi e aguardo
    pending_requests: list[TeamJoinRequestEntry] = []
    # Membros com ping de localização recente (últimos 15 min).
    online_count: int = 0
    # Loja da equipe: cofre (soma dos pontos dos integrantes − já gasto)
    # e cosméticos equipados (itens de escopo "team").
    team_balance: int = 0
    team_spent: int = 0
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_effect: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None


class TeamWallet(BaseModel):
    """Cofre da equipe: soma dos pontos dos integrantes menos o já gasto."""

    balance: int
    spent_points: int
    members_points: int


class TeamInventory(BaseModel):
    """Itens de escopo "team" comprados + equipados."""

    owned: list[str]
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_effect: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None


# ---------- Territórios (RF06-RF09) ----------

class LatLng(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)


class TrackPoint(LatLng):
    timestamp: datetime
    segment: int = Field(default=0, ge=0, le=1000)
    # Incerteza do GNSS em metros, quando o aparelho reporta. É ela que define
    # o quão perto do ponto de partida ainda conta como laço fechado.
    accuracy: float | None = Field(default=None, ge=0, le=1000)

    @field_validator("timestamp")
    @classmethod
    def timezone_required(cls, value):
        if value.tzinfo is None:
            raise ValueError("Informe o fuso horário de cada ponto GPS.")
        return value.astimezone(timezone.utc)

    @field_validator("accuracy", mode="before")
    @classmethod
    def accuracy_must_be_finite(cls, value):
        # Uma leitura quebrada não pode custar a corrida: sem incerteza válida,
        # o fechamento do laço volta ao piso fixo.
        if isinstance(value, float) and not math.isfinite(value):
            return None
        return value


class TerritorySummary(BaseModel):
    id: str
    name: str
    coordinates: list[LatLng]  # anel externo do polígono, para desenhar no mapa
    center: LatLng
    radius_m: float
    status: str  # "disponivel" | "conquistado"
    owner_type: str | None  # "user" | "team"
    owner_display: str | None  # apelido do usuário ou nome da equipe dona
    takeovers: int = 0  # quantas vezes o território trocou de dono


class OwnerHistoryEntry(BaseModel):
    owner_type: str  # "user" | "team"
    owner_display: str
    conquered_at: datetime


class TerritoryDetail(TerritorySummary):
    conquered_at: datetime | None
    points_value: int
    history: list[OwnerHistoryEntry] = Field(default_factory=list)  # donos anteriores, do mais recente ao mais antigo
    # Marcas a bater — ritmo e distância do laço que conquistou
    owner_pace_seconds_per_km: int | None = None
    owner_distance_m: float | None = None
    owner_duration_seconds: int | None = None


class WildSpawn(BaseModel):
    """Território selvagem estilo Pokémon GO: aparece sozinho no mapa."""

    key: str
    center: LatLng
    radius_m: float
    relevance: int
    rarity: str  # "comum" | "raro" | "épico"
    spawned_at: datetime
    expires_at: datetime


class ClaimRequest(BaseModel):
    # Mecânica de laço fechado: o trajeto inteiro, do início ao fim — precisa
    # fechar um laço (RN05) pra virar ou retomar um território.
    track: list[TrackPoint] = Field(min_length=2, max_length=10000)
    request_id: str = Field(min_length=8, max_length=80)
    team_id: str | None = None  # RN15 — se informado, o território vai para a equipe
    name: str | None = Field(default=None, max_length=80)
    # Desafio de retomada: "pace" (ritmo) ou "distance" (distância),
    # escolhido antes de correr. Obrigatório só contra território com marca.
    challenge: str | None = None

    @field_validator("challenge")
    @classmethod
    def validate_challenge(cls, value: str | None) -> str | None:
        if value is not None and value not in ("pace", "distance"):
            raise ValueError("Desafio deve ser 'pace' (ritmo) ou 'distance' (distância).")
        return value


class ClaimResponse(BaseModel):
    territory: TerritoryDetail
    created_new: bool  # true = o laço não sobrepôs nenhum território existente
    points_awarded: int
    area_m2: float
    new_total_score: int
    new_level: int  # RF11 — nível após a conquista
    leveled_up: bool  # RF11 / RN16 — subiu de nível nesta conquista
    # Desafios de ritmo/distância — defaults preservam recibos antigos
    challenge: str | None = None
    challenge_won: bool | None = None  # None = território novo, sem desafio
    beaten_pace_seconds_per_km: int | None = None
    beaten_distance_m: float | None = None


# ---------- Geolocalização (RF14 / RNF20) ----------

class LocationPingRequest(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)


# ---------- Ranking e histórico (RF12, RF13) ----------

class RankingEntry(BaseModel):
    position: int
    owner_type: str  # "user" | "team"
    name: str
    photo_url: str | None
    total_score: int
    territories_count: int
    level: int  # RF11 / RN10
    # Liga do corredor; equipes não têm troféus, então não têm emblema.
    league: LeagueBadge | None = None
    # Cosméticos equipados na loja (refletem no ranking e nas telas).
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_effect: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None


class HistoryEntry(BaseModel):
    territory_name: str | None
    delta: int
    reason: str
    created_at: datetime


# ---------- Notificações (RF18, RN16) ----------

class NotificationEntry(BaseModel):
    id: str
    message: str
    type: str
    is_read: bool
    created_at: datetime


class RunRequest(ClaimRequest):
    id: UUID
    conquer: bool = False
    utc_offset_minutes: int = Field(default=0, ge=-720, le=840)


class RunSummary(BaseModel):
    id: str
    name: str
    started_at: datetime
    distance_m: float
    duration_seconds: int
    pace_seconds_per_km: int | None
    claim: ClaimResponse | None
    claim_error: str | None
    coins_earned: int | None = None


class RunDetail(RunSummary):
    track: list[TrackPoint]


class RunProgressGoal(BaseModel):
    name: str
    value: int | float
    target: int
    unit: str


class RunProgressBadge(BaseModel):
    name: str
    earned: bool


class RunTeamContributor(BaseModel):
    username: str
    distance_km: float


class RunTeamProgress(BaseModel):
    name: str
    target_km: int
    distance_km: float
    contributors: list[RunTeamContributor]


class RunProgress(BaseModel):
    week_start: datetime
    runs_count: int
    distance_km: float
    longest_run_km: float
    streak_days: int = 0
    goals: list[RunProgressGoal]
    badges: list[RunProgressBadge]
    team: RunTeamProgress | None


# ---------- Pass Runover (temporada mensal movida a XP) ----------

class PassClaimRequest(BaseModel):
    tier: int = Field(ge=1, le=30)
    track: Literal["free", "premium"] = "free"


class PassReward(BaseModel):
    coins: int
    item_id: str | None = None
    claimed: bool = False


class PassTier(BaseModel):
    tier: int
    threshold: int
    unlocked: bool
    free: PassReward
    premium: PassReward


class PassStatus(BaseModel):
    season_id: str
    ends_at: datetime
    seasonal_points: int
    unlocked_tier: int
    premium_unlocked: bool
    premium_price_coins: int
    tiers: list[PassTier]


# ---------- Mercado interno (moedas + cosméticos) ----------

# Widgets que o dono pode exibir no mural do perfil, em qualquer ordem.
MURAL_WIDGETS = ("emoticons", "conquistas", "atividades", "estatisticas", "cosmeticos")

class ShopItem(BaseModel):
    id: str
    category: str
    name: str
    price: int
    scope: str = "user"  # "user" | "team" (loja da equipe, preços altos)
    payload: dict


class WalletEntry(BaseModel):
    delta: int
    reason: str
    created_at: datetime


class Wallet(BaseModel):
    balance: int
    transactions: list[WalletEntry]


class Inventory(BaseModel):
    owned: list[str]
    equipped_avatar: str | None = None
    equipped_frame: str | None = None
    equipped_effect: str | None = None
    equipped_banner: str | None = None
    equipped_name_style: str | None = None
    equipped_emoticons: list[str] = []


class PurchaseRequest(BaseModel):
    item_id: str


class EquipRequest(BaseModel):
    category: str
    item_id: str | None = None


# ---------- Insígnias (as conquistas publicadas no mural) ----------

class Badge(BaseModel):
    id: str
    name: str
    description: str
    icon: str
    category: str  # chave do grupo em app/services/badges.py (o app dá nome e cor)
    metric: str  # chave da métrica em app/services/badges.py
    threshold: float
    progress: float  # valor atual da métrica, para "3 de 10"
    earned: bool
    earned_at: datetime | None = None


# ---------- Ligas (troféus competitivos por desempenho) ----------


class LeagueNext(BaseModel):
    league: str  # chave da liga em app/services/leagues.py
    name: str
    division: int | None  # None quando o próximo degrau é a Lenda


class LeagueStatus(BaseModel):
    trophies: int  # RR acumulado (piso em 0)
    league: str
    name: str
    color: str  # cor oficial da liga, para o ícone
    division: int | None  # None = Lenda, que não tem divisões
    rr: int  # RR dentro da divisão atual
    rr_to_next: int | None  # RR que falta para o próximo degrau
    next: LeagueNext | None  # None quando já é a Lenda


class LeagueTier(BaseModel):
    division: int | None  # None = Lenda não tem divisões
    at: int  # RR necessário para estar neste degrau


class LeagueEntry(BaseModel):
    key: str
    name: str
    color: str
    shape: str  # forma desenhada no hexágono (lado do app)
    tiers: list[LeagueTier]


class LeaguesResponse(BaseModel):
    me: LeagueStatus
    ladder: list[LeagueEntry]

