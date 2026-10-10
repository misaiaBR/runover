import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/home_screen.dart';
import 'package:runover_app/screens/season_pass_screen.dart';
import 'package:runover_app/screens/profile_screen.dart';
import 'package:runover_app/screens/speed_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pass_screen_test.dart' show passStatus;

Map<String, dynamic> teamJson() => {
  'id': 't1',
  'name': 'Trovão',
  'photo_url': null,
  'creator_username': 'marina',
  'member_count': 5,
  'members': [
    {
      'username': 'marina',
      'photo_url': null,
      'is_admin': true,
      'is_online': true,
    },
    {
      'username': 'joao',
      'photo_url': null,
      'is_admin': false,
      'is_online': true,
    },
  ],
  'total_score': 900,
  'territories_count': 7,
  'level': 3,
  'level_progress': 0.5,
  'points_to_next_level': 100,
  // Nível 3 → terceiro anel da base.
  'zone_capacity': 37,
  'is_owner': true,
  'is_admin': true,
  'my_request': null,
  'pending_requests': [
    {
      'id': 'r1',
      'username': 'novo',
      'photo_url': null,
      'created_at': '2026-01-01T00:00:00Z',
    },
  ],
  'online_count': 2,
};

Map<String, dynamic> progressJson({int streakDays = 5}) => {
  'week_start': '2026-10-05T00:00:00Z',
  'runs_count': 3,
  'distance_km': 21.5,
  'longest_run_km': 8.4,
  'streak_days': streakDays,
  'goals': [],
  'badges': [],
  'team': null,
  'fastest_pace_seconds_per_km': 332,
};

MockClient cardDataClient({int streakDays = 5}) => MockClient((request) async {
  if (request.url.path == '/teams/mine') {
    return http.Response(jsonEncode(teamJson()), 200);
  }
  if (request.url.path == '/runs/progress') {
    return http.Response(jsonEncode(progressJson(streakDays: streakDays)), 200);
  }
  if (request.url.path == '/pass') {
    return http.Response(jsonEncode(passStatus()), 200);
  }
  return http.Response('[]', 200);
});

