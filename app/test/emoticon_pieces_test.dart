import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/emoticon_pieces.dart';
import 'package:runover_app/widgets/presence.dart';

/// O pacote de emoticons vende quatro palavras por item (`_emoticon_presentation`
/// em `backend/app/services/shop.py`): `depth`, `motion`, `badge` e `trail`,
/// além de `tint`. Se o app só lesse isso como texto de ficha técnica, "Pacote
/// pulso" e "Pacote mola" seriam o mesmo emoji cru na loja e no perfil.
///
/// O servidor também não guarda qual pacote foi equipado — `_equip_emoticons`
/// escreve glifos na lista plana `equipped_emoticons`. Estes testes amarram as
/// duas pontas: cada palavra vira um desenho distinto, e a regra de "qual pacote
/// apresenta este glifo" (cobertura + maior patamar) tem uma única resposta,
/// inclusive no perfil de outra pessoa.
ShopItem _pack(
  String id, {
  List<String> emoji = const ['🏆'],
  String? depth,
  String? motion,
  String? badge,
  bool? trail,
  String? tint,
  int tier = 1,
}) => ShopItem(
  id: id,
  category: 'emoticon',
  name: 'Pacote $id',
  price: 40 * tier,
  payload: {
    'animated': true,
    'tier': tier,
    'emoji': emoji,
    'depth': ?depth,
    'motion': ?motion,
    'badge': ?badge,
    'trail': ?trail,
    'tint': ?tint,
  },
);

ShopItem _avatar(String id, {String? depth}) => ShopItem(
  id: id,
  category: 'avatar',
  name: 'Rosto $id',
  price: 60,
  payload: {'animated': false, 'tier': 1, 'depth': ?depth},
);

