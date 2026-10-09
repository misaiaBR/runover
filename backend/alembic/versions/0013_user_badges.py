"""Insígnias: tabela de ganho por usuário.

Cria user_badges (uma linha por insígnia cumprida, com a data em que o
servidor a registrou). Idempotente de propósito: o create_all continua
criando o esquema completo em bancos novos, então a revisão tolera a
tabela já existente.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0013_user_badges"
down_revision = "0012_pass_runover"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    tables = set(inspect(conn).get_table_names())
    if "user_badges" not in tables:
        op.create_table(
            "user_badges",
            sa.Column("id", sa.String(), primary_key=True),
            sa.Column("user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, index=True),
            sa.Column("badge_id", sa.String(64), nullable=False, index=True),
            sa.Column("earned_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("user_id", "badge_id", name="uq_user_badge"),
        )


def downgrade() -> None:
    op.drop_table("user_badges")
