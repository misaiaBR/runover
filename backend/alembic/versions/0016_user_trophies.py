"""Troféus (RR) das ligas competitivas em users.

Conquistas somam RR, derrotas em desafio e perdas de território próprio
subtraem. Idempotente de propósito: o create_all continua criando o
esquema completo em bancos novos, então a revisão tolera a coluna já
existente.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0016_user_trophies"
down_revision = "0015_merge_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    if "users" in set(inspect(conn).get_table_names()):
        existing = {c["name"] for c in inspect(conn).get_columns("users")}
        if "trophies" not in existing:
            op.add_column(
                "users",
                sa.Column("trophies", sa.Integer(), nullable=False, server_default="0"),
            )


def downgrade() -> None:
    op.drop_column("users", "trophies")
