/// O pacote de emoticons vira peça desenhada: material, gesto, rastro e
/// distintivo.
///
/// Cada pacote declara quatro palavras no payload (`_emoticon_presentation` em
/// `backend/app/services/shop.py`): `depth` é o material da peça, `motion` é o
/// movimento contínuo, `badge` é o distintivo no canto do avatar e `trail`
/// solta miniaturas subindo; `tint` é a cor do tratamento, porque o glifo é
/// emoji e não se pinta. Sem isto, a loja venderia "Pacote pulso 014" e
/// "Pacote mola 077" e o perfil mostraria os dois como emoji cru — a diferença
/// existiria só na ficha técnica.
///
/// O servidor não guarda qual pacote foi equipado: `_equip_emoticons` põe os
/// glifos na lista plana `equipped_emoticons`. O mural resolve o pacote com uma
/// regra só, a mesma da vitrine e do distintivo: um pacote está em jogo quando
/// todos os glifos que ele declara aparecem no mural e, entre os que disputam o
/// mesmo glifo, o de maior `tier` manda — empate, o glifo mais antigo do mural.
///
/// A caixa de cada peça é fixa e o que se mexe vive em `Transform`, então o
/// mural não salta quando o item troca ou quando o gesto estica.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'cosmetics.dart';
import 'effect_painters.dart';
import 'runover_ui.dart';

const double _tau = 6.283185307179586;

/// O diâmetro do distintivo no canto do avatar. É também o quanto o ponto de
/// presença anda para a esquerda: os dois vivem lado a lado na beira de baixo.
const double kEmoticonBadgeSize = 24;

/// Os materiais do catálogo (`EMOTICON_DEPTHS`).
enum EmoticonDepth {
  /// Bolha de vidro fosco com filete claro na borda.
  glass,

  /// Placa arredondada sobre sombras: a peça flutua sobre o cartão.
  lifted,

  /// Gradiente esférico — a peça vira objeto.
  volumetric,

  /// Sem material: só o glifo.
  flat;

  static EmoticonDepth? parse(Object? value) => _word(values, value);
}

/// Os gestos do catálogo (`EMOTICON_MOTIONS`).
enum EmoticonMotion {
  /// Estica e comprime, como gelatina.
  spring('spring'),

  /// Dois pulsos por ciclo, de tamanho e luz.
  heartbeat('heartbeat'),

  /// Giro de poucos graus com dois saltos.
  popSpin('pop_spin'),

  /// Sobe devagar e some, em loop.
  float('float');

  const EmoticonMotion(this.word);

  /// A palavra do payload. `pop_spin` não é um nome Dart no estilo do projeto,
  /// então o identificador e a palavra ficam num campo em vez de torcer para
  /// `name` bater — se bater, melhor; se não, o parse continua o mesmo.
  final String word;

  static EmoticonMotion? parse(Object? value) {
    if (value is! String) return null;
    for (final option in EmoticonMotion.values) {
      if (option.word == value) return option;
    }
    return null;
  }

  /// Fator sobre a escada de patamar: mola é o gesto mais rápido, flutua o mais
  /// lento. Sem isto, os quatro movimentos seriam o mesmo desenho em outra
  /// ordem.
  double get tempo => switch (this) {
    EmoticonMotion.spring => 1.0,
    EmoticonMotion.heartbeat => 1.25,
    EmoticonMotion.popSpin => 1.8,
    EmoticonMotion.float => 2.6,
  };
}

/// Os distintivos do catálogo (`EMOTICON_BADGES`).
enum EmoticonBadge {
  /// Só o glifo no mural.
  none,

  /// Chip no canto inferior direito do avatar.
  corner,

  /// Anel que recorta a moldura, estilo status.
  ring;

  static EmoticonBadge? parse(Object? value) => _word(values, value);
}

/// Palavra exata do payload, ou null. Uma palavra desconhecida não vira a
/// primeira opção da lista: o item continua neutro nesse eixo.
T? _word<T extends Enum>(List<T> options, Object? value) {
  if (value is! String) return null;
  for (final option in options) {
    if (option.name == value) return option;
  }
  return null;
}

