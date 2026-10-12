"""Cadastro com e-mail confirmado: o caminho que toda conta nova percorre.

Desde o portão de confirmação, `POST /auth/register` não devolve token — a
conta entra depois de digitar o código que foi para o e-mail. Teste que só
precisa de um usuário autenticado chama `auth_headers`; teste do próprio portão
usa as peças separadas para afirmar sobre cada passo.

O código vem na resposta (`debug_code`) porque os módulos de teste ligam
`MAIL_CONSOLE_FALLBACK`: sem essa chave, nenhum teste dependeria de caixa de
correio — nem de rede.
"""

PASSWORD = 'Password123'


def register(client, *, username, email, full_name='Test User', password=PASSWORD):
    """POST /auth/register cru: devolve a resposta para o teste afirmar."""
    return client.post('/auth/register', json={
        'full_name': full_name, 'username': username,
        'email': email, 'password': password, 'accept_terms': True,
    })


def verify(client, email, code):
    """POST /auth/verify-email cru, pelo mesmo motivo."""
    return client.post('/auth/verify-email', json={'email': email, 'code': code})


def create_verified_user(client, *, username, email, full_name='Test User', password=PASSWORD):
    """Cria a conta, confirma o endereço e devolve o token de acesso."""
    created = register(client, username=username, email=email,
                       full_name=full_name, password=password)
    assert created.status_code == 201, created.text
    confirmed = verify(client, email, created.json()['debug_code'])
    assert confirmed.status_code == 200, confirmed.text
    return confirmed.json()['access_token']


def auth_headers(client, *, username, email, full_name='Test User', password=PASSWORD):
    """`create_verified_user` já em formato de cabeçalho Authorization."""
    token = create_verified_user(client, username=username, email=email,
                                 full_name=full_name, password=password)
    return {'Authorization': f'Bearer {token}'}
