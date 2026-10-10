import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/public_profile_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/league_emblem.dart';

import 'profile_screen_test.dart' show profileData;const publicData = {
  'username': 'ana',
  'photo_url': null,
  'total_score': 450,
  'territories_count': 8,
  'rank_position': 2,
  'team_name': 'Lobos do Asfalto',
  'level': 3,
  'level_progress': 0.5,
  'points_to_next_level': 200,
  'equipped_emoticons': ['🏆'],
  'league': {
    'league': 'turbo',
    'name': 'Turbo',
    'color': '#F5A524',
    'shape': 'triangle',
    'division': 2,
  },
};

void main() {
  http.Response jsonResponse(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<void> open(
    WidgetTester tester, {
    int status = 200,
    Map<String, dynamic>? body,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/users/ana') {
          return jsonResponse(body ?? publicData, status);
        }
        return jsonResponse({}, 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileData);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const PublicProfileScreen(username: 'ana'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('perfil público segue a lógica da tela de perfil', (
    tester,
  ) async {
    await open(tester);
    // Cartão de identidade: nome, nível, apelido, emoticons, equipe.
    expect(find.text('ana'), findsOneWidget);
    expect(find.text('@ana'), findsWidgets);
    expect(find.text('Nv 3'), findsOneWidget);
    expect(find.text('🏆'), findsOneWidget);
    expect(find.text('Lobos do Asfalto'), findsOneWidget);
    // Métricas e evolução (sem dados privados como tempo de jogo).
    expect(find.text('Pontos'), findsOneWidget);
    expect(find.text('Territórios'), findsOneWidget);
    expect(find.text('Evolução'), findsOneWidget);
    expect(find.text('2º lugar no ranking'), findsOneWidget);
    // Sem menus do próprio perfil.
    expect(find.text('Editar perfil'), findsNothing);
    expect(find.text('Mural'), findsNothing);
    // A liga de quem é visto: emblema e rótulo ao lado da equipe. O saldo de
    // RR do rival não sai daqui — só do GET /leagues dele.
    expect(find.text('TURBO 2'), findsOneWidget);
    expect(find.byType(LeagueBadgeChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('perfil sem liga não mostra emblema', (tester) async {
    await open(tester, body: {...publicData, 'league': null});
    expect(find.text('Lobos do Asfalto'), findsOneWidget);
    expect(find.byType(LeagueBadgeChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('perfil privado explica o bloqueio', (tester) async {
    await open(
      tester,
      status: 403,
      body: {'detail': 'Este perfil é privado.'},
    );
    expect(find.text('Este perfil é privado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
