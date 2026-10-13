import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runover_app/models.dart';
import 'package:runover_app/theme.dart';
import 'package:runover_app/widgets/avatar_finish.dart';
import 'package:runover_app/widgets/cosmetics.dart';
import 'package:runover_app/widgets/effect_painters.dart';

/// A galeria de avatares vende quatro palavras por item: `light`, `depth`,
/// `texture` e `tint` (`_avatar_finish` em `backend/app/services/shop.py`). Se
/// o app só lesse isso como texto de ficha técnica, cem rostos continuariam
/// idênticos — o "acabamento próprio" anunciado pela loja seria propaganda.
/// Estes testes amarram o contrário: cada palavra vira um desenho, o desenho não
/// sai do rosto, e um item sem acabamento continua com o rosto cru.
ShopItem _avatar(
  String id, {
  String? light,
  String? depth,
  String? texture,
  String? tint,
}) => ShopItem(
  id: id,
  category: 'avatar',
  name: 'Rosto $id',
  price: 60,
  payload: {
    'animated': false,
    'tier': 1,
    'light': ?light,
    'depth': ?depth,
    'texture': ?texture,
    'tint': ?tint,
  },
);

AvatarFinishPainter? _painterFor(ShopItem item, {double? corner}) =>
    AvatarFinishPainter.forItem(item, cornerRadius: corner);

