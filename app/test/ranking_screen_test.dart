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
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/league_emblem.dart';

// Emblema como o servidor o devolve: chave, rótulo, cor, forma e divisão.
const turboBadge = {
  'league': 'turbo',
  'name': 'Turbo',
  'color': '#F5A524',
  'shape': 'triangle',
  'division': 2,
};

// Lenda não tem divisões: o rótulo é só o nome da liga.
const lendaBadge = {
  'league': 'lenda',
  'name': 'Lenda',
  'color': '#E8E8FF',
  'shape': 'star',
  'division': null,
};

const rankingData = [
  {
    'position': 1,
    'owner_type': 'user',
    'name': 'misaia',
    'photo_url': null,
    'total_score': 900,
    'territories_count': 15,
    'level': 4,
    'league': turboBadge,
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
  Future<void> open(
    WidgetTester tester,
    Brightness brightness, {
    List<Map<String, dynamic>>? ranking,
    List<Map<String, dynamic>>? catalog,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/ranking') {
          return http.Response(jsonEncode(ranking ?? rankingData), 200);
        }
        if (request.url.path == '/shop/catalog') {
          return http.Response(jsonEncode(catalog ?? const []), 200);
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

  testWidgets('ranking mostra foto, nome e cards da loja', (tester) async {
    const catalog = [
      {
        'id': 'frame_bronze',
        'category': 'frame',
        'name': 'Moldura bronze',
        'price': 100,
        'payload': {
          'colors': ['#CD7F32'],
          'animated': false,
        },
      },
      {
        'id': 'name_neon',
        'category': 'name_style',
        'name': 'Nome neon',
        'price': 250,
        'payload': {
          'colors': ['#3DDBB0'],
          'glow': true,
          'animated': false,
        },
      },
      {
        'id': 'banner_oceano',
        'category': 'banner',
        'name': 'Oceano',
        'price': 200,
        'payload': {
          'colors': ['#0EA5E9', '#1E3A8A'],
          'animated': false,
        },
      },
    ];
    await open(
      tester,
      Brightness.light,
      ranking: [
        {
          ...rankingData[0],
          'equipped_frame': 'frame_bronze',
          'equipped_name_style': 'name_neon',
        },
        rankingData[1],
        {
          'position': 3,
          'owner_type': 'user',
          'name': 'bob',
          'photo_url': null,
          'total_score': 200,
          'territories_count': 4,
          'level': 2,
        },
        rankingData[2],
        {
          'position': 4,
          'owner_type': 'user',
          'name': 'ze',
          'photo_url': null,
          'total_score': 100,
          'territories_count': 2,
          'level': 1,
          'equipped_banner': 'banner_oceano',
        },
      ],
      catalog: catalog,
    );
    // Nome com o estilo equipado.
    expect(
      tester.widget<Text>(find.text('@misaia')).style?.color,
      const Color(0xFF3DDBB0),
    );
    // Moldura da loja no avatar.
    final framed = tester.widgetList<FramedAvatar>(
      find.byType(FramedAvatar),
    );
    expect(framed.any((f) => f.frame?.id == 'frame_bronze'), isTrue);
    // Card com o fundo da faixa equipada.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient != null,
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pódio mostra a liga do rival e a equipe fica sem emblema', (
    tester,
  ) async {
    await open(
      tester,
      Brightness.light,
      ranking: [
        rankingData[0], // 1º: Turbo 2
        {...rankingData[1], 'league': null}, // 2º: sem emblema
        rankingData[2], // equipe: o servidor nunca manda liga
      ],
    );
    // O emblema de quem corre aparece com o rótulo da escada.
    expect(find.text('TURBO 2'), findsOneWidget);
    expect(find.byType(LeagueBadgeChip), findsOneWidget);
    // Na aba de equipes o card existe, mas ninguém disputa a escada.
    await tester.tap(find.text('Equipes'));
    await tester.pumpAndSettle();
    expect(find.text('Lobos do Asfalto'), findsOneWidget);
    expect(find.byType(LeagueBadgeChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card da lista traz a liga e Lenda vem sem divisão', (
    tester,
  ) async {
    await open(
      tester,
      Brightness.light,
      ranking: [
        rankingData[0],
        rankingData[1],
        {
          'position': 3,
          'owner_type': 'user',
          'name': 'bob',
          'photo_url': null,
          'total_score': 200,
          'territories_count': 4,
          'level': 2,
        },
        {
          'position': 4,
          'owner_type': 'user',
          'name': 'avelino',
          'photo_url': null,
          'total_score': 90,
          'territories_count': 2,
          'level': 9,
          'league': lendaBadge,
        },
      ],
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    // O card da lista carrega o chip; "Lenda" não tem número de divisão.
    expect(find.text('@avelino'), findsOneWidget);
    expect(find.text('LENDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
