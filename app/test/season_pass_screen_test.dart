import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/screens/season_pass_screen.dart';
import 'package:runover_app/season_pass/demo_season.dart';
import 'package:runover_app/season_pass/models.dart';
import 'package:runover_app/theme.dart';

Future<void> openSeason(
  WidgetTester tester, {
  Season? season,
  Future<void> Function(int level, RewardLane lane)? onClaim,
  VoidCallback? onOpenPass,
  // Larga o bastante para as 7 colunas existirem de uma vez (a trilha é lazy).
  Size size = const Size(1400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(),
      home: SeasonPassScreen(
        season: season ?? demoSeason(),
        onClaim: onClaim,
        onOpenPass: onOpenPass,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('os quatro estados aparecem e o banner do passe é exibido', (
    tester,
  ) async {
    await openSeason(tester);
    expect(find.text('Temporada Aurora'), findsOneWidget);
    expect(find.text('Nível 4'), findsOneWidget);
    // 1–3 grátis resgatadas, 4 grátis resgatável.
    expect(find.text('Resgatado'), findsNWidgets(3));
    expect(find.text('Resgatar'), findsOneWidget);
    // Faixa do passe sem passe: níveis alcançados pedem o passe.
    expect(find.text('Requer passe'), findsNWidgets(4));
    // Níveis 5–7 bloqueados nas duas faixas.
    expect(find.text('Nível 5'), findsNWidgets(2));
    expect(find.text('Nível 6'), findsNWidgets(2));
    expect(find.text('Nível 7'), findsNWidgets(2));
    expect(find.textContaining('Só itens visuais'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resgatar muda o estado na hora e chama onClaim', (tester) async {
    RewardLane? gotLane;
    int? gotLevel;
    await openSeason(
      tester,
      onClaim: (level, lane) async {
        gotLevel = level;
        gotLane = lane;
      },
    );
    await tester.tap(find.text('Resgatar'));
    await tester.pumpAndSettle();
    expect(gotLevel, 4);
    expect(gotLane, RewardLane.free);
    expect(find.text('Resgatar'), findsNothing);
    expect(find.text('Resgatado'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro no resgate desfaz o estado e mostra mensagem', (
    tester,
  ) async {
    await openSeason(
      tester,
      onClaim: (level, lane) async => throw Exception('falhou'),
    );
    await tester.tap(find.text('Resgatar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível resgatar. Tente de novo.'),
      findsOneWidget,
    );
    expect(find.text('Resgatar'), findsOneWidget);
    expect(find.text('Resgatado'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('com passe não há banner nem "Requer passe"', (tester) async {
    final demo = demoSeason();
    final season = Season(
      name: demo.name,
      endsAt: demo.endsAt,
      levels: demo.levels,
      currentLevel: demo.currentLevel,
      points: demo.points,
      pointsForNext: demo.pointsForNext,
      hasPass: true,
      claimed: demo.claimed,
    );
    await openSeason(tester, season: season);
    expect(find.text('Requer passe'), findsNothing);
    expect(find.textContaining('Só itens visuais'), findsNothing);
    // Nível 4 do passe vira resgatável junto da grátis — e o mesmo vale
    // para a faixa do passe dos níveis 1–3 já alcançados.
    expect(find.text('Resgatar'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('em 360 px abre sem overflow', (tester) async {
    await openSeason(tester, size: const Size(360, 740));
    // A página (vertical) é a primeira lista; a segunda é a trilha horizontal.
    await tester.scrollUntilVisible(
      find.text('Ver passe'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ver passe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
