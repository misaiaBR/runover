import os
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone

_tmp = tempfile.TemporaryDirectory()
os.environ['DATABASE_URL'] = 'sqlite:///' + _tmp.name + '/test.db'
os.environ['SECRET_KEY'] = 'local-test-signing-key-for-runover-tests'
# O código de confirmação sai na resposta do cadastro: nada de caixa de correio
# nem de rede durante os testes.
os.environ['MAIL_CONSOLE_FALLBACK'] = 'true'
os.environ['BREVO_API_KEY'] = ''

from fastapi.testclient import TestClient
from app.core.database import Base, SessionLocal, engine, initialize_database
from app.main import app
from app.models import Run, Team, TeamMember, Territory, TerritoryOwnership, User
from auth_helpers import auth_headers


def _register(client, username='deleteme', email='delete@example.com'):
    return auth_headers(client, username=username, email=email, full_name='Delete Me')


class AccountDeletionTests(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()
        self.headers = _register(self.client)

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_delete_removes_account_and_kills_session(self):
        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 204, response.text)

        gone = self.client.get('/users/me', headers=self.headers)
        self.assertEqual(gone.status_code, 401)

        login = self.client.post('/auth/login', json={
            'email': 'delete@example.com', 'password': 'Password123',
        })
        self.assertEqual(login.status_code, 401)

        db = SessionLocal()
        try:
            self.assertIsNone(
                db.query(User).filter(User.username == 'deleteme').first()
            )
        finally:
            db.close()

    def test_public_profile_still_served(self):
        response = self.client.get('/users/deleteme', headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['username'], 'deleteme')

    def test_delete_frees_territories(self):
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.username == 'deleteme').one()
            territory = Territory(
                name='Praça Teste',
                geojson='{"type":"Point","coordinates":[0,0]}',
                radius_m=50, relevance=1,
            )
            db.add(territory)
            db.flush()
            db.add(TerritoryOwnership(
                territory_id=territory.id, owner_user_id=user.id, points=10,
            ))
            db.commit()
        finally:
            db.close()

        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 204, response.text)

        db = SessionLocal()
        try:
            ownership = db.query(TerritoryOwnership).one()
            self.assertIsNone(ownership.owner_user_id)
        finally:
            db.close()

    def test_delete_blocked_with_other_members(self):
        created = self.client.post(
            '/teams', json={'name': 'Time Saída'}, headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)
        team_id = created.json()['id']

        headers_b = _register(
            self.client, username='colega', email='colega@example.com',
        )
        joined = self.client.post(
            f'/teams/{team_id}/join', headers=headers_b,
        )
        self.assertEqual(joined.status_code, 202, joined.text)
        pending = self.client.get(
            f'/teams/{team_id}/requests', headers=self.headers,
        ).json()
        approved = self.client.post(
            f"/teams/{team_id}/requests/{pending[0]['id']}/approve",
            headers=self.headers,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 409)
        self.assertIn('equipe', response.json()['detail'])

        me = self.client.get('/users/me', headers=self.headers)
        self.assertEqual(me.status_code, 200)

    def test_delete_dissolves_sole_member_team(self):
        created = self.client.post(
            '/teams', json={'name': 'Time Solo'}, headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)

        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 204, response.text)

        db = SessionLocal()
        try:
            self.assertEqual(db.query(Team).count(), 0)
            self.assertEqual(db.query(TeamMember).count(), 0)
        finally:
            db.close()

    def _team_with_colleague(self, team_name='Time Saída'):
        created = self.client.post(
            '/teams', json={'name': team_name}, headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)
        team_id = created.json()['id']

        headers_b = _register(
            self.client, username='colega', email='colega@example.com',
        )
        joined = self.client.post(
            f'/teams/{team_id}/join', headers=headers_b,
        )
        self.assertEqual(joined.status_code, 202, joined.text)
        pending = self.client.get(
            f'/teams/{team_id}/requests', headers=self.headers,
        ).json()
        approved = self.client.post(
            f"/teams/{team_id}/requests/{pending[0]['id']}/approve",
            headers=self.headers,
        )
        self.assertEqual(approved.status_code, 200, approved.text)
        return team_id, headers_b

    def test_leave_transfers_ownership_then_delete_succeeds(self):
        team_id, headers_b = self._team_with_colleague('Time Revezamento')

        left = self.client.post(
            '/teams/leave', json={'successor_username': 'colega'}, headers=self.headers,
        )
        self.assertEqual(left.status_code, 204, left.text)

        detail = self.client.get(
            f'/teams/{team_id}', headers=headers_b,
        ).json()
        self.assertEqual(detail['creator_username'], 'colega')

        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 204, response.text)

        db = SessionLocal()
        try:
            self.assertEqual(db.query(Team).count(), 1)
        finally:
            db.close()

    def test_owner_leave_without_choice_is_rejected(self):
        team_id, headers_b = self._team_with_colleague('Time Indeciso')

        left = self.client.post('/teams/leave', headers=self.headers)
        self.assertEqual(left.status_code, 409, left.text)

        detail = self.client.get(
            f'/teams/{team_id}', headers=headers_b,
        ).json()
        self.assertEqual(detail['creator_username'], 'deleteme')

    def test_owner_leave_with_outsider_successor_is_rejected(self):
        team_id, headers_b = self._team_with_colleague('Time Exigente')

        left = self.client.post(
            '/teams/leave', json={'successor_username': 'estranho'}, headers=self.headers,
        )
        self.assertEqual(left.status_code, 400, left.text)

    def test_owner_leave_dissolves_team_and_notifies(self):
        from app.models import Notification
        team_id, headers_b = self._team_with_colleague('Time Fim')

        left = self.client.post(
            '/teams/leave', json={'dissolve': True}, headers=self.headers,
        )
        self.assertEqual(left.status_code, 204, left.text)

        db = SessionLocal()
        try:
            self.assertEqual(db.query(Team).count(), 0)
            self.assertEqual(db.query(TeamMember).count(), 0)
            notes = db.query(Notification).all()
            self.assertTrue(
                any('dissolvida' in n.message for n in notes), [n.message for n in notes],
            )
        finally:
            db.close()

    def test_leave_dissolves_sole_member_team(self):
        created = self.client.post(
            '/teams', json={'name': 'Time Eremita'}, headers=self.headers,
        )
        self.assertEqual(created.status_code, 201, created.text)
        team_id = created.json()['id']

        db = SessionLocal()
        try:
            user = db.query(User).filter(User.username == 'deleteme').one()
            now = datetime.now(timezone.utc).replace(tzinfo=None)
            db.add(Run(
                id=str(uuid.uuid4()),
                user_id=user.id,
                team_id=team_id,
                request_hash='r' * 64,
                track_hash='h' * 64,
                track_json='[]',
                started_at=now - timedelta(minutes=10),
                ended_at=now,
                distance_m=100,
                duration_seconds=60,
                name='Teste de dissoluÃ§Ã£o',
                result_json='{}',
            ))
            db.commit()
        finally:
            db.close()

        left = self.client.post('/teams/leave', headers=self.headers)
        self.assertEqual(left.status_code, 204, left.text)

        db = SessionLocal()
        try:
            self.assertEqual(db.query(Team).count(), 0)
            self.assertEqual(db.query(TeamMember).count(), 0)
            self.assertIsNone(db.query(Run).one().team_id)
        finally:
            db.close()

    def test_delete_transfers_legacy_orphan(self):
        team_id, headers_b = self._team_with_colleague('Time Legado')

        # Simula a regra antiga: criador saiu sem transferir o dono.
        db = SessionLocal()
        try:
            user = db.query(User).filter(User.username == 'deleteme').one()
            db.query(TeamMember).filter(
                TeamMember.user_id == user.id,
            ).delete(synchronize_session=False)
            db.commit()
        finally:
            db.close()

        response = self.client.delete('/users/me', headers=self.headers)
        self.assertEqual(response.status_code, 204, response.text)

        detail = self.client.get(
            f'/teams/{team_id}', headers=headers_b,
        ).json()
        self.assertEqual(detail['creator_username'], 'colega')


if __name__ == '__main__':
    unittest.main()
