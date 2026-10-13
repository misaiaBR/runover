/// Um renderizador por tipo de efeito de palco.
///
/// O catálogo manda `kind`, `density`, `cycle_ms` e `hue`
/// (`backend/app/services/shop.py`, em `EFFECT_KINDS`) e este arquivo é onde
/// cada `kind` vira desenho. Não existe emoji de efeito aqui: quando o app só
/// conhecia duas figuras, "Tempestade" e "Faíscas" chegavam à vitrine iguais e a
/// loja perdia a única coisa que diferenciava os itens — o desenho.
///
/// A camada é decorativa e cobre dois fundos possíveis: o cartão do tema (perfil
/// e ficha do produto) e o gradiente fixo e escuro da raridade (caixa de arte da
/// vitrine e do passe). Quem desenha recebe as tintas já resolvidas para o fundo
/// coberto — `accent` é a cor do item legível ali, `neutral` é a tinta clara do
/// fundo (branco sobre o gradiente, `Pal.heading` sobre o cartão).
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';

const double _tau = 6.283185307179586;

/// Os tipos que este arquivo desenha: a mesma lista de `EFFECT_KINDS` do
/// catálogo. Um `kind` fora dela cai em `sparkle` — a loja não desenha um efeito
/// que ela não conhece, e o teste da vitrine no backend não deixa anunciar um.
const List<String> kEffectKinds = [
  'sparkle',
  'fire',
  'ember',
  'cold_spark',
  'confetti',
  'streamer',
  'fog',
  'smoke',
  'color_smoke',
  'wind',
  'rain',
  'snow',
  'storm',
  'laser',
  'strobe',
  'hologram',
  'projection',
  'lens_flare',
  'orbit',
];

