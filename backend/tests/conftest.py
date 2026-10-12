import os

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("SECRET_KEY", "test-only-secret-key-that-is-long-enough")
# Nenhum teste depende de caixa de correio: o código de confirmação vai para a
# resposta do cadastro (auth_helpers), como no desenvolvimento local.
os.environ.setdefault("MAIL_CONSOLE_FALLBACK", "true")
# Mesmo com uma chave real no ambiente de quem roda os testes, nada sai para a
# internet: a entrega é sempre simulada (test_email_brevo) ou vai para o log.
os.environ.setdefault("BREVO_API_KEY", "")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.database import Base, get_db
from app.main import app

test_engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSession = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)


def override_get_db():
    db = TestSession()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db


@pytest.fixture(autouse=True)
def clean_database():
    Base.metadata.drop_all(bind=test_engine)
    Base.metadata.create_all(bind=test_engine)
    yield


@pytest.fixture
def client():
    # Do not enter the application lifespan: its local demo seed uses the
    # development engine, while each request is redirected to test_engine.
    yield TestClient(app)


@pytest.fixture
def db_session():
    db = TestSession()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture
def registered_user(client):
    response = client.post("/auth/register", json={
        "full_name": "Test Runner",
        "username": "testrunner",
        "email": "runner@example.com",
        "password": "original123",
        "accept_terms": True,
    })
    assert response.status_code == 201
    body = response.json()
    # A conta existe, mas não entra: o token só sai depois do código.
    assert "access_token" not in body
    confirmed = client.post("/auth/verify-email", json={
        "email": "runner@example.com",
        "code": body["debug_code"],
    })
    assert confirmed.status_code == 200, confirmed.text
    return {"token": confirmed.json()["access_token"], "email": "runner@example.com"}
