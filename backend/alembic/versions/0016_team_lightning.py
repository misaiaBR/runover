"""Dominacao Relampago: sessoes curtas da equipe e corredor na posse.

Cria lightning_sessions + lightning_participants e adiciona
territory_ownership.runner_user_id (quem correu o laco — nulo em linhas
antigas). Idempotente de proposito: o create_all continua criando o esquema
completo em bancos novos, entao a revisao tolera tabela/coluna ja existentes.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0016_team_lightning"
down_revision = "0015_merge_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    tables = set(inspect(conn).get_table_names())
    if "lightning_sessions" not in tables:
        op.create_table(
            "lightning_sessions",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("team_id", sa.String(), sa.ForeignKey("teams.id"), nullable=False, index=True),
            sa.Column("created_by", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("duration_min", sa.Integer(), nullable=False),
            sa.Column("starts_at", sa.DateTime(), nullable=True),
            sa.Column("ends_at", sa.DateTime(), nullable=False),
            sa.Column("finalized", sa.Boolean(), nullable=True),
            sa.Column("bonus_points", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )
    if "lightning_participants" not in tables:
        op.create_table(
            "lightning_participants",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("session_id", sa.String(), sa.ForeignKey("lightning_sessions.id"), nullable=False, index=True),
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("joined_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("session_id", "user_id", name="uq_lightning_entry"),
        )
    columns = (
        {c["name"] for c in inspect(conn).get_columns("territory_ownership")}
        if "territory_ownership" in tables
        else set()
    )
    if "territory_ownership" in tables and "runner_user_id" not in columns:
        op.add_column(
            "territory_ownership",
            sa.Column("runner_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        )


def downgrade() -> None:
    op.drop_column("territory_ownership", "runner_user_id")
    op.drop_table("lightning_participants")
    op.drop_table("lightning_sessions")
