import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    full_name: Mapped[str] = mapped_column(String, nullable=False)
    username: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)  # RN02
    email: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String, nullable=False)  # RNF01
    photo_url: Mapped[str | None] = mapped_column(String, nullable=True)  # RF01 — foto de perfil
    is_public: Mapped[bool] = mapped_column(default=True)  # RF05 — configuração de privacidade / RN13
    share_activities: Mapped[bool] = mapped_column(default=True)  # Privacidade das corridas e atividades
    pronouns: Mapped[str | None] = mapped_column(String(80), nullable=True)
    # Presença: como o próprio corredor aparece. O servidor guarda a chave e o
    # app dá nome e cor. "disponivel" | "ausente" (continua contando como
    # online) | "nao_incomodar" (só o risco de perda e os pedidos da equipe
    # chegam) | "invisivel" (some da contagem de online da equipe).
    presence: Mapped[str] = mapped_column(String(16), default="disponivel")
    # Batimento do app aberto (POST /presence). É o sinal de "por aqui" de quem
    # não está correndo; o ping de GPS continua valendo enquanto corre.
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True, index=True
    )
    coin_balance: Mapped[int] = mapped_column(Integer, default=0)
    equipped_cosmetics: Mapped[str] = mapped_column(String, default="")
    daily_mission_date: Mapped[str | None] = mapped_column(String(10), nullable=True)
    daily_mission_claimed: Mapped[bool] = mapped_column(default=False)
    play_seconds: Mapped[int] = mapped_column(Integer, default=0)  # RF19 — tempo de jogo acumulado
    # Mercado interno (moedas + cosméticos).
    coins_balance: Mapped[int] = mapped_column(Integer, default=0)
    # Ligas competitivas: RR ganho em conquistas e perdido em derrotas/perdas.
    trophies: Mapped[int] = mapped_column(Integer, default=0)
    equipped_avatar: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_frame: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_effect: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_banner: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_name_style: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_emoticons: Mapped[str] = mapped_column(String(256), default="")
    # Mural: widgets que o dono escolheu exibir no perfil (csv de ids).
    mural_widgets: Mapped[str] = mapped_column(
        String(256), default="emoticons,conquistas,atividades,estatisticas"
    )
    # Preferências de treino (editáveis em PATCH /users/me)
    distance_units: Mapped[str] = mapped_column(String(2), default="km")  # "km" | "mi"
    weekly_frequency: Mapped[int | None] = mapped_column(Integer, nullable=True)  # dias/semana (1..7)
    training_days: Mapped[str] = mapped_column(String(32), default="")  # dias livres, ex. "seg,qua,sex"
    activity_level: Mapped[str | None] = mapped_column(String(24), nullable=True)
    accepted_terms_at: Mapped[datetime] = mapped_column(DateTime, default=_now)  # RN01
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    # Desativação temporária (volta com reativação; diferente de excluir)
    is_active: Mapped[bool] = mapped_column(default=True)
    deactivated_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class UserCosmetic(Base):
    __tablename__ = "user_cosmetics"
    __table_args__ = (UniqueConstraint("user_id", "item_id", name="uq_user_cosmetic"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    item_id: Mapped[str] = mapped_column(String(64), nullable=False)
    purchased_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class UserFavorite(Base):
    __tablename__ = "user_favorites"
    __table_args__ = (UniqueConstraint("user_id", "item_id", name="uq_user_favorite"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    item_id: Mapped[str] = mapped_column(String(64), nullable=False)


class OAuthIdentity(Base):
    """Verified external identity linked to a RUNOVER user."""

    __tablename__ = "oauth_identities"
    __table_args__ = (UniqueConstraint("provider", "subject", name="uq_oauth_provider_subject"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    provider: Mapped[str] = mapped_column(String(16), nullable=False)
    subject: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    user: Mapped["User"] = relationship()


class Team(Base):
    """Equipe — RF16/RN14/RN15, UC10 (Criar/Participar de equipe)."""

    __tablename__ = "teams"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String, nullable=False)
    photo_url: Mapped[str | None] = mapped_column(String, nullable=True)
    creator_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    # Loja da equipe: pontos já gastos do cofre (saldo = soma dos pontos
    # dos integrantes − spent_points; ninguém perde nível ao comprar).
    spent_points: Mapped[int] = mapped_column(Integer, default=0)
    # Cosméticos equipados da equipe (itens de escopo "team" da loja).
    equipped_avatar: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_frame: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_effect: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_banner: Mapped[str | None] = mapped_column(String(64), nullable=True)
    equipped_name_style: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Ajustes da equipe: quem pode entrar, visibilidade na descoberta,
    # avisos e convite por link (token opaco, regenerável).
    join_mode: Mapped[str] = mapped_column(String(16), default="approval", nullable=False)
    listed: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    notify_risk: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    notify_requests: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    invite_token: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True)

    creator: Mapped["User"] = relationship()
    members: Mapped[list["TeamMember"]] = relationship(back_populates="team")


class TeamMember(Base):
    __tablename__ = "team_members"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    team: Mapped["Team"] = relationship(back_populates="members")
    user: Mapped["User"] = relationship()


class TeamAdmin(Base):
    """Admins escolhidos pelo dono (criador). Dono sempre tem poder total."""

    __tablename__ = "team_admins"
    __table_args__ = (UniqueConstraint("team_id", "user_id", name="uq_team_admin"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    granted_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class TeamJoinRequest(Base):
    """Pedido de entrada: dono/admins aprovam ou recusam.

    Quando `invited_by` está preenchido o pedido nasceu de um convite: o
    convidado é quem decide, aceitando ou recusando.
    """

    __tablename__ = "team_join_requests"
    __table_args__ = (
        Index(
            "uq_team_join_pending",
            "team_id",
            "user_id",
            unique=True,
            sqlite_where=text("status = 'pending'"),
            postgresql_where=text("status = 'pending'"),
        ),
    )

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id"), nullable=False, index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    invited_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    status: Mapped[str] = mapped_column(String(16), default="pending")  # pending|approved|rejected|declined
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    team: Mapped["Team"] = relationship()
    user: Mapped["User"] = relationship(foreign_keys=[user_id])
    # `users` aparece duas vezes nesta tabela (quem pede e quem chamou),
    # então cada relacionamento precisa dizer qual chave usa.
    inviter: Mapped["User | None"] = relationship(
        foreign_keys=[invited_by],
        primaryjoin="TeamJoinRequest.invited_by == User.id",
    )


class Territory(Base):
    __tablename__ = "territories"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    name: Mapped[str] = mapped_column(String, nullable=False)
    # GeoJSON Polygon serializado como texto — ver app/geometry.py (substitui PostGIS no protótipo local)
    geojson: Mapped[str] = mapped_column(Text, nullable=False)
    radius_m: Mapped[float] = mapped_column(Float, nullable=False)  # UC11 — raio de conquista
    # Centroide em graus para o pré-filtro indexado da busca por proximidade.
    # Nulo em linhas anteriores à migração 0002 (a busca recai no geojson).
    center_lat: Mapped[float | None] = mapped_column(Float, nullable=True, index=True)
    center_lng: Mapped[float | None] = mapped_column(Float, nullable=True, index=True)
    # Célula H3 do centroide (res 9, ver app/h3cells.py) para o pré-filtro
    # indexado da busca por proximidade. Nulo em linhas anteriores à
    # migração 0003 (a busca recai na caixa delimitadora).
    h3_cell: Mapped[str | None] = mapped_column(String(15), nullable=True, index=True)
    relevance: Mapped[int] = mapped_column(Integer, default=1)  # RN09 — peso na pontuação
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)

    ownerships: Mapped[list["TerritoryOwnership"]] = relationship(
        back_populates="territory", order_by="TerritoryOwnership.conquered_at"
    )


class TerritoryOwnership(Base):
    """Cada conquista gera uma nova linha — o dono atual é a mais recente (RF13/RN12).

    Dono é um usuário OU uma equipe (RN07/RN15), nunca os dois.
    """

    __tablename__ = "territory_ownership"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    territory_id: Mapped[str] = mapped_column(ForeignKey("territories.id"), nullable=False)
    owner_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    owner_team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id"), nullable=True)
    points: Mapped[int] = mapped_column(Integer, nullable=False)  # RN09
    conquered_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)

    territory: Mapped["Territory"] = relationship(back_populates="ownerships")
    owner_user: Mapped["User | None"] = relationship()
    owner_team: Mapped["Team | None"] = relationship()


class ConquestMark(Base):
    """Marca do dono atual: ritmo e distância do laço que conquistou.

    Um rival só retoma o território vencendo o desafio escolhido —
    ritmo mais rápido ou mais distância em tempo igual ou menor.
    """

    __tablename__ = "conquest_marks"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    territory_id: Mapped[str] = mapped_column(ForeignKey("territories.id"), nullable=False, index=True)
    owner_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    owner_team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id"), nullable=True)
    pace_seconds_per_km: Mapped[int] = mapped_column(Integer, nullable=False)
    distance_m: Mapped[float] = mapped_column(Float, nullable=False)
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class SpawnClaim(Base):
    """Marca selvagem consumida: o laço que a cobriu virou território."""

    __tablename__ = "spawn_claims"
    __table_args__ = (UniqueConstraint("spawn_key", name="uq_spawn_key"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    spawn_key: Mapped[str] = mapped_column(String, nullable=False, index=True)
    territory_id: Mapped[str | None] = mapped_column(ForeignKey("territories.id"), nullable=True)
    claimed_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)


class ScoreEvent(Base):
    """Histórico de conquista/perda — RF13, RN12 (Historico no diagrama de classes)."""

    __tablename__ = "score_events"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id"), nullable=True)
    territory_id: Mapped[str | None] = mapped_column(ForeignKey("territories.id"), nullable=True)
    delta: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(String, nullable=False)  # "conquista" | "perda"
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)

    user: Mapped["User | None"] = relationship()
    team: Mapped["Team | None"] = relationship()
    territory: Mapped["Territory | None"] = relationship()


class Notification(Base):
    """RF18/RN16, UC "Receber Notificação"."""

    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    message: Mapped[str] = mapped_column(String, nullable=False)
    type: Mapped[str] = mapped_column(String, nullable=False)  # "conquista" | "perda" | "ranking"
    is_read: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)

    user: Mapped["User"] = relationship()


class LocationPing(Base):
    """Geolocalização — RF14/RNF20: histórico de posições para auditoria."""

    __tablename__ = "location_pings"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)


class MutationLock(Base):
    """One database row serializes game mutations on SQLite and PostgreSQL."""
    __tablename__ = "mutation_lock"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[int] = mapped_column(Integer, default=0)


class PasswordReset(Base):
    __tablename__ = "password_resets"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class PasswordResetToken(Base):
    __tablename__ = "password_reset_tokens"
    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    token_hash: Mapped[str] = mapped_column(String, unique=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)

    user: Mapped["User"] = relationship()


class ClaimReceipt(Base):
    __tablename__ = "claim_receipts"
    __table_args__ = (UniqueConstraint("user_id", "request_id", name="uq_claim_user_request"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    request_id: Mapped[str] = mapped_column(String, nullable=False)
    payload_hash: Mapped[str] = mapped_column(String, nullable=False)
    response_json: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, nullable=False)


class AuthAttempt(Base):
    __tablename__ = "auth_attempts"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    window_start: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    count: Mapped[int] = mapped_column(Integer, default=0)


class CoinTransaction(Base):
    """Extrato das moedinhas: todo crédito/débito passa por aqui."""

    __tablename__ = "coin_transactions"

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    delta: Mapped[int] = mapped_column(Integer, nullable=False)
    reason: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now, index=True)


class UserItem(Base):
    """Inventário: itens do mercado já comprados (um por usuário)."""

    __tablename__ = "user_items"
    __table_args__ = (UniqueConstraint("user_id", "item_id", name="uq_user_item"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    item_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class UserBadge(Base):
    """Insígnia já cumprida: guarda quando o servidor registrou o ganho.

    O catálogo (regra e limiar) versiona em `app/services/badges.py`; aqui só
    existe a linha de quem ganhou, uma vez por insígnia.
    """

    __tablename__ = "user_badges"
    __table_args__ = (UniqueConstraint("user_id", "badge_id", name="uq_user_badge"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    badge_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    earned_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class TeamItem(Base):
    """Inventário da equipe: itens de escopo "team" comprados com o cofre
    (soma dos pontos dos integrantes). Um por equipe."""

    __tablename__ = "team_items"
    __table_args__ = (UniqueConstraint("team_id", "item_id", name="uq_team_item"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    team_id: Mapped[str] = mapped_column(ForeignKey("teams.id"), nullable=False, index=True)
    item_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class PassPremium(Base):
    """Trilha premium do Pass Runover: desbloqueio único por temporada,
    pago em moedas. Sem ele, só a trilha gratuita resgata."""

    __tablename__ = "pass_premium"
    __table_args__ = (UniqueConstraint("user_id", "season_id", name="uq_pass_premium"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    season_id: Mapped[str] = mapped_column(String(7), nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class PassClaim(Base):
    """Recompensa de tier resgatada (uma por temporada/tier/trilha)."""

    __tablename__ = "pass_claims"
    __table_args__ = (UniqueConstraint("user_id", "season_id", "tier", "track", name="uq_pass_claim"),)

    id: Mapped[str] = mapped_column(String, primary_key=True, default=_uuid)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), nullable=False, index=True)
    season_id: Mapped[str] = mapped_column(String(7), nullable=False, index=True)
    tier: Mapped[int] = mapped_column(Integer, nullable=False)
    track: Mapped[str] = mapped_column(String(16), nullable=False)  # "free" | "premium"
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)


class Run(Base):
    __tablename__ = "runs"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    team_id: Mapped[str | None] = mapped_column(ForeignKey("teams.id"), nullable=True, index=True)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    track_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    track_json: Mapped[str] = mapped_column(Text, nullable=False)
    started_at: Mapped[datetime] = mapped_column(DateTime, index=True)
    ended_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    distance_m: Mapped[float] = mapped_column(Float, nullable=False)
    duration_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    result_json: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_now)
