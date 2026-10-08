import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/ranking_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

const rankingData = [
  {
    'position': 1,
    'owner_type': 'user',
    'name': 'misaia',
    'photo_url': null,
    'total_score': 900,
    'territories_count': 15,
    'level': 4,
  },
  {
    'position': 2,
    'owner_type': 'user',
    'name': 'ana',
    'photo_url': null,
    'total_score': 450,
    'territories_count': 8,
    'level': 3,
  },
  {
    'position': 3,
    'owner_type': 'team',
    'name': 'Lobos do Asfalto',
    'photo_url': null,
    'total_score': 320,
    'territories_count': 6,
    'level': 2,
  },
];

void main() {
  Future<void> open(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/ranking') {
          return http.Response(jsonEncode(rankingData), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson({
        'id': '1',
        'full_name': 'Misaia',
        'username': 'misaia',
        'email': 'misaia@example.com',
        'total_score': 900,
        'territories_count': 15,
      });
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          darkTheme: buildRunoverTheme(brightness: Brightness.dark),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: const RankingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ranking reference layout is visible in light mode', (
    tester,
  ) async {
    await open(tester, Brightness.light);
    expect(find.text('Ranking'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Jogadores'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Ranking')).style?.color,
      Theme.of(tester.element(find.text('Ranking'))).colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ranking reference layout is visible in dark mode', (
    tester,
  ) async {
    await open(tester, Brightness.dark);
    expect(find.text('Ranking'), findsOneWidget);
    expect(find.text('Semana'), findsOneWidget);
    expect(find.text('Jogadores'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Ranking')).style?.color,
      Theme.of(tester.element(find.text('Ranking'))).colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ranking title adapts to brightness', (tester) async {
    Future<Color?> titleColor(Brightness brightness) async {
      await open(tester, brightness);
      return tester.widget<Text>(find.text('Ranking')).style?.color;
    }

    final light = await titleColor(Brightness.light);
    final dark = await titleColor(Brightness.dark);
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light, isNot(dark));
  });
}
