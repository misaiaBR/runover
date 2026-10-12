"""Confirmação de e-mail no cadastro: a coluna no usuário e a tabela de códigos.

`email_verified_at` nasce nulo para conta nova, e as contas que já existiam são
marcadas como confirmadas na mesma revisão — quem jogava antes do portão não
pode ser trancado fora do próprio aplicativo por uma coluna que não existia.

A revisão é idempotente de propósito, como as anteriores: o create_all já monta
o esquema completo em bancos novos, então ela tolera coluna e tabela já
existentes.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

revision = "0019_email_verification"
down_revision = "0018_team_lightning"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    tables = set(inspect(conn).get_table_names())
    if "users" not in tables:
        return
    existing = {c["name"] for c in inspect(conn).get_columns("users")}
    if "email_verified_at" not in existing:
        op.add_column(
            "users",
            sa.Column("email_verified_at", sa.DateTime(), nullable=True),
        )
        # Contas antigas já estavam em jogo: o portão vale para quem chega
        # depois dele.
        conn.exec_driver_sql(
            "UPDATE users SET email_verified_at = CURRENT_TIMESTAMP "
            "WHERE email_verified_at IS NULL"
        )
    if "email_verification_tokens" not in tables:
        op.create_table(
            "email_verification_tokens",
            sa.Column("id", sa.String(), nullable=False),
            sa.Column("user_id", sa.String(), nullable=False),
            sa.Column("token_hash", sa.String(), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("attempts", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("token_hash"),
        )
        op.create_index(
            "ix_email_verification_tokens_user_id",
            "email_verification_tokens",
            ["user_id"],
        )
        op.create_index(
            "ix_email_verification_tokens_expires_at",
            "email_verification_tokens",
            ["expires_at"],
        )


def downgrade() -> None:
    op.drop_index("ix_email_verification_tokens_expires_at", table_name="email_verification_tokens")
    op.drop_index("ix_email_verification_tokens_user_id", table_name="email_verification_tokens")
    op.drop_table("email_verification_tokens")
    op.drop_column("users", "email_verified_at")
