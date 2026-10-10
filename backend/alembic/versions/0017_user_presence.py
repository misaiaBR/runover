"""Presença do corredor em users: o estado escolhido e o último batimento.

"disponivel" é o padrão de quem nunca mudou o estado; last_seen_at nasce vazio e
só é escrito por POST /presence. A revisão é idempotente de propósito, como a
anterior: o create_all já monta o esquema completo em bancos novos, então ela
tolera as colunas já existentes.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0017_user_presence"
down_revision = "0016_user_trophies"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    if "users" not in set(inspect(conn).get_table_names()):
        return
    existing = {c["name"] for c in inspect(conn).get_columns("users")}
    if "presence" not in existing:
        op.add_column(
            "users",
            sa.Column(
                "presence",
                sa.String(length=16),
                nullable=False,
                server_default="disponivel",
            ),
        )
    if "last_seen_at" not in existing:
        op.add_column("users", sa.Column("last_seen_at", sa.DateTime(), nullable=True))
        op.create_index("ix_users_last_seen_at", "users", ["last_seen_at"])


def downgrade() -> None:
    op.drop_index("ix_users_last_seen_at", table_name="users")
    op.drop_column("users", "last_seen_at")
    op.drop_column("users", "presence")
