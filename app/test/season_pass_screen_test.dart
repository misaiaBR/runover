import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/screens/season_pass_screen.dart';
import 'package:runover_app/season_pass/models.dart';
import 'package:runover_app/season_pass/widgets/season_pass_banner.dart';
import 'package:runover_app/season_pass/widgets/season_pass_progress_card.dart';
import 'package:runover_app/theme.dart';

import 'season_pass_fixture.dart';

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
      levelStartPoints: demo.levelStartPoints,
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
    // O banner divide a linha com o progresso, acima da trilha: já aparece na
    // primeira tela, sem rolar a página inteira.
    expect(find.text('Desbloquear passe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('progresso e banner ficam lado a lado, com a trilha abaixo', (
    tester,
  ) async {
    await openSeason(tester, size: const Size(451, 900));
    final progress = tester.getRect(find.byType(SeasonPassProgressCard));
    final banner = tester.getRect(find.byType(SeasonPassBanner));
    // Um ao lado do outro: o banner começa depois do fim do progresso e na
    // mesma linha dele.
    expect(banner.left, greaterThanOrEqualTo(progress.right));
    expect((banner.top - progress.top).abs(), lessThan(8));
    // E a trilha vem abaixo dos dois.
    expect(
      tester.getTopLeft(find.text('Grátis')).dy,
      greaterThan(progress.bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trilha abre no nível atual, não no nível 1', (tester) async {
    await openSeason(tester, season: longSeason(), size: const Size(900, 700));
    expect(find.text('L12 grátis'), findsOneWidget);
    // Os níveis anteriores ao atual ficam atrás, no arrasto — não na cara de
    // quem acabou de abrir a tela.
    expect(find.text('L1 grátis'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o fim da trilha aparece depois do último nível', (
    tester,
  ) async {
    await openSeason(
      tester,
      season: longSeason(levels: 30, currentLevel: 1),
      size: const Size(900, 700),
    );
    expect(find.text('Fim da trilha'), findsNothing);
    await tester.dragUntilVisible(
      find.text('Fim da trilha'),
      find.byType(Scrollable).last,
      const Offset(-400, 0),
    );
    expect(find.text('Fim da trilha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Requer passe" abre a confirmação do passe', (tester) async {
    var opened = 0;
    await openSeason(tester, onOpenPass: () => opened++);
    // Cartão tocável: o nível já foi alcançado, falta só o passe.
    await tester.tap(find.text('Requer passe').first);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nível bloqueado não se passa por disponível', (tester) async {
    var claimed = 0;
    var opened = 0;
    await openSeason(
      tester,
      onClaim: (level, lane) async => claimed++,
      onOpenPass: () => opened++,
    );
    // O cartão de um nível ainda não alcançado não abre nada: nem resgate,
    // nem venda.
    await tester.tap(find.text('Nível 6').first);
    await tester.pumpAndSettle();
    expect(claimed, 0);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });
}
