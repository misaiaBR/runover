import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/screens/badges_screen.dart';
import 'package:runover_app/services/api_client.dart';
import 'package:runover_app/state/app_state.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/insignia.dart';

/// GET /badges como o servidor o devolve: sete regras em três categorias,
/// duas ganhas e cinco bloqueadas — a mais perto de sair é "Meia maratona".
Map<String, dynamic> _badge({
  required String id,
  required String name,
  required String category,
  required String icon,
  required String metric,
  required num threshold,
  required num progress,
  bool earned = false,
  String? earnedAt,
}) => {
  'id': id,
  'name': name,
  'description': 'Regra de $name.',
  'icon': icon,
  'category': category,
  'metric': metric,
  'threshold': threshold,
  'progress': progress,
  'earned': earned,
  'earned_at': earnedAt,
};

final catalogData = <Map<String, dynamic>>[
  _badge(
    id: 'badge_primeira_corrida',
    name: 'Primeira corrida',
    category: 'corridas',
    icon: 'run',
    metric: 'runs',
    threshold: 1,
    progress: 12,
    earned: true,
    earnedAt: '2026-03-07T10:00:00Z',
  ),
  _badge(
    id: 'badge_cinco_corridas',
    name: 'Cinco corridas',
    category: 'corridas',
    icon: 'run',
    metric: 'runs',
    threshold: 5,
    progress: 2,
  ),
  _badge(
    id: 'badge_dez_corridas',
    name: 'Dez corridas',
    category: 'corridas',
    icon: 'run',
    metric: 'runs',
    threshold: 10,
    progress: 2,
  ),
  _badge(
    id: 'badge_cinco_km',
    name: '5 km em um laço',
    category: 'distancia',
    icon: 'route',
    metric: 'longest_km',
    threshold: 5,
    progress: 10.4,
    earned: true,
    earnedAt: '2026-04-02T09:30:00Z',
  ),
  _badge(
    id: 'badge_meia_maratona',
    name: 'Meia maratona',
    category: 'distancia',
    icon: 'route',
    metric: 'longest_km',
    threshold: 21,
    progress: 10.4,
  ),
  _badge(
    id: 'badge_em_equipe',
    name: 'Em uma equipe',
    category: 'equipe',
    icon: 'team',
    metric: 'team',
    threshold: 1,
    progress: 0,
  ),
  _badge(
    id: 'badge_pit_stop',
    name: 'Pit stop completo',
    category: 'equipe',
    icon: 'team',
    metric: 'pit_stop',
    threshold: 1,
    progress: 0,
  ),
];

/// O mesmo catálogo para quem ainda não ganhou nada. Regra não cumprida nunca
/// vem com progresso acima do limiar — o servidor concede no instante em que a
/// meta é batida —, então o que passava do limiar volta para 90% dele.
final noneEarnedData = <Map<String, dynamic>>[
  for (final entry in catalogData)
    {
      ...entry,
      'earned': false,
      'earned_at': null,
      'progress': (entry['progress'] as num) > (entry['threshold'] as num)
          ? (entry['threshold'] as num) * 0.9
          : entry['progress'],
    },
];

Future<void> openScreen(
  WidgetTester tester, {
  bool fail = false,
  int failures = 1,
  Size size = const Size(390, 844),
  List<Map<String, dynamic>>? data,
}) async {
  tester.view.physicalSize = size;
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
      return http.Response(jsonEncode(data ?? catalogData), 200);
    }),
  );
  addTearDown(api.close);
  final state = AppState(api: api);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildRunoverTheme(brightness: Brightness.dark),
        home: const BadgesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Rola a lista até o texto aparecer — a tela é uma ListView única, e o que
/// está fora da tela não chega a ser construído. Só rola para baixo: o alvo
/// precisa estar abaixo de onde a lista está.
Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

