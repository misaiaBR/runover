"""O portão do cadastro: a conta existe, mas só entra depois do código do e-mail.

Nenhum teste aqui lê caixa de correio: com `MAIL_CONSOLE_FALLBACK` (ligado no
`conftest.py`) o código vai para o log e para a resposta de cadastro, e a
entrega real pela Brevo é simulada com monkeypatch quando o teste precisa saber
qual código saiu.
"""

from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.models import EmailVerificationToken, User
from app.services.email import EmailDeliveryError
from auth_helpers import PASSWORD, register, verify

EMAIL = "novo@example.com"
USERNAME = "novorunner"


def _capture_sent_codes(monkeypatch):
    """Registra o código que cada envio levaria ao provedor."""
    sent = []
    monkeypatch.setattr(
        "app.routers.auth.send_email_verification_email",
        lambda email, username, code: sent.append((email, username, code)),
    )
    return sent


def _age_latest_token(db_session, seconds=120):
    """Passa o tempo do último código emitido: o reenvio tem janela de 60s."""
    token = db_session.query(EmailVerificationToken).order_by(
        EmailVerificationToken.created_at.desc()
    ).first()
    token.created_at = datetime.now(timezone.utc) - timedelta(seconds=seconds)
    db_session.commit()


def test_register_creates_the_account_without_a_session(client):
    created = register(client, username=USERNAME, email=EMAIL)
    assert created.status_code == 201, created.text
    body = created.json()
    assert "access_token" not in body
    assert body["requires_verification"] is True
    assert body["email"] == EMAIL
    assert body["expires_in_minutes"] == settings.email_verification_expire_minutes
    assert body["resend_after_seconds"] == settings.email_verification_cooldown_seconds
    assert body["debug_code"]


def test_the_gate_stays_shut_until_the_code_is_typed(client):
    created = register(client, username=USERNAME, email=EMAIL)

    denied = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert denied.status_code == 403
    detail = denied.json()["detail"]
    assert detail["code"] == "email_verification_required"
    assert "Confirme seu e-mail" in detail["message"]

    assert verify(client, EMAIL, created.json()["debug_code"]).status_code == 200

    allowed = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert allowed.status_code == 200, allowed.text


def test_the_app_can_tell_the_gate_apart_from_a_deactivated_account(client):
    """Os dois 403 têm saídas opostas, e só um deles traz seletor.

    A conta desativada continua com a resposta de sempre (string); quem muda é
    o portão novo, para o aplicativo saber se oferece reativar ou o código.
    """
    created = register(client, username=USERNAME, email=EMAIL)
    token = verify(client, EMAIL, created.json()["debug_code"]).json()["access_token"]
    assert client.post(
        "/users/me/deactivate", headers={"Authorization": f"Bearer {token}"}
    ).status_code == 204

    deactivated = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert deactivated.status_code == 403
    assert deactivated.json()["detail"] == "Esta conta está desativada. Reative-a para continuar."


def test_wrong_password_stays_generic_before_the_gate(client):
    """A senha errada continua dizendo apenas 'e-mail ou senha incorretos'.

    Se o portão respondesse primeiro, a resposta viraria um catálogo de quais
    endereços têm conta aqui.
    """
    register(client, username=USERNAME, email=EMAIL)
    for email in (EMAIL, "ninguem@example.com"):
        response = client.post("/auth/login", json={"email": email, "password": "senha-errada-1"})
        assert response.status_code == 401
        assert response.json()["detail"] == "E-mail ou senha incorretos."


def test_the_code_is_single_use(client):
    created = register(client, username=USERNAME, email=EMAIL)
    code = created.json()["debug_code"]

    assert verify(client, EMAIL, code).status_code == 200
    again = verify(client, EMAIL, code)
    assert again.status_code == 400
    assert "já está confirmada" in again.json()["detail"]


def test_a_bad_code_is_refused_and_five_of_them_burn_the_real_one(client, db_session):
    created = register(client, username=USERNAME, email=EMAIL)
    code = created.json()["debug_code"]

    for guess in ("000000000000", "111111111111", "222222222222", "333333333333"):
        wrong = verify(client, EMAIL, guess)
        assert wrong.status_code == 400
        assert "inválido, expirado ou já utilizado" in wrong.json()["detail"]

    # Quatro erros ainda deixam o código verdadeiro de pé.
    assert verify(client, EMAIL, code).status_code == 200

    register(client, username="terceira", email="terceira@example.com")
    for _attempt in range(5):
        assert verify(client, "terceira@example.com", "999999999999").status_code == 400
    pending = db_session.query(EmailVerificationToken).filter(
        EmailVerificationToken.used_at.is_(None)
    ).join(User).filter(User.username == "terceira").count()
    assert pending == 0, "cinco erros queimam o código pendente"


def test_an_expired_code_is_refused(client, db_session):
    created = register(client, username=USERNAME, email=EMAIL)
    code = created.json()["debug_code"]
    token = db_session.query(EmailVerificationToken).one()
    token.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db_session.commit()

    expired = verify(client, EMAIL, code)
    assert expired.status_code == 400
    assert "expirado" in expired.json()["detail"]