/// A apresentação declarada por um pacote de emoticons.
class EmoticonPresentation {
  const EmoticonPresentation({
    required this.depth,
    required this.motion,
    required this.badge,
    required this.trail,
    this.tint,
  });

  final EmoticonDepth depth;
  final EmoticonMotion motion;
  final EmoticonBadge badge;
  final bool trail;

  /// A cor do tratamento — nunca do glifo, que é emoji.
  final Color? tint;

  /// null quando o item não é de emoticon ou não declara nenhuma das palavras:
  /// pacote antigo continua glifo cru, e o app não inventa material nem gesto.
  ///
  /// A categoria entra no teste porque `depth` é palavra das duas lojas — o
  /// `depth` do rosto (`inner`, `bevel`, `flat`) não é material de emoticon.
  static EmoticonPresentation? of(ShopItem? item) {
    if (item == null || item.category != 'emoticon') return null;
    final payload = item.payload;
    final depth = EmoticonDepth.parse(payload['depth']);
    final motion = EmoticonMotion.parse(payload['motion']);
    final badge = EmoticonBadge.parse(payload['badge']);
    final trail = payload['trail'] is bool;
    final tint = cosmeticHexColor(payload['tint']);
    if (depth == null &&
        motion == null &&
        badge == null &&
        !trail &&
        tint == null) {
      return null;
    }
    return EmoticonPresentation(
      depth: depth ?? EmoticonDepth.flat,
      motion: motion ?? EmoticonMotion.spring,
      badge: badge ?? EmoticonBadge.none,
      trail: payload['trail'] == true,
      tint: tint,
    );
  }

  @override
  String toString() =>
      'EmoticonPresentation($depth, $motion, $badge, trail: $trail)';
}

/// Os glifos que o pacote declara.
List<String> emoticonGlyphs(ShopItem item) => [
  for (final raw in (item.payload['emoji'] as List? ?? const [])) '$raw',
];

/// O que o mural sustenta: um pacote só entra quando todos os glifos que ele
/// declara estão no mural. É a leitura honesta da lista plana do servidor —
/// pacote de três glifos cortado por `MAX_EQUIPPED_EMOTICONS` não aparece com
/// apresentação que o mural não mostra.
List<ShopItem> emoticonPacksInPlay(
  List<ShopItem> catalog,
  List<String> mural,
) {
  return [
    for (final item in catalog)
      if (item.category == 'emoticon' &&
          emoticonGlyphs(item).isNotEmpty &&
          emoticonGlyphs(item).every(mural.contains))
        item,
  ];
}

/// Maior patamar ganha; empatando, o pacote do glifo mais antigo do mural. Vale
/// para a apresentação do glifo e para o distintivo do avatar, então mora aqui.
ShopItem? _governs(List<ShopItem> candidates, List<String> mural) {
  ShopItem? best;
  for (final item in candidates) {
    if (best == null) {
      best = item;
      continue;
    }
    final tier = animationTier(item);
    final leader = animationTier(best);
    if (tier != leader) {
      if (tier > leader) best = item;
      continue;
    }
    if (_firstIndexOf(item, mural) < _firstIndexOf(best, mural)) best = item;
  }
  return best;
}

int _firstIndexOf(ShopItem pack, List<String> mural) {
  var index = -1;
  for (final glyph in emoticonGlyphs(pack)) {
    final found = mural.indexOf(glyph);
    if (found >= 0 && (index < 0 || found < index)) index = found;
  }
  return index < 0 ? mural.length + 1 : index;
}

/// Um glifo do mural com o pacote que o apresenta.
class EmoticonGlyph {
  const EmoticonGlyph({required this.glyph, this.pack});

  final String glyph;

  /// null quando nenhum pacote do catálogo declara aquele glifo — o mural então
  /// continua o emoji cru, com o mesmo espalhamento de sempre.
  final ShopItem? pack;
}

/// O mural resolvido, glifo por glifo, com o dono do distintivo do avatar.
class EmoticonMural {
  const EmoticonMural({required this.entries, this.badgePack});

