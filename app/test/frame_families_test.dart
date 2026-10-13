import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/frame_painters.dart';

/// O catálogo declara nove famílias em `payload['style']`. Cada uma precisa
/// virar um desenho próprio no avatar; se duas famílias desenharem o mesmo anel
/// colorido, o `style` passou a ser texto de ficha técnica. Estes testes
/// amarram o contrário: cada família tem um pintor, e as palavras do payload
/// mudam o traço sem derrubar a tela.
ShopItem _frame(
  String style, {
  Map<String, dynamic> extra = const {},
  bool animated = true,
  int tier = 3,
}) => ShopItem(
  id: 'frame_$style',
  category: 'frame',
  name: 'Moldura $style',
  price: 100 * tier,
  payload: {
    'colors': ['#F59E0B', '#22D3EE'],
    'animated': animated,
    'tier': tier,
    'style': style,
    ...extra,
  },
);

/// As palavras que o servidor usa em `_frame_params`, com um exemplo de cada.
const Map<String, Map<String, dynamic>> _showcase = {
  'glass': {'blur': 2, 'edge': '#FFFFFF'},
  'mono': {'thickness': 2, 'pulse': true},
  'geo': {'notch': 'corner_tl'},
  'metal': {'grade': 'ouro', 'ornament': 'wings'},
  'faction': {'texture': 'circuit'},
  'ring': {'gauge': 'xp'},
  'chroma': {'speed_ms': 2600},
  'ambient': {'particle': 'stardust', 'count': 10},
  'glitch': {'jitter': 2, 'interval_ms': 1200},
};

/// Sem chave, o `pumpWidget` seguinte reaproveita o `State` e o relógio continua
/// de onde parou — o que é exatamente o caminho de trocar de item na mesma tela,
/// e justamente o que estes testes não querem medir.
int _wearCount = 0;

Future<void> _wear(
  WidgetTester tester,
  ShopItem frame, {
  List<FrameGauge> gauges = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunoverTheme(),
      home: Scaffold(
        body: Center(
          child: FramedAvatar(
            key: ValueKey('wear-${_wearCount++}'),
            radius: 30,
            frame: frame,
            gauges: gauges,
            fallbackLetter: 'V',
          ),
        ),
      ),
    ),
  );
  // `pump` e não `pumpAndSettle`: as famílias que giram nunca assentam.
  await tester.pump();
}

/// O pintor da moldura, lido direto da árvore — é um só por avatar.
FrameFamilyPainter _painter(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.foregroundPainter)
      .whereType<FrameFamilyPainter>()
      .toList();
  expect(painters, hasLength(1));
  return painters.single;
}

/// Desenha o aro num quadro descartável: o que importa aqui é o traço não
/// quebrar com o payload do catálogo.
void _draw(FrameFamilyPainter painter) {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), const Size(80, 80));
  recorder.endRecording();
}

