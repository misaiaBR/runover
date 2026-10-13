/// As nove famílias de moldura que o catálogo declara em `payload['style']`.
///
/// O backend mantém a cor em `colors` porque todo anel tem cor; o que muda de
/// família para família é o desenho por cima dela — desfoque, ornamento,
/// textura, medidor, rastro. Este arquivo é onde cada uma dessas palavras vira
/// traço. Sem ele, uma moldura de vidro e uma de partículas saíam da loja com o
/// mesmo anel colorido, e o `style` ficava sendo texto de ficha técnica.
///
/// A geometria é sempre a mesma caixa que [FramedAvatar] já reservava: o aro
/// mora entre `rInner` e `rOuter` e nada aqui muda o tamanho que o perfil ocupa.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import 'cosmetics.dart';
import 'effect_painters.dart';

/// As famílias conhecidas, nas mesmas palavras do `FRAME_STYLES` do servidor.
enum FrameFamily {
  glass,
  mono,
  geo,
  metal,
  faction,
  ring,
  chroma,
  ambient,
  glitch;

  static FrameFamily? parse(Object? style) {
    for (final family in FrameFamily.values) {
      if (family.name == style) return family;
    }
    return null;
  }

  /// O que a família precisa de relógio para existir.
  ///
  /// `mono` só se mexe quando o payload pede pulso; `ring` é o medidor de um
  /// número que já é do perfil, não uma animação.
  bool loops(Map<String, dynamic> payload) => switch (this) {
    FrameFamily.mono => payload['pulse'] == true,
    FrameFamily.chroma ||
    FrameFamily.ambient ||
    FrameFamily.glitch => true,
    _ => false,
  };

  /// Período do loop, quando a família declara um. É o servidor que diz a
  /// velocidade (`speed_ms` do neon, `interval_ms` da falha); as demais ficam
  /// com a escada de patamar que o anel já usa.
  Duration? period(Map<String, dynamic> payload) => switch (this) {
    FrameFamily.chroma => _ms(payload['speed_ms']) ??
      const Duration(milliseconds: 2200),
    FrameFamily.glitch => _ms(payload['interval_ms']) ??
      const Duration(milliseconds: 1400),
    _ => null,
  };
}

Duration? _ms(Object? raw) {
  if (raw is! num) return null;
  final ms = raw.toInt();
  if (ms < 200) return null;
  return Duration(milliseconds: ms);
}

/// A família do item, ou null quando ele não declara nenhuma (as molduras
/// antigas e as de parceria continuam no anel simples de cor).
FrameFamily? frameFamily(ShopItem? frame) =>
    frame == null ? null : FrameFamily.parse(frame.payload['style']);

/// O que cada medidor marca, e em quantas casas. O `gauge` do payload é o
/// rótulo do que a moldura está medindo; o número vem de quem desenha o
/// avatar ([FrameGauge]).
const Map<String, int> _gaugeTicks = {
  'xp': 20,
  'sequencia': 7,
  'territorio': 12,
};

/// As grandezas que uma moldura de medidor pode mostrar.
enum GaugeMeasure { xp, sequencia, territorio }

/// Um número real do perfil, com o que ele mede.
class FrameGauge {
  const FrameGauge(this.measure, this.value);

  final GaugeMeasure measure;

  /// 0..1 da grandeza, no instante em que o avatar foi desenhado.
  final double value;
}

/// O preenchimento que a moldura de medidor mostra.
///
/// A moldura declara no `gauge` do payload o que pretende medir; de todos os
/// números que quem veste o avatar tem ([gauges]), vale apenas o que bate com
/// essa palavra. Um medidor de sequência pintado com o XP da vez é um sinal
/// falso, e sinal falso é pior que sinal nenhum — daí o `null`, que deixa o
/// anel aberto, sem inventar progresso.
double? gaugeFill(Object? kind, List<FrameGauge> gauges) {
  if (kind is! String) return null;
  for (final gauge in gauges) {
    if (gauge.measure.name == kind) return gauge.value.clamp(0.0, 1.0);
  }
  return null;
}

