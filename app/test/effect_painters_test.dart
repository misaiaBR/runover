import 'dart:ui' as ui;

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
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(brightness: brightness),
      // O pedido de movimento reduzido chega pela árvore de `MediaQuery`, como
      // chega no aparelho de quem desligou a animação do sistema.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
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

/// Brilho médio de um quadro do efeito, desenhado fora da tela. É a forma de
/// contar flash por segundo sem depender do relógio do teste.
Future<double> _brilho(EffectSpec spec, double progress) async {
  final recorder = ui.PictureRecorder();
  StageEffectPainter(
    spec: spec,
    progress: progress,
    accent: spec.tint(),
    neutral: Colors.white,
  ).paint(Canvas(recorder), const Size(120, 60));
  final image = await recorder.endRecording().toImage(120, 60);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  var total = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    total += bytes.getUint8(i) + bytes.getUint8(i + 1) + bytes.getUint8(i + 2);
  }
  return total / (120 * 60 * 3);
}

/// Quantos clarões o item acende em [segundos]: cada curva que sobe acima do
/// meio tom entre duas amostras é um flash.
Future<int> _flashes(
  ShopItem item, {
  double seconds = 1,
  int amostras = 240,
}) async {
  final spec = EffectSpec.from(item);
  final ciclo = spec.cycleMs / 1000;
  final curva = <double>[];
  for (var i = 0; i < amostras; i++) {
    curva.add(await _brilho(spec, (seconds * i / amostras / ciclo) % 1));
  }
  final maior = curva.reduce((a, b) => a > b ? a : b);
  final menor = curva.reduce((a, b) => a < b ? a : b);
  final corte = menor + (maior - menor) * .5;
  var beiradas = 0;
  for (var i = 1; i < curva.length; i++) {
    if (curva[i - 1] < corte && curva[i] >= corte) beiradas++;
  }
  return beiradas;
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

  test('o estroboscópio cabe no teto de flashes por segundo', () {
    // Pior caso do vocabulário: `density` no teto com o ciclo no piso. O item
    // pediria 46 clarões em 600 ms; o relógio entrega só os que a taxa segura
    // permite — piscar mais que isso é gatilho, não cosmético.
    final pior = EffectSpec.from(
      _effect(id: 'e_pior', kind: 'strobe', density: 46, cycleMs: 600),
    );
    expect(pior.strobeFlashes, 1);
    // Um item normal da loja continua piscando o que pode: o teto segura a taxa,
    // não apaga o efeito comprado.
    final comum = EffectSpec.from(
      _effect(id: 'e_comum', kind: 'strobe', density: 6, cycleMs: 1400),
    );
    expect(comum.strobeFlashes, 4);
    expect(
      comum.strobeFlashes / (comum.cycleMs / 1000),
      lessThanOrEqualTo(kMaxFlashesPerSecond.toDouble()),
    );
  });

  testWidgets('o palco desenhado não passa de três clarões por segundo', (
    tester,
  ) async {
    // A regra mora no `EffectSpec`, mas o que a pessoa vê é o pintor: contado no
    // desenho de verdade, quadro a quadro, nenhum item do vocabulário pode
    // estourar a taxa.
    late int pior;
    late int comum;
    await tester.runAsync(() async {
      pior = await _flashes(
        _effect(id: 'e_pior', kind: 'strobe', density: 46, cycleMs: 600),
      );
      comum = await _flashes(
        _effect(id: 'e_comum', kind: 'strobe', density: 6, cycleMs: 1400),
      );
    });
    expect(
      pior,
      greaterThan(0),
      reason: 'estroboscópio que não pisca deixou de ser o produto',
    );
    expect(pior, lessThanOrEqualTo(kMaxFlashesPerSecond));
    expect(comum, lessThanOrEqualTo(kMaxFlashesPerSecond));
  });

  testWidgets('movimento reduzido apaga o relógio do palco', (tester) async {
    final item = _effect(
      id: 'e_comum',
      kind: 'strobe',
      density: 6,
      cycleMs: 1400,
    );
    await _pumpField(tester, item);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.hasRunningAnimations,
      isTrue,
      reason: 'sem o pedido do aparelho o palco anima',
    );
    // Quem desligou a animação do sistema muda de ideia no meio da sessão: o
    // relógio tem de apagar sem reabrir a tela.
    await _pumpField(tester, item, reduceMotion: true);
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.hasRunningAnimations, isFalse);
    expect(_painter(tester).progress, 0);
    expect(tester.takeException(), isNull);
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