/// Pinta o material sobre uma caixa vazia e devolve os pixels em RGBA puro. É o
/// único jeito de perguntar se `glass` e `volumetric` são desenhos diferentes,
/// em vez de confiar que o widget montou.
Future<ByteData> _material(
  EmoticonDepth depth, {
  Color tint = const Color(0xFFFFC93C),
  double pulse = 0.5,
  double side = 64,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  EmoticonMaterialPainter(
    depth: depth,
    tint: tint,
    pulse: pulse,
  ).paint(canvas, Size(side, side));
  final image = await recorder.endRecording().toImage(side.ceil(), side.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

/// Soma de todas as diferenças entre duas pinturas, canal por canal. Zero
/// significa "o mesmo desenho".
int _totalDelta(ByteData a, ByteData b) {
  var total = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    for (var channel = 0; channel < 4; channel++) {
      total += (a.getUint8(i + channel) - b.getUint8(i + channel)).abs();
    }
  }
  return total;
}

int _alphaSum(ByteData pixels) {
  var total = 0;
  for (var i = 3; i < pixels.lengthInBytes; i += 4) {
    total += pixels.getUint8(i);
  }
  return total;
}

/// Quantos picos (máximos locais estritos) o gesto tem num ciclo amostrado.
/// É assim que se confere o "dois pulsos" do `heartbeat` e os "dois saltos" do
/// `pop_spin` sem depender do relógio do widget.
int _peaksOf(double Function(double t) sample, {int steps = 250}) {
  var peaks = 0;
  for (var i = 1; i < steps; i++) {
    final before = sample((i - 1) / steps);
    final here = sample(i / steps);
    final after = sample((i + 1) / steps);
    if (here > before && here > after) peaks++;
  }
  return peaks;
}

/// O movimento inteiro como texto, para comparar gestos entre si sem depender
/// de `toString` de objeto (que seria identidade, não desenho).
String _signature(EmoticonGesture g) => [
  g.scaleX,
  g.scaleY,
  g.dy,
  g.rotation,
  g.pulse,
  g.opacity,
].map((value) => value.toStringAsFixed(4)).join('|');

void _expectPresentation(
  EmoticonPresentation? actual, {
  required EmoticonDepth depth,
  required EmoticonMotion motion,
  required EmoticonBadge badge,
  required bool trail,
  Color? tint,
}) {
  expect(actual, isNotNull);
  expect(actual!.depth, depth);
  expect(actual.motion, motion);
  expect(actual.badge, badge);
  expect(actual.trail, trail);
  expect(actual.tint, tint);
}

void main() {
  test('as quatro palavras do catálogo viram eixos; fora delas, nada', () {
    for (final depth in EmoticonDepth.values) {
      expect(EmoticonDepth.parse(depth.name), depth);
    }
    for (final badge in EmoticonBadge.values) {
      expect(EmoticonBadge.parse(badge.name), badge);
    }
    // `motion` é a única família cuja palavra difere do identificador Dart
    // (`pop_spin`), e o parse é pela palavra do payload, não pelo nome.
    for (final motion in EmoticonMotion.values) {
      expect(EmoticonMotion.parse(motion.word), motion);
    }
    expect(EmoticonMotion.popSpin.word, 'pop_spin');
    // Palavra inventada ou tipo errado não viram a primeira opção da lista.
    expect(EmoticonDepth.parse('cristal'), isNull);
    expect(EmoticonMotion.parse('spin'), isNull);
    expect(EmoticonBadge.parse(3), isNull);
    expect(EmoticonDepth.parse(null), isNull);
  });

  test('um item só ganha apresentação quando é de emoticon e declara algo', () {
    _expectPresentation(
      EmoticonPresentation.of(
        _pack(
          'emoticon_troféu',
          depth: 'volumetric',
          motion: 'heartbeat',
          badge: 'corner',
          trail: true,
          tint: '#FFC93C',
          tier: 4,
        ),
      ),
      depth: EmoticonDepth.volumetric,
      motion: EmoticonMotion.heartbeat,
      badge: EmoticonBadge.corner,
      trail: true,
      tint: const Color(0xFFFFC93C),
    );

    // Eixo ausente é o neutro dele, não uma aposta: `depth` ausente não vira
    // vidro só porque o item tem gesto.
    _expectPresentation(
      EmoticonPresentation.of(_pack('b', motion: 'float')),
      depth: EmoticonDepth.flat,
      motion: EmoticonMotion.float,
      badge: EmoticonBadge.none,
      trail: false,
    );

    // Pacote anterior à loja de apresentações: nenhuma palavra, glifo cru.
    expect(EmoticonPresentation.of(_pack('c')), isNull);
    expect(EmoticonPresentation.of(null), isNull);

    // `depth` é palavra das duas lojas. O `flat` de um rosto não é material de
    // emoticon: a categoria precisa barrar o vazamento.
    expect(EmoticonPresentation.of(_avatar('avatar_x', depth: 'flat')), isNull);
    expect(EmoticonPresentation.of(_avatar('avatar_y', depth: 'glass')), isNull);

    // Hex mal escrito não derruba a tela nem inventa cor.
    _expectPresentation(
      EmoticonPresentation.of(_pack('d', depth: 'glass', tint: '#ZZZZZZ')),
      depth: EmoticonDepth.glass,
      motion: EmoticonMotion.spring,
      badge: EmoticonBadge.none,
      trail: false,
    );
  });

  test('os quatro gestos são curvas diferentes, não o mesmo desenho', () {
    // Mola: o eixo que estica é o que comprime o outro.
    final jelly = emoticonGestureOf(EmoticonMotion.spring, 0.25);
    expect(jelly.scaleY, greaterThan(1));
    expect(jelly.scaleX, lessThan(1));
    expect(jelly.rotation, 0);
    expect(jelly.dy, 0);

    // Pulso: duas batidas e silêncio, e o instante zero continua parado — se a
    // volta ao começo tivesse valor, a peça daria um tranco a cada ciclo.
    double beat(double t) => emoticonGestureOf(EmoticonMotion.heartbeat, t).pulse;
    final thump = emoticonGestureOf(EmoticonMotion.heartbeat, 0);
    expect(thump.pulse, 0);
    expect(thump.scaleX, 1);
    expect(emoticonGestureOf(EmoticonMotion.heartbeat, 1).pulse, 0);
    expect(_peaksOf(beat), 2);
    final bump = emoticonGestureOf(EmoticonMotion.heartbeat, 0.16);
    expect(bump.scaleX, bump.scaleY);

    // Giro: poucos graus, com amplitude limitada, e dois saltos por ciclo.
    final spin = emoticonGestureOf(EmoticonMotion.popSpin, 0.25);
    expect(spin.rotation, greaterThan(0.2));
    expect(spin.rotation, lessThan(0.35));
    expect(
      emoticonGestureOf(EmoticonMotion.popSpin, 0.75).rotation,
      lessThan(-0.2),
    );
    expect(
      _peaksOf((t) => emoticonGestureOf(EmoticonMotion.popSpin, t).pulse),
      2,
    );

    // Flutua: sobe e apaga — é o único gesto que muda posição e opacidade.
    final drift = emoticonGestureOf(EmoticonMotion.float, 0.5);
    expect(drift.dy, lessThan(0));
    expect(drift.opacity, greaterThan(0.9));
    expect(emoticonGestureOf(EmoticonMotion.float, 0).opacity, lessThan(0.5));
    expect(emoticonGestureOf(EmoticonMotion.float, 1).opacity, lessThan(0.5));
    expect(emoticonGestureOf(EmoticonMotion.float, 0.8).dy, lessThan(drift.dy));

    // Conferência final: no mesmo instante, os quatro gestos devolvem movimentos
    // distintos. Se dois casassem, `motion` seria enfeite de ficha técnica.
    final signatures = {
      for (final motion in EmoticonMotion.values)
        motion: _signature(emoticonGestureOf(motion, 0.37)),
    };
    expect(signatures.values.toSet(), hasLength(EmoticonMotion.values.length));
  });

  test('o ritmo vem do gesto e do patamar, não de um pulso único', () {
    final periods = {
      for (final motion in EmoticonMotion.values)
        motion: emoticonPeriodOf(motion, 2).inMilliseconds,
    };
    expect(periods.values.toSet(), hasLength(4));
    // Patamar mais alto corre mais: é a escada do catálogo, não escolha do app.
    for (final motion in EmoticonMotion.values) {
      expect(
        emoticonPeriodOf(motion, 4).inMilliseconds,
        lessThan(emoticonPeriodOf(motion, 1).inMilliseconds),
      );
    }
  });

  testWidgets('cada material é uma pintura; `flat` não pinta nada', (
    tester,
  ) async {
    late ByteData flat;
    late ByteData glass;
    late ByteData lifted;
    late ByteData orb;
    late ByteData glassDark;
    late ByteData glassBright;
    await tester.runAsync(() async {
      flat = await _material(EmoticonDepth.flat);
      glass = await _material(EmoticonDepth.glass);
      lifted = await _material(EmoticonDepth.lifted);
      orb = await _material(EmoticonDepth.volumetric);
      glassDark = await _material(EmoticonDepth.glass, pulse: 0);
      glassBright = await _material(EmoticonDepth.glass, pulse: 1);
    });
    expect(_alphaSum(flat), 0);
    expect(_alphaSum(glass), greaterThan(0));
    expect(_alphaSum(lifted), greaterThan(0));
    expect(_alphaSum(orb), greaterThan(0));
    // Par a par: três materiais, três desenhos. Um painter com três nomes seria
    // a loja vendendo o mesmo vidro três vezes.
    expect(_totalDelta(glass, lifted), greaterThan(0));
    expect(_totalDelta(glass, orb), greaterThan(0));
    expect(_totalDelta(lifted, orb), greaterThan(0));
    // A luz do gesto também é pintura: o halo acende com o pulso.
    expect(_totalDelta(glassDark, glassBright), greaterThan(0));
  });

  testWidgets('toda combinação do catálogo monta sem estourar', (
    tester,
  ) async {
    for (final depth in EmoticonDepth.values) {
      for (final motion in EmoticonMotion.values) {
        for (final trail in const [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildRunoverTheme(),
              home: Scaffold(
                body: Center(
                  child: EmoticonPiece(
                    glyph: '🏆',
                    pack: _pack(
                      'emoticon_teste',
                      depth: depth.name,
                      motion: motion.word,
                      badge: 'corner',
                      trail: trail,
                      tint: '#FFC93C',
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.text('🏆'), findsWidgets);
        }
      }
    }
  });

  testWidgets('a peça ocupa a mesma caixa em qualquer apresentação', (
    tester,
  ) async {
    Future<Size> wear(ShopItem pack, {double fontSize = 20}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: EmoticonPiece(
                glyph: '🏆',
                pack: pack,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Dois instantes do mesmo ciclo: o gesto vive em `Transform`, então o
      // mural não pula quando a peça respira nem quando o pacote troca.
      final before = tester.getSize(find.byType(EmoticonPiece));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getSize(find.byType(EmoticonPiece)), before);
      return before;
    }

    // fontSize 20 * 1.35
    expect(
      await wear(_pack('vidro', depth: 'glass', motion: 'spring')),
      const Size(27, 27),
    );
    expect(
      await wear(
        _pack('orbe', depth: 'volumetric', motion: 'float', trail: true),
      ),
      const Size(27, 27),
    );
    // A prévia da vitrine é a mesma peça em outro tamanho, com a mesma caixa
    // quadrada: 30 * 1.35.
    expect(
      await wear(_pack('rastro', depth: 'lifted', trail: true), fontSize: 30),
      const Size(40.5, 40.5),
    );

    Future<int> glyphCount(String glyph, bool trail) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: EmoticonPiece(
                glyph: glyph,
                pack: _pack('rastro', depth: 'glass', trail: trail),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.widgetList<Text>(find.byType(Text)).length;
    }

    // O rastro é o glifo comprado: três miniaturas além da peça.
    expect(await glyphCount('⚡', true), 4);
    expect(await glyphCount('⚡', false), 1);
  });

  testWidgets('sem pacote o glifo continua cru e uma pintura por peça', (
    tester,
  ) async {
    List<EmoticonMaterialPainter> painters() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<EmoticonMaterialPainter>()
        .toList();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(body: Center(child: EmoticonPiece(glyph: '🏆'))),
      ),
    );
    await tester.pump();
    expect(painters(), isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunoverTheme(),
        home: Scaffold(
          body: Center(
            child: Wrap(
              children: [
                EmoticonPiece(
                  glyph: '🏆',
                  pack: _pack('p', depth: 'glass', motion: 'spring'),
                ),
                EmoticonPiece(glyph: '🥇'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(painters(), hasLength(1));
  });

  testWidgets('a tinta sobrevive à troca de tema', (tester) async {
    Future<Color> ink({
      Brightness brightness = Brightness.light,
      bool onDarkSurface = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: EmoticonPiece(
                glyph: '🏆',
                pack: _pack('amarelo', depth: 'glass', tint: '#FFC93C'),
                onDarkSurface: onDarkSurface,
              ),
            ),
          ),
        ),
      );
      // `MaterialApp` troca o tema com `AnimatedTheme`: no primeiro frame o
      // brilho ainda é o do tema anterior, e a tinta seria queimada contra o
      // cartão errado. Uma espera curta resolve o pulso do `Breathe` das peças.
      await tester.pump(const Duration(milliseconds: 250));
      return tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<EmoticonMaterialPainter>()
          .single
          .tint;
    }

    final claro = await ink();
    final escuro = await ink(brightness: Brightness.dark);
    // O amarelo do catálogo some no cartão branco: no tema claro a peça é
    // queimada, no escuro ela continua a cor vendida.
    expect(claro.computeLuminance(), lessThan(escuro.computeLuminance()));
    // A arte da vitrine fica sobre o gradiente fixo e escuro da raridade, onde a
    // tinta queimada do tema claro sumiria — ali o matiz cru continua.
    expect(
      await ink(onDarkSurface: true),
      cosmeticHexColor('#FFC93C'),
    );
  });

  test('um pacote só entra no mural quando o mural o sustenta inteiro', () {
    final trofeu = _pack(
      'emoticon_troféu',
      emoji: ['🏆'],
      depth: 'volumetric',
      motion: 'heartbeat',
      badge: 'corner',
      tier: 4,
    );
    final campeao = _pack(
      'emoticon_campeão',
      emoji: ['🏆', '⚡', '🥇', '🎖'],
      depth: 'lifted',
      motion: 'spring',
      badge: 'ring',
      tier: 3,
    );
    final catalog = [trofeu, campeao];

    // `MAX_EQUIPPED_EMOTICONS` corta o campeão em quatro glifos: quem equipa só
    // o troféu tem o troféu apresentado, e um pacote incompleto não aparece com
    // acabamento que o mural não mostra.
    expect(emoticonPacksInPlay(catalog, const ['🏆']), [trofeu]);
    final partial = emoticonMural(catalog, const ['🏆']);
    expect(partial.entries.single.pack, trofeu);
    expect(partial.badgePack, trofeu);

    // Mural completo: os dois estão em jogo e disputam o mesmo glifo.
    expect(
      emoticonPacksInPlay(catalog, const ['🏆', '⚡', '🥇', '🎖']).toSet(),
      catalog.toSet(),
    );
  });

  test('maior patamar ganha o glifo e o distintivo; empate, o glifo antigo', () {
    const full = ['🏆', '⚡', '🥇', '🎖'];
    final trofeu = _pack(
      'emoticon_troféu',
      emoji: ['🏆'],
      depth: 'volumetric',
      badge: 'corner',
      tier: 4,
    );
    final campeao = _pack(
      'emoticon_campeão',
      emoji: full,
      depth: 'lifted',
      badge: 'ring',
      tier: 3,
    );

    // Quem paga mais vê o item se mexendo mais: o `tier` do servidor decide.
    final rich = emoticonMural([campeao, trofeu], full);
    expect(_ownerOf(rich, '🏆'), trofeu);
    expect(_ownerOf(rich, '⚡'), campeao);
    expect(rich.badgePack, trofeu);

    // Empate de patamar: o pacote do glifo mais antigo do mural manda. A lista
    // do servidor é ordem de equipamento, então a resposta é estável para quem
    // vê o perfil de outra pessoa — e não depende da ordem do catálogo.
    final antigo = _pack(
      'p_antigo',
      emoji: ['🥇', '🏆'],
      depth: 'glass',
      tier: 2,
    );
    final novo = _pack('p_novo', emoji: ['🏆'], depth: 'volumetric', tier: 2);
    // Mural onde o glifo do pacote antigo foi equipado primeiro.
    const disputado = ['🥇', '🏆'];
    for (final catalog in [
      [novo, antigo],
      [antigo, novo],
    ]) {
      expect(_ownerOf(emoticonMural(catalog, disputado), '🏆'), antigo);
    }
    // O glifo mais antigo só desempata entre patamares iguais: `tier` maior
    // continua mandando, que é o que a loja entrega para quem paga mais.
    final rico = _pack('p_rico', emoji: ['🏆'], depth: 'volumetric', tier: 3);
    expect(_ownerOf(emoticonMural([antigo, rico], disputado), '🏆'), rico);

    // Pacote sem distintivo não tira o distintivo de quem tem; e se ninguém em
    // jogo declara, o avatar continua só com o ponto de presença.
    final raio = _pack('emoticon_raio', emoji: ['⚡'], depth: 'glass', tier: 1);
    expect(emoticonMural([raio], const ['⚡']).badgePack, isNull);

    // Mural vazio e glifo que nenhum pacote do catálogo declara.
    final empty = emoticonMural([trofeu], const []);
    expect(empty.entries, isEmpty);
    expect(empty.badgePack, isNull);
    final orphan = emoticonMural([trofeu], const ['🌧']);
    expect(orphan.entries.single.glyph, '🌧');
    expect(orphan.entries.single.pack, isNull);
    expect(orphan.badgePack, isNull);
  });

  testWidgets('distintivo e ponto de presença dividem a beira de baixo', (
    tester,
  ) async {
    final corner = _pack(
      'emoticon_troféu',
      emoji: ['🏆'],
      depth: 'volumetric',
      badge: 'corner',
      tint: '#FFC93C',
    );
    final ring = _pack(
      'emoticon_campeão',
      emoji: ['🥇'],
      depth: 'lifted',
      badge: 'ring',
      tint: '#3DDBB0',
    );

    Future<void> avatarWith(Widget? badge) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: const ValueKey('avatar'),
                width: 88,
                height: 88,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (badge != null)
                      Positioned(right: 2, bottom: 2, child: badge),
                    Positioned(
                      right: presenceRightOffset(badge: badge),
                      bottom: 2,
                      child: const PresenceDot(visible: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // A moldura serve de régua: o `Center` desloca tudo no palco de teste, e o
    // que importa é a distância até a beira de baixo do avatar.
    double rightGap(Finder finder) =>
        tester.getRect(find.byKey(const ValueKey('avatar'))).right -
        tester.getTopRight(finder).dx;

    await avatarWith(emoticonBadgeFor(corner));
    expect(tester.getSize(find.byType(AvatarEmoticonBadge)),
        const Size(kEmoticonBadgeSize, kEmoticonBadgeSize));
    expect(rightGap(find.byType(AvatarEmoticonBadge)), 2);
    // Lado a lado, nenhum suprimido: o ponto anda o tamanho do distintivo e
    // ainda sobram 4 px de folga entre os dois.
    expect(rightGap(find.byType(PresenceDot)), 2 + kEmoticonBadgeSize + 4);
    expect(
      tester.getTopRight(find.byType(PresenceDot)).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(AvatarEmoticonBadge)).dx),
    );
    expect(presenceRightOffset(badge: emoticonBadgeFor(corner)),
        2 + kEmoticonBadgeSize + 4);
    expect(find.text('🏆'), findsOneWidget);

    // O anel (estilo status) desloca o ponto do mesmo jeito que o chip.
    await avatarWith(emoticonBadgeFor(ring));
    expect(rightGap(find.byType(PresenceDot)), 2 + kEmoticonBadgeSize + 4);
    expect(find.text('🥇'), findsOneWidget);

    // Sem distintivo, o ponto volta ao canto de sempre.
    await avatarWith(null);
    expect(presenceRightOffset(badge: null), 2);
    expect(rightGap(find.byType(PresenceDot)), 2);

    expect(emoticonBadgeFor(_pack('badge_none', badge: 'none')), isNull);
    expect(emoticonBadgeFor(_pack('sem_palavra')), isNull);
    // Pacote que declara distintivo mas não tem glifo para pôr nele.
    expect(emoticonBadgeFor(_pack('vazio', emoji: [], badge: 'corner')), isNull);
  });

  test('os glifos do pacote vêm do payload, como no catálogo', () {
    expect(emoticonGlyphs(_pack('p', emoji: ['🏆', '⚡'])), ['🏆', '⚡']);
    expect(emoticonGlyphs(_pack('vazio', emoji: [])), isEmpty);
    expect(emoticonGlyphs(_avatar('rosto')), isEmpty);
  });
}

ShopItem? _ownerOf(EmoticonMural mural, String glyph) =>
    mural.entries.firstWhere((entry) => entry.glyph == glyph).pack;
