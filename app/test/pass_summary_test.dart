import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/screens/pass_screen.dart';

/// O resumo usa a mesma régua da trilha (Season.levelProgress): só conta os
/// pontos ganhos desde que o último nível abriu, não o total acumulado.
Map<String, dynamic> _status({required int points, required int unlocked}) => {
  'season_id': '2026-10',
  'seasonal_points': points,
  'unlocked_tier': unlocked,
  'premium_unlocked': false,
  'tiers': [
    {'tier': 1, 'threshold': 200, 'unlocked': unlocked >= 1},
    {'tier': 2, 'threshold': 400, 'unlocked': unlocked >= 2},
  ],
};

Future<void> _open(WidgetTester tester, Map<String, dynamic> status) async {
  await tester.pumpWidget(MaterialApp(home: PassSummary(status: status)));
  await tester.pump();
}

void main() {
  testWidgets('progresso mede a janela do nível, como a trilha', (tester) async {
    await _open(tester, _status(points: 250, unlocked: 1));
    // (250 - 200) / (400 - 200) = 25% — o acumulado (250 / 400 = 62,5%)
    // contradizia o cartão de progresso.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(0.25, 0.001));
    expect(find.text('Faltam 150 XP para o tier 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pontos além do limiar não geram "Faltam" negativo', (
    tester,
  ) async {
    await _open(tester, _status(points: 450, unlocked: 1));
    expect(find.text('Faltam 0 XP para o tier 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
