import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/screens/leagues_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/league_emblem.dart';

/// Escada da temporada como o servidor a devolve: 7 ligas de 3 divisões,
/// 100 RR por divisão, e a Lenda no topo sem divisões.
const List<({String key, String name, String color, String shape})> _leagues = [
  (key: 'largada', name: 'Largada', color: '#8A94A6', shape: 'circle'),
  (key: 'trote', name: 'Trote', color: '#D9822B', shape: 'triangle'),
  (key: 'ritmo', name: 'Ritmo', color: '#C9CFD6', shape: 'diamond'),
  (key: 'podio', name: 'Pódio', color: '#FFB020', shape: 'pentagon'),
  (key: 'turbo', name: 'Turbo', color: '#22D3EE', shape: 'hexagon'),
  (key: 'elite', name: 'Elite', color: '#A78BFA', shape: 'octagon'),
  (key: 'mestre', name: 'Mestre', color: '#34D399', shape: 'gem'),
];

List<Map<String, dynamic>> _ladderJson() {
  final ladder = <Map<String, dynamic>>[];
  var at = 0;
  for (final league in _leagues) {
    ladder.add({
      'key': league.key,
      'name': league.name,
      'color': league.color,
      'shape': league.shape,
      'tiers': [
        for (var division = 1; division <= 3; division++)
          {'division': division, 'at': at + (division - 1) * 100},
      ],
    });
    at += 300;
  }
  ladder.add({
    'key': 'lenda',
    'name': 'Lenda',
    'color': '#F472B6',
    'shape': 'star',
    'tiers': [
      {'division': null, 'at': at},
    ],
  });
  return ladder;
}

/// Posição do jogador derivada do saldo, igual ao `status_for` do servidor.
Map<String, dynamic> _meJson(int trophies) {
  final ladder = _ladderJson();
  var entryIndex = 0;
  var tierIndex = 0;
  for (var l = 0; l < ladder.length; l++) {
    final tiers = (ladder[l]['tiers'] as List).cast<Map<String, dynamic>>();
    for (var t = 0; t < tiers.length; t++) {
      if (trophies >= tiers[t]['at']) {
        entryIndex = l;
        tierIndex = t;
      }
    }
  }
  final entry = ladder[entryIndex];
  final tiers = (entry['tiers'] as List).cast<Map<String, dynamic>>();
  final tier = tiers[tierIndex];
  final isLast = entryIndex == ladder.length - 1;
  final next = isLast
      ? null
      : () {
          if (tierIndex + 1 < tiers.length) {
            final nextTier = tiers[tierIndex + 1];
            return {
              'league': entry['key'],
              'name': entry['name'],
              'division': nextTier['division'],
            };
          }
          final nextEntry = ladder[entryIndex + 1];
          final nextTiers = (nextEntry['tiers'] as List)
              .cast<Map<String, dynamic>>();
          return {
            'league': nextEntry['key'],
            'name': nextEntry['name'],
            'division': nextTiers.first['division'],
          };
        }();
  return {
    'trophies': trophies,
    'league': entry['key'],
    'name': entry['name'],
    'color': entry['color'],
    'division': tier['division'],
    'rr': trophies - tier['at'],
    'rr_to_next': isLast ? null : 100 - (trophies - tier['at']),
    'next': next,
  };
}

Map<String, dynamic> _leaguesJson(int trophies) => {
  'me': _meJson(trophies),
  'ladder': _ladderJson(),
};

Future<void> openLeagues(
  WidgetTester tester, {
  required int trophies,
  bool fail = false,
  // Largo o bastante para a escada inteira (8 colunas) caber na área útil.
  Size size = const Size(1000, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var attempts = 0;
  final api = ApiClient(
    client: MockClient((request) async {
      if (request.url.path != '/leagues') return http.Response('{}', 404);
      attempts++;
      if (fail && attempts == 1) {
        return http.Response('{"detail":"Indisponível"}', 503);
      }
      return http.Response(jsonEncode(_leaguesJson(trophies)), 200);
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
        home: const LeaguesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Quantos emblemas da escada aparecem apagados (degrau acima do saldo).
int _dimmedEmblems(WidgetTester tester) {
  var dimmed = 0;
  for (final emblem in tester.widgetList<LeagueEmblem>(
    find.byType(LeagueEmblem),
  )) {
    if (emblem.dimmed) dimmed++;
  }
  return dimmed;
}

void main() {
  testWidgets('a escada mostra as oito ligas e a posição atual', (
    tester,
  ) async {
    await openLeagues(tester, trophies: 1230);

    expect(find.text('Ligas do RUNOVER'), findsOneWidget);
    for (final league in _leagues) {
      expect(find.text(league.name.toUpperCase()), findsOneWidget);
    }
    expect(find.text('LENDA'), findsOneWidget);

    // Card de posição: 1.230 RR é o primeiro degrau do Turbo (1.200), e a
    // divisão 3 é a mais alta dentro da liga.
    expect(find.text('TURBO 1'), findsOneWidget);
    expect(find.text('1.230 troféus (RR)'), findsOneWidget);
    expect(find.text('30 / 100 RR nesta divisão'), findsOneWidget);
    expect(find.textContaining('Faltam 70 RR'), findsOneWidget);

    // 21 degraus das ligas + 1 da Lenda + o emblema do próprio card.
    expect(find.byType(LeagueEmblem), findsNWidgets(23));
    expect(tester.takeException(), isNull);
  });

  testWidgets('degraus acima do saldo ficam apagados', (tester) async {
    await openLeagues(tester, trophies: 1230);
    // Alcançou os 13 degraus até 1.200 RR; restam 8 + a Lenda sem brilho.
    expect(_dimmedEmblems(tester), 9);

    // O degrau atual é o único com destaque.
    final highlighted = tester
        .widgetList<LeagueEmblem>(find.byType(LeagueEmblem))
        .where((e) => e.highlight);
    expect(highlighted, hasLength(2)); // card + célula da escada
  });

  testWidgets('na Lenda não há progresso de divisão', (tester) async {
    await openLeagues(tester, trophies: 2100);
    expect(find.text('LENDA'), findsWidgets);
    expect(find.text('2.100 troféus (RR)'), findsOneWidget);
    expect(find.text('Você está no topo da escada.'), findsOneWidget);
    expect(find.textContaining('RR nesta divisão'), findsNothing);
    expect(find.textContaining('Faltam'), findsNothing);
    // Tudo alcançado: só a Lenda, que é o próprio degrau atual, fica acesa.
    expect(_dimmedEmblems(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha ao carregar oferece uma nova tentativa', (tester) async {
    await openLeagues(tester, trophies: 1230, fail: true);
    expect(find.text('Não foi possível carregar as ligas.'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('TURBO 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('em 390 px a escada rola na horizontal sem cortar o cabeçalho', (
    tester,
  ) async {
    // A largura do tabuleiro inclui a coluna de rótulos: sem ela o cabeçalho
    // estourava a linha e a última liga ficava fora da tela.
    await openLeagues(tester, trophies: 1230, size: const Size(390, 844));
    expect(find.text('TURBO 1'), findsOneWidget);
    expect(find.text('LENDA'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