/// Os metais nobres, do bronze ao diamante: quatro paradas de matiz que
/// varrem o aro e fazem o anel ler como material, não como cor chapada.
const Map<String, List<int>> _metalStops = {
  'bronze': [0xFF3B2410, 0xFFCD7F32, 0xFFE8B07A, 0xFF8A5A2B],
  'prata': [0xFF555B60, 0xFFC0C0C0, 0xFFF2F2F2, 0xFF7E868D],
  'ouro': [0xFF6B4A00, 0xFFFFC93C, 0xFFFFF3C4, 0xFFB58200],
  'platina': [0xFF3E4A55, 0xFFDCE6EE, 0xFFFFFFFF, 0xFF8FA3B4],
  'diamante': [0xFF0E4E63, 0xFF7FE7FF, 0xFFFFFFFF, 0xFF2AA6C9],
};

/// Ângulo de cada chanfro possível da família `geo`.
const Map<String, double> _notchAngles = {
  'top': -math.pi / 2,
  'right': 0,
  'bottom': math.pi / 2,
  'left': math.pi,
  'corner_tl': -math.pi * 0.75,
  'corner_br': math.pi * 0.25,
};

class FrameFamilyPainter extends CustomPainter {
  FrameFamilyPainter({
    required this.family,
    required this.item,
    required this.progress,
    this.gauges = const [],
  });

  final FrameFamily family;
  final ShopItem item;

  /// 0..1 do loop da família (varredura do neon, piscada da falha).
  final double progress;

  /// Os números do medidor, quando quem veste o avatar tem algum. Só o que
  /// mede a mesma grandeza do `gauge` do payload é desenhado.
  final List<FrameGauge> gauges;

  Map<String, dynamic> get _payload => item.payload;
  List<Color> get _colors => cosmeticColors(item);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;
    final box = Rect.fromLTWH(
      (size.width - side) / 2,
      (size.height - side) / 2,
      side,
      side,
    );
    final center = box.center;
    // O aro encosta na borda da caixa, como o anel simples de cor fazia: 6 px
    // de traço, metade sobre a borda do rosto e metade no respiro. As duas
    // famílias que têm desenho fora do aro — o chanfro da `geo` e a
    // asa/joia/espigão do `metal` — recuam 4,5 px para que o ornamento caiba
    // no espaço que o perfil reserva. Nada vaza da caixa, nada empurra o
    // layout de quem veste a moldura.
    final ornamented =
        family == FrameFamily.geo ||
        (family == FrameFamily.metal && '${_payload['ornament']}' != 'none');
    final outer = side / 2 - (ornamented ? 4.5 : 0.5);
    const band = 6.0;
    final inner = outer - band;
    final colors = _colors;
    final base = colors.first;

