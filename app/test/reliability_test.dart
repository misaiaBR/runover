import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/services/run_store.dart';
import 'package:runover_app/services/session_store.dart';
import 'package:runover_app/services/run_sync.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/screens/forgot_password_screen.dart';
import 'package:runover_app/screens/tracking_route_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'timeout is recoverable and leaves the request payload unchanged',
    () async {
      final sent = <String>[];
      var first = true;
      final api = ApiClient(
        timeout: const Duration(milliseconds: 10),
        client: MockClient((request) async {
          sent.add(request.body);
          if (first) {
            first = false;
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          return http.Response('{"id":"same-run"}', 200);
        }),
      );
      final payload = {'id': 'same-run', 'track': []};
      await expectLater(
        api.saveRun(payload),
        throwsA(
          isA<ApiException>().having((e) => e.retryable, 'retryable', true),
        ),
      );
      expect((await api.saveRun(payload))['id'], 'same-run');
      expect(sent[0], sent[1]);
      api.close();
    },
  );

  test('non-JSON server errors become ApiException', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => http.Response('<h1>Unavailable</h1>', 503),
      ),
    );
    await expectLater(
      api.getProgress(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
    );
    api.close();
  });

  test('transport failures become recoverable errors', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      api.listRuns(),
      throwsA(
        isA<ApiException>().having((e) => e.retryable, 'retryable', true),
      ),
    );
    api.close();
  });

  test(
    'bootstrap retains token on temporary failure, removes it on 401',
    () async {
      // Sessão temporária: o token vive no SessionStore, nunca no
      // armazenamento persistente.
      SessionStore.clearToken();
      SessionStore.saveToken('local-token');
      var status = 503;
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response('{"detail":"unavailable"}', status),
        ),
      );
      final state = AppState(api: api);
      await state.bootstrap();
      expect(state.status, AuthStatus.unavailable);
      expect(api.isAuthenticated, isTrue);
      status = 401;
      await state.bootstrap();
      expect(state.status, AuthStatus.signedOut);
      expect(api.isAuthenticated, isFalse);
      state.dispose();
      api.close();
    },
  );

  test('draft survives reopening and is isolated by account', () async {
    final draft = RunDraft.create();
    draft.track.add({
      'lat': 10.0,
      'lng': 10.0,
      'timestamp': '2026-10-03T12:00:00Z',
      'segment': 0,
    });
    draft.queued = true;
    draft.conquer = true;
    await RunStore('alice').save(draft);
    final restored = (await RunStore('alice').list()).single;
    expect(jsonEncode(restored.payload), jsonEncode(draft.payload));
    expect(restored.queued, isTrue);
    expect(await RunStore('bob').list(), isEmpty);
    await RunStore('alice').remove(draft.id);
    expect(await RunStore('alice').list(), isEmpty);
  });

  test(
    'concurrent persistence preserves the latest snapshot and other drafts',
    () async {
      final store = RunStore('alice');
      final a = RunDraft.create(), b = RunDraft.create();
      final first = store.save(a);
      a.name = 'Last snapshot';
      await Future.wait([first, store.save(a), store.save(b)]);
      final drafts = await store.list();
      expect(drafts.length, 2);
      expect(drafts.singleWhere((d) => d.id == a.id).name, 'Last snapshot');
    },
  );

  test('repeated resume without a GPS fix does not skip segments', () {
    final draft = RunDraft.create();
    draft.beginSegment();
    expect(draft.segment, 0);
    draft.track.add({
      'lat': 10.0,
      'lng': 10.0,
      'timestamp': '2026-10-03T12:00:00Z',
      'segment': 0,
    });
    draft.beginSegment();
    draft.beginSegment();
    expect(draft.segment, 1);
    draft.track.add({
      'lat': 10.001,
      'lng': 10.0,
      'timestamp': '2026-10-03T12:01:00Z',
      'segment': 1,
    });
    draft.beginSegment();
    expect(draft.segment, 2);
  });

  test('explicit rejection allows correcting a persisted run', () async {
    for (final status in [400, 403, 422]) {
      final store = RunStore('alice-$status');
      final draft = RunDraft.create();
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response('{"detail":"Corrija os dados"}', status),
        ),
      );
      await expectLater(
        RunSync(api, store).submit(draft),
        throwsA(isA<ApiException>()),
      );
      expect(draft.queued, isFalse);
      final restored = (await store.list()).single;
      expect(restored.id, draft.id);
      expect(restored.queued, isFalse);
      api.close();
    }
  });

  test(
    'uncertain or conflicting upload stays frozen until confirmed',
    () async {
      for (final status in [null, 409, 500]) {
        final store = RunStore('alice-$status');
        final draft = RunDraft.create();
        final requests = <String>[];
        var rejected = true;
        final api = ApiClient(
          client: MockClient((request) async {
            requests.add(request.body);
            if (rejected) {
              if (status == null) throw http.ClientException('offline');
              return http.Response('{"detail":"Tente novamente"}', status);
            }
            return http.Response(jsonEncode({'id': draft.id}), 200);
          }),
        );
        final sync = RunSync(api, store);
        await expectLater(sync.submit(draft), throwsA(isA<ApiException>()));
        final restored = (await store.list()).single;
        expect(restored.queued, isTrue);
        rejected = false;
        final result = await sync.submit(restored);
        expect(result['id'], draft.id);
        expect(requests.first, requests.last);
        expect(await store.list(), isEmpty);
        api.close();
      }
    },
  );

  test('gps validator rejects noisy and impossible points', () {
    final points = [
      {
        'lat': -23.55,
        'lng': -46.63,
        'timestamp': '2026-10-03T12:00:00Z',
        'accuracy': 10,
      },
      {
        'lat': -23.5501,
        'lng': -46.6301,
        'timestamp': '2026-10-03T12:00:10Z',
        'accuracy': 20,
      },
      {
        'lat': -23.55,
        'lng': -46.63,
        'timestamp': '2026-10-03T12:00:11Z',
        'accuracy': 10,
      },
      {
        'lat': -23.55,
        'lng': -46.63,
        'timestamp': '2026-10-03T12:00:12Z',
        'accuracy': 90,
      },
    ];
    final filtered = TrackingScreenRouteProcessor.filterTrack(
      points,
      accuracy: 60,
    );
    expect(filtered.length, 3);
    expect(filtered.last['lat'], closeTo(-23.55, 0.0001));
  });

  test('o salto do GPS é julgado pelo intervalo fracionário', () {
    // 0,9 s e 5,9 s eram truncados para 0 e 5. O salto de 0,9 s deixava de ser
    // leitura torta e encerrava a gravação na primeira leitura torta; o
    // deslocamento de 5,9 s era jogado fora como salto.
    const base = {
      'lat': 0.0,
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:00.000Z',
    };
    const quaseUmSegundo = {
      'lat': 0.0025, // ~278 m em 0,9 s
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:00.900Z',
    };
    const quaseSeisSegundos = {
      'lat': 0.0025, // ~278 m em 5,9 s
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:05.900Z',
    };
    const perto = {
      'lat': 0.0005, // ~56 m em 2 s: corrida normal
      'lng': 0.0,
      'timestamp': '2026-10-13T18:00:02.000Z',
    };
    expect(
      TrackingScreenRouteProcessor.looksLikeBadFix(base, quaseUmSegundo),
      isTrue,
    );
    expect(
      TrackingScreenRouteProcessor.looksLikeBadFix(base, quaseSeisSegundos),
      isFalse,
    );
    expect(TrackingScreenRouteProcessor.looksLikeBadFix(base, perto), isFalse);
  });

  test(
    'route simplifier keeps meaningful turns and removes redundant points',
    () {
      final points = [
        {
          'lat': -23.55,
          'lng': -46.63,
          'timestamp': '2026-10-03T12:00:00Z',
          'accuracy': 10,
        },
        {
          'lat': -23.55001,
          'lng': -46.63001,
          'timestamp': '2026-10-03T12:00:05Z',
          'accuracy': 10,
        },
        {
          'lat': -23.55002,
          'lng': -46.63002,
          'timestamp': '2026-10-03T12:00:10Z',
          'accuracy': 10,
        },
        {
          'lat': -23.551,
          'lng': -46.631,
          'timestamp': '2026-10-03T12:00:20Z',
          'accuracy': 10,
        },
        {
          'lat': -23.552,
          'lng': -46.632,
          'timestamp': '2026-10-03T12:00:30Z',
          'accuracy': 10,
        },
      ];
      final simplified = TrackingScreenRouteProcessor.simplifyTrack(
        points,
        minDistanceMeters: 12,
      );
      expect(simplified.length, lessThan(points.length));
      expect(simplified.first['lat'], closeTo(-23.55, 0.0001));
      expect(simplified.last['lat'], closeTo(-23.552, 0.0001));
    },
  );

  testWidgets('password recovery requires the code received by email', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final api = ApiClient(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"message":"Instructions sent if registered"}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: api),
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'alice@example.com');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.text('Código recebido por e-mail'), findsOneWidget);
    expect(requests.length, 1);
    expect(requests.single.url.path, '/auth/forgot-password');
    expect(find.textContaining('modo demonstração'), findsNothing);
    api.close();
  });

  test('o alvo declarado do desafio viaja com a corrida', () {
    final draft = RunDraft(
      id: 'draft-alvo',
      track: const [],
      conquer: true,
      challenge: 'distance',
      targetTerritoryId: 'territorio-9',
    );
    expect(draft.payload['target_territory_id'], 'territorio-9');
    final restored = RunDraft.fromJson(
      jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
    );
    expect(restored.targetTerritoryId, 'territorio-9');
    expect(restored.challenge, 'distance');
    // Sem alvo (laço livre, caçada), o campo vai nulo: o servidor decide pela
    // sobreposição, como sempre decidiu.
    expect(RunDraft(id: 'draft-sem-alvo', track: const []).payload.containsKey(
      'target_territory_id',
    ), isTrue);
    expect(
      RunDraft(id: 'draft-sem-alvo-2', track: const []).payload[
        'target_territory_id'
      ],
      isNull,
    );
  });
}