  final List<EmoticonGlyph> entries;

  /// O pacote de maior patamar entre os em jogo que declaram distintivo.
  final ShopItem? badgePack;

  static const EmoticonMural empty = EmoticonMural(entries: []);
}

/// Resolve a lista plana de glifos equipados contra o catálogo.
EmoticonMural emoticonMural(List<ShopItem> catalog, List<String> mural) {
  if (mural.isEmpty) return EmoticonMural.empty;
  final inPlay = emoticonPacksInPlay(catalog, mural);
  final entries = [
    for (final glyph in mural)
      EmoticonGlyph(
        glyph: glyph,
        pack: _governs([
          for (final pack in inPlay)
            if (emoticonGlyphs(pack).contains(glyph)) pack,
        ], mural),
      ),
  ];
  final badgePack = _governs([
    for (final pack in inPlay)
      if ((EmoticonPresentation.of(pack)?.badge ?? EmoticonBadge.none) !=
          EmoticonBadge.none)
        pack,
  ], mural);
  return EmoticonMural(entries: entries, badgePack: badgePack);
}

/// O gesto da peça no instante `t` de um ciclo. Tudo em fração do lado da
/// caixa, para a prévia da vitrine e o glifo do perfil fazerem o mesmo
/// movimento. É público porque a palavra do payload precisa ser conferível: se
/// `spring` e `heartbeat` devolverem a mesma curva, o `motion` virou texto de
/// ficha técnica.
class EmoticonGesture {
  const EmoticonGesture({
    this.scaleX = 1,
    this.scaleY = 1,
    this.dy = 0,
    this.rotation = 0,
    this.pulse = 0,
    this.opacity = 1,
  });

  final double scaleX;
  final double scaleY;

  /// Vertical, negativo sobe.
  final double dy;
  final double rotation;

  /// 0..1 da luz do gesto: alimenta o halo, nunca o tamanho.
  final double pulse;
  final double opacity;
}

EmoticonGesture emoticonGestureOf(EmoticonMotion motion, double t) => switch (motion) {
  EmoticonMotion.spring => _jelly(t),
  EmoticonMotion.heartbeat => _thump(t),
  EmoticonMotion.popSpin => _spin(t),
  EmoticonMotion.float => _drift(t),
};

/// Mola: o eixo que estica é o mesmo que comprime o outro — por isto a peça
/// parece de gelatina e não um zoom comum.
EmoticonGesture _jelly(double t) {
  final q = math.sin(t * _tau);
  final stretch = 0.16 * q;
  return EmoticonGesture(
    scaleX: 1 - stretch * 0.55,
    scaleY: 1 + stretch,
    pulse: (q + 1) / 2,
  );
}

/// Pulso: duas batidas e silêncio. Os picos ficam no começo do ciclo para a
/// volta ao instante zero não ter tranco.
EmoticonGesture _thump(double t) {
  final b = _lubDub(t);
  return EmoticonGesture(scaleX: 1 + 0.15 * b, scaleY: 1 + 0.15 * b, pulse: b);
}

double _lubDub(double t) {
  double peak(double center, double width) {
    final distance = (t - center).abs();
    if (distance >= width) return 0;
    final x = math.cos(distance / width * math.pi / 2);
    return x * x;
  }
  return (peak(0.16, 0.14) + 0.6 * peak(0.38, 0.11)).clamp(0.0, 1.0);
}

/// Giro: oscila ±17 graus enquanto salta duas vezes por ciclo.
EmoticonGesture _spin(double t) {
  final q = math.sin(t * _tau);
  final pop = (math.sin(t * _tau * 2) + 1) / 2;
  return EmoticonGesture(
    rotation: 0.3 * q,
    scaleX: 1 + 0.12 * pop,
    scaleY: 1 + 0.12 * pop,
    pulse: pop,
  );
}