/// Abre um dos três modos, rolando até o chip quando ele está abaixo da dobra.
Future<void> _pickView(WidgetTester tester, String label) async {
  await _scrollTo(tester, label);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// A ordem dos cards na grade, do primeiro ao último, sem depender do scroll:
/// a grade inteira é uma única filha da ListView, então todos estão construídos.
List<String> _tileOrder(WidgetTester tester) =>
    find
        .byType(BadgeTile)
        .evaluate()
        .map((candidate) => (candidate.widget as BadgeTile).badge.name)
        .toList();

Insignia _insignia(String id) =>
    Insignia.fromJson(catalogData.firstWhere((b) => b['id'] == id));

void main() {
  testWidgets('o resumo e a próxima insígnia abrem a tela', (tester) async {
    await openScreen(tester);
    expect(find.text('Ganhas · 2 de 7'), findsOneWidget);
    expect(
      find.text('O mural do perfil mostra as que você ganhou'),
      findsOneWidget,
    );
    // O card da mais perto de sair: nome, progresso e a categoria na ficha.
    expect(find.text('Meia maratona'), findsOneWidget);
    expect(find.text('10,4 de 21'), findsOneWidget);
    expect(find.text('Bloqueada · Distância'), findsOneWidget);
    // Os três modos vêm abaixo do card: a lista precisa rolar até eles.
    await _scrollTo(tester, 'Por categoria');
    expect(find.text('Mais próximas'), findsOneWidget);
    expect(find.text('Ganhas'), findsOneWidget);
    // Cada categoria com o próprio placar, na ordem em que o servidor mandou.
    expect(find.text('Corridas'), findsOneWidget);
    expect(find.text('1 de 3 ganhas'), findsOneWidget);
    await _scrollTo(tester, 'Distância');
    expect(find.text('1 de 2 ganhas'), findsOneWidget);
    await _scrollTo(tester, 'Equipe');
    expect(find.text('0 de 2 ganhas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '"Mais próximas" deixa só o que falta, da mais perto para a mais longe',
    (tester) async {
      await openScreen(tester);
      await _pickView(tester, 'Mais próximas');

      // 49,5% antes de 40%, que vem antes de 20%, e os dois zeros empatam no
      // limiar e desempate no id.
      expect(_tileOrder(tester), [
        'Meia maratona',
        'Cinco corridas',
        'Dez corridas',
        'Em uma equipe',
        'Pit stop completo',
      ]);
      expect(find.text('Primeira corrida'), findsNothing);
      expect(find.text('5 km em um laço'), findsNothing);
      expect(find.text('Corridas'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('"Ganhas" mostra as registradas com a data do ganho', (
    tester,
  ) async {
    await openScreen(tester);
    await _pickView(tester, 'Ganhas');

    expect(_tileOrder(tester), ['Primeira corrida', '5 km em um laço']);
    expect(find.text('Ganha em 7 de mar. de 2026'), findsOneWidget);
    expect(find.text('Ganha em 2 de abr. de 2026'), findsOneWidget);
    // O card da próxima fica no topo em qualquer modo — ele é o "e agora?".
    expect(find.text('Bloqueada · Distância'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'catálogo sem nada ganho mantém a próxima e zera o placar da categoria',
    (tester) async {
      await openScreen(tester, data: noneEarnedData);
      expect(find.text('Ganhas · 0 de 7'), findsOneWidget);
      // Sem nada ganho o card da próxima continua — o que falta é o assunto,
      // e ele fica no topo: a mais perto é a de 0,9 de 1 corrida.
      expect(find.text('Bloqueada · Corridas'), findsOneWidget);
      // O número do card e o do hero são o mesmo progresso: 0,9 de 1 aparece
      // uma vez em cada.
      expect(find.text('0,9 de 1'), findsNWidgets(2));
      await _scrollTo(tester, '0 de 3 ganhas');
      expect(find.text('0 de 3 ganhas'), findsOneWidget);
      // Distância e Equipe têm duas regras cada: os dois placares zerados.
      await _scrollTo(tester, 'Equipe');
      expect(find.text('0 de 2 ganhas'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a aba das ganhas avisa quando nada foi registrado', (
    tester,
  ) async {
    await openScreen(tester, data: noneEarnedData);
    await _pickView(tester, 'Ganhas');
    expect(find.text('Você ainda não ganhou nenhuma insígnia.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catálogo todo ganho não tem próxima insígnia', (tester) async {
    await openScreen(
      tester,
      data: [
        for (final entry in catalogData)
          {...entry, 'earned': true, 'earned_at': '2026-04-02T09:30:00Z'},
      ],
    );
    expect(find.text('Ganhas · 7 de 7'), findsOneWidget);
    expect(find.textContaining('Bloqueada ·'), findsNothing);
    await _pickView(tester, 'Mais próximas');
    expect(find.text('Nada bloqueado: você já ganhou todas.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('em tela larga a grade passa a caber mais colunas', (
    tester,
  ) async {
    await openScreen(tester, size: const Size(1200, 1600));
    expect(find.text('Corridas'), findsOneWidget);
    // As três corridas do catálogo entram na mesma linha da grade.
    final left = tester.getTopLeft(find.text('Primeira corrida'));
    final right = tester.getTopLeft(find.text('Dez corridas'));
    expect(right.dy, left.dy);
    expect(right.dx, greaterThan(left.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('texto grande não estoura o card', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openScreen(tester, size: const Size(390, 844));
    await _scrollTo(tester, 'Pit stop completo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a falha de catálogo oferece a tentativa novamente', (
    tester,
  ) async {
    await openScreen(tester, fail: true);
    expect(
      find.text('Não foi possível carregar suas insígnias.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    expect(find.text('Ganhas · 2 de 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a data da insígnia é o dia local de quem corre, não o do servidor', () {
    // O servidor grava em UTC: 22h de 6 de junho é ainda 6 de junho em UTC−3.
    final instant = DateTime.utc(2026, 6, 6, 22);
    expect(badgeDateLabel(instant), badgeDateLabel(instant.toLocal()));
  });

  test('uma categoria que o app ainda não conhece cai em "Outras"', () {
    expect(badgeCategoryStyle('temporada').label, 'Temporada');
    expect(badgeCategoryStyle('novo_grupo').label, 'Outras');
    expect(badgeCategoryStyle('novo_grupo').color, isNotNull);
  });

  test('a mais perto de sair é a de maior proporção, e a ganha vale 1', () {
    expect(badgeRatio(_insignia('badge_meia_maratona')), closeTo(0.495, 0.001));
    expect(badgeRatio(_insignia('badge_cinco_corridas')), closeTo(0.4, 0.001));
    expect(badgeRatio(_insignia('badge_em_equipe')), 0);
    expect(badgeRatio(_insignia('badge_primeira_corrida')), 1);
  });
}