    switch (family) {
      case FrameFamily.glass:
        _paintGlass(canvas, center, inner, outer, base);
      case FrameFamily.mono:
        _paintMono(canvas, center, outer, base);
      case FrameFamily.geo:
        _paintGeo(canvas, center, inner, outer, base);
      case FrameFamily.metal:
        _paintMetal(canvas, box, center, inner, outer, base);
      case FrameFamily.faction:
        _paintFaction(canvas, center, inner, outer, base);
      case FrameFamily.ring:
        _paintGauge(canvas, center, inner, outer, base);
      case FrameFamily.chroma:
        _paintChroma(canvas, box, center, inner, outer, colors);
      case FrameFamily.ambient:
        _paintAmbient(canvas, center, inner, outer, base);
      case FrameFamily.glitch:
        _paintGlitch(canvas, center, inner, outer, colors);
    }
  }

  Paint get _stroke => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Anel de vidro fosco: banda translúcida clara por cima da cor do item e
  /// uma hairline milimétrica na `edge` do payload. O `blur` do servidor é o
  /// quanto de leite o vidro tem — não um filtro em tempo real, que custaria
  /// quadro em todo avatar da tela.
  void _paintGlass(Canvas canvas, Offset c, double inner, double outer, Color base) {
    final blur = (_payload['blur'] as num? ?? 1).toDouble().clamp(1.0, 3.0);
    final milk = 0.18 + 0.08 * blur;
    canvas.drawCircle(
      c,
      (inner + outer) / 2,
      _stroke
        ..strokeWidth = outer - inner
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: milk),
            base.withValues(alpha: milk * 0.7),
            Colors.white.withValues(alpha: milk * 0.35),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: outer)),
    );
    canvas.drawCircle(
      c,
      outer - 0.5,
      _stroke
        ..strokeWidth = 1
        ..color = _edgeColor(base),
    );
    // O reflexo do vidro: um arco curto e claro no topo, parado no tempo.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: (inner + outer) / 2),
      -math.pi * 0.85,
      math.pi * 0.5,
      false,
      _stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  Color _edgeColor(Color fallback) {
    final edge = _payload['edge'];
    if (edge is! String) return fallback.withValues(alpha: 0.8);
    final clean = edge.replaceAll('#', '');
    final value = int.tryParse(
      clean.length == 6 ? 'FF$clean' : clean,
      radix: 16,
    );
    return value == null ? fallback.withValues(alpha: 0.8) : Color(value);
  }

  /// Borda monocromática finíssima. É a família que menos cobre o rosto: um
  /// traço de 1 ou 2 px na cor do item, e pulso quando o payload pede — o
  /// mesmo sinal de vida que a presença dá no canto do avatar.
  void _paintMono(Canvas canvas, Offset c, double outer, Color base) {
    final thickness = (_payload['thickness'] as num? ?? 1).toDouble().clamp(
      1.0,
      2.0,
    );
    final alpha = _payload['pulse'] == true
        ? 0.45 + 0.55 * (0.5 + 0.5 * math.sin(progress * math.pi * 2))
        : 1.0;
    canvas.drawCircle(
      c,
      outer - thickness / 2,
      _stroke
        ..strokeWidth = thickness
        ..color = base.withValues(alpha: alpha),
    );
  }

  /// Corte geométrico assimétrico: o aro abre num vão de 40° e fecha em
  /// chanfro reto, com um indicador apontando para fora naquele ângulo. É o
  /// que separa a moldura "de interface" da moldura de quem está ranqueado.
  void _paintGeo(Canvas canvas, Offset c, double inner, double outer, Color base) {
    final notch = _notchAngles['${_payload['notch']}'] ?? -math.pi / 2;
    const gap = 0.35;
    final mid = (inner + outer) / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: mid),
      notch + gap,
      math.pi * 2 - gap * 2,
      false,
      _stroke
        ..strokeWidth = outer - inner
        ..color = base,
    );
    final a = Offset(
      c.dx + math.cos(notch - gap) * outer,
      c.dy + math.sin(notch - gap) * outer,
    );
    final b = Offset(
      c.dx + math.cos(notch + gap) * inner,
      c.dy + math.sin(notch + gap) * inner,
    );
    canvas.drawLine(a, b, _stroke..strokeWidth = 2.5..color = base);
    // O indicador chanfrado: um triângulo no meio do vão, fora do aro.
    final tip = Offset(
      c.dx + math.cos(notch) * (outer + 3),
      c.dy + math.sin(notch) * (outer + 3),
    );
    final left = Offset(
      c.dx + math.cos(notch - 0.16) * (outer - 1),
      c.dy + math.sin(notch - 0.16) * (outer - 1),
    );
    final right = Offset(
      c.dx + math.cos(notch + 0.16) * (outer - 1),
      c.dy + math.sin(notch + 0.16) * (outer - 1),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = base,
    );
  }

  /// Metal nobre: o gradiente varre o aro com as quatro paradas do patamar e
  /// o ornamento sai do `ornament` do payload — asa, joia ou espigões. Sem
  /// ornamento o anel continua metal, só que liso.
  void _paintMetal(
    Canvas canvas,
    Rect box,
    Offset c,
    double inner,
    double outer,
    Color fallback,
  ) {
    final grade = '${_payload['grade']}';
    final stops = _metalStops[grade] ?? const [0xFF2A2240, 0xFFC0C0C0, 0xFFFFFFFF, 0xFF555B60];
    canvas.drawCircle(
      c,
      (inner + outer) / 2,
      _stroke
        ..strokeWidth = outer - inner
        ..shader = SweepGradient(
          colors: [for (final s in stops) Color(s)],
          stops: const [0.0, 0.35, 0.62, 1.0],
          transform: GradientRotation(progress * math.pi * 2),
        ).createShader(box),
    );
    switch ('${_payload['ornament']}') {
      case 'wings':
        _paintWings(canvas, c, outer);
      case 'jewel':
        _paintJewel(canvas, c, outer);
      case 'spikes':
        _paintSpikes(canvas, c, outer, Color(stops.first));
      case _:
        break;
    }
  }

  void _paintWings(Canvas canvas, Offset c, double outer) {
    final ink = _colors.first;
    for (final sign in [-1.0, 1.0]) {
      final path = Path()
        ..moveTo(c.dx + sign * outer * 0.55, c.dy - outer * 0.86)
        ..quadraticBezierTo(
          c.dx + sign * (outer + 9),
          c.dy - outer * 1.05,
          c.dx + sign * (outer + 4),
          c.dy - outer * 0.35,
        )
        ..quadraticBezierTo(
          c.dx + sign * (outer + 1),
          c.dy - outer * 0.62,
          c.dx + sign * outer * 0.62,
          c.dy - outer * 0.62,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = ink.withValues(alpha: 0.9));
    }
  }

  void _paintJewel(Canvas canvas, Offset c, double outer) {
    final ink = _colors.last;
    // A joia coroa o aro sem sair da caixa: 2,5 px acima do traço, sentada
    // sobre ele.
    final top = Offset(c.dx, c.dy - outer - 2.5);
    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(top.dx + 5, top.dy + 5)
      ..lineTo(top.dx, top.dy + 10)
      ..lineTo(top.dx - 5, top.dy + 5)
      ..close();
    canvas.drawPath(path, Paint()..color = ink);
    canvas.drawPath(
      path,
      _stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  void _paintSpikes(Canvas canvas, Offset c, double outer, Color ink) {
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final tip = Offset(
        c.dx + math.cos(angle) * (outer + 2.5),
        c.dy + math.sin(angle) * (outer + 2.5),
      );
      final left = Offset(
        c.dx + math.cos(angle - 0.13) * outer,
        c.dy + math.sin(angle - 0.13) * outer,
      );
      final right = Offset(
        c.dx + math.cos(angle + 0.13) * outer,
        c.dy + math.sin(angle + 0.13) * outer,
      );
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close(),
        Paint()..color = ink,
      );
    }
  }

  /// Facção: o aro é tecido, pedra, runa ou circuito. A faixa é recortada no
  /// anel (even-odd), então a textura nunca invade o rosto.
  void _paintFaction(
    Canvas canvas,
    Offset c,
    double inner,
    double outer,
    Color base,
  ) {
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: c, radius: outer))
      ..addOval(Rect.fromCircle(center: c, radius: inner));
    canvas.drawPath(ring, Paint()..color = base.withValues(alpha: 0.85));
    canvas.save();
    canvas.clipPath(ring);
    final box = Rect.fromCircle(center: c, radius: outer);
    switch ('${_payload['texture']}') {
      case 'stone':
        _paintSpeckles(canvas, box, base);
      case 'rune':
        _paintRunes(canvas, c, inner, outer);
      case 'circuit':
        _paintCircuit(canvas, box, c, inner, outer);
      case _:
        _paintWeave(canvas, box);
    }
    canvas.restore();
    canvas.drawPath(
      ring,
      _stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  void _paintWeave(Canvas canvas, Rect box) {
    final step = 3.0;
    final ink = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    for (var d = -box.height; d < box.width; d += step) {
      canvas.drawLine(
        Offset(box.left + d, box.top),
        Offset(box.left + d + box.height, box.bottom),
        d % (step * 2) == 0 ? ink : light,
      );
    }
  }

  void _paintSpeckles(Canvas canvas, Rect box, Color base) {
    // Pedra não é ruído aleatório de tela: a semente é o id do item, então o
    // Pedra não é ruído aleatório de tela: a semente é a mesma que o palco dos
    // efeitos usa (o id do item), então o cosmético desenha sempre as mesmas
    // lascas — na vitrine da loja e no perfil de quem equipou.
    final rng = math.Random(effectSeedOf(item.id));
    for (var i = 0; i < 40; i++) {
      final x = box.left + rng.nextDouble() * box.width;
      final y = box.top + rng.nextDouble() * box.height;
      final r = 0.6 + rng.nextDouble() * 1.1;
      final clara = rng.nextDouble() > 0.5;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..color = clara
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.35),
      );
    }
  }

  void _paintRunes(Canvas canvas, Offset c, double inner, double outer) {
    final mid = (inner + outer) / 2;
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final from = Offset(
        c.dx + math.cos(angle) * (mid - 2),
        c.dy + math.sin(angle) * (mid - 2),
      );
      final to = Offset(
        c.dx + math.cos(angle) * (mid + 2),
        c.dy + math.sin(angle) * (mid + 2),
      );
      canvas.drawLine(
        from,
        to,
        _stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    }
  }

  void _paintCircuit(Canvas canvas, Rect box, Offset c, double inner, double outer) {
    final trace = _stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.butt
      ..color = Colors.white.withValues(alpha: 0.7);
    final mid = (inner + outer) / 2;
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + 0.2;
      final p = Offset(
        c.dx + math.cos(angle) * mid,
        c.dy + math.sin(angle) * mid,
      );
      final q = Offset(
        c.dx + math.cos(angle + 0.45) * mid,
        c.dy + math.sin(angle + 0.45) * mid,
      );
      canvas.drawLine(p, Offset(q.dx, p.dy), trace);
      canvas.drawLine(Offset(q.dx, p.dy), q, trace);
      canvas.drawCircle(q, 1.3, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  /// Medidor: a moldura É a barra circular. A trilha e as marcas ficam sempre
  /// na cor do item — nada de preto sobreposto, que sumiria no tema escuro. O
  /// preenchimento só aparece quando quem veste o avatar tem o número E ele
  /// mede a mesma grandeza do `gauge` declarado: sem isso o anel se mostra
  /// aberto, nunca inventa progresso.
  void _paintGauge(Canvas canvas, Offset c, double inner, double outer, Color base) {
    final mid = (inner + outer) / 2;
    final arc = Rect.fromCircle(center: c, radius: mid);
    canvas.drawCircle(
      c,
      mid,
      _stroke
        ..strokeWidth = outer - inner
        ..color = base.withValues(alpha: 0.22),
    );
    final kind = _payload['gauge'];
    final ticks = kind is String ? (_gaugeTicks[kind] ?? 20) : 20;
    for (var i = 0; i < ticks; i++) {
      final angle = -math.pi / 2 + i * math.pi * 2 / ticks;
      canvas.drawLine(
        Offset(c.dx + math.cos(angle) * (outer - 1), c.dy + math.sin(angle) * (outer - 1)),
        Offset(c.dx + math.cos(angle) * (inner + 1), c.dy + math.sin(angle) * (inner + 1)),
        _stroke
          ..strokeWidth = 1
          ..color = base.withValues(alpha: 0.55),
      );
    }
    final fill = gaugeFill(kind, gauges);
    if (fill == null || fill <= 0) return;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      fill * math.pi * 2,
      false,
      _stroke
        ..strokeWidth = outer - inner
        ..color = base,
    );
  }

  /// Neon fluido: a varredura de cor correndo em volta, no `speed_ms` que o
  /// servidor deu. O brilho largo por baixo é o bloom do tubo de neon.
  void _paintChroma(
    Canvas canvas,
    Rect box,
    Offset c,
    double inner,
    double outer,
    List<Color> colors,
  ) {
    final sweep = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(progress * math.pi * 2),
    );
    final mid = (inner + outer) / 2;
    canvas.drawCircle(
      c,
      mid,
      _stroke
        ..strokeWidth = outer - inner + 3
        ..color = colors.first.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      c,
      mid,
      _stroke
        ..strokeWidth = outer - inner
        ..shader = sweep.createShader(box),
    );
  }

  /// Partículas ambientes: a borda fica discreta e o movimento sai dela —
  /// folha, pétala, poeira de estrela ou energia, em `count` pontos orbitando.
  void _paintAmbient(Canvas canvas, Offset c, double inner, double outer, Color base) {
    canvas.drawCircle(
      c,
      (inner + outer) / 2,
      _stroke
        ..strokeWidth = 1.5
        ..color = base.withValues(alpha: 0.7),
    );
    final count = ((_payload['count'] as num? ?? 8).toInt()).clamp(3, 18);
    final kind = '${_payload['particle']}';
    final radius = outer + 2.5;
    for (var i = 0; i < count; i++) {
      final angle =
          progress * math.pi * 2 + i * math.pi * 2 / count + (i.isEven ? 0.2 : -0.2);
      final bob = math.sin(progress * math.pi * 4 + i) * 1.6;
      final p = Offset(
        c.dx + math.cos(angle) * (radius + bob),
        c.dy + math.sin(angle) * (radius + bob),
      );
      final paint = Paint()..color = base.withValues(alpha: 0.9);
      switch (kind) {
        case 'leaf':
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(angle + math.pi / 2);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 2.2, height: 4),
            paint,
          );
          canvas.restore();
        case 'petal':
          canvas.drawCircle(p, 1.8, paint);
          canvas.drawCircle(p, 2.6, Paint()..color = base.withValues(alpha: 0.25));
        case 'energy':
          canvas.drawLine(
            p,
            Offset(
              p.dx + math.cos(angle + math.pi / 2) * 4,
              p.dy + math.sin(angle + math.pi / 2) * 4,
            ),
            _stroke
              ..strokeWidth = 1.4
              ..color = paint.color,
          );
        case _:
          // Poeira de estrela: quatro pontas curtas.
          for (var k = 0; k < 4; k++) {
            final a = k * math.pi / 2 + angle;
            canvas.drawLine(
              p,
              Offset(p.dx + math.cos(a) * 2.6, p.dy + math.sin(a) * 2.6),
              _stroke
                ..strokeWidth = 1
                ..color = paint.color,
            );
          }
      }
    }
  }

  /// Falha digital: pedaços do aro deslocam no raio e trocam de matiz, piscando
  /// no `interval_ms` do item. É estática de propósito — a moldura que respira
  /// é outra família.
  void _paintGlitch(
    Canvas canvas,
    Offset c,
    double inner,
    double outer,
    List<Color> colors,
  ) {
    final mid = (inner + outer) / 2;
    canvas.drawCircle(
      c,
      mid,
      _stroke
        ..strokeWidth = outer - inner
        ..color = colors.first,
    );
    // A piscada ocupa o fim do ciclo: a maior parte do tempo a moldura é só o
    // anel, e a falha é o susto.
    final on = progress > 0.62;
    if (!on) return;
    final jitter = ((_payload['jitter'] as num? ?? 2).toInt()).clamp(1, 6);
    final other = colors.length > 1 ? colors[1] : colors.first;
    for (var i = 0; i < jitter; i++) {
      final start = i * math.pi * 2 / jitter + progress * 1.7;
      final shift = (i.isEven ? 2.2 : -2.2) * (0.5 + 0.5 * math.sin(progress * 12 + i));
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: mid + shift),
        start,
        0.5,
        false,
        _stroke
          ..strokeWidth = outer - inner
          ..color = other,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: mid - shift),
        start + 0.12,
        0.26,
        false,
        _stroke
          ..strokeWidth = outer - inner
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(FrameFamilyPainter old) =>
      old.progress != progress ||
      old.family != family ||
      old.item.id != item.id ||
      !_sameGauges(old.gauges, gauges);

  /// Os números do medidor são uma lista nova a cada rebuild do perfil; sem
  /// comparar par a par, o aro se redesenharia até quando nada mudou.
  static bool _sameGauges(List<FrameGauge> a, List<FrameGauge> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].measure != b[i].measure || a[i].value != b[i].value) {
        return false;
      }
    }
    return true;
  }
}