/// Flutua: sobe e apaga, e é o único gesto que some de fato — por isso o
/// `opacity` entra no gesto, não na peça.
EmoticonGesture _drift(double t) {
  final fade = math.sin(t * math.pi);
  return EmoticonGesture(
    dy: -0.3 * t,
    scaleX: 1 - 0.05 * t,
    scaleY: 1 - 0.05 * t,
    opacity: 0.35 + 0.65 * fade,
    pulse: fade,
  );
}

/// O período do gesto: a escada de patamar do catálogo (`tier`), no ritmo do
/// movimento. Um `motion` sem período próprio seria o mesmo desenho em outra
/// ordem.
Duration emoticonPeriodOf(EmoticonMotion motion, int tier) => Duration(
  milliseconds: ((1500 - 250 * tier) * motion.tempo).round(),
);

/// O material da peça, desenhado por baixo do glifo.
class EmoticonMaterialPainter extends CustomPainter {
  const EmoticonMaterialPainter({
    required this.depth,
    required this.tint,
    required this.pulse,
  });

  final EmoticonDepth depth;
  final Color tint;

  /// A luz do gesto no instante pintado.
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || depth == EmoticonDepth.flat) return;
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final r = side * 0.46;
    switch (depth) {
      case EmoticonDepth.glass:
        _glass(canvas, center, r);
      case EmoticonDepth.lifted:
        _lifted(canvas, center, r);
      case EmoticonDepth.volumetric:
        _orb(canvas, center, r);
      case EmoticonDepth.flat:
        return;
    }
    _halo(canvas, center, r);
  }

  /// O claro do vidro não pode ser branco puro: sobre o cartão do tema claro
  /// ele desaparece. Uma tinta puxada ao matiz continua legível nos dois temas.
  Color get _shine => Color.lerp(tint, Colors.white, 0.62)!;

  void _glass(Canvas canvas, Offset center, double r) {
    final bubble = Rect.fromCircle(center: center, radius: r);
    // O recheio vai do claro ao escuro na vertical: sobre o cartão branco do
    // tema claro um disco de tinta única desapareceria, e sobre o escuro do
    // mock ele continuaria lendo como bolha.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _shine.withValues(alpha: 0.30 + 0.12 * pulse),
            tint.withValues(alpha: 0.22 + 0.10 * pulse),
            Color.lerp(tint, Colors.black, 0.45)!.withValues(alpha: .30),
          ],
          stops: const [0, .55, 1],
        ).createShader(bubble),
    );
    final arc = Rect.fromCircle(center: center, radius: r * 0.84);
    canvas.drawArc(
      arc,
      math.pi * 1.12,
      math.pi * 0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.16
        ..color = _shine.withValues(alpha: 0.75),
    );
    // O escuro embaixo é o que faz o círculo ter espessura em vez de mancha.
    canvas.drawArc(
      arc,
      math.pi * 0.16,
      math.pi * 0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * 0.12
        ..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.lerp(tint, Colors.black, 0.35)!.withValues(
          alpha: 0.4 + 0.25 * pulse,
        ),
    );
  }

  /// A placa levantada: um quadrado arredondado na cor do pacote, apoiado sobre
  /// três sombras que abrem para baixo. É o material que mais precisa de forma,
  /// não só de tinta: sobre o cartão escuro do tema a sombra pura some, e a
  /// placa colorida continua mostrando que a peça está acima do perfil.
  void _lifted(Canvas canvas, Offset center, double r) {
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: r * 1.66, height: r * 1.66),
      Radius.circular(r * 0.44),
    );
    for (var layer = 3; layer >= 1; layer--) {
      canvas.drawRRect(
        plate.shift(Offset(0, r * 0.07 * layer)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.09 * layer)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.13 * layer),
      );
    }
    canvas.drawRRect(
      plate,
      Paint()..color = tint.withValues(alpha: 0.26 + 0.12 * pulse),
    );
    // O filete claro em cima e o escuro embaixo são a espessura da placa.
    canvas.drawRRect(
      plate.deflate(r * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _shine.withValues(alpha: .8),
            Color.lerp(tint, Colors.black, .55)!.withValues(alpha: .55),
          ],
        ).createShader(plate.outerRect),
    );
  }

  void _orb(Canvas canvas, Offset center, double r) {
    final sphere = Rect.fromCircle(center: center, radius: r);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.42),
          radius: 1.15,
          colors: [
            _shine.withValues(alpha: 0.85),
            tint.withValues(alpha: 0.62),
            Color.lerp(tint, Colors.black, 0.5)!.withValues(alpha: 0.75),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(sphere),
    );
    canvas.drawArc(
      sphere.deflate(r * 0.06),
      math.pi * 0.12,
      math.pi * 0.66,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      Offset(center.dx - r * 0.3, center.dy - r * 0.36),
      r * (0.12 + 0.05 * pulse),
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
  }

  /// O halo é comum aos quatro materiais e quem o acende é o gesto: por isso
  /// `heartbeat` pulsa luz e `spring` só respira tamanho.
  void _halo(Canvas canvas, Offset center, double r) {
    if (pulse < 0.02) return;
    canvas.drawCircle(
      center,
      r * (1.04 + 0.3 * pulse),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = tint.withValues(alpha: 0.45 * (1 - pulse)),
    );
  }

  @override
  bool shouldRepaint(EmoticonMaterialPainter old) =>
      old.depth != depth || old.tint != tint || old.pulse != pulse;
}

