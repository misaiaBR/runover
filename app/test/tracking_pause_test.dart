import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/tracking_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

class _FakeGeo extends GeolocatorPlatform {
  _FakeGeo({this.positions = const [], this.streamError = false});

  /// Posições que o stream entrega depois do Iniciar — para testar o que a
  /// tela faz com um par de pontos de veículo.
  final List<Position> positions;

  /// O stream falha depois de entregar as posições: é o GPS caindo no meio da
  /// corrida, o único caso em que a gravação para sozinha.
  final bool streamError;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async =>
      _fix();

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) async* {
    for (final position in positions) {
      yield position;
    }
    if (streamError) throw Exception('sem sinal');
  }
}

Position _fix() => Position(
  longitude: -46.8523,
  latitude: -23.6489,
  timestamp: DateTime.now(),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late GeolocatorPlatform original;

  setUp(() {
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _FakeGeo();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Map<String, dynamic> draftJson() => {
    'id': '11111111-1111-4111-8111-111111111111',
    'track': [
      for (var i = 0; i < 3; i++)
        {
          'lat': -23.6489,
          'lng': -46.8523 + i * 0.0001,
          'timestamp': DateTime.now()
              .subtract(Duration(minutes: 3 - i))
              .toIso8601String(),
          'segment': 0,
        },
    ],
    'name': '',
    'segment': 0,
    'queued': false,
    'conquer': true,
    'challenge': 'pace',
    'team_id': null,
  };

  Future<void> open(
    WidgetTester tester, {
    Territory? challengeTarget,
    Map<String, dynamic>? draft,
    List<Position>? positions,
    bool streamError = false,
  }) async {
    if (positions != null || streamError) {
      GeolocatorPlatform.instance = _FakeGeo(
        positions: positions ?? const [],
        streamError: streamError,
      );
    }
    SharedPreferences.setMockInitialValues({
      'runover_drafts_profile-test': jsonEncode([draft ?? draftJson()]),
    });
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/territories') {
          return http.Response('[]', 200);
        }
        if (request.url.path == '/territories/wild') {
          return http.Response(
            jsonEncode([
              {
                'key': 'w1',
                'center': {'lat': -23.6489, 'lng': -46.8523},
                'radius_m': 100,
                'relevance': 1,
                'rarity': 'comum',
                'spawned_at': '2026-10-06T00:00:00Z',
                'expires_at': '2026-10-07T00:00:00Z',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileData)
      ..status = AuthStatus.signedIn;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: TrackingScreen(challengeTarget: challengeTarget),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('não existe pausar: a gravação vai do Iniciar ao Salvar',
      (tester) async {
    await open(tester);
    expect(find.text('Continuar'), findsOneWidget);

    await tester.ensureVisible(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // A pessoa não tem como interromper de propósito, então não há botão de
    // pausa, nem aviso de pausa, nem pausa registrada no resumo.
    expect(find.text('Pausar'), findsNothing);
    expect(find.text('Pausar corrida?'), findsNothing);
    expect(find.textContaining('Pausas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parada automática do GPS deixa continuar', (tester) async {
    await open(tester, streamError: true);
    await tester.ensureVisible(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    expect(find.textContaining('O GPS foi interrompido'), findsOneWidget);
    expect(find.textContaining('Pausas (1): GPS'), findsOneWidget);
    expect(find.text('Pausar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminar para enviar não conta como pausa', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Salvar corrida'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar corrida'));
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();

    // O envio falha (a API do teste não responde), e a gravação terminada para
    // enviar não pode aparecer como pausa: antes aparecia, e duas tentativas
    // viravam duas "pausas" que ninguém fez.
    expect(find.textContaining('permanece neste aparelho'), findsOneWidget);
    expect(find.textContaining('Pausas'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desafiar com corrida em andamento avisa em vez de trocar de alvo',
      (tester) async {
    await open(tester, challengeTarget: _rivalTerritory());
    expect(
      find.textContaining('o desafio escolhido não foi aplicado'),
      findsOneWidget,
    );
    // A dica do alvo declarado não pode aparecer num percurso que não o carrega.
    expect(find.textContaining('Desafio declarado'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final rows =
        jsonDecode(prefs.getString('runover_drafts_profile-test')!) as List;
    expect(rows.single['target_territory_id'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rascunho sem trajeto adota o alvo escolhido no mapa',
      (tester) async {
    await open(
      tester,
      challengeTarget: _rivalTerritory(),
      draft: draftJson()..['track'] = [],
    );
    final prefs = await SharedPreferences.getInstance();
    final rows =
        jsonDecode(prefs.getString('runover_drafts_profile-test')!) as List;
    expect(rows.single['target_territory_id'], 'territorio-alvo');
    expect(rows.single['conquer'], isTrue);
    expect(find.textContaining('Desafio declarado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movimento de veículo pausa o registro em vez de gravar',
      (tester) async {
    // A barra de ação fica abaixo dos 600 px da dobra de teste: sem janela alta
    // o toque em "Iniciar" cai fora da tela e a gravação nem começa.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await open(
      tester,
      draft: draftJson()..['track'] = [],
      positions: [_fixAt(0), _fixAt(5, latStep: 0.0018)],
    );
    await tester.tap(find.text('Iniciar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('mais rápido que uma corrida'), findsOneWidget);
    // O ponto de trem não entra no trajeto: com só o primeiro ponto gravado a
    // corrida continua em 0,00 km, e a pausa aparece com o motivo.
    expect(find.textContaining('0.00 km'), findsOneWidget);
    expect(find.textContaining('Pausas (1): veículo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// ~200 m em 5 s = 40 m/s: acima do teto que o servidor usa para decidir que o
/// movimento não é de uma corrida (`max_plausible_speed_mps`).
Position _fixAt(int second, {double latStep = 0}) => Position(
  longitude: -46.8523,
  latitude: -23.6489 + latStep,
  timestamp: DateTime.utc(2026, 10, 13, 18, 0, second),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Territory _rivalTerritory() => Territory.fromJson({
  'id': 'territorio-alvo',
  'name': 'Praça do Desafio',
  'coordinates': const [],
  'center': const {'lat': -23.6489, 'lng': -46.8523},
  'radius_m': 80,
  'status': 'conquistado',
  'owner_type': 'user',
  'owner_display': 'outro',
  'takeovers': 0,
});