/// Semente estável do item: o mesmo id desenha sempre o mesmo campo, na loja, no
/// perfil de quem equipou e no cartão de ranking. `String.hashCode` não serve —
/// ele muda a cada execução da VM.
int effectSeedOf(String id) {
  var hash = 0x811C9DC5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

/// A física do item, lida do payload com teto e piso: um `density` absurdo
/// transformaria o cartão em borrão, e um ciclo de 10 ms é um flashes contínuo.
class EffectSpec {
  const EffectSpec({
    required this.kind,
    required this.density,
    required this.cycleMs,
    required this.hue,
    required this.seed,
  });

  final String kind;
  final int density;
  final int cycleMs;
  final double hue;
  final int seed;

  factory EffectSpec.from(ShopItem item) {
    final payload = item.payload;
    final kind = payload['kind'] is String ? payload['kind'] as String : '';
    return EffectSpec(
      kind: kEffectKinds.contains(kind) ? kind : 'sparkle',
      density: _intOf(payload['density'], 9).clamp(2, 46),
      cycleMs: _intOf(payload['cycle_ms'], 2400).clamp(600, 8000),
      hue: ((payload['hue'] as num?)?.toDouble() ?? 45) % 360,
      seed: effectSeedOf(item.id),
    );
  }

  /// Um ciclo completo do efeito — é a duração do controller que anima a camada.
  Duration get cycle => Duration(milliseconds: cycleMs);

  /// Cor do tipo, do matiz que o servidor deu para o item.
  Color tint({double saturation = .85, double value = 1, double shift = 0}) =>
      HSVColor.fromAHSV(
        1,
        (hue + shift) % 360,
        saturation.clamp(0.0, 1.0),
        value.clamp(0.0, 1.0),
      ).toColor();

  static int _intOf(Object? value, int fallback) =>
      value is num ? value.toInt() : fallback;
}

/// Quantas unidades do tipo cabem na caixa.
///
/// `density` é calibrada para o cartão de perfil (o retângulo largo da vitrine).
/// Na miniatura de 60 px a mesma contagem viraria mancha, então ela entra
/// proporcionalmente à área, com piso de três para o campo nunca esvaziar.
int effectUnits(Size size, int density) {
  final area = size.width * size.height;
  final factor = math.min(1.0, area / (240 * 88));
  return math.max(3, (density * math.max(0.28, factor)).round());
}

/// Desenha o campo do efeito dentro da caixa que lhe é dada.
class StageEffectPainter extends CustomPainter {
  StageEffectPainter({
    required this.spec,
    required this.progress,
    required this.accent,
    required this.neutral,
  });

  final EffectSpec spec;

  /// 0..1 dentro de um ciclo (`AnimationController.value`).
  final double progress;
  final Color accent;
  final Color neutral;

  /// Tudo é medido em relação ao lado menor: uma prévia de 60 px e um cartão de
  /// perfil de 300 px precisam mostrar o mesmo efeito, só que em outra escala.
  double _k(Size size) => math.max(0.4, math.min(size.width, size.height) / 88);

  /// `density` é calibrada para um cartão de perfil; ver [effectUnits].
  int _units(Size size, int density) => effectUnits(size, density);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.clipRect(Offset.zero & size);
    final r = math.Random(spec.seed);
    final t = progress % 1.0;
    switch (spec.kind) {
      case 'sparkle':
        _sparkle(canvas, size, r, t);
      case 'fire':
        _fire(canvas, size, r, t);
      case 'ember':
        _ember(canvas, size, r, t);
      case 'cold_spark':
        _coldSpark(canvas, size, r, t);
      case 'confetti':
        _confetti(canvas, size, r, t);
      case 'streamer':
        _streamer(canvas, size, r, t);
      case 'fog':
        _fog(canvas, size, r, t);
      case 'smoke':
        _smoke(canvas, size, r, t);
      case 'color_smoke':
        _colorSmoke(canvas, size, r, t);
      case 'wind':
        _wind(canvas, size, r, t);
      case 'rain':
        _rain(canvas, size, r, t, slant: 3, speed: 1);
      case 'snow':
        _snow(canvas, size, r, t);
      case 'storm':
        _storm(canvas, size, r, t);
      case 'laser':
        _laser(canvas, size, r, t);
      case 'strobe':
        _strobe(canvas, size, r, t);
      case 'hologram':
        _hologram(canvas, size, r, t);
      case 'projection':
        _projection(canvas, size, r, t);
      case 'lens_flare':
        _lensFlare(canvas, size, r, t);
      case 'orbit':
        _orbit(canvas, size, r, t);
      default:
        _sparkle(canvas, size, r, t);
    }
  }

  // ---------------------------------------------------------------- partículas

  void _sparkle(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * size.width;
      final y = r.nextDouble() * size.height;
      final base = (2 + r.nextDouble() * 3) * k;
      final phase = (t + i / n) % 1;
      final twinkle = math.sin(phase * math.pi);
      _star(
        canvas,
        Offset(x, y),
        base * (0.45 + 0.95 * twinkle),
        accent.withValues(alpha: 0.15 + 0.85 * twinkle),
      );
    }
  }

  void _fire(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * size.width;
      final phase = (t * (0.8 + r.nextDouble() * 0.5) + i / n) % 1;
      final height = (16 + r.nextDouble() * 12) * k;
      final width = height * (0.45 + 0.25 * math.sin(phase * _tau + i));
      final baseY = size.height * 1.02 - phase * size.height * 0.9;
      final sway = math.sin(phase * _tau * 1.5 + i) * 2 * k;
      final path = Path()
        ..moveTo(x + sway, baseY - height)
        ..quadraticBezierTo(
          x + sway + width / 2,
          baseY - height * 0.3,
          x + sway,
          baseY,
        )
        ..quadraticBezierTo(
          x + sway - width / 2,
          baseY - height * 0.3,
          x + sway,
          baseY - height,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              accent.withValues(alpha: 0.9 * (1 - phase)),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromLTRB(
              x + sway - width,
              baseY - height,
              x + sway + width,
              baseY,
            ),
          ),
      );
    }
  }

  void _ember(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x0 = r.nextDouble() * size.width;
      final speed = 0.6 + r.nextDouble() * 0.5;
      final wobble = (3 + r.nextDouble() * 6) * k;
      final radius = (1 + r.nextDouble() * 1.8) * k;
      final flicker = r.nextDouble();
      for (var trail = 3; trail >= 0; trail--) {
        final phase = (t * speed + i / n - trail * 0.04) % 1;
        final y = size.height * 1.05 - phase * size.height * 1.15;
        final x = x0 + math.sin(phase * _tau * 1.4 + i) * wobble;
        final lit =
            0.55 + 0.45 * math.sin(phase * _tau * 3 + flicker * _tau);
        canvas.drawCircle(
          Offset(x, y),
          radius * (1 - trail * 0.18),
          Paint()
            ..color = accent.withValues(
              alpha: (0.9 - trail * 0.22) * lit * (1 - phase * 0.35),
            ),
        );
      }
    }
  }

  void _coldSpark(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    final fromLeft = spec.seed % 2 == 0;
    final origin = Offset(
      size.width * (fromLeft ? 0.16 : 0.84),
      size.height * 0.95,
    );
    final jet = Color.lerp(neutral, accent, 0.35)!;
    for (var i = 0; i < n; i++) {
      final spread = (r.nextDouble() - 0.5) * 0.85;
      final reach = 0.45 + r.nextDouble() * 0.55;
      final phase = (t * (1.1 + r.nextDouble() * 0.6) + i / n) % 1;
      final distance = phase * size.height * reach;
      final angle =
          -math.pi / 2 + spread + (fromLeft ? 1 : -1) * 0.3 * phase;
      final p = Offset(
        origin.dx + math.cos(angle) * distance,
        origin.dy + math.sin(angle) * distance,
      );
      canvas.drawCircle(
        p,
        (0.9 + r.nextDouble() * 1.6) * k * (1 - phase * 0.55),
        Paint()..color = jet.withValues(alpha: 0.95 * (1 - phase)),
      );
    }
    final glow = 8 * k;
    canvas.drawCircle(
      origin,
      glow,
      Paint()
        ..shader = RadialGradient(
          colors: [
            jet.withValues(alpha: 0.55),
            jet.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: origin, radius: glow)),
    );
  }

  void _confetti(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * size.width;
      final drift = (r.nextDouble() - 0.5) * size.width * 0.2;
      final spin = r.nextDouble() * _tau;
      final pieceW = (2.5 + r.nextDouble() * 2.5) * k;
      final pieceH = (3.5 + r.nextDouble() * 3.5) * k;
      final phase = (t * (0.8 + r.nextDouble() * 0.6) + i / n) % 1;
      final y = -pieceH + phase * (size.height + pieceH * 2);
      final color = HSVColor.fromAHSV(
        0.9 * (1 - phase * 0.4),
        (spec.hue + i * 47) % 360,
        0.8,
        0.95,
      ).toColor();
      canvas.save();
      canvas.translate(x + drift * phase, y);
      canvas.rotate(spin + phase * _tau * 1.5);
      // A peça gira de lado: na borda ela vira fio.
      final flat = 0.25 + 0.75 * math.cos(spin + phase * _tau * 3).abs();
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: pieceW * flat,
          height: pieceH,
        ),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  void _streamer(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * size.width;
      final amplitude = (4 + r.nextDouble() * 8) * k;
      final length = size.height * (0.3 + r.nextDouble() * 0.2);
      final phase = (t * (0.55 + r.nextDouble() * 0.45) + i / n) % 1;
      final top = -length + phase * (size.height + length);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6 * k
        ..color = HSVColor.fromAHSV(
          0.8 * (1 - phase * 0.5),
          (spec.hue + i * 71) % 360,
          0.75,
          0.95,
        ).toColor();
      final path = Path();
      for (var s = 0; s <= 7; s++) {
        final f = s / 7;
        final p = Offset(
          x + math.sin(phase * _tau * 2 + f * 5 + i) * amplitude * (0.3 + f),
          top + f * length,
        );
        if (s == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _fog(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    for (var i = 0; i < n; i++) {
      final speed = 0.06 + r.nextDouble() * 0.1;
      final x =
          ((r.nextDouble() + t * speed) % 1) * size.width * 1.4 -
          size.width * 0.2;
      final cy = size.height * (0.72 + r.nextDouble() * 0.24);
      final rx = size.width * (0.16 + r.nextDouble() * 0.2);
      final ry = size.height * (0.06 + r.nextDouble() * 0.07);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, cy), width: rx * 2, height: ry * 2),
        Paint()
          ..color = Color.lerp(neutral, accent, 0.35)!.withValues(
            alpha: 0.1 + r.nextDouble() * 0.1,
          )
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, ry),
      );
    }
  }

  void _smoke(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    for (var i = 0; i < n; i++) {
      final x0 = r.nextDouble() * size.width;
      final growth = 0.16 + r.nextDouble() * 0.14;
      final phase = (t * (0.45 + r.nextDouble() * 0.4) + i / n) % 1;
      final y = size.height * 1.05 - phase * size.height * 1.1;
      final radius = size.height * growth * (0.3 + phase);
      final x = x0 + math.sin(phase * _tau + i) * size.width * 0.06;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = Color.lerp(neutral, accent, 0.2)!.withValues(
            alpha: 0.18 * (1 - phase),
          )
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            radius * 0.5,
          ),
      );
    }
  }

  void _colorSmoke(Canvas canvas, Size size, math.Random r, double t) {
    final bursts = math.max(2, (_units(size, spec.density) / 3).ceil());
    for (var b = 0; b < bursts; b++) {
      final cx = r.nextDouble() * size.width;
      final cy = size.height * (0.35 + r.nextDouble() * 0.5);
      final phase = (t + b / bursts) % 1;
      final radius = math.min(size.width, size.height) * (0.1 + phase * 0.4);
      final alpha = (1 - phase) * 0.45;
      for (var lobe = 0; lobe < 3; lobe++) {
        final angle = phase * _tau + lobe * _tau / 3 + b;
        final center = Offset(
          cx + math.cos(angle) * radius * 0.35,
          cy + math.sin(angle) * radius * 0.35,
        );
        canvas.drawCircle(
          center,
          radius * 0.7,
          Paint()
            ..color = HSVColor.fromAHSV(
              alpha,
              (spec.hue + lobe * 60 + b * 25) % 360,
              0.8,
              0.95,
            ).toColor()
            ..maskFilter = ui.MaskFilter.blur(
              ui.BlurStyle.normal,
              radius * 0.45,
            ),
        );
      }
    }
  }

  void _wind(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final y = r.nextDouble() * size.height;
      final length = size.width * (0.12 + r.nextDouble() * 0.22);
      final curl = (r.nextDouble() - 0.5) * size.height * 0.06;
      final phase = (t * (0.6 + r.nextDouble() * 0.8) + r.nextDouble()) % 1;
      final x = -length + phase * (size.width + length * 2);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (0.8 + r.nextDouble() * 0.9) * k
        ..color = accent.withValues(alpha: 0.7 * math.sin(phase * math.pi));
      canvas.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + length * 0.5, y + curl, x + length, y),
        paint,
      );
    }
  }

  /// Chuva — também é o corpo da tempestade, com caimento e velocidade maiores.
  void _rain(
    Canvas canvas,
    Size size,
    math.Random r,
    double t, {
    required double slant,
    required double speed,
  }) {
    final n = _units(size, spec.density);
    final k = _k(size);
    final drop = Color.lerp(neutral, accent, 0.5)!;
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * size.width * 1.2 - size.width * 0.1;
      final length = (6 + r.nextDouble() * 8) * k;
      final phase = (t * speed + i / n) % 1;
      final y = -length + phase * (size.height + length * 2);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.1 * k
        ..color = drop.withValues(
          alpha: 0.3 + 0.4 * math.sin(phase * math.pi),
        );
      canvas.drawLine(Offset(x, y), Offset(x - slant * k, y + length), paint);
      if (phase > 0.94) {
        final splash = (phase - 0.94) / 0.06;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(x - slant * k, size.height - 2 * k),
            width: 7 * k * splash,
            height: 3 * k * splash,
          ),
          0,
          math.pi,
          false,
          paint..color = drop.withValues(alpha: 0.35 * (1 - splash)),
        );
      }
    }
  }

  void _snow(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    for (var i = 0; i < n; i++) {
      final x0 = r.nextDouble() * size.width;
      final radius = (1.2 + r.nextDouble() * 2.2) * k;
      final sway = (2 + r.nextDouble() * 5) * k;
      final phase = (t * (0.3 + r.nextDouble() * 0.35) + i / n) % 1;
      final y = -radius + phase * (size.height + radius * 2);
      final x = x0 + math.sin(phase * _tau * 1.6 + i) * sway;
      final lit = 0.45 + 0.55 * math.sin(phase * math.pi);
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = neutral.withValues(alpha: lit),
      );
      if (radius > 2.6 * k) {
        final flake = Paint()
          ..color = neutral.withValues(alpha: lit * 0.75)
          ..strokeWidth = k;
        for (var spoke = 0; spoke < 3; spoke++) {
          final angle = spoke * math.pi / 3 + phase;
          final dx = math.cos(angle) * radius * 1.7;
          final dy = math.sin(angle) * radius * 1.7;
          flake.color = neutral.withValues(alpha: lit * 0.4);
          canvas.drawLine(
            Offset(x - dx, y - dy),
            Offset(x + dx, y + dy),
            flake,
          );
        }
      }
    }
  }

  void _storm(Canvas canvas, Size size, math.Random r, double t) {
    _rain(canvas, size, r, t, slant: 9, speed: 1.7);
    // Um clarão por ciclo, com o raio em zigue-zague desenhado sobre a chuva.
    final distance = (t - 0.55).abs();
    if (distance >= 0.08) return;
    final intensity = 1 - distance / 0.08;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = neutral.withValues(alpha: 0.12 * intensity),
    );
    final bolt = math.Random(spec.seed ^ 0x51ED);
    final path = Path();
    var x = size.width * (0.2 + bolt.nextDouble() * 0.6);
    path.moveTo(x, 0);
    for (var step = 1; step <= 6; step++) {
      x += (bolt.nextDouble() - 0.5) * size.width * 0.2;
      path.lineTo(x, size.height * 0.8 * step / 6);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * _k(size)
        ..strokeJoin = StrokeJoin.round
        ..color = neutral.withValues(alpha: 0.9 * intensity),
    );
  }

  // ------------------------------------------------------------- luz e ópticos

  void _laser(Canvas canvas, Size size, math.Random r, double t) {
    final n = math.max(3, _units(size, spec.density));
    final k = _k(size);
    final origins = [
      Offset(size.width * 0.22, 0),
      Offset(size.width * 0.78, 0),
    ];
    canvas.saveLayer(Offset.zero & size, Paint());
    for (var i = 0; i < n; i++) {
      final origin = origins[i % origins.length];
      final spread = (i / n - 0.5) * 1.4;
      final sweep = math.sin(t * _tau + i * 0.7 + r.nextDouble() * 0.2) * 0.4;
      final angle = math.pi / 2 + spread + sweep;
      final length = size.height * 1.8;
      final color = HSVColor.fromAHSV(
        0.6,
        (spec.hue + i * 30) % 360,
        0.9,
        1,
      ).toColor();
      canvas.drawLine(
        origin,
        Offset(
          origin.dx + math.cos(angle) * length,
          origin.dy + math.sin(angle) * length,
        ),
        Paint()
          ..color = color
          ..strokeWidth = (1.2 + 1.8 * math.sin(t * _tau * 2 + i).abs()) * k
          ..strokeCap = StrokeCap.round
          ..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.restore();
  }

  void _strobe(Canvas canvas, Size size, math.Random r, double t) {
    final pulses = math.max(2, spec.density);
    final frac = (t * pulses) % 1;
    final intensity = math.pow(math.sin(frac * math.pi), 8).toDouble();
    if (intensity < 0.01) return;
    final radius = math.min(size.width, size.height) * 0.6;
    canvas.saveLayer(Offset.zero & size, Paint());
    for (var side = 0; side < 2; side++) {
      final center = Offset(
        size.width * (side == 0 ? 0.3 : 0.7),
        size.height * (side == 0 ? 0.4 : 0.6),
      );
      final color = (side == 0 ? accent : neutral).withValues(
        alpha: 0.5 * intensity,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.restore();
  }

  void _hologram(Canvas canvas, Size size, math.Random r, double t) {
    final band = size.height * 0.22;
    final top = (t % 1) * (size.height + band) - band;
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, top + band),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.3),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTRB(0, top, size.width, top + band)),
    );
    final step = math.max(4.0, 4 * _k(size));
    final scanline = Paint()
      ..color = accent.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (var y = step / 2; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanline);
    }
    final flicker = 0.5 + 0.5 * math.sin(t * _tau * 3);
    canvas.drawRect(
      (Offset.zero & size).deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * _k(size)
        ..color = accent.withValues(alpha: 0.28 * flicker),
    );
  }

  void _projection(Canvas canvas, Size size, math.Random r, double t) {
    final cell = math.max(14.0, math.min(size.width, size.height) * 0.22);
    final columns = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final wave = t * (columns + rows + 2);
    final radius = cell * 0.3;
    for (var c = 0; c < columns; c++) {
      for (var row = 0; row < rows; row++) {
        final distance = (c + row - wave).abs();
        final lit = distance < 1.4 ? (1.4 - distance) / 1.4 : 0.0;
        final center = Offset((c + 0.5) * cell, (row + 0.5) * cell);
        final path = Path()
          ..moveTo(center.dx, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx, center.dy + radius)
          ..lineTo(center.dx - radius, center.dy)
          ..close();
        if (lit > 0) {
          canvas.drawPath(
            path,
            Paint()..color = accent.withValues(alpha: 0.5 * lit),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = accent.withValues(alpha: 0.12 + 0.5 * lit),
        );
      }
    }
  }

  void _lensFlare(Canvas canvas, Size size, math.Random r, double t) {
    final k = _k(size);
    final path0 = Offset(-size.width * 0.1, size.height * 0.25);
    final path1 = Offset(size.width * 1.1, size.height * 0.75);
    final center = Offset.lerp(path0, path1, t % 1)!;
    final lit = math.sin((t % 1) * math.pi);
    final halo = math.min(size.width, size.height) * 0.34;
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(
      center,
      halo,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.5 * lit),
            accent.withValues(alpha: 0.12 * lit),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: halo))
        ..blendMode = ui.BlendMode.plus,
    );
    canvas.drawRect(
      Rect.fromLTRB(0, center.dy - 1.5 * k, size.width, center.dy + 1.5 * k),
      Paint()
        ..shader = LinearGradient(
          colors: [
            neutral.withValues(alpha: 0),
            neutral.withValues(alpha: 0.45 * lit),
            neutral.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromLTRB(0, center.dy - 1.5 * k, size.width, center.dy + 1.5 * k),
        )
        ..blendMode = ui.BlendMode.plus,
    );
    for (var spike = 0; spike < 6; spike++) {
      final angle = spike * math.pi / 3 + (t % 1) * _tau * 0.25;
      final length = halo * (spike.isEven ? 1.5 : 0.8);
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(angle) * length,
          center.dy + math.sin(angle) * length,
        ),
        Paint()
          ..color = neutral.withValues(alpha: 0.25 * lit)
          ..strokeWidth = 1.2 * k
          ..blendMode = ui.BlendMode.plus,
      );
    }
    final opposite = Offset(
      size.width - center.dx,
      size.height - center.dy,
    );
    for (var ghost = 1; ghost <= 4; ghost++) {
      final p = Offset.lerp(center, opposite, ghost / 4)!;
      canvas.drawCircle(
        p,
        halo * (0.1 + 0.08 * ghost),
        Paint()
          ..color = HSVColor.fromAHSV(
            0.18 * lit,
            (spec.hue + ghost * 55) % 360,
            0.8,
            1,
          ).toColor()
          ..blendMode = ui.BlendMode.plus,
      );
    }
    canvas.restore();
  }

  void _orbit(Canvas canvas, Size size, math.Random r, double t) {
    final n = _units(size, spec.density);
    final k = _k(size);
    final center = Offset(size.width / 2, size.height * 0.55);
    final rx = size.width * 0.42;
    final ry = size.height * 0.3;
    final tilt = ((spec.seed % 7) - 3) * 0.08;
    for (var i = 0; i < n; i++) {
      final start = i / n * _tau + (spec.seed % 11) * 0.3;
      for (var trail = 3; trail >= 0; trail--) {
        final angle = start + (t + trail * 0.02) * _tau;
        final depth = (math.sin(angle + tilt) + 1) / 2;
        canvas.drawCircle(
          center +
              Offset(math.cos(angle) * rx, math.sin(angle + tilt) * ry),
          (1 + depth * 2.2) * k * (1 - trail * 0.15),
          Paint()
            ..color = accent.withValues(
              alpha: (0.9 - trail * 0.22) * (0.35 + 0.65 * depth),
            ),
        );
      }
    }
  }

  /// Estrela de quatro pontas — a figura do `sparkle`, desenhada, não emoji.
  void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var vertex = 0; vertex < 8; vertex++) {
      final angle = -math.pi / 2 + vertex * math.pi / 4;
      final reach = vertex.isEven ? radius : radius * 0.34;
      final p = Offset(
        center.dx + math.cos(angle) * reach,
        center.dy + math.sin(angle) * reach,
      );
      if (vertex == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(StageEffectPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.neutral != neutral ||
      old.spec.kind != spec.kind ||
      old.spec.density != spec.density ||
      old.spec.hue != spec.hue ||
      old.spec.seed != spec.seed;
}