def test_resend_replaces_the_previous_code(client, db_session, monkeypatch):
    sent = _capture_sent_codes(monkeypatch)
    register(client, username=USERNAME, email=EMAIL)
    first_code = sent[0][2]

    _age_latest_token(db_session)
    resent = client.post("/auth/resend-verification", json={"email": EMAIL})
    assert resent.status_code == 200
    assert "Verifique também o spam" in resent.json()["message"]
    assert resent.json()["resend_after_seconds"] == settings.email_verification_cooldown_seconds
    assert len(sent) == 2
    second_code = sent[1][2]
    assert second_code != first_code

    assert verify(client, EMAIL, first_code).status_code == 400
    assert verify(client, EMAIL, second_code).status_code == 200


def test_resend_waits_for_the_cooldown(client, db_session, monkeypatch):
    """O reenvio imediato não gasta um segundo e-mail."""
    sent = _capture_sent_codes(monkeypatch)
    register(client, username=USERNAME, email=EMAIL)

    blocked = client.post("/auth/resend-verification", json={"email": EMAIL})
    assert blocked.status_code == 200
    assert len(sent) == 1

    _age_latest_token(db_session)
    client.post("/auth/resend-verification", json={"email": EMAIL})
    assert len(sent) == 2

    # A janela de 60s vale a partir do último envio, não só do cadastro.
    client.post("/auth/resend-verification", json={"email": EMAIL})
    assert len(sent) == 2


def test_resend_does_not_confirm_anything_about_the_address(client, db_session, monkeypatch):
    """Desconhecido e já confirmado recebem literalmente a mesma resposta."""
    sent = _capture_sent_codes(monkeypatch)
    unknown = client.post("/auth/resend-verification", json={"email": "ninguem@example.com"})

    register(client, username=USERNAME, email=EMAIL)
    assert verify(client, EMAIL, sent[0][2]).status_code == 200
    # Fora da janela de reenvio: o único motivo para não enviar é já estar confirmado.
    _age_latest_token(db_session)
    confirmed = client.post("/auth/resend-verification", json={"email": EMAIL})

    assert unknown.json() == confirmed.json()
    assert len(sent) == 1, "só o cadastro enviou algo"


def test_a_resend_that_cannot_be_delivered_still_stays_generic(
    client, db_session, monkeypatch
):
    """Se o provedor cair no meio do reenvio, a resposta não pode virar dedo-duro.

    Sem o modo de console, a entrega levanta 503. No cadastro isso é intencional
    (é melhor falhar do que deixar alguém de fora do próprio e-mail), mas no
    reenvio o 503 diria "esta conta existe e espera código". O rollback ainda
    deixa o código que a pessoa já recebeu em pé.
    """

    def fail_delivery(email, username, code):
        raise EmailDeliveryError("provedor fora do ar")

    created = register(client, username=USERNAME, email=EMAIL)
    code = created.json()["debug_code"]
    monkeypatch.setattr(settings, "mail_console_fallback", False)
    monkeypatch.setattr(
        "app.routers.auth.send_email_verification_email", fail_delivery
    )

    _age_latest_token(db_session)
    pending = client.post("/auth/resend-verification", json={"email": EMAIL})
    unknown = client.post(
        "/auth/resend-verification", json={"email": "ninguem@example.com"}
    )

    assert pending.status_code == 200, pending.text
    assert pending.json() == unknown.json()
    assert verify(client, EMAIL, code).status_code == 200, "o código antigo continua válido"


def test_the_mailbox_is_case_insensitive(client):
    """`NOVO@EXAMPLE.COM` e `novo@example.com` são a mesma caixa de correio."""
    created = register(client, username=USERNAME, email="NOVO@EXAMPLE.COM")
    assert created.status_code == 201, created.text
    assert created.json()["email"] == EMAIL

    denied = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert denied.status_code == 403
    confirmed = verify(client, "novo@Example.com", created.json()["debug_code"])
    assert confirmed.status_code == 200, confirmed.text


def test_a_plus_tag_does_not_open_a_second_mailbox(client):
    """`novo+r1@` e `novo+r2@` são a mesma caixa, e o portão trata como uma só.

    Sem cortar a etiqueta, criar contas em série é trocar um sufixo no fim do
    nome: cada conta recebe o próprio código no mesmo endereço e passa pelo
    portão de novo, quantas vezes a pessoa quiser.
    """
    created = register(client, username=USERNAME, email="novo+r1@example.com")
    assert created.status_code == 201, created.text
    assert created.json()["email"] == EMAIL

    dup = register(client, username="outro", email="novo+r2@example.com")
    assert dup.status_code == 400
    assert "Já existe uma conta com esse e-mail." in dup.json()["detail"]

    # Quem se cadastrou com a etiqueta entra com ela ou sem ela.
    denied = client.post(
        "/auth/login", json={"email": "novo+r1@example.com", "password": PASSWORD}
    )
    assert denied.status_code == 403
    assert denied.json()["detail"]["code"] == "email_verification_required"
    assert verify(client, "novo+r1@example.com", created.json()["debug_code"]).status_code == 200

    logged = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert logged.status_code == 200, logged.text


