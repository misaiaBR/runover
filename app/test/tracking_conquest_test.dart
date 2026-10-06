import 'dart:convert';

import 'package:flutter/material.dart';
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
  Position pos = _fix(-23.6489, -46.8523);

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
      pos;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      const Stream.empty();
}

Position _fix(double lat, double lng) => Position(
  longitude: lng,
  latitude: lat,
  timestamp: DateTime.now(),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Map<String, dynamic> _wild(double lat, double lng) => {
  'key': 'w1',
  'center': {'lat': lat, 'lng': lng},
  'radius_m': 100,
  'relevance': 1,
  'rarity': 'comum',
  'spawned_at': '2026-10-06T00:00:00Z',
  'expires_at': '2026-10-07T00:00:00Z',
};

void main() {
  late _FakeGeo geo;
  late GeolocatorPlatform original;

  setUp(() {
    geo = _FakeGeo();
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  Future<void> open(
    WidgetTester tester, {
    required double wildLat,
    required double wildLng,
  }) async {
    SharedPreferences.setMockInitialValues({});
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
            jsonEncode([_wild(wildLat, wildLng)]),
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
          home: const TrackingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tentar conquistar território'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Iniciar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iniciar'));
    await tester.pumpAndSettle();
  }

  testWidgets('sobre o selvagem mantem a conquista', (tester) async {
    await open(tester, wildLat: -23.6489, wildLng: -46.8523);
    expect(find.text('Pausar'), findsOneWidget);
    expect(find.textContaining('corrida normal'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('longe do selvagem vira corrida normal', (tester) async {
    await open(tester, wildLat: -22.0, wildLng: -46.0);
    expect(find.text('Pausar'), findsOneWidget);
    expect(find.textContaining('corrida normal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
