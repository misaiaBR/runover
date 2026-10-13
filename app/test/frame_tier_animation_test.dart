import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/cosmetics.dart';

/// O anel da moldura respira no ritmo do `tier` que o servidor calcula pelo
/// preço. Sem essa escada, uma moldura de bronze e uma de diamante teriam o
/// mesmo pulso — e é exatamente isso que estes testes recusam.
ShopItem _frame(String id, {required int tier}) => ShopItem(
  id: id,
  category: 'frame',
  name: id,
  price: 100 * tier,
  payload: {
    'colors': ['#F59E0B', '#EF4444'],
    'animated': true,
    'tier': tier,
  },
);

ShopItem _avatar(String id, {required int tier}) => ShopItem(
  id: id,
  category: 'avatar',
  name: id,
  price: 100 * tier,
  payload: {
    'generated': 'adventurer',
    'seed': id,
    'animated': true,
    'tier': tier,
  },
);

/// [wearKey] monta um estado novo a cada chamada; sem chave a árvore é
/// reaproveitada, que é justamente o caminho de trocar de item na mesma tela.
Future<void> _wear(
  WidgetTester tester, {
  ShopItem? frame,
  ShopItem? avatar,
  String? wearKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(),
      home: Scaffold(
        body: Center(
          child: FramedAvatar(
            key: wearKey == null ? null : Key(wearKey),
            radius: 30,
            frame: frame,
            avatarItem: avatar,
            fallbackLetter: 'V',
          ),
        ),
      ),
    ),
  );
  // `pump` e não `pumpAndSettle`: o anel gira em loop e nunca assenta.
  await tester.pump();
}

/// A escada documentada no widget: período `1500 - 250 * tier` ms e brilho
/// `(12 + 4 * tier) * glow`, com `glow` subindo de 0,6 a 1,0 na primeira perna
/// do pulso. O teste refaz a conta para o número não virar opinião.
double _expectedGlow(int tier, int elapsedMs) {
  final period = 1500 - 250 * tier;
  final value = (elapsedMs / period).clamp(0.0, 1.0);
  return (12 + 4 * tier) * (0.6 + 0.4 * value);
}

/// O `Container` circular que projeta sombra é o do pulso: o brilho é a leitura
/// visível do patamar.
double _glow(WidgetTester tester) {
  for (final box in tester.widgetList<Container>(find.byType(Container))) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.shape == BoxShape.circle) {
      final shadows = decoration.boxShadow;
      if (shadows != null && shadows.isNotEmpty) return shadows.first.blurRadius;
    }
  }
  throw StateError('o anel animado não foi desenhado');
}

/// O pintor da vida do anel, lido direto da árvore: é um só por avatar.
RingLifePainter _ringPainter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.foregroundPainter)
      .whereType<RingLifePainter>()
      .toList();
  expect(painters, hasLength(1));
  return painters.single;
}

void main() {
  test('animationTier lê o patamar do payload e fica entre 1 e 4', () {
    expect(animationTier(null), 1);
    expect(animationTier(_frame('a', tier: 1)), 1);
    expect(animationTier(_frame('b', tier: 3)), 3);
    // O catálogo só entrega 1..4; um payload torto não pode acelerar o anel.
    expect(animationTier(_frame('c', tier: 0)), 1);
    expect(animationTier(_frame('d', tier: 9)), 4);
    expect(
      animationTier(
        ShopItem(
          id: 'e',
          category: 'frame',
          name: 'e',
          price: 1,
          payload: {'tier': 'quatro'},
        ),
      ),
      1,
    );
  });

  testWidgets('cada patamar pulsa no seu próprio ritmo', (tester) async {
    for (final tier in [1, 2, 3, 4]) {
      await _wear(
        tester,
        frame: _frame('frame_tier_$tier', tier: tier),
        wearKey: 'wear-$tier',
      );
      // 400 ms é menor que o período do patamar 4, então todos ainda sobem.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_ringPainter(tester).tier, tier);
      expect(
        _glow(tester),
        closeTo(_expectedGlow(tier, 400), 0.01),
        reason: 'patamar $tier deve bater o pulso do preço',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('o anel veste o maior patamar entre moldura e avatar', (
    tester,
  ) async {
    await _wear(
      tester,
      frame: _frame('frame_bronze', tier: 1),
      avatar: _avatar('avatar_caratos', tier: 4),
      wearKey: 'wear-mix',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(_ringPainter(tester).tier, 4);
    expect(_glow(tester), closeTo(_expectedGlow(4, 400), 0.01));
  });

  testWidgets('trocar o item na mesma tela reacende no ritmo novo', (
    tester,
  ) async {
    await _wear(tester, frame: _frame('frame_devagar', tier: 1));
    await _wear(tester, frame: _frame('frame_rapido', tier: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_ringPainter(tester).tier, 4);
    expect(_glow(tester), closeTo(_expectedGlow(4, 400), 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconstruir a tela não inverte o pulso do anel simples', (
    tester,
  ) async {
    // O anel de cor vai e volta (`reverse: true`). `repeat()` recomeça a perna
    // de ida, então reacender o relógio em todo rebuild do perfil — que escuta
    // `AppState` e tem `FutureBuilder` — faria o brilho trocar de direção no
    // meio do respiro. O brilho é a leitura visível da perna do pulso.
    final frame = _frame('frame_simples', tier: 4); // período de 500 ms
    await _wear(tester, frame: frame);
    await tester.pump(const Duration(milliseconds: 400));
    final subindo = _glow(tester);
    await tester.pump(const Duration(milliseconds: 450)); // virou e desce
    final descendo = _glow(tester);
    expect(descendo, lessThan(subindo), reason: 'o anel deveria estar descendo');

    await _wear(tester, frame: frame); // mesma moldura, só pintou de novo
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      _glow(tester),
      lessThan(descendo),
      reason: 'a reconstrução virou a perna do pulso',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('os quatro patamares desenham o anel sem exceção', (
    tester,
  ) async {
    for (final tier in [1, 2, 3, 4]) {
      await _wear(
        tester,
        frame: _frame('frame_$tier', tier: tier),
        wearKey: 'paint-$tier',
      );
      for (final step in const [120, 380, 640, 1100, 1900]) {
        await tester.pump(Duration(milliseconds: step));
      }
      final painter = _ringPainter(tester);
      // O traço do anel roda sobre a caixa dele; cada patamar exercita um
      // caminho (1 só respira, 2 varre, 3 acende as três bolinhas).
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(80, 80));
      recorder.endRecording();
      expect(painter.progress, inInclusiveRange(0.0, 1.0));
      expect(tester.takeException(), isNull);
    }
  });
}
