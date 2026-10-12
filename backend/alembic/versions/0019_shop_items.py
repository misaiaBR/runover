"""Add shop_items table for dynamic catalog.

Revision ID: 0019
Revises: 0018_team_lightning
Create Date: 2026-10-12 00:00:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "0019"
down_revision = "0018_team_lightning"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "shop_items",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("category", sa.String(), nullable=False),
        sa.Column("price", sa.Integer(), nullable=False, default=0),
        sa.Column("scope", sa.String(), nullable=False, default="user"),
        sa.Column("payload", sa.JSON(), nullable=False, default={}),
        sa.Column("created_at", sa.DateTime(), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("shop_items")