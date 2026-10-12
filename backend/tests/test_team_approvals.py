import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

_tmp = tempfile.TemporaryDirectory()
os.environ['DATABASE_URL'] = 'sqlite:///' + _tmp.name + '/test.db'
os.environ['SECRET_KEY'] = 'local-test-signing-key-for-runover-tests'
os.environ['MAIL_CONSOLE_FALLBACK'] = 'true'
os.environ['BREVO_API_KEY'] = ''

from fastapi.testclient import TestClient
from app.core.database import Base, SessionLocal, engine, initialize_database
from app.main import app
from app.models import LocationPing, User
from auth_helpers import auth_headers


def _register(client, username, email):
    return auth_headers(client, username=username, email=email,
                        full_name=username.title())


class TeamApprovalTests(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()
        self.owner = _register(self.client, 'dono', 'dono@example.com')
        team = self.client.post(
            '/teams', json={'name': 'Time Aprova'}, headers=self.owner,
        )
        assert team.status_code == 201, team.text
        self.team_id = team.json()['id']
        self.applicant = _register(self.client, 'novo', 'novo@example.com')

    def tearDown(self):
        self.client.__exit__(None, None, None)

    def test_join_creates_pending_request(self):
        response = self.client.post(
            f'/teams/{self.team_id}/join', headers=self.applicant,
        )
        self.assertEqual(response.status_code, 202, response.text)

        mine = self.client.get('/teams/mine', headers=self.applicant)
        self.assertEqual(mine.status_code, 404)

        detail = self.client.get(
            f'/teams/{self.team_id}', headers=self.applicant,
        ).json()
        self.assertEqual(detail['my_request'], 'pending')

        owner_view = self.client.get(
            f'/teams/{self.team_id}', headers=self.owner,
        ).json()
        self.assertTrue(owner_view['is_owner'])
        self.assertEqual(len(owner_view['pending_requests']), 1)
        self.assertEqual(
            owner_view['pending_requests'][0]['username'], 'novo',
        )

    def test_duplicate_request_is_rejected(self):
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        again = self.client.post(
            f'/teams/{self.team_id}/join', headers=self.applicant,
        )
        self.assertEqual(again.status_code, 409)

    def test_owner_approves_and_applicant_joins(self):
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        approved = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

        mine = self.client.get('/teams/mine', headers=self.applicant)
        self.assertEqual(mine.status_code, 200)
        self.assertEqual(mine.json()['id'], self.team_id)

        inbox = self.client.get(
            '/notifications', headers=self.applicant,
        ).json()
        self.assertTrue(
            any('aceito' in n['message'] for n in inbox),
            inbox,
        )

    def test_online_count_reflects_recent_pings(self):
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        approved = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

        ping = self.client.post(
            '/location', json={'lat': -23.6, 'lng': -46.8},
            headers=self.applicant,
        )
        self.assertEqual(ping.status_code, 204, ping.text)

        mine = self.client.get('/teams/mine', headers=self.applicant)
        self.assertEqual(mine.status_code, 200, mine.text)
        self.assertEqual(mine.json()['member_count'], 2)
        # Só o applicant pingou; o dono segue offline.
        self.assertEqual(mine.json()['online_count'], 1)

    def test_stale_ping_does_not_count_as_online(self):
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        approved = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

        # Ping antigo do dono (1h, fora da janela de 15 min).
        with SessionLocal() as db:
            owner = db.query(User).filter(User.username == 'dono').one()
            db.add(LocationPing(
                user_id=owner.id,
                latitude=-23.6,
                longitude=-46.8,
                recorded_at=datetime.now(timezone.utc).replace(
                    tzinfo=None,
                ) - timedelta(hours=1),
            ))
            db.commit()

        mine = self.client.get('/teams/mine', headers=self.owner)
        self.assertEqual(mine.status_code, 200, mine.text)
        self.assertEqual(mine.json()['online_count'], 0)

    def test_reject_keeps_applicant_out(self):
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        rejected = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/reject",
            headers=self.owner,
        )
        self.assertEqual(rejected.status_code, 200)
        mine = self.client.get('/teams/mine', headers=self.applicant)
        self.assertEqual(mine.status_code, 404)

    def test_non_admin_cannot_decide(self):
        other = _register(self.client, 'xeru', 'xeru@example.com')
        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        denied = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=other,
        )
        self.assertEqual(denied.status_code, 403)
        hidden = self.client.get(
            f'/teams/{self.team_id}/requests', headers=other,
        )
        self.assertEqual(hidden.status_code, 403)

    def test_owner_promotes_admin_who_approves(self):
        member = _register(self.client, 'membro', 'membro@example.com')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        promoted = self.client.post(
            f'/teams/{self.team_id}/admins',
            json={'username': 'membro'},
            headers=self.owner,
        )
        self.assertEqual(promoted.status_code, 200, promoted.text)
        admins = [
            m for m in promoted.json()['members'] if m['is_admin']
        ]
        self.assertEqual({m['username'] for m in admins}, {'dono', 'membro'})

        applicant2 = _register(self.client, 'novo2', 'novo2@example.com')
        self.client.post(
            f'/teams/{self.team_id}/join', headers=applicant2,
        )
        pending2 = self.client.get(
            f'/teams/{self.team_id}/requests', headers=member,
        ).json()
        approved = self.client.post(
            f"/teams/{self.team_id}/requests/{pending2[0]['id']}/approve",
            headers=member,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

    def test_only_owner_manages_admins(self):
        member = _register(self.client, 'membro', 'membro@example.com')
        denied = self.client.post(
            f'/teams/{self.team_id}/admins',
            json={'username': 'membro'},
            headers=member,
        )
        self.assertEqual(denied.status_code, 403)
        stranger = self.client.post(
            f'/teams/{self.team_id}/admins',
            json={'username': 'fantasma'},
            headers=self.owner,
        )
        self.assertEqual(stranger.status_code, 404)

    def test_owner_demotes_admin(self):
        member = _register(self.client, 'membro', 'membro@example.com')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.client.post(
            f'/teams/{self.team_id}/admins',
            json={'username': 'membro'},
            headers=self.owner,
        )
        demoted = self.client.delete(
            f'/teams/{self.team_id}/admins/membro', headers=self.owner,
        )
        self.assertEqual(demoted.status_code, 200, demoted.text)
        admins = [
            m for m in demoted.json()['members'] if m['is_admin']
        ]
        self.assertEqual([m['username'] for m in admins], ['dono'])

        owner_out = self.client.delete(
            f'/teams/{self.team_id}/admins/dono', headers=self.owner,
        )
        self.assertEqual(owner_out.status_code, 400)

    def test_approve_withdraws_other_pendings(self):
        owner2 = _register(self.client, 'dono2', 'dono2@example.com')
        other = self.client.post(
            '/teams', json={'name': 'Outro Time'}, headers=owner2,
        )
        other_id = other.json()['id']

        self.client.post(f'/teams/{self.team_id}/join', headers=self.applicant)
        self.client.post(f'/teams/{other_id}/join', headers=self.applicant)

        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        approved = self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.assertEqual(approved.status_code, 200, approved.text)

        leftovers = self.client.get(
            f'/teams/{other_id}/requests', headers=owner2,
        ).json()
        self.assertEqual(leftovers, [])

    def test_admin_updates_photo_and_name(self):
        member = _register(self.client, 'membro', 'membro@example.com')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        self.client.post(
            f'/teams/{self.team_id}/admins',
            json={'username': 'membro'},
            headers=self.owner,
        )
        updated = self.client.patch(
            f'/teams/{self.team_id}',
            json={'name': 'Time Novo', 'photo_url': None},
            headers=member,
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()['name'], 'Time Novo')

        outsider = _register(self.client, 'fora', 'fora@example.com')
        denied = self.client.patch(
            f'/teams/{self.team_id}',
            json={'name': 'Time X'},
            headers=outsider,
        )
        self.assertEqual(denied.status_code, 403)

    def test_owner_disbands_team(self):
        member = _register(self.client, 'membro', 'membro@example.com')
        self.client.post(f'/teams/{self.team_id}/join', headers=member)
        pending = self.client.get(
            f'/teams/{self.team_id}/requests', headers=self.owner,
        ).json()
        self.client.post(
            f"/teams/{self.team_id}/requests/{pending[0]['id']}/approve",
            headers=self.owner,
        )
        gone = self.client.delete(
            f'/teams/{self.team_id}', headers=self.owner,
        )
        self.assertEqual(gone.status_code, 204, gone.text)
        missing = self.client.get(
            f'/teams/{self.team_id}', headers=self.owner,
        )
        self.assertEqual(missing.status_code, 404)
        mine = self.client.get('/teams/mine', headers=member)
        self.assertEqual(mine.status_code, 404)

    def test_non_owner_cannot_disband(self):
        denied = self.client.delete(
            f'/teams/{self.team_id}', headers=self.applicant,
        )
        self.assertEqual(denied.status_code, 403)


if __name__ == '__main__':
    unittest.main()
