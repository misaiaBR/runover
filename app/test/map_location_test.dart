import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/map_screen.dart';
import 'package:runover_app/screens/tracking_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/services/position_refiner.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/widgets/crown_icon.dart';
import 'package:runover_app/widgets/play_mode_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_screen_test.dart' show profileData;

class FakeGeolocation extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  Position position = fix(accuracy: 1500);
  Object? error;
  int requests = 0;
  LocationSettings? requestedSettings;
  Stream<Position> updates = const Stream.empty();

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      updates;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    requests++;
    requestedSettings = locationSettings;
    if (error != null) throw error!;
    return position;
  }
}

Position fix({required double accuracy, double lat = -23.7, DateTime? time}) =>
    Position(
      longitude: -46.7,
      latitude: lat,
      timestamp: time ?? DateTime.now(),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late GeolocatorPlatform original;
  late FakeGeolocation geo;
  late ApiClient api;

  setUp(() {
    original = GeolocatorPlatform.instance;
    geo = FakeGeolocation();
    GeolocatorPlatform.instance = geo;
    api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/territories') return http.Response('[]', 200);
        if (request.url.path == '/location') return http.Response('', 204);
        return http.Response('{"detail":"Sessão de teste"}', 401);
      }),
    );
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
    api.close();
  });

  Future<void> pumpMap(WidgetTester tester) async {
    // Map markers pulse continuously, and a coarse position can spend up to
    // 15 seconds in the location refiner. Advance the fake clock without
    // waiting for all animations to stop.
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
  }

  /// Todos os marcadores visíveis: as camadas são separadas por categoria
  /// (livres, dominados, selvagens, posição) para o foco da mecânica apagar
  /// cada uma sem tocar nas outras.
  Iterable<Marker> allMarkers(WidgetTester tester) =>
      tester
          .widgetList<MarkerLayer>(find.byType(MarkerLayer))
          .expand((layer) => layer.markers);

  Future<void> openMap(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: api),
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await pumpMap(tester);
  }

  testWidgets('coarse location displays uncertainty in meters on the map', (
    tester,
  ) async {
    await openMap(tester);
    expect(
      find.textContaining('Localização aproximada: margem informada de 1.5 km'),
      findsOneWidget,
    );
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 1500);
    expect(circle.useRadiusInMeter, isTrue);
    expect(geo.requestedSettings!.accuracy, LocationAccuracy.best);
    expect(geo.requestedSettings!.timeLimit, const Duration(seconds: 15));
  });

  testWidgets('fresh location replaces the old point, circle and camera', (
    tester,
  ) async {
    await openMap(tester);
    geo.position = fix(accuracy: 12, lat: -23.6);
    await tester.tap(find.byTooltip('Atualizar localização'));
    await pumpMap(tester);
    expect(geo.requests, 2);
    expect(
      find.text('Localização estimada: margem informada de 12 m.'),
      findsOneWidget,
    );
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 12);
    expect(circle.point.latitude, -23.6);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController!.camera.center.latitude, -23.6);
  });

  testWidgets('map uses a refined reading instead of the first coarse fix', (
    tester,
  ) async {
    geo.position = fix(accuracy: 19800);
    geo.updates = Stream.fromIterable([fix(accuracy: 12, lat: -23.6)]);
    await openMap(tester);
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 12);
    expect(circle.point.latitude, -23.6);
    expect(
      find.text('Localização estimada: margem informada de 12 m.'),
      findsOneWidget,
    );
  });

  testWidgets('denied permission is explained without placing a user marker', (
    tester,
  ) async {
    geo.permission = LocationPermission.deniedForever;
    await openMap(tester);
    expect(
      find.textContaining('Permita o acesso à localização'),
      findsOneWidget,
    );
    expect(geo.requests, 0);
    expect(allMarkers(tester), isEmpty);
    expect(find.byType(CircleLayer), findsNothing);
  });

  testWidgets(
    'failed refresh removes the old point and offers another attempt',
    (tester) async {
      await openMap(tester);
      geo.error = TimeoutException('timeout');
      await tester.tap(find.byTooltip('Atualizar localização'));
      await pumpMap(tester);
      expect(find.textContaining('A localização demorou'), findsOneWidget);
      expect(allMarkers(tester), isEmpty);
      expect(find.byType(CircleLayer), findsNothing);
      geo.error = null;
      await tester.tap(find.byTooltip('Atualizar localização'));
      await pumpMap(tester);
      expect(find.byType(CircleLayer), findsOneWidget);
    },
  );

  testWidgets('unknown accuracy is not presented as a precise fix', (
    tester,
  ) async {
    geo.position = fix(accuracy: 0);
    await openMap(tester);
    expect(find.textContaining('não informou a precisão'), findsOneWidget);
    expect(find.byType(CircleLayer), findsNothing);
  });

  testWidgets('old fixes do not appear as the current position', (
    tester,
  ) async {
    geo.position = fix(
      accuracy: 10,
      time: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    await openMap(tester);
    expect(
      find.textContaining('posição recebida está desatualizada'),
      findsOneWidget,
    );
    expect(allMarkers(tester), isEmpty);
  });

  testWidgets('o mapa obedece ao modo escolhido na dica', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: api),
        child: const MaterialApp(
          home: MapScreen(focus: PlayMode.huntWild),
        ),
      ),
    );
    await pumpMap(tester);
    expect(find.textContaining('Caçando selvagem'), findsOneWidget);
    await tester.tap(find.byTooltip('Dispensar dica'));
    await tester.pump();
    expect(find.textContaining('Caçando selvagem'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'refinement keeps the best valid reading within a fixed deadline',
    () async {
      final stream = StreamController<Position>();
      geo.updates = stream.stream;
      final refiner = PositionRefiner();
      Position? result;
      final pending = refiner
          .refine(fix(accuracy: 19800))
          .then((p) => result = p);
      stream.add(fix(accuracy: 500));
      await Future<void>.delayed(const Duration(seconds: 10));
      stream.add(fix(accuracy: 800));
      stream.add(fix(accuracy: 1, lat: double.nan));
      stream.add(
        fix(
          accuracy: 1,
          time: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
      );
      stream.add(fix(accuracy: 0));
      expect(result, isNull);

      await pending;
      expect(result!.accuracy, 500);
      expect(stream.hasListener, isFalse);
      unawaited(stream.close());
      refiner.dispose();
    },
  );

  test('precise first fix does not start an extra subscription', () async {
    final stream = StreamController<Position>();
    geo.updates = stream.stream;
    final refiner = PositionRefiner();
    final initial = fix(accuracy: 10);
    expect(await refiner.refine(initial), same(initial));
    expect(stream.hasListener, isFalse);
    unawaited(stream.close());
    refiner.dispose();
  });

  test('silent provider times out and retains the approximate fix', () async {
    final stream = StreamController<Position>();
    geo.updates = stream.stream;
    final refiner = PositionRefiner();
    final initial = fix(accuracy: 19800);
    final pending = refiner.refine(initial);

    expect(await pending, same(initial));
    expect(stream.hasListener, isFalse);
    unawaited(stream.close());
    refiner.dispose();
  });

  test('provider errors retain the fix and release the subscription', () async {
    final stream = StreamController<Position>();
    geo.updates = stream.stream;
    final refiner = PositionRefiner();
    final initial = fix(accuracy: 19800);
    final pending = refiner.refine(initial);
    stream.addError(StateError('provider unavailable'));

    expect(await pending, same(initial));
    expect(stream.hasListener, isFalse);
    unawaited(stream.close());
    refiner.dispose();
  });

  testWidgets('disposing the map stops an ongoing location refinement', (
    tester,
  ) async {
    final stream = StreamController<Position>();
    geo.updates = stream.stream;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: api),
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await tester.pump();
    expect(stream.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(stream.hasListener, isFalse);
    unawaited(stream.close());
  });

  Map<String, dynamic> territoryJson(
    String id,
    String? owner, {
    double lat = -23.7,
  }) => {
    'id': id,
    'name': id,
    'coordinates': [
      {'lat': lat - .001, 'lng': -46.7},
      {'lat': lat - .001, 'lng': -46.699},
      {'lat': lat + .001, 'lng': -46.699},
      {'lat': lat + .001, 'lng': -46.7},
    ],
    'center': {'lat': lat, 'lng': -46.6995},
    'radius_m': 100,
    'status': owner == null ? 'disponivel' : 'conquistado',
    'owner_type': owner == null ? null : 'user',
    'owner_display': owner,
    'takeovers': 0,
  };

  testWidgets('free areas show no crown until conquered', (tester) async {
    final localApi = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/territories') {
          return http.Response(
            jsonEncode([
              territoryJson('livre', null),
              territoryJson('dominado', 'rival', lat: -23.701),
            ]),
            200,
          );
        }
        if (request.url.path == '/location') {
          return http.Response('', 204);
        }
        return http.Response('{"detail":"Sessão de teste"}', 401);
      }),
    );
    addTearDown(localApi.close);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: localApi),
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await pumpMap(tester);
    expect(find.byType(CrownIcon), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the territory body opens its sheet', (tester) async {
    final localApi = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/territories') {
          return http.Response(
            jsonEncode([
              {
                'id': 'tocavel',
                'name': 'Área Tocável',
                // Quadrado ao redor da posição do usuário (-23.7, -46.7),
                // com o centro ~78m ao norte: o toque no centro da tela
                // cai dentro do polígono e longe do marcador.
                'coordinates': [
                  {'lat': -23.7005, 'lng': -46.7012},
                  {'lat': -23.7005, 'lng': -46.6988},
                  {'lat': -23.6981, 'lng': -46.6988},
                  {'lat': -23.6981, 'lng': -46.7012},
                ],
                'center': {'lat': -23.6993, 'lng': -46.7},
                'radius_m': 100,
                'status': 'conquistado',
                'owner_type': 'user',
                'owner_display': 'rival',
                'takeovers': 0,
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/location') {
          return http.Response('', 204);
        }
        return http.Response('{"detail":"Sessão de teste"}', 401);
      }),
    );
    addTearDown(localApi.close);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(api: localApi),
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await pumpMap(tester);

    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Área Tocável'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o spawn selvagem abre a corrida já mirando nele', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final expires = DateTime.now().add(const Duration(minutes: 30));
    final localApi = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/territories') return http.Response('[]', 200);
        if (request.url.path == '/territories/wild') {
          return http.Response(
            jsonEncode([
              {
                'key': 'selvagem-1',
                // Exatamente a posição do usuário: o marcador cai no centro
                // da tela e o toque o atinge.
                'center': {'lat': -23.7, 'lng': -46.7},
                'radius_m': 120,
                'relevance': 3,
                'rarity': 'comum',
                'spawned_at': DateTime.now().toUtc().toIso8601String(),
                'expires_at': expires.toUtc().toIso8601String(),
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/location') return http.Response('', 204);
        return http.Response('{"detail":"Sessão de teste"}', 401);
      }),
    );
    addTearDown(localApi.close);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) =>
            AppState(api: localApi)
              ..profile = UserProfile.fromJson(profileData)
              ..status = AuthStatus.signedIn,
        child: const MaterialApp(home: MapScreen()),
      ),
    );
    await pumpMap(tester);

    // O spawn está exatamente na posição do usuário, então o centro do mapa é
    // o centro do marcador: é o toque no mapa que abre a ficha.
    await tester.tapAt(tester.getCenter(find.byType(FlutterMap)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Território selvagem (comum)'), findsOneWidget);
    expect(find.text('Correr até aqui'), findsOneWidget);

    await tester.tap(find.text('Correr até aqui'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TrackingScreen), findsOneWidget);
    expect(
      find.textContaining('Rumo ao território selvagem'),
      findsOneWidget,
    );
    // Viemos do mapa buscando conquista: a corrida nasce como conquista.
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
