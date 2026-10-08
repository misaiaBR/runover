import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/screens/teams_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/services/profile_image_provider.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';

const teamData = {
  'id': 'team-test',
  'name': 'Lobos do Asfalto',
  'creator_username': 'misaia',
  'member_count': 2,
  'members': [
    {'username': 'misaia', 'photo_url': null},
    {'username': 'ana', 'photo_url': null},
  ],
  'total_score': 320,
  'territories_count': 15,
  'level': 1,
  'level_progress': 0.4,
  'points_to_next_level': 90,
};

void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response(jsonEncode(teamData), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const TeamsScreen(),
        ),
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpAndSettle();
  }

  Future<void> expectTeamLayout(WidgetTester tester) async {
    // Cabeçalho com ícone + título.
    expect(find.text('Equipe'), findsOneWidget);
    expect(find.byIcon(Icons.groups_outlined), findsOneWidget);
    // Avatar, nome e criador.
    expect(find.text('Lobos do Asfalto'), findsOneWidget);
    expect(find.text('Criada por @misaia'), findsOneWidget);
    // Selo de nível (junto ao nome e no início da barra) + legenda.
    expect(find.text('Nv 1'), findsNWidgets(2));
    expect(
      find.text(
        'Progresso de Nível 1. Total de Pontos: 320. '
        'Faltam 90 pts para o Nível 2.',
      ),
      findsOneWidget,
    );
    // Cartões de estatísticas com ícones.
    expect(find.byIcon(Icons.star), findsWidgets);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(find.text('Pontos'), findsOneWidget);
    expect(find.text('Territórios'), findsOneWidget);
    // Membros com contagem e destaque do criador.
    expect(find.text('Membros (2)'), findsOneWidget);
    expect(find.text('@misaia'), findsOneWidget);
    expect(find.text('@ana'), findsOneWidget);
    // Ação de sair (rola até o fim da lista em telas pequenas).
    await tester.scrollUntilVisible(
      find.text('Sair da equipe'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sair da equipe'), findsOneWidget);
    expect(find.byIcon(Icons.logout), findsOneWidget);
    // Sem estouros de layout.
    expect(tester.takeException(), isNull);
  }

  testWidgets('team screen fits a small phone', (tester) async {
    await open(tester, const Size(320, 740));
    await expectTeamLayout(tester);
  });

  testWidgets('team screen fits a standard phone', (tester) async {
    await open(tester, const Size(390, 844));
    await expectTeamLayout(tester);
  });

  testWidgets('team screen fits a desktop window', (tester) async {
    await open(tester, const Size(1280, 800));
    await expectTeamLayout(tester);
  });

  test('teamCardAsset é estável e usa a galeria', () {
    final first = teamCardAsset('team-1');
    expect(first, teamCardAsset('team-1'));
    expect(presetAvatars.map((p) => p.asset), contains(first));
  });

  testWidgets('lista mostra cards e pedido fica pendente', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var joins = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/teams') {
          return http.Response(
            jsonEncode([
              {
                'id': 't1',
                'name': 'Lobos do Asfalto',
                'creator_username': 'misaia',
                'member_count': 2,
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/teams/t1/join') {
          joins++;
          return http.Response(jsonEncode(teamData), 200);
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lobos do Asfalto'), findsOneWidget);
    expect(find.text('Criada por @misaia'), findsOneWidget);
    expect(find.text('2 membros'), findsOneWidget);
    expect(find.byKey(const Key('team-join-t1')), findsOneWidget);
    expect(find.text('Solicitar entrada'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('team-join-t1')));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Solicitar entrada na equipe Lobos do Asfalto'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('team-join-t1')));
    await tester.pumpAndSettle();
    expect(joins, 1);
    expect(find.text('Aguardando aprovação'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Pedido pendente em Lobos do Asfalto'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('descoberta filtra por busca e por equipes novas', (
    tester,
  ) async {    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().toUtc();
    String iso(DateTime d) => d.toIso8601String();
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/teams') {
          return http.Response(
            jsonEncode([
              {
                'id': 'nova',
                'name': 'Lobos Novos',
                'creator_username': 'misaia',
                'member_count': 2,
                'territories_count': 0,
                'created_at': iso(now),
              },
              {
                'id': 'velha',
                'name': 'Velha Guarda',
                'creator_username': 'ana',
                'member_count': 5,
                'territories_count': 12,
                'created_at': iso(now.subtract(const Duration(days: 30))),
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lobos Novos'), findsOneWidget);
    expect(find.text('Velha Guarda'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Seja o primeiro'), findsOneWidget);
    expect(find.text('Recrutando'), findsNothing);

    await tester.enterText(find.byType(TextField), 'velha');
    await tester.pumpAndSettle();
    expect(find.text('Velha Guarda'), findsOneWidget);
    expect(find.text('Lobos Novos'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Novas'));
    await tester.pumpAndSettle();
    expect(find.text('Lobos Novos'), findsOneWidget);
    expect(find.text('Velha Guarda'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('descoberta acompanha o brilho do app', (tester) async {
    Future<Color?> nameColor(Brightness brightness) async {
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/teams/mine') {
            return http.Response('{}', 404);
          }
          if (request.url.path == '/teams') {
            return http.Response(
              jsonEncode([
                {
                  'id': 't1',
                  'name': 'Lobos do Asfalto',
                  'creator_username': 'misaia',
                  'member_count': 2,
                  'territories_count': 3,
                  'created_at': DateTime.now()
                      .toUtc()
                      .toIso8601String(),
                },
              ]),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(api.close);
      final state = AppState(api: api);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: buildRunoverTheme(brightness: brightness),
            home: const TeamsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.widget<Text>(find.text('Lobos do Asfalto')).style?.color;
    }

    final light = await nameColor(Brightness.light);
    final dark = await nameColor(Brightness.dark);
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light, isNot(dark));
    expect(
      ThemeData.estimateBrightnessForColor(light!),
      Brightness.dark,
    );
    expect(ThemeData.estimateBrightnessForColor(dark!), Brightness.light);
  });

  testWidgets('team list photo falls back when the network image fails', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response('{}', 404);
        }
        if (request.url.path == '/teams') {
          return http.Response(
            jsonEncode([
              {
                'id': 'broken-photo',
                'name': 'Equipe com foto indisponÃ­vel',
                'creator_username': 'misaia',
                'member_count': 2,
                'photo_url': 'https://example.invalid/team.png',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A URL de rede é irresolúvel: o NetworkImage falha de verdade e o
    // errorBuilder precisa renderizar a arte da galeria no lugar.
    final finder = find.byKey(const Key('team-card-image-broken-photo'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<Image>(finder).image,
      isA<NetworkImage>(),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin aprova pedido na tela da equipe', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var approvals = 0;
    Map<String, dynamic> detail = {
      ...teamData,
      'is_owner': true,
      'is_admin': true,
      'pending_requests': [
        {
          'id': 'req-1',
          'username': 'ana',
          'photo_url': null,
          'created_at': '2026-10-01T00:00:00Z',
        },
      ],
    };
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response(jsonEncode(detail), 200);
        }
        if (request.url.path == '/teams/team-test/requests/req-1/approve') {
          approvals++;
          detail = {...detail, 'pending_requests': []};
          return http.Response(jsonEncode(detail), 200);
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurações da equipe'));
    await tester.pumpAndSettle();
    expect(find.text('Convites pendentes (1)'), findsOneWidget);
    expect(find.text('Quer entrar na equipe'), findsOneWidget);
    await tester.tap(find.byTooltip('Aceitar pedido'));
    await tester.pumpAndSettle();
    expect(approvals, 1);
    expect(find.text('Convites pendentes (1)'), findsNothing);
    expect(find.text('Nenhum pedido aguardando.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer da equipe edita foto, nome e dissolve', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var patches = 0;
    var deletes = 0;
    Map<String, dynamic> detail = {
      ...teamData,
      'is_owner': true,
      'is_admin': true,
      'pending_requests': [],
    };
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response(jsonEncode(detail), 200);
        }
        if (request.method == 'PATCH' &&
            request.url.path == '/teams/team-test') {
          patches++;
          detail = {...detail, 'name': 'Novo Nome'};
          return http.Response(jsonEncode(detail), 200);
        }
        if (request.method == 'DELETE' &&
            request.url.path == '/teams/team-test') {
          deletes++;
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Configurações da equipe'));
    await tester.pumpAndSettle();
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Convites pendentes (0)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('team-photo-Corredor')));
    await tester.pumpAndSettle();
    expect(patches, 1);

    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Novo Nome');
    await tester.tap(find.text('Salvar nome'));
    await tester.pumpAndSettle();
    expect(patches, 2);

    expect(find.text('Dissolver equipe'), findsOneWidget);
    await tester.tap(find.text('Dissolver equipe'));
    await tester.pumpAndSettle();
    expect(find.text('Dissolver equipe?'), findsOneWidget);
    await tester.tap(find.text('Dissolver'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('foto salva da equipe aparece no cabeçalho', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const dataUri =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRUlErkJggg==';
    final detail = {
      ...teamData,
      'photo_url': dataUri,
      'is_owner': true,
      'is_admin': true,
      'pending_requests': [],
    };
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/teams/mine') {
          return http.Response(jsonEncode(detail), 200);
        }
        return http.Response('{}', 404);
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
          home: const TeamsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final withPhoto = tester.widgetList<CircleAvatar>(
      find.byWidgetPredicate(
        (w) => w is CircleAvatar && w.foregroundImage is MemoryImage,
      ),
    );
    expect(withPhoto, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
