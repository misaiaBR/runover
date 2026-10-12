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
from auth_helpers import auth_headers


class DataExportTests(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()
        self.headers = auth_headers(
            self.client, username='exportme', email='export@example.com',
            full_name='Export Me',
        )

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_export_contains_personal_data_without_secrets(self):
        response = self.client.get('/users/me/export', headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        for section in (
            'account', 'runs', 'score_events', 'notifications',
            'location_pings', 'teams', 'oauth_providers', 'exported_at',
        ):
            self.assertIn(section, data)
        self.assertEqual(data['account']['email'], 'export@example.com')
        # A confirmação do endereço é dado pessoal da conta: sai na exportação.
        self.assertIsNotNone(data['account']['email_verified_at'])
        self.assertNotIn('password_hash', str(data))
        self.assertNotIn('Password123', str(data))

    def test_export_requires_auth(self):
        response = self.client.get('/users/me/export')
        self.assertEqual(response.status_code, 401)


if __name__ == '__main__':
    unittest.main()