/// O glifo do mural, com o material e o gesto do pacote que o apresenta.
///
/// Sem pacote — ou com pacote que não declara nenhuma palavra de apresentação —
/// continua o `Text` cru: nada aqui pinta um tratamento que o servidor não
/// vendeu para aquele item.
class EmoticonPiece extends StatelessWidget {
  const EmoticonPiece({
    super.key,
    required this.glyph,
    this.pack,
    this.fontSize = 20,
    this.onDarkSurface = false,
  });

  final String glyph;
  final ShopItem? pack;
  final double fontSize;

  /// A arte da vitrine fica sobre o gradiente fixo e escuro da raridade, onde a
  /// tinta legível do tema claro some — o mesmo critério de
  /// [ProfileEffectOverlay].
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    final presentation = EmoticonPresentation.of(pack);
    if (pack == null || presentation == null) {
      return Text(glyph, style: TextStyle(fontSize: fontSize));
    }
    return _AnimatedEmoticonPiece(
      glyph: glyph,
      pack: pack!,
      presentation: presentation,
      fontSize: fontSize,
      onDarkSurface: onDarkSurface,
    );
  }
}

class _AnimatedEmoticonPiece extends StatefulWidget {
  const _AnimatedEmoticonPiece({
    required this.glyph,
    required this.pack,
    required this.presentation,
    required this.fontSize,
    required this.onDarkSurface,
  });

  final String glyph;
  final ShopItem pack;
  final EmoticonPresentation presentation;
  final double fontSize;
  final bool onDarkSurface;

  @override
  State<_AnimatedEmoticonPiece> createState() => _AnimatedEmoticonPieceState();
}