/// Desenha um "rosto" de mentira — um disco cinza chato — e, sobre ele, o
/// acabamento pedido. Devolve os pixels em RGBA puro para poder perguntar de um
/// ponto: é o único jeito de medir se o recorte segura a tinta e se o véu pesa
/// menos numa cédula pequena.
Future<ByteData> _face(double side, {AvatarFinishPainter? finish}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawCircle(
    Offset(side / 2, side / 2),
    side / 2,
    Paint()..color = const Color(0xFF8899AA),
  );
  finish?.paint(canvas, Size(side, side));
  final image = await recorder.endRecording().toImage(
    side.ceil(),
    side.ceil(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

int _alphaAt(ByteData pixels, double side, int x, int y) =>
    pixels.getUint8(((y * side.ceil() + x) * 4) + 3);

/// Quanto o acabamento mudou a cor de um pixel, em soma de canais.
int _deltaAt(ByteData cru, ByteData pintado, int side, int x, int y) {
  var total = 0;
  for (var channel = 0; channel < 3; channel++) {
    final offset = (y * side + x) * 4 + channel;
    total += (pintado.getUint8(offset) - cru.getUint8(offset)).abs();
  }
  return total;
}

void _paintAll(ui.PictureRecorder recorder, AvatarFinishPainter painter) {
  final canvas = Canvas(recorder);
  painter.paint(canvas, const Size(88, 88));
}

void main() {
  test('as palavras do servidor viram eixos; fora delas, nada', () {
    for (final light in AvatarLight.values) {
      expect(AvatarLight.parse(light.name), light);
    }
    for (final depth in AvatarDepth.values) {
      expect(AvatarDepth.parse(depth.name), depth);
    }
    for (final texture in AvatarTexture.values) {
      expect(AvatarTexture.parse(texture.name), texture);
    }
    // Palavra inventada não vale: o app não desenha o que o catálogo não vende.
    expect(AvatarLight.parse('holofote'), isNull);
    expect(AvatarDepth.parse(7), isNull);
    expect(AvatarTexture.parse(null), isNull);
  });

  test('o payload inteiro vira um acabamento lido de uma vez', () {
    expect(
      AvatarFinish.of(
        _avatar(
          'a',
          light: 'rim',
          depth: 'bevel',
          texture: 'hex',
          tint: '#FFD1A1',
        ),
      ),
      const AvatarFinish(
        light: AvatarLight.rim,
        depth: AvatarDepth.bevel,
        texture: AvatarTexture.hex,
        tint: Color(0xFFFFD1A1),
      ),
    );

    // Eixo ausente é o neutro dele, não uma aposta: `depth` ausente não vira
    // chanfro só porque o item tem luz.
    expect(
      AvatarFinish.of(_avatar('b', light: 'top')),
      const AvatarFinish(
        light: AvatarLight.top,
        depth: AvatarDepth.flat,
        texture: AvatarTexture.none,
      ),
    );

    // Item anterior à galeria: nenhuma das quatro palavras, nenhum acabamento.
    expect(AvatarFinish.of(_avatar('c')), isNull);
    expect(AvatarFinish.of(null), isNull);
    // Hex mal escrito não derruba a tela nem inventa cor.
    final junk = AvatarFinish.of(_avatar('d', light: 'rim', tint: '#ZZZZZZ'));
    expect(junk?.tint, isNull);
    expect(junk?.light, AvatarLight.rim);
  });

  test('neutro por inteiro não pinta e não monta camada', () {
    // O item declara as quatro palavras, todas inertes: é o rosto cru declarado.
    final declared = _avatar(
      'e',
      light: 'none',
      depth: 'flat',
      texture: 'none',
    );
    expect(AvatarFinish.of(declared)?.paints, isFalse);
    expect(_painterFor(declared), isNull);

    final lit = _avatar('f', light: 'rim');
    expect(AvatarFinish.of(lit)?.paints, isTrue);
    expect(_painterFor(lit), isNotNull);
  });

  test('a semente é o id do item, em toda superfície', () {
    // O mesmo id lido duas vezes (vitrine e perfil) tem de desenhar a mesma
    // textura — foi a regra do `seed` do rosto, agora também do acabamento.
    expect(
      _painterFor(_avatar('avatar_galeria_007', texture: 'grain'))?.seed,
      _painterFor(_avatar('avatar_galeria_007', texture: 'grain'))?.seed,
    );
    expect(
      _painterFor(_avatar('avatar_galeria_007', texture: 'grain'))?.seed,
      effectSeedOf('avatar_galeria_007'),
    );
    expect(
      _painterFor(_avatar('avatar_galeria_008', texture: 'grain'))?.seed,
      isNot(_painterFor(_avatar('avatar_galeria_007', texture: 'grain'))?.seed),
    );
    // A folha de escolha recorta em canto arredondado; o perfil, em círculo.
    final rounded = _painterFor(_avatar('g', depth: 'bevel'), corner: 16);
    expect(rounded?.cornerRadius, 16);
    expect(_painterFor(_avatar('g', depth: 'bevel'))?.cornerRadius, isNull);
  });

  test('toda combinação do catálogo desenha sem estourar', () {
    for (final light in AvatarLight.values) {
      for (final depth in AvatarDepth.values) {
        for (final texture in AvatarTexture.values) {
          for (final tint in const ['#FFE9C9', '#CFD8FF', null]) {
            final painter = AvatarFinishPainter(
              finish: AvatarFinish(
                light: light,
                depth: depth,
                texture: texture,
                tint: tint == null ? null : cosmeticHexColor(tint),
              ),
              seed: effectSeedOf('avatar_galeria_teste'),
            );
            final recorder = ui.PictureRecorder();
            _paintAll(recorder, painter);
            recorder.endRecording().dispose();
          }
        }
      }
    }
  });

  testWidgets('o rosto com acabamento ocupa exatamente a mesma caixa', (
    tester,
  ) async {
    Future<Size> wear(ShopItem? avatar) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: FramedAvatar(
                radius: 30,
                avatarItem: avatar,
                fallbackLetter: 'V',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(FramedAvatar));
    }

    expect(await wear(_avatar('sem_acabamento')), const Size(60, 60));
    expect(
      await wear(_avatar('com_acabamento', texture: 'carbon')),
      const Size(60, 60),
    );
  });

  testWidgets('a camada é uma só, e só quando o item tem acabamento', (
    tester,
  ) async {
    Future<void> wear(ShopItem avatar) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildRunoverTheme(),
          home: Scaffold(
            body: Center(
              child: FramedAvatar(
                radius: 30,
                avatarItem: avatar,
                fallbackLetter: 'V',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    List<AvatarFinishPainter> painters() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.foregroundPainter)
        .whereType<AvatarFinishPainter>()
        .toList();

    await wear(_avatar('cru'));
    expect(painters(), isEmpty);

    // A moldura não apaga o acabamento do rosto, nem o contrário.
    await wear(_avatar('pintado', light: 'back', texture: 'dots'));
    expect(painters(), hasLength(1));
  });

  testWidgets('nenhum filete sai do rosto', (tester) async {
    final painter = _painterFor(
      _avatar(
        'saindo',
        light: 'rim',
        depth: 'bevel',
        texture: 'hex',
        tint: '#FFD1A1',
      ),
    )!;
    late ByteData pixels;
    await tester.runAsync(() async {
      pixels = await _face(88, finish: painter);
    });
    // O canto do quadrado está fora do círculo: se vazar tinta ali, o recorte
    // falhou e o perfil mostraria um selo quadrado atrás da figura.
    expect(_alphaAt(pixels, 88, 0, 0), 0);
    expect(_alphaAt(pixels, 88, 87, 0), 0);
    expect(_alphaAt(pixels, 88, 0, 87), 0);
    expect(_alphaAt(pixels, 88, 87, 87), 0);
    // E no meio do rosto há acabamento de verdade.
    expect(_alphaAt(pixels, 88, 44, 44), greaterThan(0));
  });

  testWidgets('o mesmo véu pesa menos na cédula pequena', (tester) async {
    // Só o matiz, para a medição não misturar o véu com o traço da luz.
    final tinted = _painterFor(_avatar('matiz', tint: '#FFD1A1'))!;
    late ByteData smallCru;
    late ByteData smallPinto;
    late ByteData largeCru;
    late ByteData largePinto;
    await tester.runAsync(() async {
      smallCru = await _face(24);
      smallPinto = await _face(24, finish: tinted);
      largeCru = await _face(88);
      largePinto = await _face(88, finish: tinted);
    });
    final pequeno = _deltaAt(smallCru, smallPinto, 24, 12, 12);
    final grande = _deltaAt(largeCru, largePinto, 88, 44, 44);
    // A opacidade cai com o tamanho: em 24 px o rosto comprado continua
    // aparecendo, em 88 px o acabamento aparece por inteiro.
    expect(grande, greaterThan(0));
    expect(pequeno, lessThan(grande));
  });
}
