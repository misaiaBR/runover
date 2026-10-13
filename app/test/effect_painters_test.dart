import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/effect_painters.dart';
import 'package:runover_app/widgets/offer_row.dart';
import 'package:runover_app/widgets/runover_ui.dart';

ShopItem _effect({
  required String id,
  required String kind,
  int density = 12,
  int cycleMs = 2000,
  int hue = 45,
}) => ShopItem(
  id: id,
  category: 'effect',
  name: 'Efeito $kind',
  price: 300,
  payload: {
    'kind': kind,
    'density': density,
    'cycle_ms': cycleMs,
    'hue': hue,
  },
);

ShopItem _bundle(String id, List<String> colors) => ShopItem(
  id: id,
  category: 'bundle',
  name: 'Pacote $id',
  price: 400,
  payload: {
    'grants': ['avatar_galeria_001', 'frame_colecao_002', 'banner_paisagem_003'],
    'colors': colors,
  },
);

Future<void> _pumpField(
  WidgetTester tester,
  ShopItem item, {
  Brightness brightness = Brightness.dark,
  bool onDarkSurface = false,
  Size box = const Size(320, 120),
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: box.width,
            height: box.height,
            child: ProfileEffectOverlay(
              effect: item,
              onDarkSurface: onDarkSurface,
            ),
          ),
        ),
      ),
    ),
  );
}

StageEffectPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.byType(ProfileEffectOverlay),
          matching: find.byType(CustomPaint),
        )
        .first,
  );
  return paint.painter! as StageEffectPainter;
}

void main() {
  test('o payload do item escolhe desenho, ritmo e cor', () {
    final spec = EffectSpec.from(
      _effect(id: 'e1', kind: 'storm', density: 16, cycleMs: 1100, hue: 210),
    );
    expect(spec.kind, 'storm');
    expect(spec.density, 16);
    expect(spec.cycle, const Duration(milliseconds: 1100));
    expect(spec.hue, 210);
  });

  test('um tipo que o app não conhece nunca chega ao pintor', () {
    // A loja anuncia só o vocabulário dela; se vier nome de fora, o desenho cai
    // no renderizador que existe, e não em algo inventado na hora.
    final spec = EffectSpec.from(_effect(id: 'e2', kind: 'nevoa_neon'));
    expect(spec.kind, 'sparkle');
  });

  test('física fora da escala é ajustada, não obedecida', () {
    final spec = EffectSpec.from(
      _effect(id: 'e3', kind: 'rain', density: 9000, cycleMs: 10),
    );
    expect(spec.density, 46);
    expect(spec.cycleMs, 600);
  });

  test('itens diferentes desenham campos diferentes', () {
    expect(effectSeedOf('effect_pion_001'), effectSeedOf('effect_pion_001'));
    expect(effectSeedOf('effect_pion_001'), isNot(effectSeedOf('effect_pion_002')));
  });

  testWidgets('cada tipo do catálogo tem desenho próprio', (tester) async {
    // Os 19 tipos abaixo são a mesma lista de `EFFECT_KINDS` do backend. Se um
    // nome entrar lá sem entrar aqui, o teste da vitrine derruba o boot e este
    // aqui mostra qual desenho falta.
    expect(kEffectKinds, hasLength(19));
    for (final (index, kind) in kEffectKinds.indexed) {
      await _pumpField(
        tester,
        _effect(
          id: 'efeito_$kind',
          kind: kind,
          density: 8 + (index % 5) * 6,
          hue: (index * 61) % 360,
        ),
      );
      // Vários instantes de um mesmo ciclo: névoa, laser e tempestade só podem
      // ser vistos em movimento.
      for (final ms in [0, 300, 900, 1700, 2600]) {
        await tester.pump(Duration(milliseconds: ms));
      }
      expect(tester.takeException(), isNull, reason: 'kind $kind');
      expect(_painter(tester).spec.kind, kind);
    }
  });

  test('a mesma densidade cabe na miniatura da vitrine', () {
    // O payload é do cartão de perfil; na caixa pequena a contagem entra
    // proporcionalmente à área, senão "Chuva" viraria uma só mancha.
    final card = effectUnits(const Size(240, 88), 34);
    final tile = effectUnits(const Size(64, 64), 34);
    expect(card, 34);
    expect(tile, lessThan(card));
    expect(tile, greaterThanOrEqualTo(3));
    expect(effectUnits(const Size(20, 20), 2), 3);
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('a camada se lê sobre o cartão do tema ${brightness.name}', (
      tester,
    ) async {
      await _pumpField(
        tester,
        _effect(id: 'e5', kind: 'sparkle', hue: 180),
        brightness: brightness,
      );
      final painter = _painter(tester);
      final context = tester.element(find.byType(ProfileEffectOverlay));
      expect(
        contrastOnSurfaces(painter.accent, context),
        greaterThanOrEqualTo(4.5),
      );
      expect(painter.neutral, Pal.of(context).heading);
    });
  }

  testWidgets('na caixa escura da raridade a tinta é a cor crua do item', (
    tester,
  ) async {
    // A caixa de arte da vitrine e o cartão do passe têm gradiente fixo: ali a
    // tinta queimada para o tema claro viraria preta sobre azul-marinho.
    await _pumpField(
      tester,
      _effect(id: 'e6', kind: 'hologram', hue: 280),
      brightness: Brightness.light,
      onDarkSurface: true,
    );
    final painter = _painter(tester);
    final spec = EffectSpec.from(_effect(id: 'e6', kind: 'hologram', hue: 280));
    expect(painter.accent, spec.tint());
    expect(painter.neutral, Colors.white);
  });

  testWidgets('a vitrine desenha o efeito, não um emoji', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 84,
              height: 84,
              child: ShopPreview(
                item: _effect(id: 'e7', kind: 'streamer'),
                scale: 0.62,
                onDarkSurface: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ProfileEffectOverlay), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada pacote tem capa própria na vitrine', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Column(
            children: [
              ShopPreview(item: _bundle('pacote_a', ['#FF7F4D', '#8B3A10'])),
              ShopPreview(item: _bundle('pacote_b', ['#22D3EE', '#0B4C5A'])),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final covers = tester
        .widgetList<BundleCover>(find.byType(BundleCover))
        .map((cover) => cover.item.payload['colors'].toString())
        .toList();
    expect(covers, hasLength(2));
    expect(covers.first, isNot(covers.last));
    expect(find.text('📦'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
