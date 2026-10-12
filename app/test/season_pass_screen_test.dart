import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/screens/season_pass_screen.dart';
import 'package:runover_app/season_pass/models.dart';
import 'package:runover_app/season_pass/widgets/season_pass_highlight.dart';
import 'package:runover_app/season_pass/widgets/season_pass_progress_bar.dart';
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
  // `pump`, nunca `pumpAndSettle`: as prévias de banner e faixa respiram para
  // sempre (Breathe), então a tela nunca assenta. O segundo pump entrega o
  // reposicionamento da trilha no nível atual, marcado em fim de quadro.
  await tester.pump();
  await tester.pump();
}

/// Rolador horizontal da trilha: é o único `Scrollable` da tela que corre para
/// a direita (a página e o painel correm para baixo).
Finder trailScrollable() => find.byWidgetPredicate(
  (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.right,
);

void main() {
  testWidgets('os quatro estados aparecem na trilha e o painel abre no resgate', (
    tester,
  ) async {
    await openSeason(tester);
    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('Nível 4'), findsOneWidget);
    // 1–3 grátis resgatadas, 4 grátis resgatável — o cartão bloqueado não leva
    // etiqueta: o topo já diz o nível e o nó diz os pontos.
    expect(find.text('✓ Resgatado'), findsNWidgets(3));
    expect(find.text('Requer passe'), findsNWidgets(4));
    expect(find.text('NÍVEL 5'), findsNWidgets(2));
    expect(find.text('NÍVEL 6'), findsNWidgets(2));
    expect(find.text('NÍVEL 7'), findsNWidgets(2));
    // O painel abre no que dá para resgatar agora: um "Resgatar" na faixa e
    // outro, o botão que age, no destaque.
    expect(find.text('Resgatar'), findsNWidgets(2));
    expect(find.text('RECOMPENSA DO NÍVEL 4'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resgatar'), findsOneWidget);
    // O nó da trilha mostra os pontos que abrem o nível, direto do servidor.
    expect(find.text('400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar o cartão seleciona; quem resgata é o botão do painel', (
    tester,
  ) async {
    var claimed = 0;
    await openSeason(
      tester,
      onClaim: (level, lane) async => claimed++,
    );
    // O cartão da faixa do passe no nível 2 tem nome de item e está lacrado
    // para quem não tem passe: tocar mostra o painel dele, não resgata nada.
    await tester.tap(find.text('Moldura de teste').first);
    await tester.pump();
    expect(claimed, 0);
    expect(find.text('RECOMPENSA DO NÍVEL 2'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Ativar passe · 1.200 dracmas'),
      findsOneWidget,
    );
    expect(find.textContaining('Só itens visuais'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resgatar pelo painel muda o estado na hora e chama onClaim', (
    tester,
  ) async {
    RewardLane? gotLane;
    int? gotLevel;
    await openSeason(
      tester,
      onClaim: (level, lane) async {
        gotLevel = level;
        gotLane = lane;
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Resgatar'));
    await tester.pump();
    expect(gotLevel, 4);
    expect(gotLane, RewardLane.free);
    // A recompensa seleção passa a "já resgatada" e some da faixa.
    expect(find.text('Resgatar'), findsNothing);
    expect(find.text('✓ Resgatado'), findsNWidgets(4));
    expect(find.text('Já resgatada nesta temporada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro no resgate desfaz o estado e mostra mensagem', (
    tester,
  ) async {
    await openSeason(
      tester,
      onClaim: (level, lane) async => throw Exception('falhou'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Resgatar'));
    await tester.pump();
    expect(
      find.text('Não foi possível resgatar. Tente de novo.'),
      findsOneWidget,
    );
    // Desfeito: a faixa continua oferecendo o resgate do nível 4.
    expect(find.text('Resgatar'), findsNWidgets(2));
    expect(find.text('✓ Resgatado'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('com o passe ativo o selo aparece e a faixa violeta libera', (
    tester,
  ) async {
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
    expect(find.text('Passe ativo'), findsOneWidget);
    expect(find.textContaining('Só itens visuais'), findsNothing);
    // Níveis 1–3 do passe somam aos resgatáveis do nível 4, nas duas faixas,
    // mais o botão do painel.
    expect(find.text('Resgatar'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Ativar passe" do painel abre a confirmação do passe', (
    tester,
  ) async {
    var opened = 0;
    await openSeason(tester, onOpenPass: () => opened++);
    await tester.tap(find.text('Requer passe').first);
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Ativar passe · 1.200 dracmas'),
    );
    await tester.pump();
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
    // O cartão de um nível ainda não alcançado só abre o painel dele: nem
    // resgate, nem venda.
    await tester.tap(find.text('NÍVEL 6').first);
    await tester.pump();
    expect(claimed, 0);
    expect(opened, 0);
    expect(find.text('Nível 6 abre com 600 pts.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Como ganhar pontos" lista as fontes da temporada', (
    tester,
  ) async {
    await openSeason(tester);
    await tester.tap(find.text('Como ganhar pontos'));
    await tester.pump();
    expect(find.text('Corrida concluída'), findsOneWidget);
    expect(find.text('Território conquistado'), findsOneWidget);
    expect(find.text('Meta da semana'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('em 360 px cabeçalho, trilha e painel abrem sem overflow', (
    tester,
  ) async {
    await openSeason(tester, size: const Size(360, 900));
    expect(find.text('Aurora'), findsOneWidget);
    expect(find.byType(SeasonPassProgressBar), findsOneWidget);
    expect(find.byType(SeasonPassHighlightPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trilha abre no nível atual, não no nível 1', (tester) async {
    await openSeason(tester, season: longSeason(), size: const Size(900, 700));
    // Um cartão na faixa e o painel de destaque da mesma recompensa.
    expect(find.text('L12 grátis'), findsNWidgets(2));
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
      trailScrollable(),
      const Offset(-400, 0),
    );
    expect(find.text('Fim da trilha'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