class _AnimatedEmoticonPieceState extends State<_AnimatedEmoticonPiece>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: emoticonPeriodOf(
        widget.presentation.motion,
        animationTier(widget.pack),
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(_AnimatedEmoticonPiece oldWidget) {
    super.didUpdateWidget(oldWidget);
    final duration = emoticonPeriodOf(
      widget.presentation.motion,
      animationTier(widget.pack),
    );
    if (duration == _controller.duration) return;
    // Outro pacote é outro ritmo: `repeat()` grava o período no instante em que
    // é chamado, então só trocar a duração deixaria a peça no pulso antigo.
    _controller
      ..duration = duration
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final side = widget.fontSize * 1.35;
    final raw = presentation.tint ?? Theme.of(context).colorScheme.primary;
    final tint = widget.onDarkSurface ? raw : legibleInk(raw, context);
    final seed = effectSeedOf('${widget.pack.id}${widget.glyph}');
    // A fase vem da semente do par pacote+glifo: um mural de quatro peças do
    // mesmo pacote não pulsa em bloco, e a mesma peça na vitrine respira no
    // mesmo instante do perfil de quem equipou.
    final phase = (seed % 1000) / 1000;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        final t = (_controller.value + phase) % 1;
        final gesture = emoticonGestureOf(presentation.motion, t);
        return Transform.translate(
          offset: Offset(0, gesture.dy * side),
          child: Transform.rotate(
            angle: gesture.rotation,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(
                gesture.scaleX,
                gesture.scaleY,
                1,
              ),
              child: Opacity(
                opacity: gesture.opacity,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    alignment: Alignment.center,
                    // O rastro sobe por cima do glifo e sai da caixa de
                    // propósito: cortá-lo deixaria o `trail` invisível no
                    // mural, que é justamente onde ele é comprado.
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(side, side),
                        painter: EmoticonMaterialPainter(
                          depth: presentation.depth,
                          tint: tint,
                          pulse: gesture.pulse,
                        ),
                      ),
                      Text(
                        widget.glyph,
                        style: TextStyle(fontSize: widget.fontSize),
                      ),
                      if (presentation.trail)
                        ..._trail(seed, t, side, widget.fontSize),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Miniaturas do próprio glifo subindo e apagando, defasadas entre si.
  List<Widget> _trail(int seed, double t, double side, double fontSize) {
    final rng = math.Random(seed);
    final drift = [for (var i = 0; i < 3; i++) (rng.nextDouble() - 0.5) * side];
    return [
      for (var i = 0; i < 3; i++)
        Positioned(
          left: side / 2 + drift[i] * 0.4 - side * 0.19,
          bottom: side * (0.5 + 0.62 * ((t + i / 3) % 1)),
          child: Opacity(
            opacity: 0.7 * (1 - (t + i / 3) % 1),
            child: Text(
              widget.glyph,
              style: TextStyle(fontSize: fontSize * 0.38),
            ),
          ),
        ),
    ];
  }
}

/// O distintivo do pacote no canto do avatar.
///
/// `corner` é a peça apoiada no canto, com o glifo dentro de um disco na cor do
/// pacote; `ring` é o anel que recorta a moldura, estilo status. Quem decide se
/// há distintivo é [emoticonBadgeFor].
class AvatarEmoticonBadge extends StatelessWidget {
  const AvatarEmoticonBadge({
    super.key,
    required this.pack,
    this.size = kEmoticonBadgeSize,
  });

  final ShopItem pack;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presentation = EmoticonPresentation.of(pack);
    final glyph = emoticonGlyphs(pack).isEmpty
        ? null
        : emoticonGlyphs(pack).first;
    if (presentation == null ||
        presentation.badge == EmoticonBadge.none ||
        glyph == null) {
      return const SizedBox.shrink();
    }
    final raw = presentation.tint ?? scheme.primary;
    final tint = legibleInk(raw, context);
    if (presentation.badge == EmoticonBadge.corner) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
          border: Border.all(color: tint, width: 2),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: .5),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Text(glyph, style: TextStyle(fontSize: size * 0.6)),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // O recorte é a cor do cartão, nunca branco fixo: no tema claro um anel
        // branco sobre a foto não existe.
        border: Border.all(color: scheme.surface, width: 3),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: .85), width: 1.4),
        ),
        child: Center(
          child: Text(glyph, style: TextStyle(fontSize: size * 0.55)),
        ),
      ),
    );
  }
}

/// O distintivo do avatar, ou null quando nenhum pacote em jogo o declara.
Widget? emoticonBadgeFor(ShopItem? pack, {double size = kEmoticonBadgeSize}) {
  final presentation = EmoticonPresentation.of(pack);
  if (presentation == null ||
      presentation.badge == EmoticonBadge.none ||
      emoticonGlyphs(pack!).isEmpty) {
    return null;
  }
  return AvatarEmoticonBadge(pack: pack, size: size);
}

/// O canto inferior direito é disputado: o distintivo fica encostado na beira
/// e o ponto de presença anda para a esquerda dele — lado a lado, nenhum dos
/// dois é suprimido.
double presenceRightOffset({required Widget? badge}) =>
    badge == null ? 2 : 2 + kEmoticonBadgeSize + 4;
