import concurrent.futures
import hashlib
import os
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

_tmp = tempfile.TemporaryDirectory()
test_postgres = os.environ.get('RUNOVER_TEST_POSTGRES_URL')
if test_postgres and test_postgres != 'postgresql+psycopg://postgres@127.0.0.1:55432/runover_test':
    raise RuntimeError('Use only the dedicated local runover_test PostgreSQL database.')
os.environ['DATABASE_URL'] = test_postgres or 'sqlite:///' + _tmp.name + '/test.db'
os.environ['SECRET_KEY'] = 'local-test-signing-key-for-runover-tests'
from fastapi.testclient import TestClient
from app.main import app
from app.core.database import Base, engine, initialize_database, SessionLocal
from app.h3cells import cell_for, covering_cells
from app.models import ConquestMark, PasswordResetToken, Run, ScoreEvent, Territory, User
from app.schemas import RunRequest
from app.services.mail import send_reset_email


class ApiTests(unittest.TestCase):
    def setUp(self):
        Base.metadata.drop_all(engine)
        initialize_database()
        self.client = TestClient(app)
        self.client.__enter__()
        self.sent = []
        self.mail_patch = patch(
            'app.routers.auth.send_password_reset_email',
            side_effect=lambda email, username, code: self.sent.append((email, username, code)),
        )
        self.mail_patch.start()
        self.alice = self.register('alice')
        self.bob = self.register('bobby')

    def tearDown(self):
        self.mail_patch.stop()
        self.client.__exit__(None, None, None)

    def register(self, name):
        response = self.client.post('/auth/register', json={'full_name':'Test Runner','username':name,'email':name+'@example.com','password':'Password123','accept_terms':True})
        self.assertEqual(response.status_code,201,response.text)
        return {'Authorization':'Bearer '+response.json()['access_token']}

    def payload(self, coords=None, **kwargs):
        coords = coords or [(10,10),(10,10.001),(10.001,10.001),(10.001,10),(10,10)]
        start = datetime.now(timezone.utc) - timedelta(minutes=20)
        run_id = str(uuid.uuid4())
        return {
            'id': run_id,
            'request_id': run_id,
            'track': [
                {'lat': a, 'lng': b, 'timestamp': (start + timedelta(seconds=i * 60)).isoformat()}
                for i, (a, b) in enumerate(coords)
            ],
            **kwargs,
        }

    def save(self, payload, user=None):
        return self.client.post('/runs',json=payload,headers=user or self.alice)

    def test_password_recovery_private_single_use_revokes_sessions(self):
        known = self.client.post('/auth/forgot-password',json={'email':'alice@example.com'})
        unknown = self.client.post('/auth/forgot-password',json={'email':'missing@example.com'})
        self.assertEqual(known.json(),unknown.json())
        self.assertNotIn('reset_token',known.json())
        code = self.sent[0][2]
        with SessionLocal() as db:
            stored = db.query(PasswordResetToken).one()
            self.assertEqual(stored.token_hash, hashlib.sha256(code.encode()).hexdigest())
            self.assertNotEqual(stored.token_hash, code)
        payload = {
            'email': 'alice@example.com',
            'reset_code': code,
            'new_password': 'Updated123',
        }
        self.assertEqual(self.client.post('/auth/reset-password',json=payload).status_code,200)
        self.assertEqual(self.client.post('/auth/reset-password',json=payload).status_code,400)
        self.assertEqual(self.client.get('/users/me',headers=self.alice).status_code,401)
        self.assertEqual(self.client.post('/auth/login',json={'email':'alice@example.com','password':'Updated123'}).status_code,200)

    def test_login_email_throttle_is_scoped_to_client_after_ip_limit(self):
        calls = []

        def record_throttle(_db, key, limit, minutes=15):
            calls.append((key, limit))
            return len(calls) == 1

        with patch('app.routers.auth.client_key', return_value='203.0.113.7'), patch(
            'app.routers.auth.throttle', side_effect=record_throttle,
        ):
            response = self.client.post('/auth/login', json={
                'email': 'alice@example.com',
                'password': 'Password123',
            })

        self.assertEqual(response.status_code, 429)
        self.assertEqual(calls, [
            ('login-ip:203.0.113.7', 60),
            ('login:alice@example.com:203.0.113.7', 15),
        ])

        calls.clear()
        with patch('app.routers.auth.client_key', return_value='203.0.113.7'), patch(
            'app.routers.auth.throttle', side_effect=lambda *_args: calls.append(True) or False,
        ):
            response = self.client.post('/auth/login', json={
                'email': 'alice@example.com',
                'password': 'Password123',
            })
        self.assertEqual(response.status_code, 429)
        self.assertEqual(len(calls), 1)

    def test_run_response_models_preserve_summary_and_detail_fields(self):
        payload = self.payload()
        saved = self.save(payload)
        self.assertEqual(saved.status_code, 200, saved.text)
        run_id = saved.json()['id']
        listed = self.client.get('/runs',headers=self.alice)
        self.assertEqual(listed.status_code, 200, listed.text)
        summary = listed.json()[0]
        self.assertNotIn('track', summary)
        self.assertIn('claim', summary)
        self.assertIn('claim_error', summary)
        detail = self.client.get(f'/runs/{run_id}',headers=self.alice).json()
        self.assertEqual(len(detail['track']), len(payload['track']))
        self.assertEqual(self.client.get('/runs/progress',headers=self.alice).status_code, 200)

    def test_expired_token_and_rate_limit(self):
        for _ in range(5):
            self.assertEqual(self.client.post('/auth/forgot-password',json={'email':'alice@example.com'}).status_code,200)
        self.assertEqual(len(self.sent),1)
        with SessionLocal() as db:
            db.query(PasswordResetToken).update({
                'expires_at': datetime.now(timezone.utc) - timedelta(seconds=1),
            })
            db.commit()
        response = self.client.post('/auth/reset-password',json={
            'email': 'alice@example.com',
            'reset_code': self.sent[0][2],
            'new_password': 'Updated123',
        })
        self.assertEqual(response.status_code,400)

    def test_profile_training_prefs_roundtrip_and_validation(self):
        me = self.client.get('/users/me', headers=self.alice).json()
        self.assertEqual(me['distance_units'], 'km')
        self.assertIsNone(me['weekly_frequency'])
        self.assertEqual(me['training_days'], [])
        self.assertIsNone(me['activity_level'])

        updated = self.client.patch('/users/me', headers=self.alice, json={
            'distance_units': 'mi',
            'weekly_frequency': 3,
            'training_days': ['sex', 'seg', 'seg', 'qua'],
            'activity_level': 'iniciante',
        })
        self.assertEqual(updated.status_code, 200, updated.text)
        body = updated.json()
        self.assertEqual(body['distance_units'], 'mi')
        self.assertEqual(body['weekly_frequency'], 3)
        self.assertEqual(body['training_days'], ['seg', 'qua', 'sex'])
        self.assertEqual(body['activity_level'], 'iniciante')

        cleared = self.client.patch('/users/me', headers=self.alice, json={
            'weekly_frequency': None,
            'training_days': [],
            'activity_level': None,
        })
        self.assertEqual(cleared.status_code, 200, cleared.text)
        self.assertIsNone(cleared.json()['weekly_frequency'])
        self.assertEqual(cleared.json()['training_days'], [])
        self.assertIsNone(cleared.json()['activity_level'])

        self.assertEqual(self.client.patch('/users/me', headers=self.alice, json={'distance_units': 'kmh'}).status_code, 422)
        self.assertEqual(self.client.patch('/users/me', headers=self.alice, json={'weekly_frequency': 9}).status_code, 422)
        self.assertEqual(self.client.patch('/users/me', headers=self.alice, json={'training_days': ['feriado']}).status_code, 422)
        self.assertEqual(self.client.patch('/users/me', headers=self.alice, json={'activity_level': 'ultra'}).status_code, 422)

    def test_profile_password_and_photo(self):
        self.assertEqual(self.client.patch('/users/me',headers=self.alice,json={'password':'12345678'}).status_code,422)
        self.client.patch('/users/me',headers=self.alice,json={'photo_url':'https://example.com/photo'})
        self.assertIsNone(self.client.patch('/users/me',headers=self.alice,json={'photo_url':None}).json()['photo_url'])
        self.assertEqual(self.client.patch('/users/me',headers=self.alice,json={'password':'Updated123'}).status_code,200)
        self.assertEqual(self.client.get('/users/me',headers=self.alice).status_code,401)

    def test_claim_is_idempotent_and_private(self):
        payload = self.payload(conquer=True)
        a,b = self.save(payload),self.save(payload)
        self.assertEqual(a.status_code,200,a.text)
        self.assertEqual(b.status_code,200,b.text)
        body_a, body_b = dict(a.json()), dict(b.json())
        # O replay idempotente não credita moedas de novo: só a primeira
        # resposta traz o total ganho; o restante do corpo é idêntico.
        earned = body_a.pop('coins_earned', None)
        body_b.pop('coins_earned', None)
        self.assertEqual(body_a,body_b)
        self.assertGreater(earned, 0)
        wallet = self.client.get('/shop/wallet', headers=self.alice).json()
        self.assertEqual(wallet['balance'], earned)
        self.assertIsNotNone(a.json()['claim'])
        with SessionLocal() as db:
            self.assertEqual(db.query(Run).count(),1)
            self.assertEqual(db.query(ScoreEvent).filter(ScoreEvent.reason=='conquista').count(),1)
        self.assertEqual(self.client.get('/runs/'+payload['id'],headers=self.bob).status_code,404)
        self.assertEqual(self.client.get('/runs',headers=self.bob).json(),[])
        self.assertEqual(self.save({**payload,'name':'different'}).status_code,409)
        self.assertEqual(self.save({**payload,'id':str(uuid.uuid4())},self.bob).status_code,409)
        changed_segments={**payload,'id':str(uuid.uuid4()),'track':[{**p,'segment':1} for p in payload['track']]}
        self.assertEqual(self.save(changed_segments,self.bob).status_code,409)
        self.assertEqual(self.client.post('/territories/claim',headers=self.bob,json=payload).status_code,410)

    def test_open_run_saved_without_conquest(self):
        p = self.payload(coords=[(10,10),(10,10.001),(10,10.002)],conquer=True)
        response=self.save(p)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNone(response.json()['claim'])
        self.assertTrue(response.json()['claim_error'])
        profile=self.client.get('/users/me',headers=self.alice).json()
        self.assertEqual(profile['play_seconds'],120)
        self.assertEqual(profile['total_score'],0)

    def test_geometry_errors_do_not_500(self):
        self.assertEqual(self.save(self.payload(coords=[(11,11)]*4,conquer=True)).status_code,400)
        coords=[(12,12),(12,12.001),(12.001,12.001),(12.001,12),(12,12),(12,11.999),(11.999,11.999),(11.999,12),(12,12)]
        response=self.save(self.payload(coords=coords,conquer=True))
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNone(response.json()['claim'])
        self.assertTrue(response.json()['claim_error'])

    def test_invalid_track_data(self):
        for key,value in [('lat',91),('lng',181),('timestamp','2026-01-01T00:00:00')]:
            p=self.payload();p['track'][0][key]=value
            self.assertEqual(self.save(p).status_code,422)
        p=self.payload();p['track'][1]['timestamp']=p['track'][0]['timestamp']
        self.assertEqual(self.save(p).status_code,400)
        p=self.payload();p['track'][0]['timestamp']=(datetime.now(timezone.utc)-timedelta(days=8)).isoformat()
        self.assertEqual(self.save(p).status_code,400)
        p=self.payload();start=datetime.now(timezone.utc)-timedelta(minutes=1)
        for i,point in enumerate(p['track']):point['timestamp']=(start+timedelta(seconds=i)).isoformat()
        self.assertEqual(self.save(p).status_code,400)

    def test_pause_with_a_long_jump_cannot_conquer(self):
        p=self.payload(conquer=True)
        for point in p['track'][2:]:point['segment']=1
        response=self.save(p)
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(response.json()['duration_seconds'],180)
        self.assertIsNone(response.json()['claim'])
        self.assertTrue(response.json()['claim_error'])

    def test_pause_resuming_in_place_still_conquers(self):
        p=self.payload(conquer=True)
        for point in p['track'][2:]:point['segment']=1
        # Retomar a ~11 m de onde parou é buraco de GPS, não deslocamento: o
        # traçado continua sendo o laço que o corredor fechou.
        p['track'][2]['lat']=10.0001
        response=self.save(p)
        self.assertEqual(response.status_code,200,response.text)
        body=response.json()
        self.assertIsNone(body['claim_error'])
        self.assertIsNotNone(body['claim'])
        # O vão entre pausa e retomada segue fora do tempo somado.
        self.assertEqual(body['duration_seconds'],180)

    def test_gps_gap_does_not_void_the_saved_run(self):
        p=self.payload(conquer=True)
        # Retomou 4,9 km adiante: o vão entre a pausa e a retomada é um
        # teleporte, mas cada trecho continua coerente com uma corrida.
        for point in p['track'][2:]:
            point['segment']=1
            point['lat']=round(point['lat']+0.045,6)
        response=self.save(p)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNone(response.json()['claim'])
        self.assertTrue(response.json()['claim_error'])
        # Sem a pausa registrada, o mesmo salto é fraude e a corrida não entra.
        moving=self.payload()
        for point in moving['track'][2:]:
            point['lat']=round(point['lat']+0.045,6)
        for point in moving['track']:
            point['timestamp']=(datetime.fromisoformat(point['timestamp'])-timedelta(minutes=30)).isoformat()
        self.assertEqual(self.save(moving).status_code,400)

    def test_loop_closure_follows_reported_accuracy(self):
        # Atrás de um prédio o relógio fecha a volta a ~61 m do ponto de
        # partida. Com a incerteza reportada isso ainda é laço; sem ela, não.
        closed=self.payload(conquer=True)
        closed['track'][-1]['lat']=10.00055
        for point in closed['track']:point['accuracy']=50.0
        response=self.save(closed)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNotNone(response.json()['claim'])
        tight=self.payload(conquer=True)
        tight['track'][-1]['lat']=10.00055
        for point in tight['track']:
            point['timestamp']=(datetime.fromisoformat(point['timestamp'])-timedelta(minutes=30)).isoformat()
        response=self.save(tight)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNone(response.json()['claim'])
        self.assertIn('não fechado',response.json()['claim_error'])

    def test_team_progress_and_authorization(self):
        # Relógio congelado numa segunda-feira: corridas "há 20 minutos"
        # reais cairiam no domingo após a meia-noite e sairiam da semana.
        from datetime import datetime as real_datetime
        frozen_now = real_datetime(2026, 10, 5, 12, 0, tzinfo=timezone.utc)
        class FrozenDateTime(real_datetime):
            @classmethod
            def now(cls, tz=None):
                return frozen_now if tz is not None else frozen_now.replace(tzinfo=None)
        team=self.client.post('/teams',headers=self.alice,json={'name':'Runners'}).json()
        p=self.payload(conquer=True,team_id=team['id'])
        start=frozen_now-timedelta(minutes=20)
        p['track']=[{'lat':q['lat'],'lng':q['lng'],'timestamp':(start+timedelta(seconds=i*60)).isoformat()} for i,q in enumerate(p['track'])]
        with patch('app.routers.runs.datetime', FrozenDateTime):
            self.assertEqual(self.save(p,self.bob).status_code,403)
            response=self.save(p)
            self.assertEqual(response.status_code,200,response.text)
            self.assertEqual(response.json()['claim']['territory']['owner_type'],'team')
            self.assertGreater(response.json()['claim']['new_total_score'],0)
            progress=self.client.get('/runs/progress',headers=self.alice).json()
            self.assertEqual(progress['runs_count'],1)
            self.assertTrue(progress['badges'][0]['earned'])
            self.assertTrue(progress['badges'][1]['earned'])
            self.assertGreater(progress['team']['distance_km'],0)
            self.assertIsNone(self.client.get('/runs/progress',headers=self.bob).json()['team'])

    def test_concurrent_same_request_scores_once(self):
        p=self.payload(conquer=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda _:self.save(p),range(2)))
        self.assertEqual([r.status_code for r in responses],[200,200])
        bodies=[dict(r.json()) for r in responses]
        earned=[b.pop('coins_earned', None) for b in bodies]
        self.assertEqual(bodies[0],bodies[1])
        # Só uma das respostas carrega o crédito; a carteira confirma
        # que as moedas entraram uma única vez.
        credited=[e for e in earned if e]
        self.assertEqual(len(credited),1)
        wallet=self.client.get('/shop/wallet',headers=self.alice).json()
        self.assertEqual(wallet['balance'],credited[0])
        with SessionLocal() as db:
            self.assertEqual(db.query(Run).count(),1)
            self.assertEqual(db.query(ScoreEvent).filter(ScoreEvent.reason=='conquista').count(),1)

    def test_same_owner_claim_keeps_activity_without_new_score(self):
        first=self.payload(conquer=True)
        response=self.save(first)
        self.assertEqual(response.status_code,200,response.text)
        second=self.payload(conquer=True)
        for p in second['track']:
            p['timestamp']=(datetime.fromisoformat(p['timestamp'])+timedelta(minutes=10)).isoformat()
        response=self.save(second)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNone(response.json()['claim'])
        with SessionLocal() as db:
            self.assertEqual(db.query(Run).count(),2)
            self.assertEqual(db.query(ScoreEvent).filter(ScoreEvent.reason=='conquista').count(),1)

    def test_territory_lists_takeovers(self):
        self.assertEqual(self.save(self.payload(conquer=True)).status_code,200)
        takeover=self.payload(conquer=True,challenge='pace')
        start=datetime.now(timezone.utc)-timedelta(minutes=10)
        takeover['track']=[{'lat':p['lat'],'lng':p['lng'],'timestamp':(start+timedelta(seconds=i*20)).isoformat()} for i,p in enumerate(takeover['track'])]
        response=self.save(takeover,self.bob)
        self.assertEqual(response.status_code,200,response.text)
        self.assertIsNotNone(response.json()['claim'])
        claimed=[t for t in self.client.get('/territories',headers=self.alice).json() if t['owner_display']]
        self.assertEqual([(t['owner_display'],t['takeovers']) for t in claimed],[('bobby',1)])
        detail=self.client.get('/territories/'+claimed[0]['id'],headers=self.alice).json()
        self.assertEqual(detail['takeovers'],1)
        self.assertEqual([(h['owner_type'],h['owner_display']) for h in detail['history']],[('user','alice')])

    def test_first_conquest_sets_owner_mark(self):
        payload = self.payload(conquer=True, challenge='pace')
        response = self.save(payload)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertTrue(claim['created_new'])
        self.assertIsNone(claim['challenge_won'])
        self.assertIsNone(claim['beaten_pace_seconds_per_km'])
        detail = self.client.get(
            '/territories/' + claim['territory']['id'], headers=self.alice
        ).json()
        self.assertIsNotNone(detail['owner_pace_seconds_per_km'])
        self.assertGreater(detail['owner_distance_m'], 0)
        self.assertIsNotNone(detail['owner_duration_seconds'])

    def test_faster_pace_challenge_takes_territory(self):
        first = self.save(self.payload(conquer=True))
        territory_id = first.json()['claim']['territory']['id']
        beat = self.payload(conquer=True, challenge='pace')
        beat['id'] = str(uuid.uuid4())
        start = datetime.now(timezone.utc) - timedelta(minutes=10)
        beat['track'] = [
            {'lat': p['lat'], 'lng': p['lng'],
             'timestamp': (start + timedelta(seconds=i * 20)).isoformat()}
            for i, p in enumerate(beat['track'])
        ]
        response = self.save(beat, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertFalse(claim['created_new'])
        self.assertTrue(claim['challenge_won'])
        self.assertGreater(claim['points_awarded'], 0)
        self.assertGreater(
            claim['beaten_pace_seconds_per_km'],
            claim['territory']['owner_pace_seconds_per_km'],
        )
        detail = self.client.get(
            f'/territories/{territory_id}', headers=self.bob
        ).json()
        self.assertEqual(detail['owner_display'], 'bobby')

    def test_slower_pace_challenge_keeps_territory(self):
        first = self.save(self.payload(conquer=True))
        territory_id = first.json()['claim']['territory']['id']
        slow = self.payload(conquer=True, challenge='pace')
        slow['id'] = str(uuid.uuid4())
        start = datetime.now(timezone.utc) - timedelta(minutes=20)
        slow['track'] = [
            {'lat': p['lat'], 'lng': p['lng'],
             'timestamp': (start + timedelta(seconds=i * 240)).isoformat()}
            for i, p in enumerate(slow['track'])
        ]
        response = self.save(slow, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertFalse(claim['challenge_won'])
        self.assertEqual(claim['points_awarded'], 0)
        detail = self.client.get(
            f'/territories/{territory_id}', headers=self.bob
        ).json()
        self.assertEqual(detail['owner_display'], 'alice')
        self.assertEqual(
            detail['owner_pace_seconds_per_km'],
            claim['beaten_pace_seconds_per_km'],
        )
        replay = self.save(slow, self.bob)
        replay_body, response_body = dict(replay.json()), dict(response.json())
        # Replay idempotente não credita moedas de novo.
        self.assertGreater(response_body.pop('coins_earned', 0), 0)
        replay_body.pop('coins_earned', None)
        self.assertEqual(replay_body, response_body)
        with SessionLocal() as db:
            self.assertEqual(db.query(ScoreEvent).filter(ScoreEvent.reason == 'perda').count(), 0)
            self.assertEqual(db.query(ScoreEvent).filter(ScoreEvent.reason == 'conquista').count(), 1)

    def test_distance_challenge_win_and_loss(self):
        first = self.save(self.payload(conquer=True))
        territory_id = first.json()['claim']['territory']['id']
        bigger = [(10, 10), (10, 10.0015), (10.0015, 10.0015), (10.0015, 10), (10, 10)]
        race = self.payload(coords=bigger, conquer=True, challenge='distance')
        race['id'] = str(uuid.uuid4())
        response = self.save(race, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertTrue(claim['challenge_won'])
        self.assertGreater(claim['points_awarded'], 0)
        self.assertGreater(claim['beaten_distance_m'], 0)
        detail = self.client.get(
            f'/territories/{territory_id}', headers=self.bob
        ).json()
        self.assertEqual(detail['owner_display'], 'bobby')

        carol = self.register('carol')
        huge = [(10, 10), (10, 10.002), (10.002, 10.002), (10.002, 10), (10, 10)]
        over = self.payload(coords=huge, conquer=True, challenge='distance')
        over['id'] = str(uuid.uuid4())
        start = datetime.now(timezone.utc) - timedelta(minutes=20)
        over['track'] = [
            {'lat': p['lat'], 'lng': p['lng'],
             'timestamp': (start + timedelta(seconds=i * 120)).isoformat()}
            for i, p in enumerate(over['track'])
        ]
        response = self.save(over, carol)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertFalse(claim['challenge_won'])
        self.assertEqual(claim['points_awarded'], 0)
        detail = self.client.get(
            f'/territories/{territory_id}', headers=carol
        ).json()
        self.assertEqual(detail['owner_display'], 'bobby')
        self.assertEqual(claim['beaten_distance_m'], detail['owner_distance_m'])

    def test_tied_challenges_keep_territory(self):
        first = self.save(self.payload(conquer=True))
        territory_id = first.json()['claim']['territory']['id']
        tie = self.payload(conquer=True, challenge='pace')
        tie['id'] = str(uuid.uuid4())
        response = self.save(tie, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertFalse(claim['challenge_won'])
        self.assertEqual(claim['points_awarded'], 0)
        equal = self.payload(conquer=True, challenge='distance')
        equal['id'] = str(uuid.uuid4())
        for p in equal['track']:
            p['timestamp'] = (datetime.fromisoformat(p['timestamp']) + timedelta(minutes=10)).isoformat()
        response = self.save(equal, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertFalse(claim['challenge_won'])
        self.assertEqual(claim['points_awarded'], 0)
        detail = self.client.get(
            f'/territories/{territory_id}', headers=self.bob
        ).json()
        self.assertEqual(detail['owner_display'], 'alice')

    def test_conquest_without_challenge_choice_is_rejected(self):
        self.save(self.payload(conquer=True))
        race = self.payload(conquer=True)
        race['id'] = str(uuid.uuid4())
        response = self.save(race, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertIsNone(response.json()['claim'])
        self.assertIn('ritmo ou distância', response.json()['claim_error'])

    def test_territory_without_mark_allows_legacy_takeover(self):
        first = self.save(self.payload(conquer=True))
        territory_id = first.json()['claim']['territory']['id']
        with SessionLocal() as db:
            db.query(ConquestMark).delete()
            db.commit()
        race = self.payload(conquer=True)
        race['id'] = str(uuid.uuid4())
        response = self.save(race, self.bob)
        self.assertEqual(response.status_code, 200, response.text)
        claim = response.json()['claim']
        self.assertGreater(claim['points_awarded'], 0)
        self.assertIsNone(claim['challenge_won'])
        detail = self.client.get(
            f'/territories/{territory_id}', headers=self.bob
        ).json()
        self.assertEqual(detail['owner_display'], 'bobby')

    def test_additive_initialization_preserves_existing_user(self):
        initialize_database()
        self.assertEqual(self.client.get('/users/me',headers=self.alice).status_code,200)

    def test_owner_loading_avoids_n_plus_one(self):
        from sqlalchemy import event
        from app.services.scoring import current_ownerships
        self.assertEqual(self.save(self.payload(conquer=True)).status_code,200)
        far = [(20,20),(20,20.001),(20.001,20.001),(20.001,20),(20,20)]
        self.assertEqual(self.save(self.payload(coords=far,conquer=True),self.bob).status_code,200)
        carol = self.register('carol')
        farther = [(30,30),(30,30.001),(30.001,30.001),(30.001,30),(30,30)]
        self.assertEqual(self.save(self.payload(coords=farther,conquer=True),carol).status_code,200)
        queries = []
        def count(conn, cursor, statement, parameters, context, executemany):
            queries.append(statement)
        event.listen(engine, "before_cursor_execute", count)
        try:
            with SessionLocal() as db:
                displays = [
                    o.owner_team.name if o.owner_team_id else o.owner_user.username
                    for o in current_ownerships(db)
                ]
        finally:
            event.remove(engine, "before_cursor_execute", count)
        self.assertEqual(sorted(displays), ['alice','bobby','carol'])
        self.assertLessEqual(len(queries), 3)

    def test_migrations_retry_transient_failures(self):
        from sqlalchemy.exc import OperationalError
        from app.core import database
        calls = []
        def flaky(cfg, revision):
            calls.append(revision)
            if len(calls) < 3:
                raise OperationalError("boom", None, Exception("conexao"))
            return None
        with patch("alembic.command.upgrade", side_effect=flaky), patch("app.core.database.sleep") as nap:
            database._apply_migrations()
        self.assertEqual(calls, ["head"] * 3)
        self.assertEqual(nap.call_count, 2)

    def test_migrations_stamp_current_version(self):
        from sqlalchemy import text
        initialize_database()
        with SessionLocal() as db:
            version = db.execute(text("SELECT version_num FROM alembic_version")).scalar()
        self.assertEqual(version, "0017_user_presence")

    def test_wild_endpoint_is_deterministic_and_shared(self):
        params = {"lat": -23.6489, "lng": -46.8523, "radius_km": 2}
        ways = [( "footway", [(-23.6495, -46.8530), (-23.6480, -46.8515)])]
        with patch("app.services.spawns.fetch_street_ways", return_value=ways):
            first = self.client.get("/territories/wild", params=params, headers=self.alice).json()
            second = self.client.get("/territories/wild", params=params, headers=self.bob).json()
        if first and second and first[0]["spawned_at"] != second[0]["spawned_at"]:
            self.skipTest("cruzou a hora cheia no meio do teste")
        self.assertEqual(first, second)
        self.assertTrue(first)
        keys = [s["key"] for s in first]
        self.assertEqual(len(keys), len(set(keys)))
        for s in first:
            self.assertIn(s["rarity"], ("comum", "raro", "épico"))
            spawned = datetime.fromisoformat(s["spawned_at"])
            expires = datetime.fromisoformat(s["expires_at"])
            self.assertEqual((expires - spawned).total_seconds(), 3600)
            self.assertEqual(spawned.minute, 0)

    def test_wild_spawns_rotate_each_hour(self):
        from app.services import spawns as wild
        base = datetime(2026, 10, 5, 12, 0, tzinfo=timezone.utc)
        with patch("app.services.spawns.fetch_street_ways", return_value=[]):
            first, second = set(), set()
            for dlat in (-0.01, 0.0, 0.01):
                for dlng in (-0.01, 0.0, 0.01):
                    kw = {"radius_km": 1.0, "pioneer_keep": 1.0, "activity": []}
                    first.update(s["key"] for s in wild.wild_spawns_for(
                        -23.6489 + dlat, -46.8523 + dlng, now=base, **kw))
                    second.update(s["key"] for s in wild.wild_spawns_for(
                        -23.6489 + dlat, -46.8523 + dlng,
                        now=base + timedelta(hours=1), **kw))
        self.assertTrue(first)
        self.assertTrue(second)
        self.assertFalse(first & second)

    def test_conquering_wild_spawn_consumes_it(self):
        from app.models import SpawnClaim
        from app.services import spawns as wild
        now = datetime.now(timezone.utc)
        with patch("app.services.spawns.fetch_street_ways", return_value=[]):
            spawns = wild.wild_spawns_for(
                10.0, 10.0, 2.0, now,
                activity=[(10.0, 10.0, 500.0)], pioneer_keep=1.0,
            )
            self.assertTrue(spawns)
            target = spawns[0]
            delta = 0.0005
            coords = [
                (target["lat"] - delta, target["lng"] - delta),
                (target["lat"] - delta, target["lng"] + delta),
                (target["lat"] + delta, target["lng"] + delta),
                (target["lat"] + delta, target["lng"] - delta),
                (target["lat"] - delta, target["lng"] - delta),
            ]
            payload = self.payload(coords=coords, conquer=True)
            response = self.save(payload)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertTrue(response.json()["claim"]["created_new"])
            with SessionLocal() as db:
                claimed = db.query(SpawnClaim).filter_by(spawn_key=target["key"]).count()
            self.assertEqual(claimed, 1)
            remaining = self.client.get("/territories/wild", params={
                "lat": 10.0, "lng": 10.0, "radius_km": 2,
            }, headers=self.alice).json()
            self.assertNotIn(target["key"], [s["key"] for s in remaining])

    def test_street_snapped_spawn_stays_near_ways(self):
        from app.services import spawns as wild
        ways = [("footway", [(10.0, 10.0), (10.0, 10.002)])]
        base = datetime(2026, 10, 5, 12, 0, tzinfo=timezone.utc)
        with patch("app.services.spawns.fetch_street_ways", return_value=ways):
            spawns = wild.wild_spawns_for(10.0, 10.001, 2.0, base, activity=[])
        self.assertTrue(spawns)
        for s in spawns:
            self.assertGreaterEqual(s["lat"], 9.999)
            self.assertLessEqual(s["lat"], 10.001)
            self.assertGreaterEqual(s["lng"], 9.9999)
            self.assertLessEqual(s["lng"], 10.0021)

    def test_offline_spawn_needs_activity_or_pioneer(self):
        from app.geometry import haversine_m
        from app.services import spawns as wild
        base = datetime(2026, 10, 5, 12, 0, tzinfo=timezone.utc)
        with patch("app.services.spawns.fetch_street_ways", return_value=[]):
            lonely = wild.wild_spawns_for(
                10.0, 10.0, 2.0, base, activity=[], pioneer_keep=0.0)
            self.assertEqual(lonely, [])
            near = wild.wild_spawns_for(
                10.0, 10.0, 2.0, base,
                activity=[(10.0, 10.0, 500.0)], pioneer_keep=0.0)
            self.assertTrue(near)
            for s in near:
                self.assertLessEqual(haversine_m(10.0, 10.0, s["lat"], s["lng"]), 1000)
            pioneer = wild.wild_spawns_for(
                10.0, 10.0, 2.0, base, activity=[], pioneer_keep=1.0)
            self.assertTrue(pioneer)

    def test_street_fetch_failure_returns_empty(self):
        from app.services import spawns as wild
        with patch("app.services.spawns.httpx.post", side_effect=Exception("offline")):
            self.assertEqual(wild.fetch_street_ways(10.0, 10.0), [])

    def test_conquest_stores_centroid_for_nearby_prefilter(self):
        response = self.save(self.payload(conquer=True))
        self.assertEqual(response.status_code, 200, response.text)
        territory_id = response.json()['claim']['territory']['id']
        with SessionLocal() as db:
            territory = db.get(Territory, territory_id)
            self.assertIsNotNone(territory.center_lat)
            self.assertIsNotNone(territory.center_lng)
            self.assertAlmostEqual(territory.center_lat, 10.0005, places=3)
            self.assertAlmostEqual(territory.center_lng, 10.0005, places=3)

    def test_h3_cell_populated_on_claim_and_nearby(self):
        response = self.save(self.payload(conquer=True))
        self.assertEqual(response.status_code, 200, response.text)
        territory_id = response.json()['claim']['territory']['id']
        with SessionLocal() as db:
            territory = db.get(Territory, territory_id)
            self.assertIsNotNone(territory.h3_cell)
            self.assertEqual(
                territory.h3_cell,
                cell_for(territory.center_lat, territory.center_lng),
            )
        params = {"lat": 10.0005, "lng": 10.0005}
        # Raio pequeno: pré-filtro por célula H3; raio grande: caixa legada.
        self.assertIsNotNone(covering_cells(10.0005, 10.0005, 2000))
        self.assertIsNone(covering_cells(10.0005, 10.0005, 200_000))
        near_small = self.client.get("/territories/nearby", params={
            **params, "radius_km": 2,
        }, headers=self.alice).json()
        near_big = self.client.get("/territories/nearby", params={
            **params, "radius_km": 200,
        }, headers=self.alice).json()
        self.assertEqual([t["id"] for t in near_small], [territory_id])
        self.assertEqual([t["id"] for t in near_big], [territory_id])
        far = self.client.get("/territories/nearby", params={
            "lat": -23.6, "lng": -46.85, "radius_km": 2,
        }, headers=self.alice).json()
        self.assertEqual(far, [])

    def test_h3cells_helper_validation(self):
        self.assertEqual(cell_for(10.0, 10.0), cell_for(10.0, 10.0))
        self.assertEqual(len(cell_for(10.0, 10.0)), 15)
        self.assertIn(cell_for(10.0, 10.0), covering_cells(10.0, 10.0, 500))
        self.assertIsNone(covering_cells(10.0, 10.0, 200_000))
        with self.assertRaises(ValueError):
            cell_for(91.0, 0.0)
        with self.assertRaises(ValueError):
            covering_cells(10.0, 10.0, 0)

    def test_nearby_falls_back_to_geojson_without_centroid(self):
        response = self.save(self.payload(conquer=True))
        territory_id = response.json()['claim']['territory']['id']
        with SessionLocal() as db:
            db.query(Territory).filter(Territory.id == territory_id).update({
                "center_lat": None, "center_lng": None,
            })
            db.commit()
        found = self.client.get("/territories/nearby", params={
            "lat": 10.0005, "lng": 10.0005, "radius_km": 5,
        }, headers=self.alice).json()
        self.assertEqual([t["id"] for t in found], [territory_id])


class MailDeliveryTests(unittest.TestCase):
    def test_disabled_mail_backend_raises_without_logging_secrets(self):
        with patch('app.services.mail.settings.mail_backend', 'disabled'):
            with self.assertLogs('app.services.mail', level='WARNING') as logs:
                with self.assertRaisesRegex(RuntimeError, 'not configured'):
                    send_reset_email('private@example.com', 'secret-token')
        self.assertNotIn('private@example.com', '\n'.join(logs.output))
        self.assertNotIn('secret-token', '\n'.join(logs.output))

    def test_mail_delivery_exception_is_reraised_without_logging_details(self):
        with patch('app.services.mail.settings.mail_backend', 'smtp'), patch(
            'app.services.mail.smtplib.SMTP', side_effect=OSError('provider secret')
        ):
            with self.assertLogs('app.services.mail', level='ERROR') as logs:
                with self.assertRaisesRegex(OSError, 'provider secret'):
                    send_reset_email('private@example.com', 'secret-token')
        logged = '\n'.join(logs.output)
        self.assertNotIn('private@example.com', logged)
        self.assertNotIn('secret-token', logged)
        self.assertNotIn('provider secret', logged)


if __name__ == '__main__':
    unittest.main()
