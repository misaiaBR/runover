import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/screens/badges_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show insigniasData;

Future<void> openScreen(
  WidgetTester tester, {
  bool fail = false,
  int failures = 1,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var attempts = 0;
  final api = ApiClient(
    client: MockClient((request) async {
      if (request.url.path != '/badges') return http.Response('{}', 404);
      attempts++;
      if (fail && attempts <= failures) {
        return http.Response('{"detail":"Indisponível"}', 503);
      }
      return http.Response(jsonEncode(insigniasData), 200);
    }),
  );
  addTearDown(api.close);
  final state = AppState(api: api);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildRunoverTheme(),
        home: const BadgesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the screen lists the catalog with the earned date and the '
      'progress of what is still locked', (tester) async {
    await openScreen(tester);
    expect(find.text('Ganhas · 2 de 5'), findsOneWidget);
    expect(find.text('Ganha em 7 de mar. de 2026'), findsOneWidget);
    expect(find.text('Ganha em 2 de abr. de 2026'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Meia maratona'), 200);
    expect(find.text('Bloqueada · 10,4 de 21'), findsOneWidget);
    expect(find.text('Bloqueada · 2 de 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed catalog offers a retry that loads it', (tester) async {
    await openScreen(tester, fail: true);
    expect(find.text('Não foi possível carregar suas insígnias.'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ganhas · 2 de 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