void main() {
  test('as nove famílias do catálogo existem no enum', () {
    expect(FrameFamily.values.map((f) => f.name).toList(), _showcase.keys);
    expect(FrameFamily.parse('glass'), FrameFamily.glass);
    // Palavra que o servidor não usa (e a moldura de parceria, que não tem
    // style) ficam no anel simples de cor.
    expect(FrameFamily.parse('cristal'), null);
    expect(FrameFamily.parse(null), null);
    expect(frameFamily(_frame('glitch')), FrameFamily.glitch);
    expect(frameFamily(null), null);
  });

  testWidgets('cada família desenha um pintor próprio, sem o anel simples', (
    tester,
  ) async {
    // O espaço que o perfil reserva é o mesmo do anel simples: rosto de 60 +
    // 3 de respiro de cada lado. Nenhuma família empurra o layout.
    await _wear(tester, _frame('sem estilo', extra: {'style': null}));
    final ocupado = tester.getSize(find.byType(FramedAvatar));
    expect(ocupado, const Size(66, 66));
    for (final entry in _showcase.entries) {
      await _wear(tester, _frame(entry.key, extra: entry.value));
      final painter = _painter(tester);
      expect(painter.family.name, entry.key);
      expect(painter.item.id, 'frame_${entry.key}');
      expect(
        tester.getSize(find.byType(FramedAvatar)),
        ocupado,
        reason: '${entry.key} mudou o espaço que o avatar ocupa',
      );
      // A vida do anel simples (varredura + partículas de patamar) não se
      // empilha por cima do desenho da família.
      final simples = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<RingLifePainter>();
      expect(simples, isEmpty, reason: '${entry.key} vestiu o anel antigo');
      _draw(painter);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('todas as palavras do vocabulário de moldura desenham', (
    tester,
  ) async {
    const variants = <String, List<Object?>>{
      'blur': [1, 2, 3, 7],
      'thickness': [1, 2, 5],
      'pulse': [true, false],
      'notch': ['top', 'right', 'bottom', 'left', 'corner_tl', 'corner_br', 'lateral'],
      'grade': ['bronze', 'prata', 'ouro', 'platina', 'diamante', ' mithril '],
      'ornament': ['none', 'wings', 'jewel', 'spikes', 'coroa'],
      'texture': ['carbon', 'stone', 'rune', 'circuit', 'musgo'],
      'gauge': ['xp', 'sequencia', 'territorio', 'ouro'],
      'speed_ms': [1600, 2200, 4000],
      'particle': ['leaf', 'petal', 'stardust', 'energy', 'faisca'],
      'count': [6, 15, 40],
      'jitter': [1, 3, 9],
      'interval_ms': [900, 1400, 2699],
    };
    for (final entry in variants.entries) {
      for (final value in entry.value) {
        for (final family in _showcase.keys) {
          final frame = _frame(family, extra: {entry.key: value});
          await _wear(tester, frame);
          _draw(_painter(tester));
          expect(
            tester.takeException(),
            isNull,
            reason: '$family com ${entry.key}: $value derrubou o aro',
          );
        }
      }
    }
  });

  testWidgets('a família manda no relógio quando o catálogo diz estático', (
    tester,
  ) async {
    // Falha e neon têm movimento próprio: giram mesmo sem o `animated` do
    // catálogo, que é o que dá vida a um item parado.
    for (final style in ['glitch', 'chroma', 'ambient']) {
      await _wear(tester, _frame(style, animated: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        _painter(tester).progress,
        greaterThan(0),
        reason: '$style precisa de relógio para existir',
      );
    }
    // Vidro, corte e medidor são desenho, não animação: ficam congelados.
    for (final style in ['glass', 'geo', 'ring', 'metal', 'faction']) {
      await _wear(tester, _frame(style, animated: false));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        _painter(tester).progress,
        0,
        reason: '$style não declara loop e veio como item parado',
      );
    }
    // O traço fino só pulsa se o payload pedir.
    await _wear(tester, _frame('mono', animated: false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_painter(tester).progress, 0);
    await _wear(tester, _frame('mono', extra: {'pulse': true}, animated: false));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_painter(tester).progress, greaterThan(0));
  });

  testWidgets('a velocidade vem do payload; sem ela vale a escada de patamar', (
    tester,
  ) async {
    await _wear(tester, _frame('chroma', extra: {'speed_ms': 3000}, tier: 4));
    await tester.pump(const Duration(milliseconds: 1500));
    // 1500 de um ciclo de 3000 — o `speed_ms` do servidor ganhou do patamar 4.
    expect(_painter(tester).progress, closeTo(0.5, 0.02));

    await _wear(tester, _frame('glitch', extra: {'interval_ms': 1000}, tier: 4));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_painter(tester).progress, closeTo(0.25, 0.02));

    // Família muda: o período volta a ser o do preço (1500 - 250 * 4 = 500 ms).
    await _wear(tester, _frame('metal', extra: {'grade': 'diamante'}, tier: 4));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_painter(tester).progress, closeTo(0.5, 0.02));
  });

  test('o medidor só pinta o número que mede a mesma grandeza', () {
    const xp = [FrameGauge(GaugeMeasure.xp, 0.4)];
    expect(gaugeFill('xp', xp), 0.4);
    expect(gaugeFill('sequencia', xp), null);
    expect(gaugeFill(null, xp), null);
    expect(gaugeFill('xp', const []), null);
    // Dos números que o perfil tem, vale o que a moldura pediu.
    expect(
      gaugeFill('territorio', const [
        FrameGauge(GaugeMeasure.xp, 0.2),
        FrameGauge(GaugeMeasure.territorio, 0.75),
      ]),
      0.75,
    );
    // Fora de 0..1 não existe: o traço não pode sair do aro.
    expect(gaugeFill('xp', const [FrameGauge(GaugeMeasure.xp, 3)]), 1);
    expect(gaugeFill('xp', const [FrameGauge(GaugeMeasure.xp, -1)]), 0);
  });

  testWidgets('a moldura de medidor recebe os números de quem veste o avatar', (
    tester,
  ) async {
    await _wear(
      tester,
      _frame('ring', extra: {'gauge': 'xp'}),
      gauges: const [FrameGauge(GaugeMeasure.xp, 0.6)],
    );
    final painter = _painter(tester);
    expect(painter.gauges, hasLength(1));
    _draw(painter);
    expect(tester.takeException(), isNull);

    // Na loja ninguém tem número: o aro se mostra aberto, com as marcas do
    // medidor, e não preenche nada.
    await _wear(tester, _frame('ring', extra: {'gauge': 'xp'}));
    expect(_painter(tester).gauges, isEmpty);
  });
}
