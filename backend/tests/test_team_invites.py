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


def _register(client, username):
    return auth_headers(client, username=username,
                        email=f'{username}@example.com',
                        full_name=username.title())


class TeamInviteTests(unittest.TestCase):
    """Convite por @usuário: o admin chama, mas só o convidado decide."""

    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()
        self.owner = _register(self.client, 'dono')
        team = self.client.post(
            '/teams', json={'name': 'Time Convida'}, headers=self.owner,
        )
        assert team.status_code == 201, team.text
        self.team_id = team.json()['id']
        self.invited = _register(self.client, 'convidado')

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def _invite(self, username, headers=None):
        return self.client.post(
            f'/teams/{self.team_id}/invites',
            json={'username': username},
            headers=headers or self.owner,
        )

    def _invites(self, headers=None):
        return self.client.get('/teams/invites', headers=headers or self.invited)

    def test_invite_lands_on_the_invited_not_on_the_admin(self):
        invited = self._invite('convidado')
        self.assertEqual(invited.status_code, 200, invited.text)
        self.assertEqual(invited.json()['member_count'], 1)

        mine = self._invites().json()
        self.assertEqual(len(mine), 1)
        self.assertEqual(mine[0]['team_name'], 'Time Convida')
        self.assertEqual(mine[0]['invited_by_username'], 'dono')

        inbox = self.client.get('/notifications', headers=self.invited).json()
        self.assertTrue(
            any('convidou' in n['message'] for n in inbox), inbox,
        )

    def test_accept_adds_the_invited_to_the_team(self):
        self._invite('convidado')
        request_id = self._invites().json()[0]['id']

        accepted = self.client.post(
            f'/teams/invites/{request_id}/accept', headers=self.invited,
        )
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertEqual(accepted.json()['member_count'], 2)
        self.assertEqual(self._invites().json(), [])

        inbox = self.client.get('/notifications', headers=self.owner).json()
        self.assertTrue(
            any('aceitou' in n['message'] for n in inbox), inbox,
        )

    def test_decline_keeps_the_invited_out(self):
        self._invite('convidado')
        request_id = self._invites().json()[0]['id']

        declined = self.client.post(
            f'/teams/invites/{request_id}/decline', headers=self.invited,
        )
        self.assertEqual(declined.status_code, 204, declined.text)
        self.assertEqual(self._invites().json(), [])
        self.assertEqual(
            self.client.get('/teams/mine', headers=self.owner).json()['member_count'],
            1,
        )

        inbox = self.client.get('/notifications', headers=self.owner).json()
        self.assertTrue(
            any('recusou' in n['message'] for n in inbox), inbox,
        )

    def test_answering_twice_is_not_allowed(self):
        self._invite('convidado')
        request_id = self._invites().json()[0]['id']
        self.client.post(
            f'/teams/invites/{request_id}/accept', headers=self.invited,
        )
        again = self.client.post(
            f'/teams/invites/{request_id}/decline', headers=self.invited,
        )
        self.assertEqual(again.status_code, 404)

    def test_only_admin_may_invite(self):
        member = _register(self.client, 'membro')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        denied = self._invite('estranho', headers=member)
        self.assertEqual(denied.status_code, 403)

    def test_invite_rejects_unknown_or_taken_players(self):
        self.assertEqual(self._invite('fantasma').status_code, 404)

        other_owner = _register(self.client, 'dono2')
        other = self.client.post(
            '/teams', json={'name': 'Outro Time'}, headers=other_owner,
        )
        other_id = other.json()['id']
        self.client.post(f'/teams/{other_id}/join', headers=self.invited)
        requests = self.client.get(
            f'/teams/{other_id}/requests', headers=other_owner,
        ).json()
        self.client.post(
            f'/teams/{other_id}/requests/{requests[0]["id"]}/approve',
            headers=other_owner,
        )
        taken = self._invite('convidado')
        self.assertEqual(taken.status_code, 400, taken.text)

        member = _register(self.client, 'membro')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        already = self._invite('membro')
        self.assertEqual(already.status_code, 400, already.text)


if __name__ == '__main__':
    unittest.main()