def test_a_name_that_is_only_a_tag_is_not_mangled(client):
    """Não sobra caixa nenhuma se cortar o `+` de um nome que começa com ele."""
    created = register(client, username="estranho", email="+soetag@example.com")
    assert created.status_code == 201, created.text
    assert created.json()["email"] == "+soetag@example.com"


def test_a_second_account_on_the_same_mailbox_is_refused(client):
    register(client, username=USERNAME, email=EMAIL)
    dup = register(client, username="outro", email="NOVO@example.com")
    assert dup.status_code == 400
    assert "Já existe uma conta com esse e-mail." in dup.json()["detail"]


def test_disposable_domains_are_rejected_at_the_door(client):
    """Domínio descartável não é caixa de correio que a pessoa controla."""
    response = register(client, username="descartavel", email="gente@mailinator.com")
    assert response.status_code == 422
    messages = [item["msg"] for item in response.json()["detail"]]
    assert any("não é aceito" in message for message in messages)


def test_a_pending_account_reserves_its_username(client):
    register(client, username=USERNAME, email=EMAIL)
    dup = register(client, username=USERNAME, email="outro@example.com")
    assert dup.status_code == 400
    assert "nome de usuário já está em uso" in dup.json()["detail"]


def test_without_a_provider_no_half_account_is_left_behind(client, monkeypatch):
    """Sem provedor e sem o modo de console, nada de conta que não consegue entrar."""
    monkeypatch.setattr(settings, "brevo_api_key", "")
    monkeypatch.setattr(settings, "mail_console_fallback", False)

    broken = register(client, username=USERNAME, email=EMAIL)
    assert broken.status_code == 503
    assert "Não foi possível enviar o código" in broken.json()["detail"]

    # O cadastro falhou inteiro: nem o endereço nem o nome ficaram presos.
    ghost = client.post("/auth/login", json={"email": EMAIL, "password": PASSWORD})
    assert ghost.status_code == 401
    monkeypatch.setattr(settings, "mail_console_fallback", True)
    retry = register(client, username=USERNAME, email=EMAIL)
    assert retry.status_code == 201, retry.text


def test_finishing_a_password_reset_also_opens_the_gate(client, monkeypatch):
    """Quem recebe o código de recuperação no e-mail já provou a caixa de correio."""
    sent = []
    monkeypatch.setattr(
        "app.routers.auth.send_password_reset_email",
        lambda email, username, code: sent.append(code),
    )
    register(client, username=USERNAME, email=EMAIL)

    assert client.post("/auth/forgot-password", json={"email": EMAIL}).status_code == 200
    reset = client.post("/auth/reset-password", json={
        "email": EMAIL, "reset_code": sent[0], "new_password": "nova1234",
    })
    assert reset.status_code == 200, reset.text

    logged = client.post("/auth/login", json={"email": EMAIL, "password": "nova1234"})
    assert logged.status_code == 200, logged.text


def test_reactivating_also_demands_the_confirmed_mailbox(client, db_session):
    """Desativada sem e-mail confirmado reativa depois de confirmar, não antes.

    Só se chega a esse estado mexendo no banco — desativar exige sessão, e
    sessão exige o código — mas a ordem do portão importa: reativar não pode
    abrir o aplicativo para quem nunca provou a caixa de correio.
    """
    created = register(client, username=USERNAME, email=EMAIL)
    token = verify(client, EMAIL, created.json()["debug_code"]).json()["access_token"]
    assert client.post(
        "/users/me/deactivate", headers={"Authorization": f"Bearer {token}"}
    ).status_code == 204
    user = db_session.query(User).filter_by(email=EMAIL).one()
    user.email_verified_at = None
    db_session.commit()

    denied = client.post("/auth/reactivate", json={"email": EMAIL, "password": PASSWORD})
    assert denied.status_code == 403
    assert denied.json()["detail"]["code"] == "email_verification_required"

    db_session.expire_all()
    assert db_session.query(User).filter_by(email=EMAIL).one().is_active is False


def test_social_accounts_already_arrive_confirmed(client, db_session, monkeypatch):
    """O provedor respondeu e-mail verificado: pedir código seria atrito vazio."""
    monkeypatch.setattr(
        "app.routers.auth.verify_identity",
        lambda provider, token: {
            "subject": "google-sub-novo", "email": "social@example.com",
            "full_name": "Social Runner", "photo_url": None,
        },
    )
    entry = client.post("/auth/oauth/google", json={"id_token": "fake-token-0123456789"})
    assert entry.status_code == 200, entry.text

    user = db_session.query(User).filter_by(email="social@example.com").one()
    assert user.email_verified_at is not None
    assert db_session.query(EmailVerificationToken).count() == 0