void main() {
  testWidgets('map tab opens on a light start screen without loading the map', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var territoryRequests = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path.startsWith('/territories')) territoryRequests++;
        return http.Response('[]', 200);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson({
        'id': '1',
        'full_name': 'Marina Oliveira',
        'username': 'marina',
        'email': 'marina@example.com',
        'photo_url': null,
        'total_score': 0,
        'territories_count': 0,
        'rank_position': null,
        'team_name': null,
        'level': 1,
        'level_progress': 0,
        'points_to_next_level': 100,
        'is_public': true,
        'play_seconds': 0,
      });
    addTearDown(state.dispose);
    var menuOpened = false;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: HomeScreen(onOpenMenu: () => menuOpened = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ESCOLHA SEU MODO'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(territoryRequests, 0);

    await tester.tap(find.byTooltip('Menu'));
    expect(menuOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows game mode cards with real stats', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder verticalScrollable() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axis == Axis.vertical,
    );

    expect(find.text('ESCOLHA SEU MODO'), findsOneWidget);
    expect(find.text('DOMINAÇÃO DE TERRITÓRIOS'), findsOneWidget);
    expect(find.text('DESAFIO DE VELOCIDADE'), findsOneWidget);
    // Velocidade: dados reais do progresso (nada de recorde inventado).
    expect(find.text('3 corridas'), findsOneWidget);
    expect(find.text('recorde 8,4 km'), findsOneWidget);
    // Sequência: vem do backend, não é mais estática.
    expect(find.text('5 dias'), findsOneWidget);
    expect(find.text('0 dias'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('PIT STOP DE EQUIPE'),
      200,
      scrollable: verticalScrollable(),
    );
    expect(find.text('PIT STOP DE EQUIPE'), findsOneWidget);
    // Equipe: dados reais (membros, online, pedidos pendentes).
    expect(find.text('5 membros'), findsOneWidget);
    expect(find.text('2 online'), findsOneWidget);
    expect(find.text('Nv 3'), findsOneWidget);
    expect(find.text('1 PEDIDO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a moldura do avatar abre o perfil', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // O alvo é a moldura inteira, não o selo pequeno: o toque cai no canto
    // superior esquerdo do anel, longe do "NV".
    final frame = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Abrir perfil',
    );
    expect(frame, findsOneWidget);
    final rect = tester.getRect(frame);
    await tester.tapAt(rect.topLeft + const Offset(6, 6));
    // O perfil tem animações contínuas: avança o relógio em vez de
    // pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o nível e o anel da moldura vêm da conta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson({
        'id': '1',
        'full_name': 'Marina Oliveira',
        'username': 'misaia',
        'email': 'misaia@example.com',
        'photo_url': null,
        'total_score': 4200,
        'territories_count': 3,
        'rank_position': 12,
        'team_name': null,
        'level': 7,
        'level_progress': 0.5,
        'points_to_next_level': 800,
        'is_public': true,
        'play_seconds': 0,
      });
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NV 7'), findsOneWidget);
    // A moldura é o anel de XP do nível: pinta em volta do avatar.
    expect(
      find.ancestor(
        of: find.text('NV 7'),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chama da sequência escala com os dias', (tester) async {
    Future<Icon> flame(int days) async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(client: cardDataClient(streakDays: days));
      addTearDown(api.close);
      final state = AppState(api: api);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: buildRunoverTheme(),
            // Chave nova a cada faixa: reaproveitando a mesma árvore o estado
            // da home não roda `initState` de novo e ficaria na sequência
            // antiga.
            home: HomeScreen(key: ValueKey('streak$days')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final finder = days <= 0
          ? find.byIcon(Icons.local_fire_department_outlined)
          : find.byIcon(Icons.local_fire_department);
      expect(finder, findsOneWidget, reason: '$days dias');
      return tester.widget<Icon>(finder);
    }

    // Sem sequência a chama se apaga; com 120 dias ela é maior e dourada.
    expect((await flame(0)).size, 16);
    expect((await flame(3)).size, 16);
    expect((await flame(14)).size, 20);
    expect((await flame(60)).color, Pal.gold);
    final record = await flame(120);
    expect(record.size, 26);
    expect(record.shadows, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode cards show retry on load failure, not empty states', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final profileJson = {
      'id': '1',
      'full_name': 'Marina Oliveira',
      'username': 'marina',
      'email': 'marina@example.com',
      'photo_url': null,
      'total_score': 0,
      'territories_count': 0,
      'rank_position': null,
      'team_name': null,
      'level': 1,
      'level_progress': 0,
      'points_to_next_level': 100,
      'is_public': true,
      'play_seconds': 0,
    };
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(jsonEncode(profileJson), 200);
        }
        return http.Response('erro', 500);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileJson);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Erro não pode se passar por "sem equipe" nem "sem corridas".
    await tester.scrollUntilVisible(
      find.text('ESCOLHA SEU MODO'),
      500,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      ),
    );
    expect(find.text('Falha ao carregar'), findsWidgets);
    expect(find.text('Sem equipe'), findsNothing);
    expect(find.text('Nenhuma corrida'), findsNothing);
    await tester.ensureVisible(find.text('TENTAR DE NOVO').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TENTAR DE NOVO').first);
    await tester.pumpAndSettle();
    expect(find.text('Falha ao carregar'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode cards keep content and action visible at large text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // A HomeScreen recarrega o perfil no initState: o mock serve o mesmo
    // perfil exibido para que o refresh não troque os dados sob o teste.
    final profileJson = {
      'id': '1',
      'full_name': 'Marina Oliveira',
      'username': 'marina',
      'email': 'marina@example.com',
      'photo_url': null,
      'total_score': 0,
      'territories_count': 12,
      'rank_position': 3,
      'team_name': null,
      'level': 1,
      'level_progress': 0,
      'points_to_next_level': 100,
      'is_public': true,
      'play_seconds': 0,
    };
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/users/me') {
          return http.Response(jsonEncode(profileJson), 200);
        }
        if (request.url.path == '/teams/mine') {
          return http.Response(jsonEncode(teamJson()), 200);
        }
        if (request.url.path == '/runs/progress') {
          return http.Response(jsonEncode(progressJson()), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(api.close);
    final state = AppState(api: api)
      ..profile = UserProfile.fromJson(profileJson);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A lista vertical é lazy: em escala grande a seção de modos só é
    // construída após rolar até ela.
    await tester.scrollUntilVisible(
      find.text('ESCOLHA SEU MODO'),
      500,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      ),
    );
    expect(find.text('ESCOLHA SEU MODO'), findsOneWidget);
    expect(find.text('12 zonas suas'), findsOneWidget);
    expect(find.text('Ranking #3'), findsOneWidget);
    expect(find.text('3 corridas'), findsOneWidget);
    expect(find.text('recorde 8,4 km'), findsOneWidget);
    // Cards are in a row on wide screens, column on narrow. Test uses narrow (390px).
    // Scroll to the buttons.
    await tester.scrollUntilVisible(
      find.text('JOGAR'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      ),
    );
    expect(find.text('JOGAR'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('PIT STOP DE EQUIPE'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      ),
    );
    expect(find.text('ENTRAR'), findsOneWidget);
    expect(find.text('5 membros'), findsOneWidget);
    expect(find.text('2 online'), findsOneWidget);
    expect(find.text('1 PEDIDO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('mode button ink stays readable on every accent', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      final hi = x > y ? x : y;
      final lo = x > y ? y : x;
      return (hi + 0.05) / (lo + 0.05);
    }

    final scheme = buildRunoverTheme().colorScheme;
    for (final accent in [scheme.primary, scheme.secondary, Pal.team]) {
      // Fixar Pal.onAccent deixava o teal abaixo de 4:1; agora cada acento
      // recebe a tinta de maior contraste.
      expect(
        contrast(accent, inkOnAccent(accent)),
        greaterThanOrEqualTo(4.5),
        reason: 'contraste insuficiente sobre $accent',
      );
    }
  });

  testWidgets('the undefined speed mode stays on screen but is not playable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Janela alta o bastante para o toque cair de fato sobre o botão: na
    // superfície padrão de 800x600 ele fica fora dos limites e o tap seria
    // um "não aconteceu" gratuito.
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('EM BREVE'),
      200,
      scrollable: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.vertical,
      ),
    );

    // O card continua presente, mas sem CTA que prometa o modo.
    expect(find.text('DESAFIO DE VELOCIDADE'), findsOneWidget);
    expect(find.text('EM BREVE'), findsOneWidget);
    expect(find.text('CORRER'), findsNothing);

    await tester.tap(find.text('EM BREVE'));
    await tester.pumpAndSettle();
    expect(find.byType(SpeedScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide window fills the height instead of leaving it empty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // 1100 e a altura mínima em que o layout largo cabe com os dois painéis
    // (grid esticado + passe); abaixo disso a home volta a rolar numa lista.
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sem rolagem: os três cards e o rodapé cabem na janela.
    expect(find.text('DOMINAÇÃO DE TERRITÓRIOS'), findsOneWidget);
    expect(find.text('PIT STOP DE EQUIPE'), findsOneWidget);
    expect(find.text('Termos e privacidade'), findsOneWidget);

    // O grid absorve a sobra, então o card cresce além do conteúdo mínimo.
    final card = tester.getRect(find.text('DOMINAÇÃO DE TERRITÓRIOS'));
    final button = tester.getRect(find.text('JOGAR'));
    expect(button.top - card.bottom, greaterThan(40));
    // O segundo painel da home larga é o passe, com rolagem própria.
    expect(find.text('PASS RUNOVER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the home embeds the pass in place of the level XP bar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // O HUD perdeu a barra de XP de nível, mas manteve nome e selo de nível.
    // Sem perfil carregado, a barra antiga mostrava exatamente esta string.
    expect(find.text('0 / 1000 XP'), findsNothing);
    expect(find.text('Corredor'), findsOneWidget);

    // A ListView da home é lazy: o passe só constrói quando entra na viewport.
    await tester.scrollUntilVisible(find.text('PASS RUNOVER'), 300);
    await tester.pumpAndSettle();
    expect(find.textContaining('outubro de 2026'), findsOneWidget);
    expect(find.textContaining('250 XP'), findsOneWidget);
    // O cartão é compacto: a lista de tiers só existe dentro da trilha.
    expect(find.text('Tier 1 · 200 XP'), findsNothing);
    expect(find.text('Ver a trilha'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Termos e privacidade'), 300);
    await tester.pumpAndSettle();
    // O passe embutido não repete o rodapé da home.
    expect(find.text('Termos e privacidade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar o cartão do passe abre a trilha de XP', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(client: cardDataClient());
    addTearDown(api.close);
    final state = AppState(api: api);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildRunoverTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Ver a trilha'), 300);
    await tester.pumpAndSettle();
    expect(find.byType(SeasonPassScreen), findsNothing);

    await tester.tap(find.text('Ver a trilha'));
    await tester.pumpAndSettle();
    expect(find.byType(SeasonPassScreen), findsOneWidget);
    // Modo backend: a temporada vem do mock (`passStatus`).
    expect(find.text('Temporada outubro de 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode cards follow the app theme', (tester) async {
    Finder modeCard() => find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final deco = w.decoration;
      return deco is BoxDecoration &&
          deco.borderRadius == BorderRadius.circular(14);
    });
    Finder verticalScrollable() => find.byWidgetPredicate(
      (w) => w is Scrollable && w.axis == Axis.vertical,
    );

    Future<void> pumpHome(Brightness brightness) async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(client: cardDataClient());
      addTearDown(api.close);
      final state = AppState(api: api);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: buildRunoverTheme(brightness: brightness),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('DOMINAÇÃO DE TERRITÓRIOS'),
        500,
        scrollable: verticalScrollable(),
      );
    }

    Color cardColor() {
      final container = tester.widget<Container>(modeCard().first);
      return (container.decoration! as BoxDecoration).color!;
    }

    Color titleColor() => tester
        .widget<Text>(find.text('DOMINAÇÃO DE TERRITÓRIOS'))
        .style!
        .color!;

    await pumpHome(Brightness.light);
    expect(modeCard(), findsWidgets);
    expect(cardColor(), Colors.white);
    expect(titleColor(), const Color(0xFF161B22));
    expect(tester.takeException(), isNull);

    await pumpHome(Brightness.dark);
    expect(modeCard(), findsWidgets);
    expect(cardColor(), const Color(0xFF1C1E2B));
    expect(titleColor(), Colors.white);
    expect(tester.takeException(), isNull);
  });
}
