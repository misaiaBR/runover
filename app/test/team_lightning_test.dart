import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/lightning_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

import 'profile_screen_test.dart' show profileData;

Map<String, dynamic> lightningBoard({bool joined = false}) {
  final participants = ['marina', if (joined) 'eu'];
  return {
    'id': 'sess1',
    'team_id': 't1',
    'team_name': 'Trovão',
    'duration_min': 15,
    'starts_at': DateTime.now()
        .subtract(const Duration(minutes: 5))
        .toIso8601String(),
    'ends_at': DateTime.now()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
    'open': true,
    'finalized': false,
    'takes': 2,
    'points': 250,
    'bonus_points': 0,
    'mvp': 'marina',
    'participants': participants,
    'entries': [
      {'username': 'marina', 'takes': 2, 'points': 250},
      if (joined) {'username': 'eu', 'takes': 0, 'points': 0},
    ],
  };
}

Map<String, dynamic> closedBoard() => {
  ...lightningBoard(joined: true),
  'open': false,
  'finalized': true,
  'bonus_points': 125,
};

Future<void> openBoard(
  WidgetTester tester, {
  required ApiClient api,
  required UserProfile profile,
}) async {
  final state = AppState(api: api)..profile = profile;
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildRunoverTheme(),
        home: const LightningScreen(sessionId: 'sess1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

UserProfile meAs(String username) => UserProfile.fromJson(
  Map<String, dynamic>.of(profileData)..['username'] = username,
);

void main() {
  testWidgets('placar aberto mostra tomadas, MVP e participantes', (
    tester,
  ) async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/lightning/sess1') {
          return http.Response(jsonEncode(lightningBoard()), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    await openBoard(tester, api: api, profile: meAs('marina'));

    expect(find.text('Relâmpago aberto!'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('@marina'), findsNWidgets(2));
    // Já participa: sem botão de entrada.
    expect(find.text('Participar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('participar chama a API e atualiza o placar', (tester) async {
    var joined = false;
    final calls = <String>[];
    final api = ApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/lightning/sess1') {
          return http.Response(
            jsonEncode(lightningBoard(joined: joined)),
            200,
          );
        }
        if (request.method == 'POST' && path == '/lightning/sess1/join') {
          calls.add('join');
          joined = true;
          return http.Response(
            jsonEncode(lightningBoard(joined: true)),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    await openBoard(tester, api: api, profile: meAs('eu'));

    await tester.tap(find.text('Participar'));
    await tester.pumpAndSettle();
    expect(calls, ['join']);
    expect(find.text('Você entrou no relâmpago!'), findsOneWidget);
    expect(find.text('@eu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('placar encerrado mostra espólio e esconde a entrada', (
    tester,
  ) async {
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/lightning/sess1') {
          return http.Response(jsonEncode(closedBoard()), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    await openBoard(tester, api: api, profile: meAs('eu'));

    expect(find.text('Relâmpago encerrado'), findsOneWidget);
    expect(find.textContaining('+125 pontos no cofre'), findsOneWidget);
    expect(find.text('Participar'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao carregar oferece nova tentativa', (tester) async {
    var attempts = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/lightning/sess1') {
          attempts++;
          if (attempts == 1) return http.Response('{"detail":"x"}', 500);
          return http.Response(jsonEncode(lightningBoard()), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    await openBoard(tester, api: api, profile: meAs('marina'));

    expect(
      find.text('Não foi possível carregar o relâmpago.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Relâmpago aberto!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
