import os
import tempfile
import unittest

_tmp = tempfile.TemporaryDirectory()
os.environ['DATABASE_URL'] = 'sqlite:///' + _tmp.name + '/test.db'
os.environ['SECRET_KEY'] = 'local-test-signing-key-for-runover-tests'
os.environ['MAIL_CONSOLE_FALLBACK'] = 'true'
os.environ['BREVO_API_KEY'] = ''

from fastapi.testclient import TestClient
from app.core.database import Base, engine, initialize_database
from app.main import app
from auth_helpers import create_verified_user, register as raw_register


def _register(client, username, email):
    # Cadastro cru: o nome já é reservado antes da confirmação do e-mail,
    # então a colisão de nome continua sendo 400 mesmo sem código digitado.
    return raw_register(client, username=username, email=email)


class UsernameUniquenessTests(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_case_variants_are_rejected(self):
        first = _register(self.client, 'Misaia', 'a@example.com')
        self.assertEqual(first.status_code, 201, first.text)
        for variant in ('misaia', 'MISAIA', ' misaia '):
            dup = _register(self.client, variant, 'other@example.com')
            self.assertEqual(dup.status_code, 400, variant)
            self.assertIn('uso', dup.json()['detail'])

    def test_profile_update_rejects_case_variant(self):
        _register(self.client, 'Misaia', 'a@example.com')
        token = create_verified_user(self.client, username='colega',
                                     email='b@example.com')
        response = self.client.patch(
            '/users/me',
            json={'username': 'MISAIA'},
            headers={'Authorization': 'Bearer ' + token},
        )
        self.assertEqual(response.status_code, 400)
        # Trocar a própria caixa continua permitido.
        me = self.client.patch(
            '/users/me',
            json={'username': 'Colega'},
            headers={'Authorization': 'Bearer ' + token},
        )
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()['username'], 'Colega')


if __name__ == '__main__':
    unittest.main()
