import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/season_pass/backend.dart';
import 'package:runover_app/season_pass/widgets/season_pass_progress_bar.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/runover_ui.dart';

/// Mapa do `GET /pass` com tiers de 200 em 200 pontos.
Map<String, dynamic> _status({
  required int points,
  required int unlockedTier,
  int maxTier = 5,
}) {
  return {
    'season_id': '2026-10',
    'ends_at': '2026-11-05T00:00:00+00:00',
    'seasonal_points': points,
    'unlocked_tier': unlockedTier,
    'premium_unlocked': false,
    'premium_price_coins': 1000,
    'tiers': [
      for (var tier = 1; tier <= maxTier; tier++)
        {
          'tier': tier,
          'threshold': tier * 200,
          'unlocked': tier <= unlockedTier,
          'free': {'coins': tier * 10, 'claimed': false},
          'premium': {'coins': tier * 20, 'claimed': false},
        },
    ],
  };
}

void main() {
  test('o progresso conta só o trecho do nível atual', () {
    // 320 pts: nível 1 aberto (200), o próximo limiar é 400.
    final season = seasonFromStatus(_status(points: 320, unlockedTier: 1), {});

    // Os números continuam acumulados…
    expect(season.points, 320);
    expect(season.pointsForNext, 400);
    expect(season.levelStartPoints, 200);
    // …mas a barra mede (320-200)/(400-200).
    expect(season.levelProgress, closeTo(0.6, 0.001));
    expect(season.pointsToNextLevel, 80);
  });

  test('sem nenhum nível aberto a barra parte do zero', () {
    final season = seasonFromStatus(_status(points: 150, unlockedTier: 0), {});
    expect(season.levelStartPoints, 0);
    expect(season.levelProgress, closeTo(0.75, 0.001));
    expect(season.pointsToNextLevel, 50);
  });

  test('com a trilha toda liberada a barra fica cheia', () {
    final season = seasonFromStatus(_status(points: 1000, unlockedTier: 5), {});
    expect(season.levelProgress, 1);
    expect(season.pointsToNextLevel, 0);
  });

  testWidgets('o card mostra o faltam do nível atual', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final season = seasonFromStatus(_status(points: 320, unlockedTier: 1), {});
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeasonPassProgressBar(season: season),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Nível 1'), findsOneWidget);
    expect(find.text('320 / 400 pts'), findsOneWidget);
    expect(find.text('Faltam 80 pts para o nível 2'), findsOneWidget);
    // A barra está no meio do caminho, não em 80% (320/400).
    final bar = tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byType(SeasonPassProgressBar),
        matching: find.byType(LinearProgressIndicator),
      ),
    );
    expect(bar.value, closeTo(0.6, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('trilha completa não fala de próximo nível', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final season = seasonFromStatus(_status(points: 1000, unlockedTier: 5), {});
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeasonPassProgressBar(season: season),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Faltam'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // O passe já foi desenhado sobre um roxo fixo, com texto branco: trocando o
  // tema do app ele continuava preso no modo escuro. As duas travas abaixo são
  // a regra nova — superfície e tintas vêm do `Pal`, e o dourado do nível passa
  // pelo contraste antes de ser tinta.
  for (final (brightness, pal) in const [
    (Brightness.dark, Pal.dark),
    (Brightness.light, Pal.light),
  ]) {
    testWidgets('a barra veste o painel ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final season = seasonFromStatus(_status(points: 320, unlockedTier: 1), {});
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(brightness: brightness),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeasonPassProgressBar(season: season),
            ),
          ),
        ),
      );
      await tester.pump();

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SeasonPassProgressBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((container.decoration! as BoxDecoration).color, pal.panel);

      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(SeasonPassProgressBar),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.backgroundColor, pal.track);

      final levelContext = tester.element(find.text('Nível 1'));
      final levelInk = tester.widget<Text>(find.text('Nível 1')).style?.color;
      expect(contrastOnSurfaces(levelInk!, levelContext), greaterThanOrEqualTo(4.5));

      final pointsInk = tester
          .widget<Text>(find.text('320 / 400 pts'))
          .style
          ?.color;
      expect(pointsInk, pal.heading);

      final remainingInk = tester
          .widget<Text>(find.text('Faltam 80 pts para o nível 2'))
          .style
          ?.color;
      expect(remainingInk, pal.muted);
      expect(tester.takeException(), isNull);
    });
  }
}
